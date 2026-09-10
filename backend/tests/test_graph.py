import pytest
import math
from app.models.canonical_paper import CanonicalPaper, Author
from app.models.enums import EdgeType, GraphJobStatus, ConfidenceLevel
from app.models.graph import GraphEdge, GraphWarning, DataCompleteness
from app.ranking.models import RankedCandidate, RankingResult, ScoreBreakdown
from app.graph.mmr import select_diverse_nodes_mmr, compute_pairwise_similarity
from app.graph.edges import synthesize_citation_edges, synthesize_similarity_edges
from app.graph.layout import generate_graph_layout, compute_node_radius
from app.graph.synthesizer import GraphSynthesizer


@pytest.fixture
def sample_origin():
    return CanonicalPaper(
        canonical_id="doi:10.1038/nature_origin",
        doi="10.1038/nature_origin",
        semantic_scholar_id="s2_origin",
        title="Deep Reinforcement Learning in Graph Synthesis",
        authors=[Author(name="Demis Hassabis", position=1)],
        year=2020,
        venue="Nature",
        citation_count=1200,
        reference_ids=["doi:10.1038/ref_alpha", "doi:10.1038/ref_beta", "doi:10.1038/ref_gamma"],
        citation_ids=["doi:10.1038/deriv_1", "doi:10.1038/deriv_2"],
        completeness=1.0,
    )


@pytest.fixture
def sample_ranked_pool():
    """Generates 45 ranked candidates with various citation links, topics, and archetypes."""
    candidates = []
    for i in range(45):
        cid = f"doi:10.1000/paper_{i}"
        
        # Make some papers prior works (cited by origin and candidates)
        if i < 8:
            refs = [f"doi:10.1000/fund_{k}" for k in range(3)]
            cites = ["doi:10.1038/nature_origin", f"doi:10.1000/paper_{i+1}"]
            arch = "prior_work"
            year = 2017
        # Make some papers derivative works (citing origin)
        elif i < 16:
            refs = ["doi:10.1038/nature_origin", "doi:10.1038/ref_alpha"]
            cites = []
            arch = "derivative_work"
            year = 2022
        else:
            refs = ["doi:10.1038/ref_beta"] if i % 2 == 0 else []
            cites = []
            arch = "similar"
            year = 2021

        paper = CanonicalPaper(
            canonical_id=cid,
            doi=cid,
            title=f"Paper Title on Neural Discovery {i}",
            year=year,
            venue="ICLR",
            citation_count=50 + (i * 20),
            reference_ids=refs,
            citation_ids=cites,
            topics=["Machine Learning", "Graph Theory"] if i % 2 == 0 else ["Optimization"],
        )

        cand = RankedCandidate(
            paper=paper,
            final_score=round(0.95 - (i * 0.015), 4),
            confidence=ConfidenceLevel.HIGH,
            score_breakdown=ScoreBreakdown(),
            prior_score=0.60 if arch == "prior_work" else 0.10,
            derivative_score=0.55 if arch == "derivative_work" else 0.05,
            archetype=arch,
            rank=i + 1,
        )
        candidates.append(cand)
    return candidates


# ==============================================================================
# 1. Acceptance Test #1: Non-Negotiable Rule #9 (Strict Edge Separation)
# ==============================================================================

def test_strict_edge_differentiation_citation_vs_similarity(sample_origin, sample_ranked_pool):
    """
    Acceptance Criteria:
      - A similarity edge cannot be mistaken for a citation edge.
      - Citation edges are directional (directed=True, type=citation).
      - Similarity edges are non-directional (directed=False, type=similarity).
      - Model validation strictly prevents directed similarity edges.
    """
    synthesizer = GraphSynthesizer()
    ranking_res = RankingResult(origin=sample_origin, ranked_candidates=sample_ranked_pool)
    snapshot = synthesizer.synthesize_snapshot(sample_origin, ranking_res)

    # 1. Verify Citation Edges
    assert len(snapshot.citation_edges) > 0
    for edge in snapshot.citation_edges:
        assert edge.type == EdgeType.CITATION
        assert edge.directed is True

    # 2. Verify Similarity Edges
    assert len(snapshot.similarity_edges) > 0
    for edge in snapshot.similarity_edges:
        assert edge.type == EdgeType.SIMILARITY
        assert edge.directed is False  # CRITICAL: Never rendered as arrows

    # 3. Verify Model Constraint: Setting directed=True on similarity edge raises ValueError
    with pytest.raises(ValueError, match="Similarity edges are non-directional"):
        GraphEdge(
            source="doi:1",
            target="doi:2",
            type=EdgeType.SIMILARITY,
            directed=True,  # VIOLATION
        )


# ==============================================================================
# 2. Acceptance Test #2: No Duplicate Nodes or Self-Edges
# ==============================================================================

def test_no_duplicate_nodes_or_self_edges(sample_origin, sample_ranked_pool):
    """
    Acceptance Criteria:
      - Graph includes no duplicate nodes.
      - Graph includes no self-edges (source != target) in citation or similarity edges.
    """
    synthesizer = GraphSynthesizer()
    ranking_res = RankingResult(origin=sample_origin, ranked_candidates=sample_ranked_pool)
    snapshot = synthesizer.synthesize_snapshot(sample_origin, ranking_res)

    # Check unique nodes
    node_ids = [n.id for n in snapshot.nodes]
    assert len(node_ids) == len(set(node_ids))

    # Check no self-edges in citation edges
    for e in snapshot.citation_edges:
        assert e.source != e.target, f"Self-edge detected in citation edges: {e.source}"

    # Check no self-edges in similarity edges
    for e in snapshot.similarity_edges:
        assert e.source != e.target, f"Self-edge detected in similarity edges: {e.source}"


# ==============================================================================
# 3. Acceptance Test #3: MMR Diversity Selection
# ==============================================================================

def test_mmr_selects_diverse_nodes_over_redundant_clones(sample_origin):
    """
    Acceptance Criteria: MMR penalizes near-identical high-scoring clones and
    ensures conceptual/topological diversity in final selected nodes.
    """
    candidates = []

    # Clone group: 10 papers with near-identical references and topics (high score 0.90)
    for i in range(10):
        paper = CanonicalPaper(
            canonical_id=f"doi:10.1000/clone_{i}",
            doi=f"10.1000/clone_{i}",
            title=f"Clone Work {i}",
            year=2021,
            reference_ids=["shared_ref_1", "shared_ref_2", "shared_ref_3"],
            topics=["Neural Networks", "Deep Learning"],
        )
        candidates.append(
            RankedCandidate(
                paper=paper,
                final_score=0.90,
                confidence=ConfidenceLevel.HIGH,
                score_breakdown=ScoreBreakdown(),
            )
        )

    # Diverse group: 10 papers with distinct topics and different references (score 0.85)
    for i in range(10):
        paper = CanonicalPaper(
            canonical_id=f"doi:10.1000/diverse_{i}",
            doi=f"10.1000/diverse_{i}",
            title=f"Diverse Field Work {i}",
            year=2021,
            reference_ids=[f"unique_ref_{i}"],
            topics=[f"Field_{i}"],
        )
        candidates.append(
            RankedCandidate(
                paper=paper,
                final_score=0.85,
                confidence=ConfidenceLevel.HIGH,
                score_breakdown=ScoreBreakdown(),
            )
        )

    # Select 6 nodes using MMR
    selected = select_diverse_nodes_mmr(
        origin=sample_origin,
        ranked_candidates=candidates,
        max_nodes=6,
        lambda_param=0.70,
    )

    selected_cids = [c.paper.canonical_id for c in selected]
    diverse_picked = [cid for cid in selected_cids if "diverse_" in cid]

    # Without MMR, top 6 would be all 6 clones. With MMR, diverse papers are chosen!
    assert len(diverse_picked) >= 2


# ==============================================================================
# 4. Acceptance Test #4: 2D Layout Stability and Bounding
# ==============================================================================

def test_layout_coordinates_finite_and_bounds_stable(sample_origin, sample_ranked_pool):
    """
    Acceptance Criteria:
      - Origin node placed at (0.0, 0.0) with is_origin=True.
      - All (x, y) coordinates are finite floats (no NaN, no Inf).
      - Node radii are in [8.0, 32.0].
      - Prior works positioned on the left (x < 0).
      - Derivative works positioned on the right (x > 0).
    """
    synthesizer = GraphSynthesizer()
    ranking_res = RankingResult(origin=sample_origin, ranked_candidates=sample_ranked_pool)
    snapshot = synthesizer.synthesize_snapshot(sample_origin, ranking_res)

    origin_node = next(n for n in snapshot.nodes if n.is_origin)
    assert origin_node.x == 0.0
    assert origin_node.y == 0.0
    assert origin_node.radius == 24.0

    for n in snapshot.nodes:
        assert not math.isnan(n.x)
        assert not math.isinf(n.x)
        assert not math.isnan(n.y)
        assert not math.isinf(n.y)
        assert 8.0 <= n.radius <= 32.0

        if n.archetype == "prior_work":
            assert n.x < 0.0, f"Prior work {n.id} should be on the left quadrant (x < 0)"
        elif n.archetype == "derivative_work":
            assert n.x > 0.0, f"Derivative work {n.id} should be on the right quadrant (x > 0)"


# ==============================================================================
# 5. Acceptance Test #5: Partial Data and Warnings
# ==============================================================================

def test_graph_snapshot_preserves_partial_state_and_warnings(sample_origin, sample_ranked_pool):
    """
    Acceptance Criteria:
      - Partial graph data correctly sets status=PARTIAL.
      - Warnings are preserved in snapshot.
      - Data completeness ratios are preserved.
    """
    synthesizer = GraphSynthesizer()
    ranking_res = RankingResult(origin=sample_origin, ranked_candidates=sample_ranked_pool)

    warnings = [
        GraphWarning(
            code="provider_timeout",
            message="OpenAlex timed out during citation enrichment",
            severity="warning",
        )
    ]
    completeness = DataCompleteness(
        metadata=0.95,
        references=0.85,
        citations=0.50,  # Low citation completeness
        semantic=0.80,
    )

    snapshot = synthesizer.synthesize_snapshot(
        origin=sample_origin,
        ranking_result=ranking_res,
        data_completeness=completeness,
        warnings=warnings,
    )

    assert snapshot.status == GraphJobStatus.PARTIAL
    assert len(snapshot.warnings) == 1
    assert snapshot.warnings[0].code == "provider_timeout"
    assert snapshot.data_completeness.citations == 0.50
