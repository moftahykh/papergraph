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
    Selects top 30 candidates (using composite PreScore + WBC ranking) and fetches
    inbound citations for origin and selected candidates with provider pagination
    and request collapsing.
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
        Selects the top 30 candidates for expensive inbound citation enrichment
        based on composite PreScore and available WBC similarity.
        """
        def ranking_key(cand: CandidateRecord) -> float:
            cid = cand.paper.canonical_id
            wbc_res = wbc_scores.get(cid)
            wbc_val = wbc_res.value if wbc_res and wbc_res.value is not None else cand.pre_score
            # 60% PreScore, 40% WBC similarity
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
        Returns:
          - citation_ids: List of canonical/provider IDs citing this work
          - status: EnrichmentStatusEnum (SUCCESS, PARTIAL, EMPTY, FAILED)
          - is_complete: True if all pages were fetched completely without error/cutoff
        """
        warnings = warnings if warnings is not None else []

        if paper.citation_ids and len(paper.citation_ids) >= 10:
            return paper.citation_ids, EnrichmentStatusEnum.SUCCESS, True

        provider_id = paper.semantic_scholar_id or paper.doi or paper.canonical_id
        cache_key = ResponseCache.generate_key("citations", provider_id)

        async def _do_fetch() -> Tuple[List[str], EnrichmentStatusEnum, bool]:
            cite_ids: List[str] = []
            cursor: Optional[str] = None
            is_complete = True
            provider_used = self.s2_provider or self.openalex_provider

            if not provider_used:
                return cite_ids, EnrichmentStatusEnum.SKIPPED, False

            try:
                while True:
                    page = await provider_used.get_citations(
                        provider_id=provider_id,
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
                        is_complete = False  # Truncated by quota limit
                        break

                status = EnrichmentStatusEnum.SUCCESS if cite_ids else EnrichmentStatusEnum.EMPTY
                if not is_complete and cite_ids:
                    status = EnrichmentStatusEnum.PARTIAL

                return cite_ids, status, is_complete

            except Exception as e:
                logger.warning(f"Error fetching citations for {paper.canonical_id}: {e}")
                warnings.append(
                    GraphWarning(
                        code="provider_citations_error",
                        message=f"Failed to fetch citations for {paper.canonical_id}: {str(e)}",
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
        Enriches inbound citations for origin and the selected top 30 candidates.
        Returns:
          - origin_result: (citation_ids, status, is_complete)
          - candidate_results: Dict[cid -> (citation_ids, status, is_complete, is_selected)]
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

        # 2. Select top 30 candidates
        selected = self.select_top_candidates(candidates, wbc_scores)
        selected_cids = {c.paper.canonical_id for c in selected}

        candidate_results: Dict[str, Tuple[List[str], EnrichmentStatusEnum, bool, bool]] = {}

        for cand in candidates:
            cid = cand.paper.canonical_id
            if cid in selected_cids:
                cites, status, complete = await self.fetch_paper_citations(
                    cand.paper, warnings=warnings
                )
                if cites:
                    cand.paper.citation_ids = list(set(cand.paper.citation_ids + cites))
                    cand.paper.citation_count = max(
                        cand.paper.citation_count, len(cand.paper.citation_ids)
                    )
                candidate_results[cid] = (cand.paper.citation_ids, status, complete, True)
            else:
                candidate_results[cid] = (
                    cand.paper.citation_ids,
                    EnrichmentStatusEnum.NOT_SELECTED,
                    False,
                    False,
                )

        return (origin_cites, origin_status, origin_complete), candidate_results
