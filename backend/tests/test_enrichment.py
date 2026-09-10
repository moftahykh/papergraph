import pytest
import asyncio
from unittest.mock import AsyncMock
from app.models.canonical_paper import CanonicalPaper, Author
from app.models.enums import MetricAvailability, GraphJobStatus
from app.models.graph import GraphWarning
from app.providers.models import RawPaper, Page
from app.candidates.models import CandidateRecord, CandidateSourceType
from app.enrichment.models import EnrichmentStatusEnum
from app.enrichment.wbc import compute_wbc
from app.enrichment.ncc import compute_ncc
from app.enrichment.metadata import BatchMetadataEnricher
from app.enrichment.references import ReferenceEnricher
from app.enrichment.citations import CitationEnricher
from app.enrichment.pipeline import EnrichmentPipeline
from app.cache.manager import ResponseCache


@pytest.fixture
def sample_origin():
    return CanonicalPaper(
        canonical_id="doi:10.1038/origin_main",
        doi="10.1038/origin_main",
        semantic_scholar_id="s2_origin_123",
        title="Deep Learning Foundations in Graph Discovery",
        normalized_title="deep learning foundations in graph discovery",
        authors=[Author(name="Ada Lovelace", position=1)],
        year=2020,
        venue="Nature",
        abstract="Foundational work on graph theory and citation analysis.",
        citation_count=250,
        reference_ids=["ref_1", "ref_2", "ref_3", "ref_shared_a", "ref_shared_b"],
        citation_ids=["cite_1", "cite_2", "cite_shared_x", "cite_shared_y"],
        completeness=1.0,
    )


@pytest.fixture
def mock_s2_provider():
    provider = AsyncMock()
    provider.name = "semantic_scholar"

    # Default batch metadata mock
    async def _get_batch_details(ids):
        results = []
        for pid in ids:
            results.append(
                RawPaper(
                    provider="semantic_scholar",
                    provider_id=pid,
                    semantic_scholar_id=pid,
                    title=f"Enriched Title for {pid}",
                    venue="Journal of AI Research",
                    abstract=f"Enriched detailed abstract for paper {pid}.",
                    year=2021,
                    citation_count=45,
                )
            )
        return results

    provider.get_batch_details = AsyncMock(side_effect=_get_batch_details)

    # Default paginated references mock
    async def _get_references(provider_id, cursor=None, limit=50):
        offset = int(cursor) if cursor and cursor.isdigit() else 0
        all_refs = [f"ref_{provider_id}_{i}" for i in range(15)]
        # Include shared references for specific papers
        if "cand_overlap" in provider_id:
            all_refs.extend(["ref_shared_a", "ref_shared_b"])

        page_items = [
            RawPaper(
                provider="semantic_scholar",
                provider_id=r,
                title=f"Ref Title {r}",
            )
            for r in all_refs[offset:offset + limit]
        ]
        next_offset = offset + len(page_items)
        has_more = next_offset < len(all_refs)
        return Page(
            items=page_items,
            total=len(all_refs),
            has_more=has_more,
            next_cursor=str(next_offset) if has_more else None,
        )

    provider.get_references = AsyncMock(side_effect=_get_references)

    # Default paginated citations mock
    async def _get_citations(provider_id, cursor=None, limit=50):
        offset = int(cursor) if cursor and cursor.isdigit() else 0
        all_cites = [f"cite_{provider_id}_{i}" for i in range(20)]
        if "cand_overlap" in provider_id:
            all_cites.extend(["cite_shared_x", "cite_shared_y"])

        page_items = [
            RawPaper(
                provider="semantic_scholar",
                provider_id=c,
                title=f"Cite Title {c}",
            )
            for c in all_cites[offset:offset + limit]
        ]
        next_offset = offset + len(page_items)
        has_more = next_offset < len(all_cites)
        return Page(
            items=page_items,
            total=len(all_cites),
            has_more=has_more,
            next_cursor=str(next_offset) if has_more else None,
        )

    provider.get_citations = AsyncMock(side_effect=_get_citations)
    return provider


# ==============================================================================
# 1. Acceptance Test #1: WBC Mathematical Correctness & Epsilon Protection
# ==============================================================================

def test_wbc_formula_with_valid_overlap():
    """WBC correctly computes intersection / (sqrt(sum_a * sum_b) + eps) in [0, 1]."""
    origin_refs = ["r1", "r2", "r3", "r4"]  # len = 4
    cand_refs = ["r2", "r3", "r5", "r6"]    # len = 4, intersection = {r2, r3} = 2

    # Expected: 2 / (sqrt(4 * 4) + 1e-8) = 2 / 4.0 = 0.50
    res = compute_wbc(origin_refs, cand_refs)
    assert res.availability == MetricAvailability.AVAILABLE
    assert res.value is not None
    assert pytest.approx(res.value, abs=1e-4) == 0.50


def test_wbc_zero_overlap_and_empty_references():
    """Zero overlap returns 0.0 with available state; empty sets do not divide by zero."""
    # Disjoint sets
    res_disjoint = compute_wbc(["r1", "r2"], ["r3", "r4"])
    assert res_disjoint.availability == MetricAvailability.AVAILABLE
    assert res_disjoint.value == 0.0

    # Empty reference sets
    res_empty = compute_wbc([], [])
    assert res_empty.availability == MetricAvailability.AVAILABLE
    assert res_empty.value == 0.0
    assert not (res_empty.value != res_empty.value)  # Check not NaN


def test_wbc_missing_and_error_states():
    """Non-Negotiable Rule #6: Missing or errored references are null, never 0.0."""
    # Unloaded / skipped references
    res_unloaded = compute_wbc(None, ["r1"], origin_ref_status="skipped")
    assert res_unloaded.availability == MetricAvailability.UNAVAILABLE
    assert res_unloaded.value is None
    assert res_unloaded.reason == "references_not_loaded"

    # Provider error during fetch
    res_err = compute_wbc(["r1"], ["r2"], cand_ref_status="failed")
    assert res_err.availability == MetricAvailability.PROVIDER_ERROR
    assert res_err.value is None
    assert res_err.reason == "provider_error"


# ==============================================================================
# 2. Acceptance Test #2: NCC Mathematical Correctness & Selection States
# ==============================================================================

def test_ncc_formula_with_valid_overlap():
    """NCC correctly computes intersection / (sqrt(len_a * len_b) + eps) in [0, 1]."""
    origin_cites = ["c1", "c2", "c3"]         # len = 3
    cand_cites = ["c2", "c3", "c4"]           # len = 3, intersection = {c2, c3} = 2

    # Expected: 2 / (sqrt(3 * 3) + 1e-8) = 2 / 3.0 = 0.666667
    res = compute_ncc(origin_cites, cand_cites, is_selected_for_citations=True)
    assert res.availability == MetricAvailability.AVAILABLE
    assert res.value is not None
    assert pytest.approx(res.value, abs=1e-4) == 0.666667


def test_ncc_not_selected_and_error_states():
    """Candidates outside Top 30 receive not_applicable; errors produce provider_error."""
    # Candidate not selected for citation enrichment
    res_not_sel = compute_ncc(["c1"], ["c2"], is_selected_for_citations=False)
    assert res_not_sel.availability == MetricAvailability.NOT_APPLICABLE
    assert res_not_sel.value is None
    assert res_not_sel.reason == "not_selected_for_citation_enrichment"

    # Provider error
    res_err = compute_ncc(["c1"], ["c2"], is_selected_for_citations=True, origin_cite_status="failed")
    assert res_err.availability == MetricAvailability.PROVIDER_ERROR
    assert res_err.value is None


# ==============================================================================
# 3. Acceptance Test #3: Request Collapsing & Caching
# ==============================================================================

@pytest.mark.asyncio
async def test_response_cache_request_collapsing():
    """
    Acceptance Criteria: Duplicate reference/citation requests are collapsed;
    multiple concurrent callers coalesce onto a single provider invocation.
    """
    cache = ResponseCache(default_ttl=60)
    call_count = 0

    async def slow_fetch():
        nonlocal call_count
        call_count += 1
        await asyncio.sleep(0.05)
        return ["ref_a", "ref_b"]

    # Trigger 5 concurrent requests for the exact same key
    tasks = [
        cache.get_or_fetch("paper:same_doi_123", slow_fetch)
        for _ in range(5)
    ]
    results = await asyncio.gather(*tasks)

    # All callers received the result, but slow_fetch was called exactly ONCE
    assert call_count == 1
    for r in results:
        assert r == ["ref_a", "ref_b"]

    # Repeat call hits cache directly
    cached_val = await cache.get("paper:same_doi_123")
    assert cached_val == ["ref_a", "ref_b"]


# ==============================================================================
# 4. Acceptance Test #4: Batch Metadata Enrichment
# ==============================================================================

@pytest.mark.asyncio
async def test_batch_metadata_enrichment(mock_s2_provider):
    """Batch metadata enrichment enriches incomplete candidate records losslessly."""
    candidates = [
        CandidateRecord(
            paper=CanonicalPaper(
                canonical_id=f"doi:10.1000/cand_{i}",
                doi=f"10.1000/cand_{i}",
                semantic_scholar_id=f"s2_cand_{i}",
                title=f"Initial Title {i}",
                abstract=None,  # Missing abstract
                venue=None,     # Missing venue
            ),
            pre_score=0.75,
        )
        for i in range(5)
    ]

    enricher = BatchMetadataEnricher(s2_provider=mock_s2_provider)
    statuses, enriched_fields = await enricher.enrich_candidates_metadata(candidates)

    for cand in candidates:
        cid = cand.paper.canonical_id
        assert statuses[cid] == EnrichmentStatusEnum.SUCCESS
        assert cand.paper.abstract is not None
        assert "Enriched detailed abstract" in cand.paper.abstract
        assert cand.paper.venue == "Journal of AI Research"
        assert cand.paper.completeness > 0.60
        assert "abstract" in enriched_fields[cid]
        assert "venue" in enriched_fields[cid]


# ==============================================================================
# 5. Acceptance Test #5: Top 30 Candidate Selection for Citations
# ==============================================================================

def test_top_30_candidate_selection_for_citations():
    """Citation enricher selects exactly 30 candidates using composite PreScore and WBC."""
    candidates = []
    wbc_scores = {}

    for i in range(60):
        cid = f"doi:10.1000/paper_{i}"
        cand = CandidateRecord(
            paper=CanonicalPaper(
                canonical_id=cid,
                doi=cid,
                title=f"Paper {i}",
            ),
            pre_score=round(i / 60.0, 3),  # 0.0 to 0.983
        )
        candidates.append(cand)
        wbc_scores[cid] = compute_wbc(["r1"], ["r1" if i > 40 else "r2"])

    enricher = CitationEnricher(max_candidates=30)
    selected = enricher.select_top_candidates(candidates, wbc_scores)

    assert len(selected) == 30
    # Highest scoring papers should be included
    selected_cids = {c.paper.canonical_id for c in selected}
    assert "doi:10.1000/paper_59" in selected_cids
    assert "doi:10.1000/paper_50" in selected_cids


# ==============================================================================
# 6. Acceptance Test #6: End-to-End Pipeline Execution (Success Path)
# ==============================================================================

@pytest.mark.asyncio
async def test_enrichment_pipeline_end_to_end_success(sample_origin, mock_s2_provider):
    """
    Acceptance Criteria: Staged pipeline enriches metadata, references, WBC,
    citations, and NCC for candidates and marks job COMPLETED.
    """
    candidates = []
    # Create 40 candidates, some with overlapping references & citations
    for i in range(40):
        is_overlap = (i % 2 == 0)
        s2_id = f"cand_overlap_{i}" if is_overlap else f"cand_normal_{i}"
        cand = CandidateRecord(
            paper=CanonicalPaper(
                canonical_id=f"doi:10.1000/{s2_id}",
                doi=f"10.1000/{s2_id}",
                semantic_scholar_id=s2_id,
                title=f"Candidate Publication {i}",
            ),
            pre_score=round(0.40 + (i * 0.01), 3),
        )
        candidates.append(cand)

    pipeline = EnrichmentPipeline(
        s2_provider=mock_s2_provider,
        max_reference_candidates=60,
        max_citation_candidates=30,
    )

    result = await pipeline.run(sample_origin, candidates)

    assert result.status == GraphJobStatus.COMPLETED
    assert len(result.candidates) == 40
    assert result.metadata_completeness >= 0.90
    assert result.references_completeness >= 0.90
    assert result.citations_completeness >= 0.90

    # Check that overlapping candidates within top 30 have positive WBC and NCC
    overlap_cand = next(c for c in result.candidates if "cand_overlap_38" in c.candidate.paper.canonical_id)
    assert overlap_cand.wbc.availability == MetricAvailability.AVAILABLE
    assert overlap_cand.wbc.value > 0.0
    assert overlap_cand.ncc.availability == MetricAvailability.AVAILABLE
    assert overlap_cand.ncc.value > 0.0

    # Non-selected candidates for citations (outside top 30) have not_applicable NCC
    non_selected = [c for c in result.candidates if c.citations_status == EnrichmentStatusEnum.NOT_SELECTED]
    assert len(non_selected) == 10  # 40 - 30 = 10
    for ns in non_selected:
        assert ns.ncc.availability == MetricAvailability.NOT_APPLICABLE
        assert ns.ncc.value is None


# ==============================================================================
# 7. Acceptance Test #7: Fault Tolerance & Graceful Partial Graph Job Handling
# ==============================================================================

@pytest.mark.asyncio
async def test_enrichment_pipeline_handles_provider_failure_gracefully(sample_origin):
    """
    Acceptance Criteria: A failed upstream provider does NOT crash the pipeline;
    graph job completes as PARTIAL with explicit warnings and data completeness ratios.
    """
    failing_provider = AsyncMock()
    failing_provider.name = "failing_s2"

    # Simulate 500 server error on references
    async def _failing_references(*args, **kwargs):
        raise ConnectionResetError("Provider connection reset by peer")

    failing_provider.get_references = AsyncMock(side_effect=_failing_references)
    failing_provider.get_batch_details = AsyncMock(side_effect=_failing_references)
    failing_provider.get_citations = AsyncMock(return_value=Page(items=[], total=0, has_more=False))

    candidates = [
        CandidateRecord(
            paper=CanonicalPaper(
                canonical_id=f"doi:10.1000/err_cand_{i}",
                doi=f"10.1000/err_cand_{i}",
                semantic_scholar_id=f"err_cand_{i}",
                title=f"Error Candidate {i}",
            ),
            pre_score=0.80,
        )
        for i in range(5)
    ]

    pipeline = EnrichmentPipeline(
        s2_provider=failing_provider,
        max_reference_candidates=60,
        max_citation_candidates=30,
    )

    # Must NOT raise exception
    result = await pipeline.run(sample_origin, candidates)

    # Verification: Marked as PARTIAL with explicit warnings
    assert result.status == GraphJobStatus.PARTIAL
    assert len(result.warnings) > 0
    warning_codes = [w.code for w in result.warnings]
    assert "provider_references_error" in warning_codes or "provider_metadata_error" in warning_codes

    # WBC metrics marked as provider_error, NOT crashed and NOT 0.0
    for cand_rec in result.candidates:
        assert cand_rec.wbc.availability == MetricAvailability.PROVIDER_ERROR
        assert cand_rec.wbc.value is None
