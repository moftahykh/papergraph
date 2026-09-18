# PaperGraph Research Monitoring — Phase 2

## Implemented

- Added a PostgreSQL scan claim timestamp and Alembic migration `0002_monitoring_scan_claim`.
- Added `MonitoringScanner` under `backend/app/monitoring/scanner.py`.
- Scans active monitored graphs that are due.
- Uses existing Semantic Scholar and OpenAlex relationship APIs for citations/recommendations.
- Uses existing Crossref provider to enrich DOI metadata when available.
- Deduplicates by DOI, provider IDs, and normalized title aliases.
- Excludes papers already present in the saved graph.
- Persists deterministic `ResearchUpdate` records with score, relation type, and explanation.
- Avoids duplicate updates on repeated scans.
- Added stale claim recovery for a worker that crashes.
- Added one-shot worker entry point:

```powershell
.\\.venv\\Scripts\\python.exe -m app.workers.monitoring_worker --once
```

## Not implemented intentionally

- FCM runtime handling.
- Push notifications.
- Automatic graph mutation.
- FastAPI in-process scheduler.
- Production cron/worker deployment configuration.

## Verification in this workspace

- Python `compileall`: passed.
- Full pytest execution was not available in this sandbox because `pytest`, `httpx`, and the project runtime dependencies are not installed here.

Run on Windows after applying migration:

```powershell
cd "C:\\Users\\hp\\AndroidStudioProjects\\Flutter Pro\\backend"
.\\.venv\\Scripts\\python.exe -m alembic upgrade head
.\\.venv\\Scripts\\python.exe -m pytest -q
.\\.venv\\Scripts\\python.exe -m app.workers.monitoring_worker --once
```

The worker calls real providers for due graphs, so run it only after confirming the local backend environment and provider configuration are ready.
