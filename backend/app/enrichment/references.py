import asyncio
import logging
from typing import List, Dict, Optional, Set, Tuple
from app.models.canonical_paper import CanonicalPaper
from app.models.graph import GraphWarning
from app.candidates.models import CandidateRecord
from app.enrichment.models import EnrichmentStatusEnum
from app.cache.manager import ResponseCache
from app.core.config import settings

logger = logging.getLogger("papergraph.enrichment.references")


class ReferenceEnricher:
    """
    Fetches outbound references for origin and retained candidates using
    provider-specific pagination with bounded concurrency. Collapses duplicate
    requests and falls back across providers when rate limits are met.
    """
    def __init__(
        self,
        s2_provider=None,
        openalex_provider=None,
        cache: Optional[ResponseCache] = None,
        max_candidates: int = settings.ENRICHMENT_MAX_CANDIDATES_REFERENCES,
        max_refs_per_paper: int = settings.ENRICHMENT_MAX_REFERENCES_PER_PAPER,
    ):
        self.s2_provider = s2_provider
        self.openalex_provider = openalex_provider
        self.cache = cache or ResponseCache()
        self.max_candidates = max_candidates
        self.max_refs_per_paper = max_refs_per_paper

    async def fetch_paper_references(
        self,
        paper: CanonicalPaper,
        warnings: Optional[List[GraphWarning]] = None,
    ) -> Tuple[List[str], EnrichmentStatusEnum, bool]:
        """
        Fetches outbound references for a single paper with pagination and caching.
        Attempts primary provider and seamlessly falls back to alternative provider.
        """
        warnings = warnings if warnings is not None else []

        # If paper already has references populated
        if paper.reference_ids and len(paper.reference_ids) >= 10:
            return paper.reference_ids, EnrichmentStatusEnum.SUCCESS, True

        provider_id = paper.semantic_scholar_id or paper.doi or paper.canonical_id
        cache_key = ResponseCache.generate_key("references", provider_id)

        async def _do_fetch() -> Tuple[List[str], EnrichmentStatusEnum, bool]:
            ref_ids: List[str] = []
            providers_to_try = [p for p in [self.s2_provider, self.openalex_provider] if p is not None]

            if not providers_to_try:
                return ref_ids, EnrichmentStatusEnum.SKIPPED, False

            for provider in providers_to_try:
                try:
                    cursor: Optional[str] = None
                    is_complete = True
                    target_id = provider_id
                    if provider.name == "openalex" and getattr(paper, "open_alex_id", None):
                        target_id = paper.open_alex_id

                    while True:
                        page = await provider.get_references(
                            provider_id=target_id,
                            cursor=cursor,
                            limit=min(100, self.max_refs_per_paper - len(ref_ids)),
                        )

                        for item in page.items:
                            cid = item.doi or item.semantic_scholar_id or item.provider_id
                            if cid and cid not in ref_ids:
                                ref_ids.append(cid)

                        if not page.has_more or not page.next_cursor:
                            is_complete = True
                            break

                        cursor = page.next_cursor
                        if len(ref_ids) >= self.max_refs_per_paper:
                            is_complete = False
                            break

                    status = EnrichmentStatusEnum.SUCCESS if ref_ids else EnrichmentStatusEnum.EMPTY
                    if not is_complete and ref_ids:
                        status = EnrichmentStatusEnum.PARTIAL

                    return ref_ids, status, is_complete

                except Exception as e:
                    logger.warning(f"[{provider.name}] Error fetching references for {paper.canonical_id}: {e}")
                    # Continue loop to try next provider

            warnings.append(
                GraphWarning(
                    code="provider_references_error",
                    message=f"Failed to fetch references for {paper.canonical_id} across all providers.",
                    severity="warning",
                )
            )
            return ref_ids, EnrichmentStatusEnum.FAILED, False

        result = await self.cache.get_or_fetch(cache_key, _do_fetch)
        return result

    async def enrich_references(
        self,
        origin: CanonicalPaper,
        candidates: List[CandidateRecord],
        warnings: Optional[List[GraphWarning]] = None,
    ) -> Tuple[
        Tuple[List[str], EnrichmentStatusEnum, bool],
        Dict[str, Tuple[List[str], EnrichmentStatusEnum, bool]],
    ]:
        """
        Enriches references for the origin paper and candidates concurrently with a bounded semaphore.
        """
        warnings = warnings if warnings is not None else []

        # 1. Fetch origin references first
        origin_refs, origin_status, origin_complete = await self.fetch_paper_references(
            origin, warnings=warnings
        )
        if origin_refs:
            merged_refs = list(set(origin.reference_ids + origin_refs))
            origin.reference_ids = merged_refs
            origin.reference_count = max(origin.reference_count or 0, len(merged_refs))

        # 2. Select candidates prioritizing higher PreScore
        sorted_candidates = sorted(candidates, key=lambda c: c.pre_score, reverse=True)
        selected_candidates = sorted_candidates[:self.max_candidates]

        # 3. Concurrent retrieval with bounded semaphore
        sem = asyncio.Semaphore(settings.ENRICHMENT_CONCURRENCY_LIMIT)

        async def _fetch_single(cand: CandidateRecord):
            async with sem:
                refs, status, complete = await self.fetch_paper_references(
                    cand.paper, warnings=warnings
                )
                if refs:
                    cand.paper.reference_ids = list(set(cand.paper.reference_ids + refs))
                    cand.paper.reference_count = max(
                        cand.paper.reference_count or 0, len(cand.paper.reference_ids)
                    )
                return cand.paper.canonical_id, (cand.paper.reference_ids, status, complete)

        tasks = [_fetch_single(c) for c in selected_candidates]
        gathered = await asyncio.gather(*tasks, return_exceptions=True)

        candidate_results: Dict[str, Tuple[List[str], EnrichmentStatusEnum, bool]] = {}
        for item in gathered:
            if isinstance(item, tuple) and len(item) == 2:
                cid, res = item
                candidate_results[cid] = res

        # 4. Fill unselected candidates
        for cand in candidates:
            cid = cand.paper.canonical_id
            if cid not in candidate_results:
                candidate_results[cid] = (
                    cand.paper.reference_ids,
                    EnrichmentStatusEnum.SKIPPED,
                    False,
                )

        return (origin_refs, origin_status, origin_complete), candidate_results
