import logging
from typing import List, Dict, Optional, Set, Tuple
from app.models.canonical_paper import CanonicalPaper
from app.models.graph import GraphWarning
from app.candidates.models import CandidateRecord
from app.enrichment.models import EnrichmentStatusEnum
from app.resolution.merger import merge_canonical_papers
from app.cache.manager import ResponseCache

logger = logging.getLogger("papergraph.enrichment.metadata")


class BatchMetadataEnricher:
    """
    Enriches metadata (abstract, venue, authors, publication year, topics) for
    the retained 60–80 candidate pool in batch requests, collapsing duplicate queries
    and gracefully handling provider errors.
    """
    def __init__(
        self,
        s2_provider=None,
        openalex_provider=None,
        cache: Optional[ResponseCache] = None,
    ):
        self.s2_provider = s2_provider
        self.openalex_provider = openalex_provider
        self.cache = cache or ResponseCache()

    async def enrich_candidates_metadata(
        self,
        candidates: List[CandidateRecord],
        warnings: Optional[List[GraphWarning]] = None,
    ) -> Tuple[Dict[str, EnrichmentStatusEnum], Dict[str, List[str]]]:
        """
        Batch-enriches metadata for candidates.
        Returns:
          - statuses: Dict[canonical_id -> EnrichmentStatusEnum]
          - enriched_fields_map: Dict[canonical_id -> list of field names enriched]
        """
        warnings = warnings if warnings is not None else []
        statuses: Dict[str, EnrichmentStatusEnum] = {}
        enriched_fields_map: Dict[str, List[str]] = {}

        if not candidates:
            return statuses, enriched_fields_map

        # 1. Identify candidates that can benefit from metadata enrichment
        # Identify S2 ID or DOI for each
        s2_lookup_map: Dict[str, CandidateRecord] = {}
        doi_lookup_map: Dict[str, CandidateRecord] = {}

        for cand in candidates:
            cid = cand.paper.canonical_id
            statuses[cid] = EnrichmentStatusEnum.SKIPPED
            enriched_fields_map[cid] = []

            # Prioritize candidates with incomplete metadata
            if cand.paper.completeness < 0.90 or not cand.paper.abstract:
                if cand.paper.semantic_scholar_id:
                    s2_lookup_map[cand.paper.semantic_scholar_id] = cand
                elif cand.paper.doi:
                    doi_lookup_map[cand.paper.doi] = cand

        # 2. Batch query Semantic Scholar if available
        if self.s2_provider and hasattr(self.s2_provider, "get_batch_details") and s2_lookup_map:
            s2_ids = list(s2_lookup_map.keys())
            try:
                # Deduplicate and check cache
                uncached_ids: List[str] = []
                cached_papers: Dict[str, CanonicalPaper] = {}

                for sid in s2_ids:
                    cache_key = ResponseCache.generate_key("s2_meta", sid)
                    cached_raw = await self.cache.get(cache_key)
                    if cached_raw is not None:
                        cached_papers[sid] = cached_raw.to_canonical()
                    else:
                        uncached_ids.append(sid)

                # Fetch uncached in batch
                if uncached_ids:
                    fetched_raw_list = await self.s2_provider.get_batch_details(uncached_ids)
                    for sid, raw in zip(uncached_ids, fetched_raw_list):
                        if raw is not None:
                            cache_key = ResponseCache.generate_key("s2_meta", sid)
                            await self.cache.set(cache_key, raw)
                            cached_papers[sid] = raw.to_canonical()

                # Apply updates
                for sid, cand in s2_lookup_map.items():
                    cid = cand.paper.canonical_id
                    if sid in cached_papers:
                        incoming = cached_papers[sid]
                        before_fields = set(self._get_populated_fields(cand.paper))
                        cand.paper = merge_canonical_papers(cand.paper, incoming)
                        after_fields = set(self._get_populated_fields(cand.paper))
                        new_fields = list(after_fields - before_fields)
                        enriched_fields_map[cid] = new_fields
                        statuses[cid] = EnrichmentStatusEnum.SUCCESS
                    else:
                        statuses[cid] = EnrichmentStatusEnum.PARTIAL

            except Exception as e:
                logger.warning(f"Batch metadata enrichment failed on S2: {e}")
                warnings.append(
                    GraphWarning(
                        code="provider_metadata_error",
                        message=f"Semantic Scholar batch metadata enrichment failed: {str(e)}",
                        severity="warning",
                    )
                )
                for sid in s2_ids:
                    cand = s2_lookup_map[sid]
                    statuses[cand.paper.canonical_id] = EnrichmentStatusEnum.FAILED

        # 3. Fallback to OpenAlex for un-enriched candidates with DOIs
        if self.openalex_provider and doi_lookup_map:
            for doi, cand in doi_lookup_map.items():
                cid = cand.paper.canonical_id
                if statuses.get(cid) == EnrichmentStatusEnum.SUCCESS:
                    continue
                try:
                    cache_key = ResponseCache.generate_key("oa_meta", doi)
                    cached_raw = await self.cache.get(cache_key)
                    if cached_raw is None:
                        raw = await self.openalex_provider.resolve(doi)
                        if raw is not None:
                            await self.cache.set(cache_key, raw)
                            cached_raw = raw
                    
                    if cached_raw is not None:
                        incoming = cached_raw.to_canonical()
                        before_fields = set(self._get_populated_fields(cand.paper))
                        cand.paper = merge_canonical_papers(cand.paper, incoming)
                        after_fields = set(self._get_populated_fields(cand.paper))
                        enriched_fields_map[cid] = list(after_fields - before_fields)
                        statuses[cid] = EnrichmentStatusEnum.SUCCESS
                except Exception as e:
                    logger.debug(f"OpenAlex metadata enrichment failed for DOI {doi}: {e}")
                    if statuses.get(cid) != EnrichmentStatusEnum.SUCCESS:
                        statuses[cid] = EnrichmentStatusEnum.FAILED

        return statuses, enriched_fields_map

    @staticmethod
    def _get_populated_fields(paper: CanonicalPaper) -> List[str]:
        fields = []
        if paper.abstract:
            fields.append("abstract")
        if paper.venue:
            fields.append("venue")
        if paper.authors:
            fields.append("authors")
        if paper.year:
            fields.append("year")
        if paper.topics:
            fields.append("topics")
        return fields
