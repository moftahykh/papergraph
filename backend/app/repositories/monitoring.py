from datetime import datetime, timedelta, timezone
from uuid import uuid4

from sqlalchemy import delete, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.monitoring import (
    DeviceToken,
    MonitoredGraph,
    MonitoredGraphPaper,
    ResearchUpdate,
    utc_now,
)
from app.schemas.monitoring import (
    CreateMonitoredGraphRequest,
    MonitoredPaperInput,
    UpdateMonitoredGraphRequest,
)


def _new_id(prefix: str) -> str:
    return f"{prefix}_{uuid4().hex}"


def _next_check_at(frequency: str, now: datetime) -> datetime:
    return now + (timedelta(days=7) if frequency == "weekly" else timedelta(days=1))


async def upsert_monitored_graph(
    db: AsyncSession,
    user_id: str,
    request: CreateMonitoredGraphRequest,
) -> MonitoredGraph:
    result = await db.execute(
        select(MonitoredGraph).where(
            MonitoredGraph.user_id == user_id,
            MonitoredGraph.local_graph_id == request.local_graph_id,
        )
    )
    graph = result.scalar_one_or_none()
    now = utc_now()

    if graph is None:
        graph = MonitoredGraph(
            id=_new_id("monitor"),
            user_id=user_id,
            local_graph_id=request.local_graph_id,
            graph_title=request.graph_title,
            status="active",
            frequency=request.frequency,
            timezone=request.timezone,
            next_check_at=_next_check_at(request.frequency, now),
            created_at=now,
            updated_at=now,
        )
        db.add(graph)
    else:
        graph.graph_title = request.graph_title
        graph.status = "active"
        graph.frequency = request.frequency
        graph.timezone = request.timezone
        graph.next_check_at = _next_check_at(request.frequency, now)
        graph.updated_at = now
        await db.execute(
            delete(MonitoredGraphPaper).where(
                MonitoredGraphPaper.monitored_graph_id == graph.id
            )
        )

    for paper in request.papers:
        db.add(
            MonitoredGraphPaper(
                id=_new_id("paper"),
                monitored_graph_id=graph.id,
                canonical_id=paper.canonical_id,
                doi=paper.doi,
                openalex_id=paper.openalex_id,
                semantic_scholar_id=paper.semantic_scholar_id,
                title=paper.title,
                year=paper.year,
            )
        )

    await db.commit()
    await db.refresh(graph)
    return graph


async def list_monitored_graphs(
    db: AsyncSession,
    user_id: str,
) -> list[MonitoredGraph]:
    result = await db.execute(
        select(MonitoredGraph)
        .where(MonitoredGraph.user_id == user_id)
        .order_by(MonitoredGraph.updated_at.desc())
    )
    return list(result.scalars().all())


async def get_owned_graph(
    db: AsyncSession,
    user_id: str,
    monitor_id: str,
) -> MonitoredGraph | None:
    result = await db.execute(
        select(MonitoredGraph).where(
            MonitoredGraph.id == monitor_id,
            MonitoredGraph.user_id == user_id,
        )
    )
    return result.scalar_one_or_none()


async def get_owned_graph_by_local_id(
    db: AsyncSession,
    user_id: str,
    local_graph_id: str,
) -> MonitoredGraph | None:
    result = await db.execute(
        select(MonitoredGraph).where(
            MonitoredGraph.local_graph_id == local_graph_id,
            MonitoredGraph.user_id == user_id,
        )
    )
    return result.scalar_one_or_none()


async def update_monitored_graph(
    db: AsyncSession,
    graph: MonitoredGraph,
    request: UpdateMonitoredGraphRequest,
) -> MonitoredGraph:
    now = utc_now()
    if request.status is not None:
        graph.status = request.status
    if request.frequency is not None:
        graph.frequency = request.frequency
        graph.next_check_at = _next_check_at(request.frequency, now)
    if request.timezone is not None:
        graph.timezone = request.timezone
    graph.updated_at = now
    await db.commit()
    await db.refresh(graph)
    return graph


async def claim_due_monitored_graph(
    db: AsyncSession,
    now: datetime | None = None,
    claim_timeout: timedelta = timedelta(minutes=15),
) -> MonitoredGraph | None:
    """Claim one due graph without allowing two workers to scan it at once.

    The claim is committed before provider calls begin. A stale claim becomes
    eligible again after ``claim_timeout`` so a crashed worker cannot strand a
    subscription permanently.
    """
    now = now or utc_now()
    stale_before = now - claim_timeout
    result = await db.execute(
        select(MonitoredGraph)
        .options(selectinload(MonitoredGraph.papers))
        .where(
            MonitoredGraph.status == "active",
            MonitoredGraph.next_check_at <= now,
            or_(
                MonitoredGraph.scan_claimed_at.is_(None),
                MonitoredGraph.scan_claimed_at < stale_before,
            ),
        )
        .order_by(MonitoredGraph.next_check_at.asc())
        .with_for_update(skip_locked=True)
        .limit(1)
    )
    graph = result.scalar_one_or_none()
    if graph is None:
        return None

    graph.scan_claimed_at = now
    await db.commit()
    await db.refresh(graph)
    return graph


async def complete_monitored_graph_scan(
    db: AsyncSession,
    graph: MonitoredGraph,
    checked_at: datetime | None = None,
) -> MonitoredGraph:
    checked_at = checked_at or utc_now()
    graph.last_checked_at = checked_at
    graph.next_check_at = _next_check_at(graph.frequency, checked_at)
    graph.scan_claimed_at = None
    graph.updated_at = checked_at
    await db.commit()
    await db.refresh(graph)
    return graph


async def release_monitored_graph_claim(
    db: AsyncSession,
    graph: MonitoredGraph,
) -> None:
    graph.scan_claimed_at = None
    await db.commit()


async def list_existing_update_ids(
    db: AsyncSession,
    graph_id: str,
) -> set[str]:
    result = await db.execute(
        select(ResearchUpdate.canonical_paper_id).where(
            ResearchUpdate.monitored_graph_id == graph_id
        )
    )
    return {str(value) for value in result.scalars().all()}


async def add_research_updates(
    db: AsyncSession,
    graph_id: str,
    updates: list[dict],
) -> int:
    """Persist only updates that are not already present for this graph."""
    if not updates:
        return 0

    existing_ids = await list_existing_update_ids(db, graph_id)
    inserted = 0
    for payload in updates:
        canonical_id = str(payload["canonical_paper_id"])
        if canonical_id in existing_ids:
            continue
        db.add(
            ResearchUpdate(
                id=_new_id("update"),
                monitored_graph_id=graph_id,
                **payload,
            )
        )
        existing_ids.add(canonical_id)
        inserted += 1

    if inserted:
        await db.commit()
    return inserted


async def delete_monitored_graph(db: AsyncSession, graph: MonitoredGraph) -> None:
    await db.delete(graph)
    await db.commit()


async def list_updates(
    db: AsyncSession,
    graph_id: str,
    limit: int,
) -> list[ResearchUpdate]:
    result = await db.execute(
        select(ResearchUpdate)
        .where(ResearchUpdate.monitored_graph_id == graph_id)
        .order_by(ResearchUpdate.detected_at.desc())
        .limit(limit)
    )
    return list(result.scalars().all())


async def mark_update_read(
    db: AsyncSession,
    update_id: str,
    graph_id: str,
) -> ResearchUpdate | None:
    result = await db.execute(
        select(ResearchUpdate).where(
            ResearchUpdate.id == update_id,
            ResearchUpdate.monitored_graph_id == graph_id,
        )
    )
    update = result.scalar_one_or_none()
    if update is None:
        return None
    update.is_read = True
    await db.commit()
    await db.refresh(update)
    return update


async def mark_update_added(
    db: AsyncSession,
    update_id: str,
    graph_id: str,
) -> ResearchUpdate | None:
    result = await db.execute(
        select(ResearchUpdate).where(
            ResearchUpdate.id == update_id,
            ResearchUpdate.monitored_graph_id == graph_id,
        )
    )
    update = result.scalar_one_or_none()
    if update is None:
        return None
    update.is_added_to_graph = True
    await db.commit()
    await db.refresh(update)
    return update


async def upsert_device_token(
    db: AsyncSession,
    user_id: str,
    token: str,
    platform: str,
) -> DeviceToken:
    result = await db.execute(
        select(DeviceToken).where(DeviceToken.fcm_token == token)
    )
    device = result.scalar_one_or_none()
    now = utc_now()
    if device is None:
        device = DeviceToken(
            id=_new_id("device"),
            user_id=user_id,
            fcm_token=token,
            platform=platform,
            last_seen_at=now,
            is_active=True,
        )
        db.add(device)
    else:
        device.user_id = user_id
        device.platform = platform
        device.last_seen_at = now
        device.is_active = True
    await db.commit()
    await db.refresh(device)
    return device


async def deactivate_device_token(
    db: AsyncSession,
    user_id: str,
    token: str,
) -> bool:
    result = await db.execute(
        select(DeviceToken).where(
            DeviceToken.user_id == user_id,
            DeviceToken.fcm_token == token,
        )
    )
    device = result.scalar_one_or_none()
    if device is None:
        return False
    device.is_active = False
    device.last_seen_at = datetime.now(timezone.utc)
    await db.commit()
    return True


async def list_active_device_tokens(
    db: AsyncSession,
    user_id: str,
) -> list[DeviceToken]:
    result = await db.execute(
        select(DeviceToken)
        .where(
            DeviceToken.user_id == user_id,
            DeviceToken.is_active.is_(True),
        )
        .order_by(DeviceToken.last_seen_at.desc())
    )
    return list(result.scalars().all())