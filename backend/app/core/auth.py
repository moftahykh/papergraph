from typing import Optional
from fastapi import Header, HTTPException, status
from pydantic import BaseModel


class AuthenticatedUser(BaseModel):
    user_id: str
    is_authenticated: bool = True
    role: str = "researcher"


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
