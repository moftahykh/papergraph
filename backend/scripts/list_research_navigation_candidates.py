from __future__ import annotations

import asyncio

from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.db.session import SessionLocal
from app.models.monitoring import MonitoredGraph
from app.repositories.monitoring import list_active_device_tokens


async def run() -> int:
    async with SessionLocal() as db:
        result = await db.execute(
            select(MonitoredGraph)
            .options(selectinload(MonitoredGraph.updates))
            .where(MonitoredGraph.status == "active")
            .order_by(MonitoredGraph.updated_at.desc())
        )
        graphs = list(result.scalars().unique().all())
        printed = 0
        for graph in graphs:
            devices = await list_active_device_tokens(db, graph.user_id)
            if not graph.updates or not devices:
                continue
            latest = max(graph.updates, key=lambda item: item.detected_at)
            print(
                f"LOCAL_GRAPH_ID={graph.local_graph_id} | "
                f"title={graph.graph_title!r} | "
                f"updates={len(graph.updates)} | "
                f"latest_update={latest.title!r} | "
                f"latest_device_seen={devices[0].last_seen_at.isoformat()}"
            )
            printed += 1

    if printed == 0:
        print(
            "No eligible graphs found. A graph must be active, have a persisted "
            "research update, and have an active device token."
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(run()))
