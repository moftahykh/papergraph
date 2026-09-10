from app.models.canonical_paper import Author
from app.providers.models import RawPaper, normalize_title


def test_normalize_title():
    assert normalize_title("  The Byzantine Generals Problem!  ") == "the byzantine generals problem"
    assert normalize_title("Deep Learning: A Practical Guide") == "deep learning a practical guide"
    assert normalize_title("") == ""


def test_raw_paper_to_canonical_with_doi():
    raw = RawPaper(
        provider="crossref",
        provider_id="10.1038/example",
        doi="10.1038/example",
        title="Example Paper Title",
        authors=[Author(name="First Author", position=1)],
        year=2020,
        venue="Nature",
        abstract="Short abstract",
        citation_count=100,
        topics=["Physics"],
    )

    canonical = raw.to_canonical()
    assert canonical.canonical_id == "doi:10.1038/example"
    assert canonical.doi == "10.1038/example"
    assert canonical.source_availability.crossref is True
    assert canonical.source_availability.semantic_scholar is False
    assert canonical.provenance["primary_provider"] == "crossref"
    assert canonical.provenance["provider_id"] == "10.1038/example"
    assert canonical.completeness == 1.0  # all 7 fields present


def test_raw_paper_to_canonical_fallback_identifiers():
    # PMID fallback when DOI absent
    raw_pmid = RawPaper(
        provider="pubmed",
        provider_id="12345678",
        pmid="12345678",
        title="Biomedical Study",
    )
    assert raw_pmid.to_canonical().canonical_id == "pmid:12345678"

    # OpenAlex fallback when DOI and PMID absent
    raw_oa = RawPaper(
        provider="openalex",
        provider_id="W99999",
        open_alex_id="https://openalex.org/W99999",
        title="OpenAlex Work",
    )
    assert raw_oa.to_canonical().canonical_id == "openalex:W99999"

    # Semantic Scholar fallback
    raw_s2 = RawPaper(
        provider="semantic_scholar",
        provider_id="s2_abc",
        semantic_scholar_id="s2_abc",
        title="S2 Paper",
    )
    assert raw_s2.to_canonical().canonical_id == "s2:s2_abc"
