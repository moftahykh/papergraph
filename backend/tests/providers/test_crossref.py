import json
from pathlib import Path
import pytest
import httpx
from app.providers.crossref import CrossRefProvider, clean_doi

FIXTURES_DIR = Path(__file__).parent / "fixtures"


@pytest.fixture
def crossref_fixture():
    with open(FIXTURES_DIR / "crossref_resolve.json", "r", encoding="utf-8") as f:
        return json.load(f)


def test_clean_doi_helper():
    assert clean_doi("https://doi.org/10.1038/nature12373") == "10.1038/nature12373"
    assert clean_doi("http://doi.org/10.1038/nature12373") == "10.1038/nature12373"
    assert clean_doi("doi:10.1038/nature12373") == "10.1038/nature12373"
    assert clean_doi("10.1038/nature12373") == "10.1038/nature12373"


@pytest.mark.asyncio
async def test_crossref_resolve_mock(crossref_fixture):
    # Mock transport returning crossref fixture
    transport = httpx.MockTransport(
        lambda request: httpx.Response(200, json=crossref_fixture)
    )
    async with httpx.AsyncClient(transport=transport) as client:
        provider = CrossRefProvider(client=client)
        raw_paper = await provider.resolve("https://doi.org/10.1038/nature12373")

        assert raw_paper is not None
        assert raw_paper.doi == "10.1038/nature12373"
        assert raw_paper.provider == "crossref"
        assert "Nanometre-scale thermometry" in raw_paper.title
        assert raw_paper.year == 2013
        assert raw_paper.venue == "Nature"
        assert raw_paper.citation_count == 850
        assert len(raw_paper.authors) == 2
        assert raw_paper.authors[0].name == "G. Kucsko"
        assert raw_paper.authors[0].affiliation == "Department of Physics, Harvard University"
        assert len(raw_paper.reference_ids) == 2
        assert "doi:10.1038/nmat2771" in raw_paper.reference_ids

        # Verify JATS XML was stripped from abstract
        assert "<jats:p>" not in raw_paper.abstract
        assert "Accurate measurement of intracellular temperature" in raw_paper.abstract

        # Verify conversion to CanonicalPaper
        canonical = raw_paper.to_canonical()
        assert canonical.canonical_id == "doi:10.1038/nature12373"
        assert canonical.source_availability.crossref is True
        assert canonical.provenance["primary_provider"] == "crossref"
