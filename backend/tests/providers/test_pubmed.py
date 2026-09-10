import json
from pathlib import Path
import pytest
import httpx
from app.providers.pubmed import PubMedProvider

FIXTURES_DIR = Path(__file__).parent / "fixtures"


@pytest.fixture
def pubmed_fixture():
    with open(FIXTURES_DIR / "pubmed_data.json", "r", encoding="utf-8") as f:
        return json.load(f)


@pytest.mark.asyncio
async def test_pubmed_resolve_and_search_mock(pubmed_fixture):
    def handle_request(request: httpx.Request):
        url = str(request.url)
        if "esearch.fcgi" in url:
            return httpx.Response(200, json=pubmed_fixture["esearch"])
        elif "esummary.fcgi" in url:
            return httpx.Response(200, json=pubmed_fixture["esummary"])
        return httpx.Response(404, json={})

    transport = httpx.MockTransport(handle_request)
    async with httpx.AsyncClient(transport=transport) as client:
        provider = PubMedProvider(client=client)

        # Test direct PMID resolution
        raw_paper = await provider.resolve("23903748")
        assert raw_paper is not None
        assert raw_paper.provider == "pubmed"
        assert raw_paper.pmid == "23903748"
        assert raw_paper.doi == "10.1038/nature12373"
        assert raw_paper.venue == "Nature"
        assert raw_paper.year == 2013
        assert len(raw_paper.authors) == 2
        assert raw_paper.authors[0].name == "Kucsko G"

        canonical = raw_paper.to_canonical()
        assert canonical.canonical_id == "doi:10.1038/nature12373"
        assert canonical.source_availability.pubmed is True

        # Test Search (two-stage ESearch -> ESummary pipeline)
        search_results = await provider.search("nanometre thermometry", limit=5)
        assert len(search_results) == 1
        assert search_results[0].pmid == "23903748"
