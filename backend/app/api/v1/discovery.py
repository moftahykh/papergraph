from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import AuthenticatedUser, get_optional_auth_user
from app.db.session import get_db
from app.repositories.discovery import (
    get_user_recommendation,
    list_discovery_topics,
)
from app.schemas.discovery import (
    DiscoveryHomeResponse,
    DiscoveryRecommendationResponse,
    DiscoveryTopicResponse,
)

router = APIRouter(prefix="/discover", tags=["Discovery"])
Database = Annotated[AsyncSession, Depends(get_db)]
OptionalUser = Annotated[
    AuthenticatedUser | None,
    Depends(get_optional_auth_user),
]


@router.get("/home", response_model=DiscoveryHomeResponse)
async def get_discovery_home(
    db: Database,
    user: OptionalUser,
) -> DiscoveryHomeResponse:
    """Return server-managed topics and a user-grounded recommendation.

    Topics are managed server-side so the mobile client never ships stale
    editorial content. The recommendation is intentionally empty for users
    without active monitoring updates rather than inventing a featured paper.
    """
    topics = await list_discovery_topics(db)
    recommendation = None

    if user is not None:
        candidate = await get_user_recommendation(db, user.user_id)
        if candidate is not None:
            update, local_graph_id, graph_title = candidate
            recommendation = DiscoveryRecommendationResponse(
                canonical_id=update.canonical_paper_id,
                doi=update.doi,
                title=update.title,
                reason=update.explanation,
                local_graph_id=local_graph_id,
                graph_title=graph_title,
                relation_type=update.relation_type,
                relevance_score=update.relevance_score,
                detected_at=update.detected_at,
            )

    return DiscoveryHomeResponse(
        topics=[
            DiscoveryTopicResponse.model_validate(topic)
            for topic in topics
        ],
        recommendation=recommendation,
    )
