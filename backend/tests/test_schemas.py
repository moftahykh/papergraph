import pytest
from pydantic import ValidationError
from app.models.enums import (
    GraphJobStatus,
    MetricAvailability,
    EdgeType,
    ConfidenceLevel,
)
from app.models.metric import MetricResult
from app.models.canonical_paper import Author, CanonicalPaper, SourceAvailability
from app.models.graph import (
    GraphNode,
    GraphEdge,
    GraphWarning,
    DataCompleteness,
    GraphOrigin,
    GraphSnapshot,
    GraphJob,
)
from app.schemas.search import SearchRequest, SearchResponse, SearchResultItem
from app.schemas.resolve import PaperResolveRequest, PaperResolveResponse
from app.schemas.graph import CreateGraphRequest, CreateGraphResponse, GraphStatusResponse
from app.schemas.paper_details import PaperDetailsResponse


# ==============================================================================
# 1. MetricResult Tests: Null vs Zero Distinction (Rule #6 & Acceptance Criteria)
# ==============================================================================

def test_metric_result_distinguishes_null_from_zero():
    """Verify that null metrics are distinguishable from zero metrics."""
    zero_metric = MetricResult(
        value=0.0,
        availability=MetricAvailability.AVAILABLE,
        reason="evaluated_no_overlap",
    )
    assert zero_metric.value == 0.0
    assert zero_metric.availability == "available"
    assert zero_metric.value is not None

    null_metric = MetricResult(
        value=None,
        availability=MetricAvailability.UNAVAILABLE,
        reason="references_not_loaded",
    )
    assert null_metric.value is None
    assert null_metric.availability == "unavailable"
    assert null_metric.reason == "references_not_loaded"

    # Ensure zero != None
    assert zero_metric.value != null_metric.value


def test_metric_result_provider_error_state():
    error_metric = MetricResult(
        value=None,
        availability=MetricAvailability.PROVIDER_ERROR,
        reason="upstream_timeout_504",
    )
    assert error_metric.availability == "provider_error"
    assert error_metric.value is None


# ==============================================================================
# 2. CanonicalPaper Normalization & Validation
# ==============================================================================

def test_canonical_paper_clean_doi():
    """Verify DOI normalization removes URL prefixes."""
    paper = CanonicalPaper(
        canonical_id="doi:10.1038/nature12373",
        doi="https://doi.org/10.1038/nature12373",
        title="Sample Nature Paper",
        normalized_title="sample nature paper",
        authors=[Author(name="Author One", position=1)],
        year=2021,
        citation_count=10,
    )
    assert paper.doi == "10.1038/nature12373"
    assert paper.canonical_id == "doi:10.1038/nature12373"
    assert paper.completeness == 0.0


def test_canonical_paper_validation_failures():
    """Verify validation rejects missing required fields and negative citations."""
    with pytest.raises(ValidationError):
        CanonicalPaper(
            canonical_id="doi:123",
            title="",  # min_length=1
            normalized_title="",
        )

    with pytest.raises(ValidationError):
        CanonicalPaper(
            canonical_id="doi:123",
            title="Valid Title",
            normalized_title="valid title",
            citation_count=-5,  # ge=0
        )


# ==============================================================================
# 3. GraphEdge Validation: Directional Citations vs Undirected Similarity (Rule #9)
# ==============================================================================

def test_graph_edge_similarity_cannot_be_directed():
    """Rule #9: Similarity edges must be non-directional and never rendered as arrows."""
    # Valid similarity edge
    edge = GraphEdge(
        source="node_a",
        target="node_b",
        type=EdgeType.SIMILARITY,
        weight=0.85,
        directed=False,
    )
    assert edge.type == "similarity"
    assert edge.directed is False

    # Attempting directed=True for similarity must raise a validation error
    with pytest.raises(ValidationError):
        GraphEdge(
            source="node_a",
            target="node_b",
            type=EdgeType.SIMILARITY,
            weight=0.85,
            directed=True,
        )


def test_graph_edge_citation_is_directed():
    """Citation edges represent directional relationships."""
    edge = GraphEdge(
        source="node_a",
        target="node_b",
        type=EdgeType.CITATION,
        weight=1.0,
        directed=True,
    )
    assert edge.type == "citation"
    assert edge.directed is True


# ==============================================================================
# 4. GraphJobStatus 16 Exact Lifecycle States
# ==============================================================================

def test_all_16_graph_job_statuses_exist():
    expected_statuses = [
        "queued",
        "resolving_origin",
        "generating_candidates",
        "pre_ranking",
        "enriching_metadata",
        "enriching_references",
        "computing_wbc",
        "enriching_citations",
        "computing_ncc",
        "computing_final_scores",
        "extracting_prior_works",
        "extracting_derivative_works",
        "building_layout",
        "completed",
        "partial",
        "failed",
    ]
    actual_statuses = [s.value for s in GraphJobStatus]
    assert actual_statuses == expected_statuses


# ==============================================================================
# 5. GraphSnapshot & Partial Graph Payload with Warnings
# ==============================================================================

def test_partial_graph_snapshot_payload():
    """Verify partial graph payload includes warnings and data completeness."""
    warning = GraphWarning(
        code="ncc_unavailable",
        message="Inbound citation data was unavailable for some papers.",
        severity="warning",
    )
    completeness = DataCompleteness(
        metadata=1.0,
        references=0.86,
        citations=0.42,
        semantic=0.91,
    )
    origin = GraphOrigin(
        id="doi:10.1186/s12879-017-2746-5",
        canonical_id="doi:10.1186/s12879-017-2746-5",
        title="Seed Clinical Paper",
        year=2017,
    )
    node = GraphNode(
        id="doi:10.1186/s12879-017-2746-5",
        canonical_id="doi:10.1186/s12879-017-2746-5",
        title="Seed Clinical Paper",
        citation_count=55,
        is_origin=True,
        radius=20.0,
        final_score=1.0,
        confidence=ConfidenceLevel.HIGH,
    )
    snapshot = GraphSnapshot(
        graph_id="graph_test_123",
        origin=origin,
        status=GraphJobStatus.PARTIAL,
        nodes=[node],
        similarity_edges=[],
        citation_edges=[],
        data_completeness=completeness,
        warnings=[warning],
    )

    assert snapshot.status == "partial"
    assert len(snapshot.warnings) == 1
    assert snapshot.warnings[0].code == "ncc_unavailable"
    assert snapshot.data_completeness.citations == 0.42


# ==============================================================================
# 6. API Request / Response Schemas Validation
# ==============================================================================

def test_search_schemas():
    req = SearchRequest(query="distributed consensus", limit=20, offset=0)
    assert req.query == "distributed consensus"

    with pytest.raises(ValidationError):
        SearchRequest(query="a", limit=10)  # min_length=2

    res = SearchResponse(
        query="distributed consensus",
        total=1,
        items=[
            SearchResultItem(
                canonical_id="doi:10.1145/1",
                title="Consensus in the Presence of Faults",
                authors=["Leslie Lamport"],
                year=1982,
                citation_count=4500,
            )
        ],
    )
    assert res.total == 1
    assert len(res.items) == 1


def test_resolve_schemas():
    req = PaperResolveRequest(identifier="10.1038/nature12373")
    assert req.identifier == "10.1038/nature12373"

    paper = CanonicalPaper(
        canonical_id="doi:10.1038/nature12373",
        title="Resolved Title",
        normalized_title="resolved title",
        citation_count=20,
    )
    res = PaperResolveResponse(
        resolved=True,
        paper=paper,
        confidence=0.98,
    )
    assert res.resolved is True
    assert res.paper.title == "Resolved Title"


def test_create_graph_request_validation():
    req = CreateGraphRequest(origin_id="doi:10.1038/nature12373", max_nodes=50)
    assert req.max_nodes == 50

    with pytest.raises(ValidationError):
        CreateGraphRequest(origin_id="doi:123", max_nodes=5)  # ge=10

    with pytest.raises(ValidationError):
        CreateGraphRequest(origin_id="doi:123", max_nodes=100)  # le=75


def test_graph_status_polling_response():
    res = GraphStatusResponse(
        graph_id="graph_job_abc",
        status=GraphJobStatus.COMPUTING_WBC,
        progress=0.45,
        current_stage=GraphJobStatus.COMPUTING_WBC,
        poll_url="/api/v1/graphs/graph_job_abc",
    )
    assert res.status == "computing_wbc"
    assert res.progress == 0.45
    assert res.snapshot is None
