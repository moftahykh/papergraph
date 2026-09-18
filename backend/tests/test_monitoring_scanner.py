from types import SimpleNamespace

import pytest

from app.monitoring.scanner import (
    MonitoringScanner,
    ProviderScanError,
    _canonical_id,
)
from app.providers.models import Page, RawPaper


def paper(
    *,
    provider: str = "semantic_scholar",
    provider_id: str = "s2-new",
    title: str = "New Research Paper",
    doi: str | None = "10.1000/new-paper",
    semantic_scholar_id: str | None = "s2-new",
    open_alex_id: str | None = None,
    year: int = 2026,
) -> RawPaper:
    return RawPaper(
        provider=provider,
        provider_id=provider_id,
        title=title,
        doi=doi,
        semantic_scholar_id=semantic_scholar_id,
        open_alex_id=open_alex_id,
        year=year,
    )


class FakeProvider:
    def __init__(self, citations=None, recommendations=None, error=None):
        self.citations = citations or []
        self.recommendations = recommendations or []
        self.error = error

    async def get_citations(self, provider_id: str, limit: int = 50):
        if self.error:
            raise self.error
        return Page(items=self.citations, total=len(self.citations))

    async def get_recommendations(self, provider_id: str, limit: int = 30):
        if self.error:
            raise self.error
        return self.recommendations


class FakeDB:
    def __init__(self, existing=None):
        self.existing = set(existing or [])
        self.added = []
        self.commits = 0

    async def execute(self, _statement):
        existing = self.existing

        class Result:
            def scalars(self):
                class Scalars:
                    def all(self):
                        return list(existing)

                return Scalars()

        return Result()

    def add(self, item):
        self.added.append(item)

    async def commit(self):
        self.commits += 1


def graph_with(*papers):
    return SimpleNamespace(id="monitor_test", papers=list(papers))


@pytest.mark.asyncio
async def test_scanner_deduplicates_same_doi_across_providers():
    same_s2 = paper(provider_id="s2-1", semantic_scholar_id="s2-1")
    same_oa = paper(
        provider="openalex",
        provider_id="W1",
        semantic_scholar_id=None,
        open_alex_id="https://openalex.org/W1",
    )
    scanner = MonitoringScanner(
        semantic_scholar=FakeProvider(citations=[same_s2]),
        openalex=FakeProvider(citations=[same_oa]),
    )
    db = FakeDB()

    result = await scanner.scan_graph(
        db,
        graph_with(
            SimpleNamespace(
                canonical_id="doi:10.1000/seed",
                doi="10.1000/seed",
                semantic_scholar_id="s2-seed",
                openalex_id="W-seed",
                title="Seed",
            )
        ),
    )

    assert result.candidates_seen == 1
    assert result.updates_created == 1
    assert db.added[0].relation_type == "direct_citation"


@pytest.mark.asyncio
async def test_scanner_excludes_papers_already_in_graph():
    candidate = paper()
    scanner = MonitoringScanner(semantic_scholar=FakeProvider(citations=[candidate]))
    db = FakeDB()
    seed = SimpleNamespace(
        canonical_id="doi:10.1000/seed",
        doi="10.1000/seed",
        semantic_scholar_id="s2-seed",
        openalex_id=None,
        title="Seed",
    )
    saved = SimpleNamespace(
        canonical_id="doi:10.1000/new-paper",
        doi="10.1000/new-paper",
        semantic_scholar_id=None,
        openalex_id=None,
        title="New Research Paper",
    )

    result = await scanner.scan_graph(db, graph_with(seed, saved))

    assert result.candidates_seen == 1
    assert result.updates_created == 0
    assert db.added == []


@pytest.mark.asyncio
async def test_scanner_is_idempotent_for_existing_update():
    candidate = paper()
    scanner = MonitoringScanner(semantic_scholar=FakeProvider(citations=[candidate]))
    db = FakeDB(existing={"doi:10.1000/new-paper"})
    seed = SimpleNamespace(
        canonical_id="doi:10.1000/seed",
        doi="10.1000/seed",
        semantic_scholar_id="s2-seed",
        openalex_id=None,
        title="Seed",
    )

    result = await scanner.scan_graph(db, graph_with(seed))

    assert result.updates_created == 0
    assert db.added == []


@pytest.mark.asyncio
async def test_scanner_can_discover_from_doi_when_provider_id_is_missing():
    candidate = paper()
    provider = FakeProvider(citations=[candidate])
    scanner = MonitoringScanner(semantic_scholar=provider)
    db = FakeDB()
    seed = SimpleNamespace(
        canonical_id="doi:10.1000/seed",
        doi="10.1000/seed",
        semantic_scholar_id=None,
        openalex_id=None,
        title="Seed",
    )

    result = await scanner.scan_graph(db, graph_with(seed))

    assert result.candidates_seen == 1
    assert result.updates_created == 1


@pytest.mark.asyncio
async def test_scanner_persists_score_and_explanation():
    candidate = paper()
    scanner = MonitoringScanner(semantic_scholar=FakeProvider(citations=[candidate]))
    db = FakeDB()
    seed = SimpleNamespace(
        canonical_id="doi:10.1000/seed",
        doi="10.1000/seed",
        semantic_scholar_id="s2-seed",
        openalex_id=None,
        title="Seed",
    )

    await scanner.scan_graph(db, graph_with(seed))

    update = db.added[0]
    assert update.relevance_score == 0.95
    assert update.relation_type == "direct_citation"
    assert "already saved" in update.explanation
    assert update.published_at.year == 2026


@pytest.mark.asyncio
async def test_scanner_filters_uncorroborated_recommendations():
    candidate = paper(
        provider_id="s2-recommendation",
        semantic_scholar_id="s2-recommendation",
    )
    scanner = MonitoringScanner(
        semantic_scholar=FakeProvider(recommendations=[candidate])
    )
    db = FakeDB()
    seed = SimpleNamespace(
        canonical_id="doi:10.1000/seed",
        doi="10.1000/seed",
        semantic_scholar_id="s2-seed",
        openalex_id=None,
        title="Seed",
    )

    result = await scanner.scan_graph(db, graph_with(seed))

    assert result.candidates_seen == 1
    assert result.updates_created == 0
    assert db.added == []


@pytest.mark.asyncio
async def test_scanner_raises_when_all_provider_calls_fail():
    scanner = MonitoringScanner(
        semantic_scholar=FakeProvider(error=RuntimeError("upstream unavailable"))
    )
    seed = SimpleNamespace(
        canonical_id="doi:10.1000/seed",
        doi="10.1000/seed",
        semantic_scholar_id="s2-seed",
        openalex_id=None,
        title="Seed",
    )

    with pytest.raises(ProviderScanError):
        await scanner.scan_graph(FakeDB(), graph_with(seed))


def test_canonical_id_prefers_doi_then_provider_id_then_title():
    assert _canonical_id(paper(doi="10.1000/test")) == "doi:10.1000/test"
    assert (
        _canonical_id(
            paper(
                doi=None,
                provider_id="W123",
                semantic_scholar_id=None,
                open_alex_id="https://openalex.org/W123",
            )
        )
        == "openalex:W123"
    )
    assert (
        _canonical_id(
            paper(
                doi=None,
                provider_id="",
                semantic_scholar_id=None,
                open_alex_id=None,
                title="Title Fallback",
            )
        )
        == "title:title fallback"
    )