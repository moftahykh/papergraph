import os
import re
import pytest
from httpx import AsyncClient, ASGITransport
from app.main import app
from app.core.config import settings
from app.core.rate_limiter import rate_limiter
from app.core.metrics import metrics


@pytest.fixture(autouse=True)
def reset_traffic_guards():
    """Resets rate limiter and metrics counters before each test."""
    rate_limiter.reset()
    metrics.reset()
    yield
    rate_limiter.reset()
    metrics.reset()


@pytest.mark.asyncio
async def test_request_size_limit_triggers_413():
    """Requests exceeding MAX_REQUEST_BODY_BYTES are rejected with HTTP 413 Payload Too Large."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # Construct large payload exceeding 2MB limit (e.g. 2.5MB string)
        huge_origin = "doi:10.1000/" + ("x" * (2 * 1024 * 1024 + 500))
        headers = {"content-length": str(len(huge_origin))}

        response = await client.post(
            f"{settings.API_V1_STR}/graphs",
            content=huge_origin,
            headers=headers,
        )

        assert response.status_code == 413
        data = response.json()
        assert "error" in data
        assert data["error"]["code"] == "PAYLOAD_TOO_LARGE"


@pytest.mark.asyncio
async def test_rate_limiter_triggers_429():
    """Excessive request burst triggers HTTP 429 Too Many Requests with Retry-After header."""
    transport = ASGITransport(app=app)
    # Temporarily set limit to 5 req/min for testing
    rate_limiter.requests_per_minute = 5
    
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # First 5 requests should pass
        for i in range(5):
            res = await client.get(f"{settings.API_V1_STR}/search?query=quantum")
            assert res.status_code == 200

        # 6th request must trigger 429
        res_blocked = await client.get(f"{settings.API_V1_STR}/search?query=quantum")
        assert res_blocked.status_code == 429
        assert "Retry-After" in res_blocked.headers
        data = res_blocked.json()
        assert data["error"]["code"] == "RATE_LIMIT_EXCEEDED"

    # Restore default limit
    rate_limiter.requests_per_minute = settings.RATE_LIMIT_PER_MINUTE


@pytest.mark.asyncio
async def test_observability_metrics_endpoint():
    """GET /api/v1/metrics returns structured observability metrics."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get(f"{settings.API_V1_STR}/metrics")
        assert response.status_code == 200
        data = response.json()
        assert "provider_latency" in data
        assert "provider_errors" in data
        assert "http_429_counts" in data
        assert "cache_metrics" in data
        assert "graph_job_duration" in data
        assert "candidate_pool_size" in data
        assert "enrichment_completeness" in data
        assert "ranking_confidence_distribution" in data
        assert "system_uptime_seconds" in data


@pytest.mark.asyncio
async def test_input_validation_bounds():
    """Unbounded or malformed queries fail fast with HTTP 422."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # Search query too short (min_length=2)
        res_short = await client.get(f"{settings.API_V1_STR}/search?query=a")
        assert res_short.status_code == 422

        # Search query too long (max_length=500)
        res_long = await client.get(f"{settings.API_V1_STR}/search?query={'a' * 505}")
        assert res_long.status_code == 422

        # Create graph request with invalid max_nodes
        res_bad_nodes = await client.post(
            f"{settings.API_V1_STR}/graphs",
            json={"origin_id": "10.1038/test", "max_nodes": 500},
        )
        assert res_bad_nodes.status_code == 422


def test_flutter_client_contains_zero_provider_secrets_and_urls():
    """
    Architecture Rule #1 & #2:
      - Flutter communicates ONLY with the PaperGraph FastAPI gateway.
      - NEVER place Semantic Scholar, OpenAlex, Crossref, or PubMed API calls or keys in Flutter.
    """
    flutter_lib_dir = os.path.abspath(
        os.path.join(os.path.dirname(__file__), "..", "..", "flutter_app", "lib")
    )
    assert os.path.isdir(flutter_lib_dir), f"Flutter lib directory not found: {flutter_lib_dir}"

    forbidden_provider_urls = [
        "api.semanticscholar.org",
        "api.openalex.org",
        "api.crossref.org",
        "eutils.ncbi.nlm.nih.gov",
    ]

    suspicious_key_patterns = [
        r"s2_api_key",
        r"openalex_key",
        r"crossref_key",
        r"ncbi_api_key",
        r"AIzaSy[a-zA-Z0-9_-]{33}",
    ]

    for root, _, files in os.walk(flutter_lib_dir):
        for file in files:
            if file.endswith(".dart"):
                file_path = os.path.join(root, file)
                with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
                    content = f.read()
                    
                    # Verify no direct third-party provider URLs
                    for url in forbidden_provider_urls:
                        assert url not in content, (
                            f"Violation of Rule #2: Found direct provider URL '{url}' in {file_path}"
                        )
                    
                    # Verify no provider secrets or API keys
                    for pattern in suspicious_key_patterns:
                        match = re.search(pattern, content, re.IGNORECASE)
                        assert not match, (
                            f"Security Violation: Found hardcoded secret pattern '{pattern}' in {file_path}"
                        )
