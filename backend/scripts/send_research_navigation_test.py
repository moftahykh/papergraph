from __future__ import annotations

import asyncio
import os

from app.db.session import SessionLocal
from app.notifications.fcm import send_research_navigation_test


CONFIRMATION = "I_UNDERSTAND_SEND_ONE_GRAPH_TEST"


async def run() -> int:
    local_graph_id = os.getenv("LOCAL_GRAPH_ID", "").strip()
    if not local_graph_id:
        raise SystemExit("Set LOCAL_GRAPH_ID to a real monitored graph ID.")
    if os.getenv("CONFIRM_FCM_GRAPH_TEST") != CONFIRMATION:
        raise SystemExit(
            "Refusing to send. Set "
            f"CONFIRM_FCM_GRAPH_TEST={CONFIRMATION}"
        )

    async with SessionLocal() as db:
        sent, graph_title, latest_update_title = await send_research_navigation_test(
            db,
            local_graph_id=local_graph_id,
            confirmation=CONFIRMATION,
        )

    print(
        "Navigation test sent="
        f"{sent} graph={graph_title!r} latest_update={latest_update_title!r}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(run()))
