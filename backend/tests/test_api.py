import pytest
import asyncio
from unittest.mock import AsyncMock, patch
from starlette.testclient import TestClient
from app.main import app
from app.models.canonical_paper import CanonicalPaper, Author
from app.providers.models import RawPaper, Page
from app.workers.job_manager import GraphJobManager

client = TestClient(app)


# ==============================================================================
# 1. Health & Documentation Endpoints
# ==============================================================================

def test_health_endpoints():
    """Verifies health check and root endpoints."""
    res_root = client.get("/health")
    assert res_root.status_code == 200
    assert res_root.json()["status"] == "ok"

    res_v1 = client.get("/api/v1/health")
    assert res_v1.status_code == 200
    assert res_v1.json()["status"] == "ok"


def test_openapi_documentation_accessible():
    """Acceptance Criteria: OpenAPI documentation is accessible."""
    res = client.get("/api/v1/openapi.json")
    assert res.status_code == 200
    schema = res.json()
    assert "paths" in schema
    assert "/api/v1/search" in schema["paths"]
    assert "/api/v1/graphs" in schema["paths"]
    assert "/api/v1/papers/resolve" in schema["paths"]


# ==============================================================================
# 2. Search Endpoint (GET /api/v1/search)
# ==============================================================================

def test_search_literature_endpoint():
    """Verifies search endpoint with parameter validation and formatting."""
    # Invalid short query (min_length=2)
    res_bad = client.get("/api/v1/search?query=a")
    assert res_bad.status_code == 422

    # Mock provider search
    mock_raw = [
        RawPaper(
            provider="semantic_scholar",
            provider_id="s2_qc_1",
            doi="10.1038/s41586-019-1666-5",
            title="Quantum Computational Supremacy Using a Programmable Superconducting Processor",
            authors=[Author(name="John Martinis", position=1)],
            year=2019,
            venue="Nature",
            citation_count=4500,
        )
    ]
    with patch("app.api.v1.search.s2_provider.search", new=AsyncMock(return_value=mock_raw)):
        res = client.get("/api/v1/search?query=quantum+computing&limit=5")
        assert res.status_code == 200
        data = res.json()
        assert data["query"] == "quantum computing"
        assert len(data["items"]) == 1
        assert "Quantum Computational Supremacy" in data["items"][0]["title"]
        assert data["disambiguation_needed"] is False


# ==============================================================================
# 3. Paper Resolution (POST /api/v1/papers/resolve)
# ==============================================================================

def test_resolve_paper_endpoint():
    """Verifies paper resolve endpoint for identifiers."""
    mock_paper = RawPaper(
        provider="semantic_scholar",
        provider_id="s2_nature_12373",
        doi="10.1038/nature12373",
        title="A Distributed Consensus Protocol",
        authors=[Author(name="Leslie Lamport", position=1)],
        year=2020,
        citation_count=150,
    )

    with patch("app.api.v1.resolve.s2_provider.resolve", new=AsyncMock(return_value=mock_paper)):
        # Test valid resolution payload
        payload = {"identifier": "10.1038/nature12373"}
        res = client.post("/api/v1/papers/resolve", json=payload)
        assert res.status_code == 200
        data = res.json()
        assert data["resolved"] is True
        assert data["paper"]["canonical_id"] == "doi:10.1038/nature12373"
        assert data["confidence"] == 1.0

    # Test invalid short identifier
    res_invalid = client.post("/api/v1/papers/resolve", json={"identifier": "1"})
    assert res_invalid.status_code == 422


# ==============================================================================
# 4. Asynchronous Graph Creation & Idempotency (POST /api/v1/graphs)
# ==============================================================================

def test_create_graph_fast_dispatch_and_idempotency():
    """
    Acceptance Criteria:
      - POST /graphs returns HTTP 202 with job ID quickly.
      - Repeating the exact same request returns the same job ID (idempotency).
    """
    payload = {
        "origin_id": "doi:10.1038/nature_seed_99",
        "max_nodes": 40,
        "include_prior_works": True,
        "include_derivative_works": True,
        "weight_profile": "default",
        "algorithm_version": "v1.0",
    }

    # 1. Fast dispatch (HTTP 202 Accepted)
    res_1 = client.post("/api/v1/graphs", json=payload)
    assert res_1.status_code == 202
    data_1 = res_1.json()
    assert "graph_id" in data_1
    assert data_1["status"] in ("queued", "resolving_origin")
    assert data_1["poll_url"].startswith("/api/v1/graphs/graph_")

    job_id_1 = data_1["graph_id"]

    # 2. Repeated identical request -> Reuses identical job (Idempotency)
    res_2 = client.post("/api/v1/graphs", json=payload)
    assert res_2.status_code == 202
    data_2 = res_2.json()
    assert data_2["graph_id"] == job_id_1  # Exact match!


# ==============================================================================
# 5. Graph Polling (GET /api/v1/graphs/{id})
# ==============================================================================

def test_poll_graph_lifecycle_and_not_found():
    """
    Acceptance Criteria:
      - Polling exposes typed lifecycle states.
      - Polling unknown job ID returns HTTP 404 with structured error envelope.
    """
    # 1. Unknown graph ID returns 404
    res_404 = client.get("/api/v1/graphs/graph_unknown_99999")
    assert res_404.status_code == 404
    err_data = res_404.json()
    assert err_data["error_code"] == "RESOURCE_NOT_FOUND"
    assert "not found" in err_data["message"].lower()

    # 2. Poll existing job
    payload = {
        "origin_id": "doi:10.1038/nature_polling_test",
        "max_nodes": 30,
        "weight_profile": "default",
        "algorithm_version": "v1.0",
    }
    create_res = client.post("/api/v1/graphs", json=payload)
    assert create_res.status_code == 202
    graph_id = create_res.json()["graph_id"]

    poll_res = client.get(f"/api/v1/graphs/{graph_id}")
    assert poll_res.status_code == 200
    poll_data = poll_res.json()
    assert poll_data["graph_id"] == graph_id
    assert "status" in poll_data
    assert "progress" in poll_data
    assert "current_stage" in poll_data
    assert poll_data["poll_url"] == f"/api/v1/graphs/{graph_id}"


# ==============================================================================
# 6. On-Demand Paper Details (GET /api/v1/papers/{id}/details)
# ==============================================================================

def test_paper_details_endpoint():
    """Verifies on-demand paper details endpoint with BibTeX generation."""
    # Seed a known canonical paper into resolver
    manager = GraphJobManager.get_instance()
    test_paper = CanonicalPaper(
        canonical_id="doi:10.1145/357172.357176",
        doi="10.1145/357172.357176",
        title="The Byzantine Generals Problem",
        authors=[Author(name="Leslie Lamport", position=1, affiliation="SRI International")],
        year=1982,
        venue="ACM TOPLAS",
        abstract="Reliable computer systems must handle malfunctioning components...",
        citation_count=8940,
        completeness=0.95,
    )
    manager.resolver.ingest(test_paper)

    res = client.get("/api/v1/papers/doi:10.1145/357172.357176/details")
    assert res.status_code == 200
    data = res.json()
    assert data["paper"]["canonical_id"] == "doi:10.1145/357172.357176"
    assert data["bibtex"] is not None
    assert "@article" in data["bibtex"]
    assert "Lamport" in data["bibtex"]
    assert "SRI International" in data["affiliations"]
    assert data["open_access_url"] == "https://doi.org/10.1145/357172.357176"

    # Non-existent paper returns 404
    res_404 = client.get("/api/v1/papers/non_existent_paper_999/details")
    assert res_404.status_code == 404
    assert res_404.json()["error_code"] == "RESOURCE_NOT_FOUND"


# ==============================================================================
# 7. Authorization Placeholder Tests
# ==============================================================================

def test_authorization_placeholder():
    """Verifies optional authorization dependency placeholder."""
    # 1. Anonymous request succeeds
    res_anon = client.get("/api/v1/search?query=consensus")
    assert res_anon.status_code == 200

    # 2. Bearer token request succeeds
    res_bearer = client.get(
        "/api/v1/search?query=consensus",
        headers={"Authorization": "Bearer sample_token_123"},
    )
    assert res_bearer.status_code == 200

    # 3. Invalid scheme fails with 401
    res_invalid = client.get(
        "/api/v1/search?query=consensus",
        headers={"Authorization": "Basic dXNlcjpwYXNz"},
    )
    assert res_invalid.status_code == 401
