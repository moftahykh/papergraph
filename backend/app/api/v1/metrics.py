from fastapi import APIRouter
from app.core.metrics import metrics, MetricsResponse

router = APIRouter(tags=["Observability"])


@router.get("/metrics", response_model=MetricsResponse)
async def get_system_metrics() -> MetricsResponse:
    """
    Returns real-time system observability metrics:
      - provider latency summaries
      - provider error counts
      - HTTP 429 counts
      - cache hit ratios
      - graph job duration statistics
      - candidate pool size distributions
      - enrichment completeness statistics
      - ranking confidence distribution
      - system uptime
    """
    return metrics.get_metrics()
