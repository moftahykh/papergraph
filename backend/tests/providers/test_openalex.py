import json
from pathlib import Path
import pytest
import httpx
from app.providers.openalex import OpenAlexProvider

FIXTURES_DIR = Path(__file__).parent / "fixtures"


@pytest.fixture
def openalex_fixture():
    with open(FIXTURES_DIR / "openalex_work.json", "r", encoding="utf-8") as f:
        return json.load(f)


@pytest.mark.asyncio
async def test_openalex_resolve_mock(openalex_fixture):
    transport = httpx.MockTransport(
        lambda request: httpx.Response(200, json=openalex_fixture)
    )
    async with httpx.AsyncClient(transport=transport) as client:
        provider = OpenAlexProvider(client=client)
        raw_paper = await provider.resolve("10.1038/nature12373")

        assert raw_paper is not None
        assert raw_paper.provider == "openalex"
        assert raw_paper.doi == "10.1038/nature12373"
        assert raw_paper.citation_count == 925
        assert raw_paper.year == 2013
        assert raw_paper.authors[0].affiliation == "Harvard University"
        assert "Thermometry" in raw_paper.topics
        assert len(raw_paper.reference_ids) == 2
        assert "openalex:W1987654321" in raw_paper.reference_ids

        # Verify inverted index abstract reconstruction
        assert raw_paper.abstract == "Accurate measurement of temperature in cells."

        # Verify CanonicalPaper conversion
        canonical = raw_paper.to_canonical()
        assert canonical.canonical_id == "doi:10.1038/nature12373"
        assert canonical.source_availability.open_alex is True


@pytest.mark.asyncio
async def test_openalex_citations_cursor_mock(openalex_fixture):
    citations_payload = {
        "meta": {
            "count": 50,
            "next_cursor": "cur_abc123",
        },
        "results": [openalex_fixture],
    }
    transport = httpx.MockTransport(
        lambda request: httpx.Response(200, json=citations_payload)
    )
    async with httpx.AsyncClient(transport=transport) as client:
        provider = OpenAlexProvider(client=client)
        page = await provider.get_citations("W2147152072", limit=1)

        assert len(page.items) == 1
        assert page.total == 50
        assert page.has_more is True
        assert page.next_cursor == "cur_abc123"
