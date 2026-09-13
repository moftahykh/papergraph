import asyncio
import logging
from typing import List, Dict, Optional, Set, Tuple
from app.models.canonical_paper import CanonicalPaper
from app.models.graph import GraphWarning
from app.models.metric import MetricResult
from app.candidates.models import CandidateRecord
from app.enrichment.models import EnrichmentStatusEnum
from app.cache.manager import ResponseCache
from app.core.config import settings

logger = logging.getLogger("papergraph.enrichment.citations")


class CitationEnricher:
    """
    Selects top candidates (using composite PreScore + WBC ranking) and fetches
    inbound citations for origin and selected candidates concurrently with bounded
    concurrency and provider fallback.
    """
    def __init__(
        self,
        s2_provider=None,
        openalex_provider=None,
        cache: Optional[ResponseCache] = None,
        max_candidates: int = settings.ENRICHMENT_MAX_CANDIDATES_CITATIONS,
        max_cites_per_paper: int = settings.ENRICHMENT_MAX_CITATIONS_PER_PAPER,
    ):
        self.s2_provider = s2_provider
        self.openalex_provider = openalex_provider
        self.cache = cache or ResponseCache()
        self.max_candidates = max_candidates
        self.max_cites_per_paper = max_cites_per_paper

    def select_top_candidates(
        self,
        candidates: List[CandidateRecord],
        wbc_scores: Dict[str, MetricResult],
    ) -> List[CandidateRecord]:
        """
        Selects top candidates for inbound citation enrichment
        based on composite PreScore and available WBC similarity.
        """
        def ranking_key(cand: CandidateRecord) -> float:
            cid = cand.paper.canonical_id
            wbc_res = wbc_scores.get(cid)
            wbc_val = wbc_res.value if wbc_res and wbc_res.value is not None else cand.pre_score
            return 0.60 * cand.pre_score + 0.40 * wbc_val

        sorted_cands = sorted(candidates, key=ranking_key, reverse=True)
        return sorted_cands[:self.max_candidates]

    async def fetch_paper_citations(
        self,
        paper: CanonicalPaper,
        warnings: Optional[List[GraphWarning]] = None,
    ) -> Tuple[List[str], EnrichmentStatusEnum, bool]:
        """
        Fetches inbound citations for a single paper with pagination and caching.
        Attempts primary provider and seamlessly falls back to alternative provider.
        """
        warnings = warnings if warnings is not None else []

        if paper.citation_ids and len(paper.citation_ids) >= 10:
            return paper.citation_ids, EnrichmentStatusEnum.SUCCESS, True

        provider_id = paper.semantic_scholar_id or paper.doi or paper.canonical_id
        cache_key = ResponseCache.generate_key("citations", provider_id)

        async def _do_fetch() -> Tuple[List[str], EnrichmentStatusEnum, bool]:
            cite_ids: List[str] = []
            providers_to_try = [p for p in [self.s2_provider, self.openalex_provider] if p is not None]

            if not providers_to_try:
                return cite_ids, EnrichmentStatusEnum.SKIPPED, False

            for provider in providers_to_try:
                try:
                    cursor: Optional[str] = None
                    is_complete = True
                    target_id = provider_id
                    if provider.name == "openalex" and getattr(paper, "open_alex_id", None):
                        target_id = paper.open_alex_id

                    while True:
                        page = await provider.get_citations(
                            provider_id=target_id,
                            cursor=cursor,
                            limit=min(100, self.max_cites_per_paper - len(cite_ids)),
                        )

                        for item in page.items:
                            cid = item.doi or item.semantic_scholar_id or item.provider_id
                            if cid and cid not in cite_ids:
                                cite_ids.append(cid)

                        if not page.has_more or not page.next_cursor:
                            is_complete = True
                            break

                        cursor = page.next_cursor
                        if len(cite_ids) >= self.max_cites_per_paper:
                            is_complete = False
                            break

                    status = EnrichmentStatusEnum.SUCCESS if cite_ids else EnrichmentStatusEnum.EMPTY
                    if not is_complete and cite_ids:
                        status = EnrichmentStatusEnum.PARTIAL

                    return cite_ids, status, is_complete

                except Exception as e:
                    logger.warning(f"[{provider.name}] Error fetching citations for {paper.canonical_id}: {e}")

            warnings.append(
                GraphWarning(
                    code="provider_citations_error",
                    message=f"Failed to fetch citations for {paper.canonical_id} across all providers.",
                    severity="warning",
                )
            )
            return cite_ids, EnrichmentStatusEnum.FAILED, False

        result = await self.cache.get_or_fetch(cache_key, _do_fetch)
        return result

    async def enrich_citations(
        self,
        origin: CanonicalPaper,
        candidates: List[CandidateRecord],
        wbc_scores: Dict[str, MetricResult],
        warnings: Optional[List[GraphWarning]] = None,
    ) -> Tuple[
        Tuple[List[str], EnrichmentStatusEnum, bool],
        Dict[str, Tuple[List[str], EnrichmentStatusEnum, bool, bool]],
    ]:
        """
        Enriches inbound citations for origin and selected candidates concurrently with a bounded semaphore.
        """
        warnings = warnings if warnings is not None else []

        # 1. Fetch origin citations first
        origin_cites, origin_status, origin_complete = await self.fetch_paper_citations(
            origin, warnings=warnings
        )
        if origin_cites:
            merged_cites = list(set(origin.citation_ids + origin_cites))
            origin.citation_ids = merged_cites
            origin.citation_count = max(origin.citation_count, len(merged_cites))

        # 2. Select top candidates
        selected = self.select_top_candidates(candidates, wbc_scores)
        selected_cids = {c.paper.canonical_id for c in selected}

        # 3. Concurrent retrieval with bounded semaphore
        sem = asyncio.Semaphore(settings.ENRICHMENT_CONCURRENCY_LIMIT)

        async def _fetch_single(cand: CandidateRecord):
            async with sem:
                cites, status, complete = await self.fetch_paper_citations(
                    cand.paper, warnings=warnings
                )
                if cites:
                    cand.paper.citation_ids = list(set(cand.paper.citation_ids + cites))
                    cand.paper.citation_count = max(
                        cand.paper.citation_count, len(cand.paper.citation_ids)
                    )
                return cand.paper.canonical_id, (cand.paper.citation_ids, status, complete, True)

        tasks = [_fetch_single(c) for c in selected]
        gathered = await asyncio.gather(*tasks, return_exceptions=True)

        candidate_results: Dict[str, Tuple[List[str], EnrichmentStatusEnum, bool, bool]] = {}
        for item in gathered:
            if isinstance(item, tuple) and len(item) == 2:
                cid, res = item
                candidate_results[cid] = res

        # 4. Fill unselected candidates
        for cand in candidates:
            cid = cand.paper.canonical_id
            if cid not in candidate_results:
                candidate_results[cid] = (
                    cand.paper.citation_ids,
                    EnrichmentStatusEnum.NOT_SELECTED,
                    False,
                    False,
                )

        return (origin_cites, origin_status, origin_complete), candidate_results
