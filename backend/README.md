FastAPI multi-provider academic discovery engine: search/resolve/graph endpoints, providers for Semantic Scholar + OpenAlex + Crossref + PubMed.

Run locally from `backend/`:

```powershell
.\.venv\Scripts\python.exe -m uvicorn app.main:app --reload
```

Run tests:

```powershell
.\.venv\Scripts\python.exe -m pytest -q
```

Run one bounded Research Monitoring scan pass:

```powershell
.\.venv\Scripts\python.exe -m app.workers.monitoring_worker --once
```

The worker scans due active graphs, persists deduplicated research updates, and
exits. It is intentionally separate from the FastAPI web process.

Run the authenticated Research Monitoring smoke test after starting the backend and applying migrations:

```powershell
$env:PAPERGRAPH_FIREBASE_ID_TOKEN = "<temporary Firebase ID token>"
.\.venv\Scripts\python.exe scripts\monitoring_smoke_test.py
```

The smoke test creates a temporary monitored graph, verifies list/pause/resume/updates, and deletes it during cleanup. It requires a valid Firebase ID token; it does not disable authentication.
