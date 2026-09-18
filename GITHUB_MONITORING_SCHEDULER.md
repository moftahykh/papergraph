# GitHub Actions Monitoring Scheduler

Render Free does not provide Shell, One-Off Jobs, or a production Cron worker for
this service. The repository therefore includes:

```text
.github/workflows/research-monitoring-scan.yml
```

It runs at the start of every hour, applies pending Alembic migrations, and runs:

```text
python -m app.workers.monitoring_worker --once
```

The worker still selects only active graphs whose `next_check_at` is due, so the
hourly workflow does not scan every graph every hour.

## Required GitHub Actions secrets

Add these under the repository's **Settings → Secrets and variables → Actions**:

| Secret | Value |
|---|---|
| `RESEARCH_MONITORING_DATABASE_URL` | Render **External Database URL** |
| `FIREBASE_PROJECT_ID` | `papergraph-cb9c3` |
| `SEMANTIC_SCHOLAR_API_KEYS` | Existing Semantic Scholar key pool, if used |
| `CROSSREF_MAILTO` | Existing Crossref contact email |
| `OPENALEX_MAILTO` | Existing OpenAlex contact email |

Never commit the database URL or provider keys. Never print them in workflow
logs. The workflow also supports manual execution through **Run workflow**.
