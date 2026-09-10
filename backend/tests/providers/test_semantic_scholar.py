import json
from pathlib import Path
import pytest
import httpx
from app.providers.semantic_scholar import SemanticScholarProvider

FIXTURES_DIR = Path(__file__).parent / "fixtures"


@pytest.fixture
def s2_fixture():
    with open(FIXTURES_DIR / "semantic_scholar_paper.json", "r", encoding="utf-8") as f:
        return json.load(f)


@pytest.mark.asyncio
async def test_semantic_scholar_resolve_mock(s2_fixture):
    transport = httpx.MockTransport(
        lambda request: httpx.Response(200, json=s2_fixture)
    )
    async with httpx.AsyncClient(transport=transport) as client:
        provider = SemanticScholarProvider(client=client)
        raw_paper = await provider.resolve("10.1038/nature12373")

        assert raw_paper is not None
        assert raw_paper.provider == "semantic_scholar"
        assert raw_paper.doi == "10.1038/nature12373"
        assert raw_paper.pmid == "23903748"
        assert raw_paper.citation_count == 940
        assert raw_paper.reference_count == 35
        assert len(raw_paper.authors) == 2
        assert "Physics" in raw_paper.topics

        canonical = raw_paper.to_canonical()
        assert canonical.canonical_id == "doi:10.1038/nature12373"
        assert canonical.source_availability.semantic_scholar is True
        assert canonical.pmid == "23903748"


@pytest.mark.asyncio
async def test_semantic_scholar_search_mock(s2_fixture):
    search_payload = {"total": 1, "offset": 0, "data": [s2_fixture]}
    transport = httpx.MockTransport(
        lambda request: httpx.Response(200, json=search_payload)
    )
    async with httpx.AsyncClient(transport=transport) as client:
        provider = SemanticScholarProvider(client=client)
        results = await provider.search("thermometry living cell", limit=5)

        assert len(results) == 1
        assert results[0].provider_id == s2_fixture["paperId"]


@pytest.mark.asyncio
async def test_semantic_scholar_references_pagination_mock(s2_fixture):
    ref_payload = {
        "total": 2,
        "offset": 0,
        "data": [{"citedPaper": s2_fixture}],
    }
    transport = httpx.MockTransport(
        lambda request: httpx.Response(200, json=ref_payload)
    )
    async with httpx.AsyncClient(transport=transport) as client:
        provider = SemanticScholarProvider(client=client)
        page = await provider.get_references("s2_test_id", limit=1)

        assert len(page.items) == 1
        assert page.total == 2
        assert page.has_more is True
        assert page.next_cursor == "1"
