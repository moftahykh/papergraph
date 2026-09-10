import pytest
import math
from app.models.canonical_paper import CanonicalPaper, Author
from app.models.enums import MetricAvailability, ConfidenceLevel
from app.models.metric import MetricResult
from app.candidates.models import CandidateRecord
from app.enrichment.models import CandidateEnrichmentRecord
from app.enrichment.wbc import compute_wbc
from app.enrichment.ncc import compute_ncc
from app.ranking.models import BaselineWeights
from app.ranking.prior import compute_prior_scores
from app.ranking.derivative import compute_derivative_scores
from app.ranking.engine import SafeRankingEngine


@pytest.fixture
def sample_origin():
    return CanonicalPaper(
        canonical_id="doi:10.1038/origin_physics",
        doi="10.1038/origin_physics",
        semantic_scholar_id="s2_origin",
        title="Foundations of Quantum Information Science",
        authors=[Author(name="Richard Feynman", position=1)],
        year=2018,
        citation_count=1000,
        reference_ids=["ref_a", "ref_b", "ref_c", "ref_d", "ref_e"],
        citation_ids=["cite_1", "cite_2", "cite_3"],
        completeness=1.0,
    )


# ==============================================================================
# 1. Acceptance Test #1: WBC and NCC Numerical Safety (No NaN or Inf)
# ==============================================================================

def test_wbc_and_ncc_never_return_nan_or_infinity():
    """WBC and NCC never return NaN or infinity even with zero or boundary inputs."""
    # Zero references / zero citations
    wbc_empty = compute_wbc([], [])
    assert wbc_empty.value is not None
    assert not math.isnan(wbc_empty.value)
    assert not math.isinf(wbc_empty.value)
    assert wbc_empty.value == 0.0

    ncc_empty = compute_ncc([], [], is_selected_for_citations=True)
    assert ncc_empty.value is not None
    assert not math.isnan(ncc_empty.value)
    assert not math.isinf(ncc_empty.value)
    assert ncc_empty.value == 0.0

    # Massive numbers
    wbc_large = compute_wbc([f"r{i}" for i in range(10000)], [f"r{i}" for i in range(5000, 15000)])
    assert wbc_large.value is not None
    assert 0.0 <= wbc_large.value <= 1.0


# ==============================================================================
# 2. Acceptance Test #2: Missing Signals are NOT Treated as Zero
# ==============================================================================

def test_missing_signals_are_not_treated_as_zero():
    """
    Non-Negotiable Rule #6 & #8: Missing signals are excluded from active signals
    and weights renormalize proportionally. A paper with a missing signal scores
    higher than a paper with an evaluated 0.0 signal.
    """
    engine = SafeRankingEngine()

    # Candidate A: Missing NCC (e.g. not selected for citation enrichment)
    # Available: semantic=0.80, wbc=0.80, direct=1.0
    signals_missing_ncc = {
        "semantic": MetricResult(value=0.80, availability=MetricAvailability.AVAILABLE),
        "wbc": MetricResult(value=0.80, availability=MetricAvailability.AVAILABLE),
        "ncc": MetricResult(value=None, availability=MetricAvailability.NOT_APPLICABLE, reason="not_selected"),
        "direct": MetricResult(value=1.0, availability=MetricAvailability.AVAILABLE),
    }

    # Candidate B: Evaluated NCC = 0.0
    signals_zero_ncc = {
        "semantic": MetricResult(value=0.80, availability=MetricAvailability.AVAILABLE),
        "wbc": MetricResult(value=0.80, availability=MetricAvailability.AVAILABLE),
        "ncc": MetricResult(value=0.0, availability=MetricAvailability.AVAILABLE),
        "direct": MetricResult(value=1.0, availability=MetricAvailability.AVAILABLE),
    }

    score_a = engine.compute_composite_score(signals_missing_ncc)
    score_b = engine.compute_composite_score(signals_zero_ncc)

    # Candidate A's NCC is null, so active weights are semantic (0.35), wbc (0.30), direct (0.15) -> sum = 0.80
    # Renormalized weights:
    #   semantic: 0.35 / 0.80 = 0.4375
    #   wbc:      0.30 / 0.80 = 0.3750
    #   direct:   0.15 / 0.80 = 0.1875
    # Expected score A = 0.4375 * 0.8 + 0.3750 * 0.8 + 0.1875 * 1.0 = 0.8375
    assert score_a.final_score is not None
    assert pytest.approx(score_a.final_score, abs=1e-4) == 0.8375

    # Candidate B has NCC = 0.0 evaluated (weight 0.20 * 0.0 drags score down)
    # Expected score B = 0.35 * 0.8 + 0.30 * 0.8 + 0.20 * 0.0 + 0.15 * 1.0 = 0.6700
    assert score_b.final_score is not None
    assert pytest.approx(score_b.final_score, abs=1e-4) == 0.6700

    # Missing NCC candidate must score significantly higher than evaluated zero NCC candidate
    assert score_a.final_score > score_b.final_score


# ==============================================================================
# 3. Acceptance Test #3: Renormalized Weights Sum to Exactly 1.0
# ==============================================================================

@pytest.mark.parametrize("active_keys", [
    ["semantic", "wbc", "ncc", "direct"],
    ["semantic", "wbc", "direct"],
    ["semantic", "wbc"],
    ["wbc", "direct"],
    ["semantic"],
    ["direct"],
])
def test_renormalized_weights_sum_to_one(active_keys):
    """Renormalized weights sum to 1.0 within tolerance for any combination of available signals."""
    engine = SafeRankingEngine()
    signals = {}

    all_keys = ["semantic", "wbc", "ncc", "direct"]
    for k in all_keys:
        if k in active_keys:
            signals[k] = MetricResult(value=0.50, availability=MetricAvailability.AVAILABLE)
        else:
            signals[k] = MetricResult(value=None, availability=MetricAvailability.UNAVAILABLE)

    breakdown = engine.compute_composite_score(signals)
    active_weights = [
        s.normalized_weight
        for s in breakdown.signals.values()
        if s.normalized_weight is not None
    ]

    assert len(active_weights) == len(active_keys)
    assert pytest.approx(sum(active_weights), abs=1e-5) == 1.0


# ==============================================================================
# 4. Acceptance Test #4: Confidence Classification
# ==============================================================================

def test_confidence_level_classification():
    """Confidence classifies accurately: 3+ -> High, 2 -> Medium, 1 -> Low, 0 -> Insufficient."""
    engine = SafeRankingEngine()

    def make_signals(count: int):
        keys = ["semantic", "wbc", "ncc", "direct"]
        return {
            k: MetricResult(value=0.50, availability=MetricAvailability.AVAILABLE) if i < count
            else MetricResult(value=None, availability=MetricAvailability.UNAVAILABLE)
            for i, k in enumerate(keys)
        }

    assert engine.compute_composite_score(make_signals(4)).confidence == ConfidenceLevel.HIGH
    assert engine.compute_composite_score(make_signals(3)).confidence == ConfidenceLevel.HIGH
    assert engine.compute_composite_score(make_signals(2)).confidence == ConfidenceLevel.MEDIUM
    assert engine.compute_composite_score(make_signals(1)).confidence == ConfidenceLevel.LOW
    assert engine.compute_composite_score(make_signals(0)).confidence == ConfidenceLevel.INSUFFICIENT


# ==============================================================================
# 5. Acceptance Test #5: PriorScore and DerivativeScore are in [0, 1]
# ==============================================================================

def test_prior_score_bounds_and_values(sample_origin):
    """PriorScore factors frequency and influence into [0.0, 1.0] without NaN."""
    papers = [
        CanonicalPaper(
            canonical_id=f"doi:10.1000/prior_{i}",
            doi=f"10.1000/prior_{i}",
            title=f"Prior Work {i}",
            year=2015,
            citation_count=(i + 1) * 200,
            reference_ids=["ref_a", "ref_b"],
        )
        for i in range(5)
    ]
    # Connect references from subsequent papers to the first paper
    for p in papers[1:]:
        p.reference_ids.append("doi:10.1000/prior_0")

    scores = compute_prior_scores(sample_origin, papers)
    assert len(scores) == 5

    for pid, score in scores.items():
        assert 0.0 <= score <= 1.0
        assert not math.isnan(score)
        assert not math.isinf(score)

    # The paper cited by all other papers should have the highest prior score
    assert scores["doi:10.1000/prior_0"] > 0.0


def test_derivative_score_requires_overlap_and_bounds(sample_origin):
    """DerivativeScore enforces overlap_count >= 2 and values in [0.0, 1.0]."""
    # Candidate 1: overlap = 0 -> must be 0.0
    cand_no_overlap = CanonicalPaper(
        canonical_id="doi:10.1000/deriv_0",
        doi="10.1000/deriv_0",
        title="Derivative 0",
        year=2021,
        citation_count=50,
        reference_ids=["unrelated_1"],
    )

    # Candidate 2: overlap = 1 -> must be 0.0 (requires >= 2)
    cand_one_overlap = CanonicalPaper(
        canonical_id="doi:10.1000/deriv_1",
        doi="10.1000/deriv_1",
        title="Derivative 1",
        year=2021,
        citation_count=50,
        reference_ids=["ref_a"],  # Only 1 shared with origin
    )

    # Candidate 3: overlap = 2 -> positive score
    cand_two_overlap = CanonicalPaper(
        canonical_id="doi:10.1000/deriv_2",
        doi="10.1000/deriv_2",
        title="Derivative 2",
        year=2021,
        citation_count=150,
        reference_ids=["ref_a", "ref_b"],  # 2 shared with origin
    )

    papers = [cand_no_overlap, cand_one_overlap, cand_two_overlap]
    scores = compute_derivative_scores(sample_origin, papers)

    # Assert strict overlap_count >= 2 requirement
    assert scores[cand_no_overlap.canonical_id] == 0.0
    assert scores[cand_one_overlap.canonical_id] == 0.0
    assert scores[cand_two_overlap.canonical_id] > 0.0
    assert scores[cand_two_overlap.canonical_id] <= 1.0


# ==============================================================================
# 6. Acceptance Test #6: Deterministic Ranking
# ==============================================================================

def test_ranking_is_deterministic(sample_origin):
    """Ranking is strictly deterministic: identical inputs yield identical rank order and scores."""
    engine = SafeRankingEngine()

    def build_candidate_pool():
        pool = []
        for i in range(15):
            cand = CandidateRecord(
                paper=CanonicalPaper(
                    canonical_id=f"doi:10.1000/cand_{i}",
                    doi=f"10.1000/cand_{i}",
                    title=f"Publication {i}",
                    year=2019 + (i % 3),
                    citation_count=(i * 37) % 500,
                    reference_ids=["ref_a", "ref_b"] if i % 2 == 0 else ["ref_c"],
                ),
                raw_semantic_score=round((i % 7) / 7.0, 3),
                is_direct_reference=(i % 3 == 0),
            )
            # Wrap in enrichment record with simulated WBC and NCC
            enrich_rec = CandidateEnrichmentRecord(
                candidate=cand,
                wbc=MetricResult(value=0.5 if i % 2 == 0 else 0.1, availability=MetricAvailability.AVAILABLE),
                ncc=MetricResult(value=0.4 if i % 4 == 0 else None, availability=MetricAvailability.AVAILABLE if i % 4 == 0 else MetricAvailability.NOT_APPLICABLE),
            )
            pool.append(enrich_rec)
        return pool

    pool_1 = build_candidate_pool()
    pool_2 = build_candidate_pool()

    res_1 = engine.rank_candidates(sample_origin, pool_1)
    res_2 = engine.rank_candidates(sample_origin, pool_2)

    assert len(res_1.ranked_candidates) == len(res_2.ranked_candidates)

    for r1, r2 in zip(res_1.ranked_candidates, res_2.ranked_candidates):
        assert r1.paper.canonical_id == r2.paper.canonical_id
        assert r1.rank == r2.rank
        assert r1.final_score == r2.final_score
        assert r1.prior_score == r2.prior_score
        assert r1.derivative_score == r2.derivative_score
        assert r1.archetype == r2.archetype
