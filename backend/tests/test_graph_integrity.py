from app.models.canonical_paper import CanonicalPaper
from app.models.enums import (
    ConfidenceLevel,
    EdgeType,
    MetricAvailability,
)
from app.models.metric import MetricResult
from app.candidates.models import CandidateRecord, CandidateSourceType
from app.enrichment.models import CandidateEnrichmentRecord
from app.graph.edges import synthesize_citation_edges
from app.graph.synthesizer import GraphSynthesizer, _bounded_candidates
from app.ranking.models import RankedCandidate, RankingResult, ScoreBreakdown


def _ranked(
    paper: CanonicalPaper,
    *,
    recommendation: bool = False,
    direct_reference: bool = False,
    direct_citation: bool = False,
    score: float = 0.8,
) -> RankedCandidate:
    record = CandidateRecord(
        paper=paper,
        sources=(
            {CandidateSourceType.RECOMMENDATION}
            if recommendation
            else {CandidateSourceType.REFERENCE}
        ),
        is_recommendation=recommendation,
        is_direct_reference=direct_reference,
        is_direct_citation=direct_citation,
        pre_score=score,
    )
    return RankedCandidate(
        paper=paper,
        candidate_record=record,
        final_score=score,
        confidence=ConfidenceLevel.MEDIUM,
        score_breakdown=ScoreBreakdown(),
    )


def test_citation_edges_normalize_doi_urls_and_prefixes():
    origin = CanonicalPaper(
        canonical_id="doi:10.1000/origin",
        doi="10.1000/origin",
        title="Origin",
        reference_ids=["https://doi.org/10.1000/older"],
    )
    older = CanonicalPaper(
        canonical_id="doi:10.1000/older",
        doi="10.1000/older",
        title="Older work",
    )

    edges = synthesize_citation_edges([origin, older])

    assert len(edges) == 1
    assert edges[0].source == origin.canonical_id
    assert edges[0].target == older.canonical_id
    assert edges[0].type == EdgeType.CITATION


def test_recommendation_only_candidates_are_bounded():
    recommendations = [
        _ranked(
            CanonicalPaper(
                canonical_id=f"doi:10.1000/recommendation-{index}",
                doi=f"10.1000/recommendation-{index}",
                title=f"Recommendation {index}",
                year=2026,
            ),
            recommendation=True,
            score=0.99 - index * 0.01,
        )
        for index in range(10)
    ]

    bounded = _bounded_candidates(recommendations, max_nodes=10)

    assert len(bounded) == 3


def test_graph_excludes_isolated_recommendations():
    origin = CanonicalPaper(
        canonical_id="doi:10.1000/origin",
        doi="10.1000/origin",
        title="A 1999 origin paper",
        year=1999,
        reference_ids=["10.1000/older"],
    )
    older = CanonicalPaper(
        canonical_id="doi:10.1000/older",
        doi="10.1000/older",
        title="An older connected paper",
        year=1988,
    )
    isolated_recommendation = CanonicalPaper(
        canonical_id="doi:10.1000/recommendation",
        doi="10.1000/recommendation",
        title="A recent recommendation with no relationship",
        year=2026,
    )

    snapshot = GraphSynthesizer().synthesize_snapshot(
        origin=origin,
        ranking_result=RankingResult(
            origin=origin,
            ranked_candidates=[
                _ranked(
                    older,
                    direct_reference=True,
                    score=0.9,
                ),
                _ranked(
                    isolated_recommendation,
                    recommendation=True,
                    score=0.95,
                ),
            ],
        ),
    )

    node_ids = {node.id for node in snapshot.nodes}
    assert origin.canonical_id in node_ids
    assert older.canonical_id in node_ids
    assert isolated_recommendation.canonical_id not in node_ids
    assert any(
        warning.code == "disconnected_nodes_excluded"
        for warning in snapshot.warnings
    )
    assert all(
        edge.source in node_ids and edge.target in node_ids
        for edge in [*snapshot.citation_edges, *snapshot.similarity_edges]
    )


def test_graph_nodes_expose_enriched_wbc_and_ncc_signals():
    origin = CanonicalPaper(
        canonical_id="doi:10.1000/origin",
        doi="10.1000/origin",
        title="Origin",
        year=2020,
        reference_ids=["10.1000/candidate"],
    )
    candidate = CanonicalPaper(
        canonical_id="doi:10.1000/candidate",
        doi="10.1000/candidate",
        title="Connected candidate",
        year=2021,
    )
    record = CandidateRecord(
        paper=candidate,
        sources={CandidateSourceType.REFERENCE},
        is_direct_reference=True,
    )
    enrichment = CandidateEnrichmentRecord(
        candidate=record,
        wbc=MetricResult(
            value=0.72,
            availability=MetricAvailability.AVAILABLE,
        ),
        ncc=MetricResult(
            value=0.41,
            availability=MetricAvailability.AVAILABLE,
        ),
    )
    ranked = RankedCandidate(
        paper=candidate,
        candidate_record=record,
        enrichment_record=enrichment,
        final_score=0.8,
        prior_score=0.2,
        derivative_score=0.4,
        confidence=ConfidenceLevel.MEDIUM,
        score_breakdown=ScoreBreakdown(),
    )

    snapshot = GraphSynthesizer().synthesize_snapshot(
        origin=origin,
        ranking_result=RankingResult(
            origin=origin,
            ranked_candidates=[ranked],
        ),
    )
    node = next(
        node for node in snapshot.nodes if node.canonical_id == candidate.canonical_id
    )

    assert node.scores is not None
    assert node.scores["wbc"].value == 0.72
    assert node.scores["ncc"].value == 0.41