import pytest
from app.models.canonical_paper import CanonicalPaper, Author
from app.models.enums import MetricAvailability
from app.providers.models import RawPaper
from app.candidates.models import CandidateRecord, CandidateSourceType
from app.candidates.prescore import compute_prescore, BASELINE_PRESCORE_WEIGHTS
from app.candidates.quota import apply_quota_retention
from app.candidates.generator import CandidatePoolGenerator


@pytest.fixture
def sample_origin():
    return CanonicalPaper(
        canonical_id="doi:10.1038/origin",
        doi="10.1038/origin",
        title="Foundational Quantum Information Theory",
        normalized_title="foundational quantum information theory",
        authors=[Author(name="Alice Physicist", position=1)],
        year=2015,
        citation_count=500,
        topics=["Quantum Physics", "Information Theory"],
        completeness=1.0,
    )


# ==============================================================================
# 1. Acceptance Test #1: Missing Semantic Score Weight Renormalization
# ==============================================================================

def test_missing_semantic_score_renormalizes_weights_without_zero_penalty(sample_origin):
    """
    Acceptance Criteria: A candidate without a semantic score is NOT treated as
    semantic score zero automatically; weights renormalize proportionally over available signals.
    """
    paper = CanonicalPaper(
        canonical_id="doi:10.1038/cand1",
        doi="10.1038/cand1",
        title="Quantum Error Correction",
        normalized_title="quantum error correction",
        authors=[Author(name="Bob Scientist", position=1)],
        year=2016,
        topics=["Quantum Physics"],
        completeness=0.80,
    )

    # Candidate WITHOUT semantic score
    cand_no_semantic = CandidateRecord(
        paper=paper,
        is_direct_reference=True,  # direct = 1.0
        raw_semantic_score=None,   # Missing semantic score
    )

    score, signals, renorm_weights = compute_prescore(cand_no_semantic, sample_origin)

    # 1. Verify semantic signal is marked unavailable
    assert signals["semantic"].availability == MetricAvailability.UNAVAILABLE
    assert signals["semantic"].value is None

    # 2. Verify semantic weight is excluded and remaining weights sum to 1.0
    assert "semantic" not in renorm_weights
    weight_sum = sum(renorm_weights.values())
    assert pytest.approx(weight_sum, abs=1e-3) == 1.0

    # 3. Verify PreScore is positive and not dragged down to zero
    assert score > 0.50

    # 4. Compare with an explicit semantic score of 0.0
    cand_with_zero_semantic = CandidateRecord(
        paper=paper,
        is_direct_reference=True,
        raw_semantic_score=0.0,  # Evaluated to 0.0
    )
    score_zero_sem, signals_zero_sem, _ = compute_prescore(
        cand_with_zero_semantic, sample_origin
    )
    assert signals_zero_sem["semantic"].availability == MetricAvailability.AVAILABLE
    assert signals_zero_sem["semantic"].value == 0.0

    # Missing semantic candidate must have HIGHER score than candidate with evaluated 0.0
    assert score > score_zero_sem


# ==============================================================================
# 2. Acceptance Test #2: Low-Citation Direct Reference Survives Quota Retention
# ==============================================================================

def test_low_citation_direct_reference_survives_quota_retention(sample_origin):
    """
    Acceptance Criteria: A low-citation direct reference can survive quota retention
    even when crowded out of the top 50 PreScore by high-scoring papers.
    """
    candidates = []

    # 1. Create 60 high-scoring generic papers (occupying Top 50 PreScore)
    for i in range(60):
        paper = CanonicalPaper(
            canonical_id=f"doi:10.1000/high_{i}",
            doi=f"10.1000/high_{i}",
            title=f"High Scoring Paper {i}",
            normalized_title=f"high scoring paper {i}",
            citation_count=1000,
            completeness=0.9,
        )
        cand = CandidateRecord(
            paper=paper,
            raw_semantic_score=0.95,
            pre_score=0.90 - (i * 0.005),  # scores from 0.90 down to 0.60
        )
        candidates.append(cand)

    # 2. Create a niche, low-citation direct reference with lower PreScore (0.45)
    niche_ref_paper = CanonicalPaper(
        canonical_id="doi:10.1000/niche_reference",
        doi="10.1000/niche_reference",
        title="Niche Specialized Reference",
        normalized_title="niche specialized reference",
        citation_count=2,  # Very low citation count!
        completeness=0.6,
    )
    niche_ref = CandidateRecord(
        paper=niche_ref_paper,
        is_direct_reference=True,
        pre_score=0.45,  # Too low to make the Top 50 PreScore cut
    )
    candidates.append(niche_ref)

    # Apply quota retention
    retained = apply_quota_retention(candidates, sample_origin, max_cap=80)
    retained_ids = {c.paper.canonical_id for c in retained}

    # Niche reference MUST survive via direct_reference_quota!
    assert "doi:10.1000/niche_reference" in retained_ids

    # Verify survival reason is explicitly recorded
    survived_ref = next(
        c for c in retained if c.paper.canonical_id == "doi:10.1000/niche_reference"
    )
    assert "direct_reference_quota" in survived_ref.retention_reasons
    assert survived_ref.is_retained is True


# ==============================================================================
# 3. Acceptance Test #3: Low-Citation Recommendation Survives Quota Retention
# ==============================================================================

def test_low_citation_recommendation_survives_quota_retention(sample_origin):
    """
    Acceptance Criteria: A recommendation result can survive even if its citation count is low.
    """
    candidates = []

    # 60 high-scoring papers
    for i in range(60):
        paper = CanonicalPaper(
            canonical_id=f"doi:10.1000/popular_{i}",
            title=f"Popular Paper {i}",
            citation_count=2500,
        )
        candidates.append(
            CandidateRecord(paper=paper, pre_score=0.85 - (i * 0.005))
        )

    # Fresh recommendation result with 0 citations
    fresh_rec_paper = CanonicalPaper(
        canonical_id="doi:10.1000/fresh_recommendation",
        title="Brand New Quantum Algorithm",
        citation_count=0,
    )
    fresh_rec = CandidateRecord(
        paper=fresh_rec_paper,
        is_recommendation=True,
        raw_semantic_score=0.98,
        pre_score=0.40,
    )
    candidates.append(fresh_rec)

    retained = apply_quota_retention(candidates, sample_origin, max_cap=80)
    retained_ids = {c.paper.canonical_id for c in retained}

    assert "doi:10.1000/fresh_recommendation" in retained_ids
    survived_rec = next(
        c for c in retained if c.paper.canonical_id == "doi:10.1000/fresh_recommendation"
    )
    assert "recommendation_quota" in survived_rec.retention_reasons


# ==============================================================================
# 4. Acceptance Test #4: Origin Never Appears in Retained Candidate Set
# ==============================================================================

def test_origin_never_appears_in_retained_candidates(sample_origin):
    """
    Acceptance Criteria: The origin never appears in the retained candidate set.
    """
    # Create candidate records including the origin paper itself (e.g. self-reference or duplicate)
    origin_candidate = CandidateRecord(
        paper=sample_origin,
        is_direct_reference=True,
        pre_score=1.0,  # Highest score
    )
    other_candidate = CandidateRecord(
        paper=CanonicalPaper(
            canonical_id="doi:10.1000/other",
            title="Other Relevant Paper",
            citation_count=10,
        ),
        pre_score=0.75,
    )

    retained = apply_quota_retention(
        [origin_candidate, other_candidate], sample_origin, max_cap=80
    )
    retained_ids = {c.paper.canonical_id for c in retained}

    assert sample_origin.canonical_id not in retained_ids
    assert "doi:10.1000/other" in retained_ids


# ==============================================================================
# 5. Pool Generation Bounds and Cap at 80
# ==============================================================================

def test_candidate_pool_generator_caps_at_80(sample_origin):
    """Verify that even with 150 candidates, the retained pool is capped at 80."""
    generator = CandidatePoolGenerator()

    # Generate 120 raw references and citations
    raw_refs = [
        RawPaper(
            provider="crossref",
            provider_id=f"ref_{i}",
            doi=f"10.1000/ref_{i}",
            title=f"Reference Paper {i}",
        )
        for i in range(60)
    ]
    raw_cites = [
        RawPaper(
            provider="semantic_scholar",
            provider_id=f"cite_{i}",
            doi=f"10.1000/cite_{i}",
            title=f"Citing Paper {i}",
        )
        for i in range(60)
    ]
    raw_recs = [
        RawPaper(
            provider="semantic_scholar",
            provider_id=f"rec_{i}",
            doi=f"10.1000/rec_{i}",
            title=f"Recommended Paper {i}",
        )
        for i in range(30)
    ]

    retained = generator.process_raw_candidates(
        origin=sample_origin,
        raw_references=raw_refs,
        raw_citations=raw_cites,
        raw_recommendations=raw_recs,
    )

    # Must be bounded and capped at 80
    assert len(retained) <= 80
    assert len(retained) >= 60

    # All survivors must have is_retained=True and retention_reasons populated
    for cand in retained:
        assert cand.is_retained is True
        assert len(cand.retention_reasons) >= 1
        assert cand.paper.canonical_id != sample_origin.canonical_id
