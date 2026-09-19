from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.discovery import DiscoveryTopic
from app.models.monitoring import MonitoredGraph, ResearchUpdate


async def list_discovery_topics(
    db: AsyncSession,
    limit: int = 8,
) -> list[DiscoveryTopic]:
    result = await db.execute(
        select(DiscoveryTopic)
        .where(DiscoveryTopic.is_active.is_(True))
        .order_by(DiscoveryTopic.rank.asc(), DiscoveryTopic.updated_at.desc())
        .limit(limit)
    )
    return list(result.scalars().all())


async def get_user_recommendation(
    db: AsyncSession,
    user_id: str,
) -> tuple[ResearchUpdate, str, str] | None:
    result = await db.execute(
        select(
            ResearchUpdate,
            MonitoredGraph.local_graph_id,
            MonitoredGraph.graph_title,
        )
        .join(
            MonitoredGraph,
            MonitoredGraph.id == ResearchUpdate.monitored_graph_id,
        )
        .where(
            MonitoredGraph.user_id == user_id,
            MonitoredGraph.status == "active",
            ResearchUpdate.is_read.is_(False),
            ResearchUpdate.is_added_to_graph.is_(False),
        )
        .order_by(
            ResearchUpdate.relevance_score.desc(),
            ResearchUpdate.detected_at.desc(),
        )
        .limit(1)
    )
    row = result.first()
    if row is None:
        return None
    update, local_graph_id, graph_title = row
    return update, local_graph_id, graph_title
