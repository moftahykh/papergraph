import pytest
from app.models.canonical_paper import CanonicalPaper, Author, SourceAvailability
from app.providers.models import RawPaper
from app.resolution.normalizers import (
    normalize_doi,
    normalize_pmid,
    normalize_title,
    extract_first_author_surname,
    build_deterministic_key,
)
from app.resolution.similarity import token_sort_ratio, is_title_match
from app.resolution.merger import merge_canonical_papers
from app.resolution.resolver import IdentityResolver


# ==============================================================================
# 1. Normalization Tests: Acceptance Criteria #1
# ==============================================================================

def test_doi_normalization_uniformity():
    """Acceptance Criteria #1: DOI URL, 'doi:...', and bare DOI resolve to the same record."""
    doi_bare = "10.1038/nature12373"
    doi_url_https = "https://doi.org/10.1038/nature12373"
    doi_url_http = "http://doi.org/10.1038/nature12373"
    doi_prefix = "doi:10.1038/nature12373"
    doi_uppercase = "10.1038/NATURE12373"

    assert normalize_doi(doi_bare) == "10.1038/nature12373"
    assert normalize_doi(doi_url_https) == "10.1038/nature12373"
    assert normalize_doi(doi_url_http) == "10.1038/nature12373"
    assert normalize_doi(doi_prefix) == "10.1038/nature12373"
    assert normalize_doi(doi_uppercase) == "10.1038/nature12373"


def test_resolver_doi_variants_deduplicate_to_single_paper():
    """Verify that records ingested with varying DOI formats merge into one."""
    resolver = IdentityResolver()

    paper1 = RawPaper(
        provider="crossref",
        provider_id="10.1038/nature12373",
        doi="https://doi.org/10.1038/nature12373",
        title="Nanometre-scale thermometry",
    )
    paper2 = RawPaper(
        provider="semantic_scholar",
        provider_id="s2_123",
        doi="doi:10.1038/nature12373",
        title="Nanometre-scale thermometry in a living cell",
    )
    paper3 = RawPaper(
        provider="openalex",
        provider_id="W12345",
        doi="10.1038/nature12373",
        title="Nanometre-scale thermometry in a living cell",
    )

    resolver.ingest(paper1)
    resolver.ingest(paper2)
    resolver.ingest(paper3)

    assert len(resolver.canonical_papers) == 1
    canonical = resolver.canonical_papers[0]
    assert canonical.canonical_id == "doi:10.1038/nature12373"
    assert canonical.source_availability.crossref is True
    assert canonical.source_availability.semantic_scholar is True
    assert canonical.source_availability.open_alex is True


# ==============================================================================
# 2. Four Provider Merging: Acceptance Criteria #2
# ==============================================================================

def test_same_work_found_in_four_providers_creates_one_canonical_paper():
    """Acceptance Criteria #2: The same work found in four providers creates one canonical paper."""
    resolver = IdentityResolver()

    # Provider 1: Crossref (Verified bibliographic data, no abstract)
    p_crossref = RawPaper(
        provider="crossref",
        provider_id="10.1038/nature12373",
        doi="10.1038/nature12373",
        title="Nanometre-scale thermometry in a living cell",
        authors=[Author(name="G. Kucsko", position=1)],
        year=2013,
        venue="Nature",
        citation_count=850,
        reference_ids=["doi:10.1038/nmat2771"],
    )

    # Provider 2: Semantic Scholar (Adds rich abstract, citations, and PMID)
    p_s2 = RawPaper(
        provider="semantic_scholar",
        provider_id="s2_12345",
        doi="10.1038/nature12373",
        pmid="23903748",
        semantic_scholar_id="s2_12345",
        title="Nanometre-scale thermometry in a living cell",
        authors=[
            Author(name="G. Kucsko", position=1),
            Author(name="P. C. Maurer", position=2),
        ],
        year=2013,
        abstract="Detailed abstract of intracellular temperature measurement.",
        citation_count=940,
        topics=["Physics", "Nanotechnology"],
    )

    # Provider 3: OpenAlex (Adds author affiliations and OpenAlex ID)
    p_openalex = RawPaper(
        provider="openalex",
        provider_id="W2147152072",
        doi="10.1038/nature12373",
        open_alex_id="https://openalex.org/W2147152072",
        title="Nanometre-scale thermometry in a living cell",
        authors=[
            Author(
                name="G. Kucsko",
                position=1,
                affiliation="Harvard Department of Physics",
            )
        ],
        year=2013,
        topics=["Optics", "Thermometry"],
    )

    # Provider 4: PubMed (PMID with biomedical topics)
    p_pubmed = RawPaper(
        provider="pubmed",
        provider_id="23903748",
        pmid="23903748",
        doi="10.1038/nature12373",
        title="Nanometre-scale thermometry in a living cell.",
        authors=[Author(name="Kucsko G", position=1)],
        year=2013,
        topics=["Biomedicine", "Life Sciences"],
    )

    # Ingest all four providers in sequence
    resolver.ingest(p_crossref)
    resolver.ingest(p_s2)
    resolver.ingest(p_openalex)
    resolver.ingest(p_pubmed)

    # Must collapse to exactly ONE canonical paper
    assert len(resolver.canonical_papers) == 1
    result = resolver.canonical_papers[0]

    # Verify merged attributes
    assert result.canonical_id == "doi:10.1038/nature12373"
    assert result.doi == "10.1038/nature12373"
    assert result.pmid == "23903748"
    assert result.semantic_scholar_id == "s2_12345"
    assert result.open_alex_id == "https://openalex.org/W2147152072"
    
    # Authors enriched with affiliation
    assert len(result.authors) == 2
    assert result.authors[0].affiliation == "Harvard Department of Physics"

    # Abstract preserved from S2 (not overwritten with null from OpenAlex/PubMed)
    assert result.abstract == "Detailed abstract of intracellular temperature measurement."

    # Max citations preserved
    assert result.citation_count == 940

    # Topics merged across providers
    assert "Physics" in result.topics
    assert "Thermometry" in result.topics
    assert "Biomedicine" in result.topics

    # All 4 sources confirmed in availability flags
    assert result.source_availability.crossref is True
    assert result.source_availability.semantic_scholar is True
    assert result.source_availability.open_alex is True
    assert result.source_availability.pubmed is True

    # Provenance tracked
    contributors = result.provenance.get("contributors", [])
    assert len(contributors) == 4
    assert "crossref" in contributors
    assert "semantic_scholar" in contributors
    assert "openalex" in contributors
    assert "pubmed" in contributors

    # Completeness recalculated
    assert result.completeness >= 0.90


# ==============================================================================
# 3. Non-Overwriting of Metadata: Task #4
# ==============================================================================

def test_metadata_merging_does_not_overwrite_with_null():
    primary = CanonicalPaper(
        canonical_id="doi:10.1000/1",
        doi="10.1000/1",
        title="Complete Study",
        normalized_title="complete study",
        authors=[Author(name="Alice Smith", position=1, affiliation="MIT")],
        year=2020,
        venue="Top Journal",
        abstract="Very detailed and informative abstract.",
        citation_count=50,
        topics=["AI"],
    )

    secondary = CanonicalPaper(
        canonical_id="doi:10.1000/1",
        doi="10.1000/1",
        title="Complete Study",
        normalized_title="complete study",
        authors=[],  # Empty authors
        year=None,   # Missing year
        venue=None,  # Missing venue
        abstract=None, # Missing abstract
        citation_count=10, # Lower citations
        topics=[],
    )

    merged = merge_canonical_papers(primary, secondary)

    # Primary values must be preserved intact!
    assert merged.abstract == "Very detailed and informative abstract."
    assert merged.year == 2020
    assert merged.venue == "Top Journal"
    assert merged.citation_count == 50
    assert len(merged.authors) == 1
    assert merged.authors[0].affiliation == "MIT"


# ==============================================================================
# 4. Ambiguous Title Disambiguation: Acceptance Criteria #3
# ==============================================================================

def test_ambiguous_title_results_returned_for_disambiguation():
    """Acceptance Criteria #3: Ambiguous title results are returned instead of being silently selected."""
    resolver = IdentityResolver()

    # Two papers with nearly identical titles but different authors and years
    paper_a = CanonicalPaper(
        canonical_id="doi:10.1000/a",
        doi="10.1000/a",
        title="Deep Learning in Medical Image Analysis",
        normalized_title="deep learning in medical image analysis",
        authors=[Author(name="John Doe", position=1)],
        year=2018,
    )
    paper_b = CanonicalPaper(
        canonical_id="doi:10.1000/b",
        doi="10.1000/b",
        title="Deep Learning for Medical Image Analysis",
        normalized_title="deep learning for medical image analysis",
        authors=[Author(name="Jane Smith", position=1)],
        year=2021,
    )

    candidates = [paper_a, paper_b]
    query = "Deep Learning Medical Image Analysis"

    resolved, exact, ambiguous, confidence = resolver.disambiguate_title_query(
        query, candidates
    )

    # Must NOT select one silently!
    assert resolved is False
    assert exact is None
    assert len(ambiguous) == 2
    assert confidence > 0.80


def test_unambiguous_exact_title_resolves_directly():
    resolver = IdentityResolver()

    paper = CanonicalPaper(
        canonical_id="doi:10.1000/consensus",
        doi="10.1000/consensus",
        title="In Search of an Understandable Consensus Algorithm",
        normalized_title="in search of an understandable consensus algorithm",
        authors=[Author(name="Diego Ongaro", position=1)],
        year=2014,
    )

    resolved, exact, ambiguous, confidence = resolver.disambiguate_title_query(
        "In Search of an Understandable Consensus Algorithm", [paper]
    )

    assert resolved is True
    assert exact is not None
    assert exact.canonical_id == "doi:10.1000/consensus"
    assert ambiguous == []


# ==============================================================================
# 5. Fuzzy and Deterministic Matching Priority
# ==============================================================================

def test_fuzzy_title_matching_deduplicates_near_duplicates():
    resolver = IdentityResolver()

    # Ingest baseline
    paper1 = RawPaper(
        provider="semantic_scholar",
        provider_id="s2_1",
        title="A Fast Distributed Consensus Protocol for Edge Networks",
        authors=[Author(name="Leslie Lamport", position=1)],
        year=2019,
    )
    resolver.ingest(paper1)

    # Ingest near-duplicate (minor word swap / formatting difference, same author & year, no DOI)
    paper2 = RawPaper(
        provider="openalex",
        provider_id="W_2",
        title="A Fast Distributed Consensus Protocol on Edge Networks",  # for vs on
        authors=[Author(name="L. Lamport", position=1)],
        year=2019,
    )
    resolver.ingest(paper2)

    # Should match via Tier 5 fuzzy title match
    assert len(resolver.canonical_papers) == 1
    assert resolver.canonical_papers[0].source_availability.semantic_scholar is True
    assert resolver.canonical_papers[0].source_availability.open_alex is True
