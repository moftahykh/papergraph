from __future__ import annotations

import asyncio
import os
from datetime import timezone, datetime

from sqlalchemy import select

from app.db.session import SessionLocal
from app.models.monitoring import MonitoredGraph


async def run() -> int:
    local_graph_id = os.getenv("LOCAL_GRAPH_ID", "").strip()
    if not local_graph_id:
        raise SystemExit("Set LOCAL_GRAPH_ID to an existing monitored graph ID.")

    async with SessionLocal() as db:
        result = await db.execute(
            select(MonitoredGraph).where(
                MonitoredGraph.local_graph_id == local_graph_id,
            )
        )
        graph = result.scalar_one_or_none()
        if graph is None:
            raise SystemExit(f"No monitored graph found for {local_graph_id}.")
        if graph.status != "active":
            raise SystemExit(
                f"Graph {local_graph_id} is {graph.status}; resume it before testing."
            )
        graph.next_check_at = datetime.now(timezone.utc)
        await db.commit()
        print(f"Graph is due for a targeted scan: {graph.graph_title!r}")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(run()))
