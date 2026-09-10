import math
import pytest
from app.models.canonical_paper import CanonicalPaper, Author
from app.models.metric import MetricResult
from app.models.enums import MetricAvailability, ConfidenceLevel
from app.candidates.models import CandidateRecord
from app.candidates.prescore import compute_prescore, BASELINE_PRESCORE_WEIGHTS
from app.enrichment.wbc import compute_wbc
from app.enrichment.ncc import compute_ncc
from app.ranking.prior import compute_prior_scores
from app.ranking.derivative import compute_derivative_scores
from app.ranking.models import RankedCandidate, RankingResult, ScoreBreakdown
from app.graph.mmr import select_diverse_nodes_mmr, compute_pairwise_similarity


@pytest.fixture
def origin_paper():
    return CanonicalPaper(
        canonical_id="doi:10.1038/origin_quantum",
        doi="10.1038/origin_quantum",
        title="Quantum Computing Foundations",
        year=2018,
        citation_count=500,
        reference_ids=["ref_1", "ref_2", "ref_3", "ref_4"],
        citation_ids=["cite_1", "cite_2", "cite_3"],
        completeness=1.0,
        topics=["Quantum Computing", "Physics"],
    )


# ==============================================================================
# 1. WBC Edge Cases
# ==============================================================================

def test_wbc_zero_denominator_both_empty():
    """Empty reference sets on both origin and candidate produce 0.0 without division by zero."""
    res = compute_wbc([], [])
    assert res.value == 0.0
    assert res.availability == MetricAvailability.AVAILABLE
    assert not math.isnan(res.value)
    assert not math.isinf(res.value)


def test_wbc_one_empty_set():
    """When either origin or candidate has empty references, WBC is 0.0."""
    res1 = compute_wbc(["ref_1", "ref_2"], [])
    assert res1.value == 0.0
    assert res1.availability == MetricAvailability.AVAILABLE

    res2 = compute_wbc([], ["ref_1", "ref_2"])
    assert res2.value == 0.0
    assert res2.availability == MetricAvailability.AVAILABLE


def test_wbc_zero_overlap():
    """Disjoint reference sets produce exactly 0.0."""
    res = compute_wbc(["ref_1", "ref_2"], ["ref_3", "ref_4"])
    assert res.value == 0.0
    assert res.availability == MetricAvailability.AVAILABLE


def test_wbc_perfect_overlap():
    """Identical reference sets produce ~1.0 with epsilon damping."""
    refs = ["ref_1", "ref_2", "ref_3"]
    res = compute_wbc(refs, refs)
    assert res.value is not None
    assert pytest.approx(res.value, abs=1e-4) == 1.0


def test_wbc_provider_error_and_unavailable():
    """Provider failure or missing references yield typed availability states."""
    err_res = compute_wbc(["ref_1"], ["ref_2"], origin_ref_status="failed")
    assert err_res.value is None
    assert err_res.availability == MetricAvailability.PROVIDER_ERROR

    unavail_res = compute_wbc(None, ["ref_2"])
    assert unavail_res.value is None
    assert unavail_res.availability == MetricAvailability.UNAVAILABLE


def test_wbc_large_sets():
    """Massive sets (10,000 items) compute safely without overflow."""
    large_origin = [f"ref_o_{i}" for i in range(10000)]
    large_candidate = [f"ref_c_{i}" for i in range(10000)]
    res = compute_wbc(large_origin, large_candidate)
    assert res.value == 0.0
    assert not math.isnan(res.value)


# ==============================================================================
# 2. NCC Edge Cases
# ==============================================================================

def test_ncc_all_zero_citations():
    """Zero citation sets yield 0.0 and available status."""
    res = compute_ncc([], [])
    assert res.value == 0.0
    assert res.availability == MetricAvailability.AVAILABLE
    assert not math.isnan(res.value)


def test_ncc_not_selected():
    """Candidates outside citation enrichment quota yield NOT_APPLICABLE."""
    res = compute_ncc(["c1"], ["c1"], is_selected_for_citations=False)
    assert res.value is None
    assert res.availability == MetricAvailability.NOT_APPLICABLE


def test_ncc_provider_error_and_missing():
    """Provider failure yields PROVIDER_ERROR; None citations yield UNAVAILABLE."""
    res_err = compute_ncc(["c1"], ["c2"], cand_cite_status="failed")
    assert res_err.value is None
    assert res_err.availability == MetricAvailability.PROVIDER_ERROR

    res_missing = compute_ncc(None, ["c2"])
    assert res_missing.value is None
    assert res_missing.availability == MetricAvailability.UNAVAILABLE


def test_ncc_partial_overlap():
    """Partial overlap calculates correct geometric mean denominator."""
    cu = ["c1", "c2", "c3", "c4"]
    cv = ["c3", "c4", "c5", "c6"]
    res = compute_ncc(cu, cv)
    assert res.value is not None
    # 2 / (sqrt(4 * 4) + eps) = 2 / 4 = 0.5
    assert pytest.approx(res.value, abs=1e-3) == 0.50


# ==============================================================================
# 3. PreScore Missing-Signal & Weight Renormalization Tests
# ==============================================================================

def test_prescore_missing_semantic_signal(origin_paper):
    """Missing semantic signal re-weights active signals proportionally and sums to 1.0."""
    cand = CandidateRecord(
        paper=CanonicalPaper(
            canonical_id="doi:10.1000/test_cand",
            title="Quantum Information Theory",
            year=2020,
            completeness=0.8,
        ),
        raw_semantic_score=None,
        is_direct_reference=True,
    )

    score, signals, renorm_weights = compute_prescore(cand, origin_paper)
    assert signals["semantic"].availability == MetricAvailability.UNAVAILABLE
    assert signals["semantic"].value is None
    assert sum(renorm_weights.values()) == pytest.approx(1.0, abs=1e-3)
    assert score > 0.0


def test_prescore_missing_publication_year(origin_paper):
    """Missing publication year excludes recency signal and renormalizes weights."""
    cand = CandidateRecord(
        paper=CanonicalPaper(
            canonical_id="doi:10.1000/no_year",
            title="Quantum Physics",
            year=None,
            completeness=0.5,
        ),
        raw_semantic_score=0.85,
        is_direct_reference=False,
    )

    score, signals, renorm_weights = compute_prescore(cand, origin_paper)
    assert signals["recency"].availability == MetricAvailability.UNAVAILABLE
    assert "recency" not in renorm_weights
    assert sum(renorm_weights.values()) == pytest.approx(1.0, abs=1e-3)
    assert score > 0.0


def test_prescore_missing_signal_beats_zero_evaluated_signal(origin_paper):
    """Rule #6: Missing signal candidate scores higher than candidate with evaluated 0.0."""
    cand_missing = CandidateRecord(
        paper=CanonicalPaper(
            canonical_id="doi:10.1000/cand_missing",
            title="Quantum Computing Foundations",
            year=2018,
            completeness=1.0,
        ),
        raw_semantic_score=None,
        is_direct_reference=True,
    )

    cand_zero = CandidateRecord(
        paper=CanonicalPaper(
            canonical_id="doi:10.1000/cand_zero",
            title="Quantum Computing Foundations",
            year=2018,
            completeness=1.0,
        ),
        raw_semantic_score=0.0,
        is_direct_reference=True,
    )

    score_missing, _, _ = compute_prescore(cand_missing, origin_paper)
    score_zero, _, _ = compute_prescore(cand_zero, origin_paper)

    assert score_missing > score_zero


# ==============================================================================
# 4. Prior and Derivative Normalization Boundary Tests
# ==============================================================================

def test_prior_and_derivative_boundary_conditions(origin_paper):
    """
    Tests edge cases for chronological prior and derivative scores:
      - Same year as seed: cannot be prior or derivative work
      - Earlier year but 0 citations: PriorScore handles low influence gracefully
      - Later year with overlap < 2: DerivativeScore is strictly 0.0
    """
    # 1. Same year candidate
    same_year_cand = CanonicalPaper(
        canonical_id="doi:10.1000/same_year",
        title="Concurrent Quantum Analysis",
        year=2018,
        citation_count=100,
        reference_ids=["ref_1", "ref_2"],
    )

    # 2. Earlier year with zero citations
    zero_cite_prior = CanonicalPaper(
        canonical_id="doi:10.1000/zero_cite_prior",
        title="Unnoticed Quantum Work",
        year=2010,
        citation_count=0,
        reference_ids=[],
    )

    # 3. Later year with only 1 overlapping reference (requires >= 2)
    one_overlap_deriv = CanonicalPaper(
        canonical_id="doi:10.1000/one_overlap",
        title="Subsequent Single Link Work",
        year=2021,
        citation_count=50,
        reference_ids=["ref_1"],  # only 1 shared with origin
    )

    # 4. Later year with 2 overlapping references
    two_overlap_deriv = CanonicalPaper(
        canonical_id="doi:10.1000/two_overlap",
        title="Subsequent Robust Derivative Work",
        year=2021,
        citation_count=150,
        reference_ids=["ref_1", "ref_2"],  # 2 shared with origin
    )

    papers = [same_year_cand, zero_cite_prior, one_overlap_deriv, two_overlap_deriv]

    prior_scores = compute_prior_scores(origin_paper, papers)
    deriv_scores = compute_derivative_scores(origin_paper, papers)

    # Zero-citation prior work should have 0 or near-0 prior score without crashing
    assert prior_scores[zero_cite_prior.canonical_id] == 0.0

    # Derivative work with overlap = 1 must be strictly 0.0
    assert deriv_scores[one_overlap_deriv.canonical_id] == 0.0

    # Derivative work with overlap >= 2 must have positive derivative score <= 1.0
    assert deriv_scores[two_overlap_deriv.canonical_id] > 0.0
    assert deriv_scores[two_overlap_deriv.canonical_id] <= 1.0


# ==============================================================================
# 5. MMR Diversity Edge Cases
# ==============================================================================

def test_mmr_empty_candidate_pool(origin_paper):
    """MMR returns empty list when given empty input."""
    assert select_diverse_nodes_mmr(origin_paper, []) == []


def test_mmr_identical_clones_penalization(origin_paper):
    """
    MMR penalizes identical clones of a high-scoring paper and selects
    a diverse alternative instead of filling all slots with clones.
    """
    # 5 identical clone candidates with high relevance (0.95)
    clones = [
        RankedCandidate(
            paper=CanonicalPaper(
                canonical_id=f"doi:10.1000/clone_{i}",
                title=f"Clone Study {i}",
                year=2019,
                citation_count=200,
                reference_ids=["shared_ref_1", "shared_ref_2"],
                citation_ids=["shared_cite_1"],
                topics=["Quantum Computing"],
            ),
            rank=i + 1,
            final_score=0.95,
            archetype="foundational",
            confidence=ConfidenceLevel.HIGH,
            score_breakdown=ScoreBreakdown(),
        )
        for i in range(5)
    ]

    # 1 diverse paper with slightly lower relevance (0.80) but distinct references/topics
    diverse_cand = RankedCandidate(
        paper=CanonicalPaper(
            canonical_id="doi:10.1000/diverse_alt",
            title="Alternative Optical Architecture",
            year=2021,
            citation_count=50,
            reference_ids=["opt_ref_a", "opt_ref_b"],
            citation_ids=["opt_cite_a"],
            topics=["Photonics", "Optical Computing"],
        ),
        rank=6,
        final_score=0.80,
        archetype="derivative",
        confidence=ConfidenceLevel.MEDIUM,
        score_breakdown=ScoreBreakdown(),
    )

    all_candidates = clones + [diverse_cand]

    # Select 3 nodes using MMR (lambda = 0.70)
    selected = select_diverse_nodes_mmr(origin_paper, all_candidates, max_nodes=3, lambda_param=0.70)

    selected_ids = [c.paper.canonical_id for c in selected]
    # The first clone is chosen for high relevance
    assert "doi:10.1000/clone_0" in selected_ids
    # Because clones have 1.0 pairwise similarity to each other, MMR must select the diverse paper!
    assert "doi:10.1000/diverse_alt" in selected_ids
    assert len(selected) == 3


def test_mmr_pure_relevance_vs_pure_diversity(origin_paper):
    """
    Lambda = 1.0 is pure relevance (greedy top-score selection).
    Lambda = 0.0 is pure diversity (picks maximum novelty).
    """
    cand_high_rel = RankedCandidate(
        paper=CanonicalPaper(
            canonical_id="doi:10.1000/high_rel",
            title="Very Similar Paper",
            reference_ids=["ref_1", "ref_2"],  # overlap with origin
            topics=["Quantum Computing"],
        ),
        rank=1,
        final_score=0.99,
        archetype="representative",
        confidence=ConfidenceLevel.HIGH,
        score_breakdown=ScoreBreakdown(),
    )

    cand_low_rel_diverse = RankedCandidate(
        paper=CanonicalPaper(
            canonical_id="doi:10.1000/diverse",
            title="Completely Distinct Paper",
            reference_ids=["unrelated_1"],
            topics=["Astrophysics"],
        ),
        rank=2,
        final_score=0.40,
        archetype="exploratory",
        confidence=ConfidenceLevel.LOW,
        score_breakdown=ScoreBreakdown(),
    )

    candidates = [cand_high_rel, cand_low_rel_diverse]

    # Pure relevance (lambda = 1.0) picks candidate with highest final score first
    res_rel = select_diverse_nodes_mmr(origin_paper, candidates, max_nodes=1, lambda_param=1.0)
    assert res_rel[0].paper.canonical_id == "doi:10.1000/high_rel"

    # Pairwise similarity: high_rel has high similarity to origin, diverse has near-zero
    sim_high = compute_pairwise_similarity(cand_high_rel.paper, origin_paper)
    sim_div = compute_pairwise_similarity(cand_low_rel_diverse.paper, origin_paper)
    assert sim_high > sim_div
