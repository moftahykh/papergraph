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
    Fetches outbound references for origin and up to 60 retained candidates using
    provider-specific pagination. Collapses duplicate requests and guarantees
    that partial reference lists are explicitly flagged as incomplete.
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
        Returns:
          - reference_ids: List of canonical/provider IDs cited
          - status: EnrichmentStatusEnum (SUCCESS, PARTIAL, EMPTY, FAILED)
          - is_complete: True if all pages were fetched completely without error/cutoff
        """
        warnings = warnings if warnings is not None else []

        # If paper already has references populated
        if paper.reference_ids and len(paper.reference_ids) >= 10:
            return paper.reference_ids, EnrichmentStatusEnum.SUCCESS, True

        provider_id = paper.semantic_scholar_id or paper.doi or paper.canonical_id
        cache_key = ResponseCache.generate_key("references", provider_id)

        async def _do_fetch() -> Tuple[List[str], EnrichmentStatusEnum, bool]:
            ref_ids: List[str] = []
            cursor: Optional[str] = None
            is_complete = True
            provider_used = self.s2_provider or self.openalex_provider

            if not provider_used:
                return ref_ids, EnrichmentStatusEnum.SKIPPED, False

            try:
                while True:
                    # Pagination call
                    page = await provider_used.get_references(
                        provider_id=provider_id,
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
                        is_complete = False  # Truncated by quota limit
                        break

                status = EnrichmentStatusEnum.SUCCESS if ref_ids else EnrichmentStatusEnum.EMPTY
                if not is_complete and ref_ids:
                    status = EnrichmentStatusEnum.PARTIAL

                return ref_ids, status, is_complete

            except Exception as e:
                logger.warning(f"Error fetching references for {paper.canonical_id}: {e}")
                warnings.append(
                    GraphWarning(
                        code="provider_references_error",
                        message=f"Failed to fetch references for {paper.canonical_id}: {str(e)}",
                        severity="warning",
                    )
                )
                return ref_ids, EnrichmentStatusEnum.FAILED, False

        # Use cache with request collapsing to prevent duplicate network calls
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
        Enriches references for the origin paper and up to max_candidates (default 60).
        """
        warnings = warnings if warnings is not None else []

        # 1. Fetch origin references first
        origin_refs, origin_status, origin_complete = await self.fetch_paper_references(
            origin, warnings=warnings
        )
        if origin_refs:
            # Merge into origin
            merged_refs = list(set(origin.reference_ids + origin_refs))
            origin.reference_ids = merged_refs
            origin.reference_count = max(origin.reference_count or 0, len(merged_refs))

        # 2. Select up to 60 candidates (prioritizing higher PreScore)
        sorted_candidates = sorted(candidates, key=lambda c: c.pre_score, reverse=True)
        selected_candidates = sorted_candidates[:self.max_candidates]
        selected_cids = {c.paper.canonical_id for c in selected_candidates}

        candidate_results: Dict[str, Tuple[List[str], EnrichmentStatusEnum, bool]] = {}

        for cand in candidates:
            cid = cand.paper.canonical_id
            if cid in selected_cids:
                refs, status, complete = await self.fetch_paper_references(
                    cand.paper, warnings=warnings
                )
                if refs:
                    cand.paper.reference_ids = list(set(cand.paper.reference_ids + refs))
                    cand.paper.reference_count = max(
                        cand.paper.reference_count or 0, len(cand.paper.reference_ids)
                    )
                candidate_results[cid] = (cand.paper.reference_ids, status, complete)
            else:
                candidate_results[cid] = (
                    cand.paper.reference_ids,
                    EnrichmentStatusEnum.SKIPPED,
                    False,
                )

        return (origin_refs, origin_status, origin_complete), candidate_results
