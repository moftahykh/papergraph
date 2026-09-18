import logging
from typing import Any, Dict, Optional
from fastapi import Header, HTTPException, status
from pydantic import BaseModel, Field
from app.core.config import settings

logger = logging.getLogger("papergraph.auth")


class AuthenticatedUser(BaseModel):
    user_id: str
    is_authenticated: bool = True
    role: str = "researcher"
    claims: Dict[str, Any] = Field(default_factory=dict)


async def get_optional_auth_user(
    authorization: Optional[str] = Header(None, alias="Authorization"),
) -> Optional[AuthenticatedUser]:
    """
    Authorization placeholder dependency for FastAPI.
    Allows public unauthenticated access for PaperGraph MVP, while accepting
    and validating Bearer tokens or API keys if provided.
    """
    if not authorization:
        # Public anonymous access
        return None

    scheme, _, token = authorization.partition(" ")
    if scheme.lower() not in ("bearer", "apikey") or not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authorization scheme. Use 'Bearer <token>' or 'ApiKey <key>'.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # Placeholder: In production, verify JWT signature or check API key against database
    return AuthenticatedUser(
        user_id=f"user_{token[:8]}",
        is_authenticated=True,
        role="researcher",
    )


def _extract_bearer_token(authorization: Optional[str]) -> str:
    if not authorization:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication is required.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token.strip():
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authorization scheme. Use 'Bearer <Firebase ID token>'.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return token.strip()


async def get_required_auth_user(
    authorization: Optional[str] = Header(None, alias="Authorization"),
) -> AuthenticatedUser:
    """Verify a Firebase ID token for account-scoped endpoints.

    Existing public MVP endpoints intentionally keep their legacy optional
    dependency. New monitoring/device endpoints must use this strict
    dependency so ownership is based on a verified Firebase UID.
    """
    token = _extract_bearer_token(authorization)
    project_id = settings.FIREBASE_PROJECT_ID
    if not project_id:
        logger.error("FIREBASE_PROJECT_ID is not configured.")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Authenticated services are not configured.",
        )

    try:
        from google.auth.transport import requests as google_requests
        from google.oauth2 import id_token

        claims = id_token.verify_firebase_token(
            token,
            google_requests.Request(),
            audience=project_id,
        )
    except Exception as exc:
        logger.info("Firebase ID token verification failed: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired Firebase ID token.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc

    user_id = str(claims.get("user_id") or claims.get("sub") or "").strip()
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Firebase token did not contain a user identity.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return AuthenticatedUser(
        user_id=user_id,
        role=str(claims.get("role") or "researcher"),
        claims=dict(claims),
    )
