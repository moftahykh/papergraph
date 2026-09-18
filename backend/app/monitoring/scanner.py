from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Awaitable, Callable

from app.models.monitoring import MonitoredGraph, MonitoredGraphPaper
from app.providers.models import RawPaper, normalize_title
from app.repositories.monitoring import add_research_updates

logger = logging.getLogger("papergraph.monitoring.scanner")


RELATION_SCORES = {
    "direct_citation": 0.95,
    "shared_references": 0.88,
    "semantic_similarity": 0.84,
    "related_recommendation": 0.78,
    "same_topic": 0.72,
}
RELATION_PRIORITY = {
    relation: index
    for index, relation in enumerate(
        (
            "same_topic",
            "related_recommendation",
            "semantic_similarity",
            "shared_references",
            "direct_citation",
        )
    )
}


class ProviderScanError(RuntimeError):
    """Raised when every provider call needed by a scan fails."""


@dataclass(slots=True)
class ScanResult:
    graph_id: str
    candidates_seen: int
    updates_created: int
    provider_errors: list[str] = field(default_factory=list)


@dataclass(slots=True)
class _Candidate:
    paper: RawPaper
    relation_type: str
    source_count: int = 1

    @property
    def score(self) -> float:
        return RELATION_SCORES[self.relation_type]


def _clean_doi(value: str | None) -> str | None:
    if not value:
        return None
    doi = value.strip().lower()
    for prefix in ("https://doi.org/", "http://doi.org/", "doi:"):
        if doi.startswith(prefix):
            doi = doi[len(prefix) :]
    return doi or None


def _canonical_id(paper: RawPaper) -> str:
    doi = _clean_doi(paper.doi)
    if doi:
        return f"doi:{doi}"
    if paper.semantic_scholar_id:
        return f"s2:{paper.semantic_scholar_id.strip()}"
    if paper.open_alex_id:
        return f"openalex:{paper.open_alex_id.rstrip('/').split('/')[-1]}"
    if paper.provider_id:
        return f"{paper.provider}:{paper.provider_id.strip()}"
    return f"title:{normalize_title(paper.title)}"


def _identity_aliases(
    *,
    canonical_id: str,
    doi: str | None = None,
    semantic_scholar_id: str | None = None,
    openalex_id: str | None = None,
    title: str | None = None,
) -> set[str]:
    aliases = {canonical_id.strip().lower()}
    clean_doi = _clean_doi(doi)
    if clean_doi:
        aliases.add(f"doi:{clean_doi}")
    if semantic_scholar_id:
        aliases.add(f"s2:{semantic_scholar_id.strip().lower()}")
    if openalex_id:
        aliases.add(f"openalex:{openalex_id.rstrip('/').split('/')[-1].lower()}")
    if title:
        aliases.add(f"title:{normalize_title(title)}")
    return aliases


def _paper_aliases(paper: RawPaper) -> set[str]:
    return _identity_aliases(
        canonical_id=_canonical_id(paper),
        doi=paper.doi,
        semantic_scholar_id=paper.semantic_scholar_id,
        openalex_id=paper.open_alex_id,
        title=paper.title,
    )


def _stored_paper_aliases(paper: MonitoredGraphPaper) -> set[str]:
    return _identity_aliases(
        canonical_id=paper.canonical_id,
        doi=paper.doi,
        semantic_scholar_id=paper.semantic_scholar_id,
        openalex_id=paper.openalex_id,
        title=paper.title,
    )


def _published_at(paper: RawPaper) -> datetime | None:
    raw = paper.raw_data or {}
    value = raw.get("publicationDate") or raw.get("publication_date")
    if isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
            return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
        except ValueError:
            pass
    if paper.year and 0 < paper.year <= 3000:
        # Provider adapters currently expose year, not a reliable full date.
        return datetime(paper.year, 1, 1, tzinfo=timezone.utc)
    return None


def _merge_paper(primary: RawPaper, enrichment: RawPaper | None) -> RawPaper:
    if enrichment is None:
        return primary
    values: dict[str, Any] = {}
    for field_name in (
        "doi",
        "abstract",
        "year",
        "venue",
        "semantic_scholar_id",
        "open_alex_id",
    ):
        if getattr(primary, field_name, None) is None:
            values[field_name] = getattr(enrichment, field_name, None)
    if not primary.title or primary.title.startswith("Untitled"):
        values["title"] = enrichment.title
    if values:
        return primary.model_copy(update=values)
    return primary


def _explanation(candidate: _Candidate) -> str:
    if candidate.relation_type == "direct_citation":
        return (
            f"Cites {candidate.source_count} paper(s) already saved in this graph."
        )
    if candidate.relation_type == "related_recommendation":
        return "Related recommendation from Semantic Scholar."
    if candidate.relation_type == "semantic_similarity":
        return "Semantically similar to papers already saved in this graph."
    if candidate.relation_type == "shared_references":
        return "Shares references with papers already saved in this graph."
    return "Matches the graph's research topic."


class MonitoringScanner:
    """Provider orchestration and deterministic update generation."""

    def __init__(
        self,
        semantic_scholar: Any | None = None,
        openalex: Any | None = None,
        crossref: Any | None = None,
    ) -> None:
        self.semantic_scholar = semantic_scholar
        self.openalex = openalex
        self.crossref = crossref

    async def _call(
        self,
        errors: list[str],
        provider_name: str,
        operation: Callable[[], Awaitable[Any]],
    ) -> tuple[Any | None, bool]:
        try:
            return await operation(), True
        except Exception as exc:  # provider failures must not crash other providers
            message = f"{provider_name}: {type(exc).__name__}"
            errors.append(message)
            logger.warning("Research monitoring provider call failed: %s", message)
            return None, False

    async def _collect_candidates(
        self,
        graph: MonitoredGraph,
        errors: list[str],
    ) -> tuple[dict[str, _Candidate], int]:
        candidates: dict[str, _Candidate] = {}
        attempted = 0
        successful = 0

        async def add_items(items: list[RawPaper], relation_type: str) -> None:
            for paper in items:
                if not paper or not paper.title:
                    continue
                paper_aliases = _paper_aliases(paper)
                key = next(
                    (
                        existing_key
                        for existing_key, existing in candidates.items()
                        if paper_aliases & _paper_aliases(existing.paper)
                    ),
                    _canonical_id(paper),
                )
                existing = candidates.get(key)
                if existing is None:
                    candidates[key] = _Candidate(
                        paper=paper,
                        relation_type=relation_type,
                    )
                elif RELATION_PRIORITY[relation_type] > RELATION_PRIORITY[
                    existing.relation_type
                ]:
                    existing.paper = _merge_paper(existing.paper, paper)
                    existing.relation_type = relation_type
                    existing.source_count += 1
                else:
                    existing.paper = _merge_paper(existing.paper, paper)
                    existing.source_count += 1

        for seed in graph.papers:
            semantic_identifier = seed.semantic_scholar_id or seed.doi
            if self.semantic_scholar and semantic_identifier:
                attempted += 2
                citations, citations_ok = await self._call(
                    errors,
                    "semantic_scholar.citations",
                    lambda semantic_identifier=semantic_identifier: self.semantic_scholar.get_citations(
                        semantic_identifier, limit=50
                    ),
                )
                recommendations, recommendations_ok = await self._call(
                    errors,
                    "semantic_scholar.recommendations",
                    lambda semantic_identifier=semantic_identifier: self.semantic_scholar.get_recommendations(
                        semantic_identifier, limit=30
                    ),
                )
                successful += int(citations_ok) + int(recommendations_ok)
                if citations:
                    await add_items(citations.items, "direct_citation")
                if recommendations:
                    await add_items(recommendations, "related_recommendation")

            if self.openalex and seed.openalex_id:
                attempted += 1
                citations, citations_ok = await self._call(
                    errors,
                    "openalex.citations",
                    lambda seed=seed: self.openalex.get_citations(
                        seed.openalex_id, limit=50
                    ),
                )
                successful += int(citations_ok)
                if citations:
                    await add_items(citations.items, "direct_citation")

        if attempted and not successful:
            raise ProviderScanError(
                "All provider calls failed during the monitoring scan."
            )
        return candidates, attempted

    async def scan_graph(self, db: Any, graph: MonitoredGraph) -> ScanResult:
        errors: list[str] = []
        candidates, _ = await self._collect_candidates(graph, errors)
        existing_aliases: set[str] = set()
        for stored_paper in graph.papers:
            existing_aliases.update(_stored_paper_aliases(stored_paper))

        payloads: list[dict[str, Any]] = []
        for candidate in candidates.values():
            paper = candidate.paper
            if _paper_aliases(paper) & existing_aliases:
                continue

            if self.crossref and paper.doi:
                enriched, _ = await self._call(
                    errors,
                    "crossref.resolve",
                    lambda paper=paper: self.crossref.resolve(paper.doi),
                )
                paper = _merge_paper(paper, enriched)

            payloads.append(
                {
                    "canonical_paper_id": _canonical_id(paper),
                    "doi": _clean_doi(paper.doi),
                    "title": paper.title.strip(),
                    "abstract": paper.abstract,
                    "published_at": _published_at(paper),
                    "relevance_score": candidate.score,
                    "relation_type": candidate.relation_type,
                    "explanation": _explanation(candidate),
                    "detected_at": datetime.now(timezone.utc),
                    "is_read": False,
                    "is_added_to_graph": False,
                }
            )

        created = await add_research_updates(db, graph.id, payloads)
        return ScanResult(
            graph_id=graph.id,
            candidates_seen=len(candidates),
            updates_created=created,
            provider_errors=errors,
        )