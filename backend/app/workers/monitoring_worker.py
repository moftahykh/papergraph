from __future__ import annotations

import argparse
import asyncio
import logging

from app.db.session import SessionLocal
from app.monitoring.scanner import MonitoringScanner
from app.notifications.fcm import send_research_update_notifications
from app.models.monitoring import utc_now
from app.providers.crossref import CrossRefProvider
from app.providers.openalex import OpenAlexProvider
from app.providers.semantic_scholar import SemanticScholarProvider
from app.repositories.monitoring import (
    claim_due_monitored_graph,
    complete_monitored_graph_scan,
    release_monitored_graph_claim,
)

logger = logging.getLogger("papergraph.workers.monitoring")


def build_scanner() -> MonitoringScanner:
    return MonitoringScanner(
        semantic_scholar=SemanticScholarProvider(),
        openalex=OpenAlexProvider(),
        crossref=CrossRefProvider(),
    )


async def run_once(max_graphs: int = 20) -> int:
    """Scan due graphs once; intended for cron or a separate worker process."""
    scanner = build_scanner()
    processed = 0

    async with SessionLocal() as db:
        while processed < max_graphs:
            graph = await claim_due_monitored_graph(db)
            if graph is None:
                break

            try:
                result = await scanner.scan_graph(db, graph)
                delivered = await send_research_update_notifications(
                    db,
                    graph,
                    result.updates_created,
                )
                if delivered:
                    graph.last_notified_at = utc_now()
                await complete_monitored_graph_scan(db, graph)
                processed += 1
                logger.info(
                    "Scanned graph %s: candidates=%d updates_created=%d provider_errors=%d",
                    result.graph_id,
                    result.candidates_seen,
                    result.updates_created,
                    len(result.provider_errors),
                )
                if delivered:
                    logger.info(
                        "Delivered research update notification to %d device(s) for graph %s.",
                        delivered,
                        result.graph_id,
                    )
            except Exception:
                await db.rollback()
                await release_monitored_graph_claim(db, graph)
                logger.exception("Monitoring scan failed for graph %s", graph.id)

    return processed


def main() -> int:
    parser = argparse.ArgumentParser(description="Run due PaperGraph monitoring scans.")
    parser.add_argument(
        "--once",
        action="store_true",
        help="Run one bounded scan pass and exit.",
    )
    parser.add_argument(
        "--max-graphs",
        type=int,
        default=20,
        help="Maximum graphs to scan in one pass (default: 20).",
    )
    args = parser.parse_args()

    if not args.once:
        parser.error("Only --once is supported until a production scheduler is configured.")

    asyncio.run(run_once(max_graphs=max(1, args.max_graphs)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())