import logging
from typing import List, Optional, Dict
from app.models.canonical_paper import CanonicalPaper
from app.models.graph import GraphWarning, DataCompleteness
from app.models.enums import GraphJobStatus, MetricAvailability
from app.candidates.models import CandidateRecord
from app.enrichment.models import (
    CandidateEnrichmentRecord,
    EnrichmentPipelineResult,
    EnrichmentStatusEnum,
)
from app.enrichment.metadata import BatchMetadataEnricher
from app.enrichment.references import ReferenceEnricher
from app.enrichment.citations import CitationEnricher
from app.enrichment.wbc import compute_wbc
from app.enrichment.ncc import compute_ncc
from app.cache.manager import ResponseCache
from app.core.config import settings

logger = logging.getLogger("papergraph.enrichment.pipeline")


class EnrichmentPipeline:
    """
    Orchestrates the 8-stage academic literature enrichment pipeline:
    1. Batch-enrich candidate metadata.
    2. Fetch outbound references for origin and up to 60 candidates.
    3. Compute Weighted Bibliographic Coupling (WBC).
    4. Select top 30 candidates for citation enrichment.
    5. Fetch inbound citing papers for origin and top 30 candidates.
    6. Compute Normalized Co-Citation (NCC).
    7. Store enrichment status and metric records.
    8. Compile completeness metrics and mark partial state if any provider fails.
    """
    def __init__(
        self,
        s2_provider=None,
        openalex_provider=None,
        cache: Optional[ResponseCache] = None,
        max_reference_candidates: int = settings.ENRICHMENT_MAX_CANDIDATES_REFERENCES,
        max_citation_candidates: int = settings.ENRICHMENT_MAX_CANDIDATES_CITATIONS,
    ):
        self.cache = cache or ResponseCache()
        self.metadata_enricher = BatchMetadataEnricher(
            s2_provider=s2_provider,
            openalex_provider=openalex_provider,
            cache=self.cache,
        )
        self.reference_enricher = ReferenceEnricher(
            s2_provider=s2_provider,
            openalex_provider=openalex_provider,
            cache=self.cache,
            max_candidates=max_reference_candidates,
        )
        self.citation_enricher = CitationEnricher(
            s2_provider=s2_provider,
            openalex_provider=openalex_provider,
            cache=self.cache,
            max_candidates=max_citation_candidates,
        )

    async def run(
        self,
        origin: CanonicalPaper,
        candidates: List[CandidateRecord],
    ) -> EnrichmentPipelineResult:
        """
        Executes staged enrichment across the retained candidate pool.
        Guarantees that provider failures do not crash the pipeline and result
        in an explicit partial graph status with warnings.
        """
        warnings: List[GraphWarning] = []

        if not candidates:
            return EnrichmentPipelineResult(
                origin=origin,
                candidates=[],
                metadata_completeness=1.0,
                references_completeness=1.0,
                citations_completeness=1.0,
                data_completeness=DataCompleteness(),
                warnings=warnings,
                status=GraphJobStatus.COMPLETED,
            )

        # ----------------------------------------------------------------------
        # Stage 1: Batch-enrich metadata for candidates
        # ----------------------------------------------------------------------
        meta_statuses, meta_fields = await self.metadata_enricher.enrich_candidates_metadata(
            candidates, warnings=warnings
        )

        # ----------------------------------------------------------------------
        # Stage 2: Fetch outbound references for origin and up to 60 candidates
        # ----------------------------------------------------------------------
        (origin_refs, origin_ref_status, origin_ref_complete), cand_refs = (
            await self.reference_enricher.enrich_references(
                origin, candidates, warnings=warnings
            )
        )

        # ----------------------------------------------------------------------
        # Stage 3: Compute WBC for all candidates against origin
        # ----------------------------------------------------------------------
        wbc_scores: Dict[str, any] = {}
        for cand in candidates:
            cid = cand.paper.canonical_id
            c_refs, c_status, _ = cand_refs.get(
                cid, (cand.paper.reference_ids, EnrichmentStatusEnum.SKIPPED, False)
            )
            wbc_res = compute_wbc(
                origin_references=origin.reference_ids,
                candidate_references=c_refs,
                origin_ref_status=origin_ref_status.value,
                cand_ref_status=c_status.value,
            )
            wbc_scores[cid] = wbc_res

        # ----------------------------------------------------------------------
        # Stage 4 & 5: Select top 30 candidates & fetch inbound citations
        # ----------------------------------------------------------------------
        (origin_cites, origin_cite_status, origin_cite_complete), cand_cites = (
            await self.citation_enricher.enrich_citations(
                origin=origin,
                candidates=candidates,
                wbc_scores=wbc_scores,
                warnings=warnings,
            )
        )

        # ----------------------------------------------------------------------
        # Stage 6: Compute NCC for all candidates against origin
        # ----------------------------------------------------------------------
        ncc_scores: Dict[str, any] = {}
        for cand in candidates:
            cid = cand.paper.canonical_id
            c_cites, c_status, _, is_sel = cand_cites.get(
                cid, (cand.paper.citation_ids, EnrichmentStatusEnum.NOT_SELECTED, False, False)
            )
            ncc_res = compute_ncc(
                origin_citations=origin.citation_ids,
                candidate_citations=c_cites,
                is_selected_for_citations=is_sel,
                origin_cite_status=origin_cite_status.value,
                cand_cite_status=c_status.value,
            )
            ncc_scores[cid] = ncc_res

        # ----------------------------------------------------------------------
        # Stage 7: Assemble CandidateEnrichmentRecords
        # ----------------------------------------------------------------------
        enrichment_records: List[CandidateEnrichmentRecord] = []
        meta_success_count = 0
        ref_complete_count = 0
        cite_complete_count = 0
        selected_cite_count = 0

        for cand in candidates:
            cid = cand.paper.canonical_id
            m_status = meta_statuses.get(cid, EnrichmentStatusEnum.SKIPPED)
            m_fields = meta_fields.get(cid, [])
            if m_status in (EnrichmentStatusEnum.SUCCESS, EnrichmentStatusEnum.SKIPPED):
                meta_success_count += 1

            c_refs, r_status, r_complete = cand_refs.get(
                cid, (cand.paper.reference_ids, EnrichmentStatusEnum.SKIPPED, False)
            )
            if r_complete:
                ref_complete_count += 1

            c_cites, cit_status, cit_complete, is_selected = cand_cites.get(
                cid, (cand.paper.citation_ids, EnrichmentStatusEnum.NOT_SELECTED, False, False)
            )
            if is_selected:
                selected_cite_count += 1
                if cit_complete:
                    cite_complete_count += 1

            rec = CandidateEnrichmentRecord(
                candidate=cand,
                metadata_status=m_status,
                enriched_fields=m_fields,
                references_status=r_status,
                references_count=len(c_refs),
                references_complete=r_complete,
                citations_status=cit_status,
                citations_count=len(c_cites),
                citations_complete=cit_complete,
                wbc=wbc_scores[cid],
                ncc=ncc_scores[cid],
            )
            enrichment_records.append(rec)

        # ----------------------------------------------------------------------
        # Stage 8: Completeness computation and job status determination
        # ----------------------------------------------------------------------
        total_cands = max(1, len(candidates))
        meta_ratio = round(meta_success_count / total_cands, 2)
        ref_ratio = round(ref_complete_count / min(total_cands, self.reference_enricher.max_candidates), 2)
        cite_ratio = round(cite_complete_count / max(1, selected_cite_count), 2) if selected_cite_count else 1.0

        # Semantic ratio from candidate pre-signals
        sem_available_count = sum(
            1 for c in candidates
            if c.pre_signals.get("semantic") and c.pre_signals["semantic"].availability == MetricAvailability.AVAILABLE
        )
        sem_ratio = round(sem_available_count / total_cands, 2)

        data_completeness = DataCompleteness(
            metadata=meta_ratio,
            references=ref_ratio,
            citations=cite_ratio,
            semantic=sem_ratio,
        )

        has_critical_warning = any(w.severity in ("warning", "error") for w in warnings)
        is_partial = has_critical_warning or (ref_ratio < 0.70) or (cite_ratio < 0.70)
        overall_status = GraphJobStatus.PARTIAL if is_partial else GraphJobStatus.COMPLETED

        return EnrichmentPipelineResult(
            origin=origin,
            candidates=enrichment_records,
            metadata_completeness=meta_ratio,
            references_completeness=ref_ratio,
            citations_completeness=cite_ratio,
            data_completeness=data_completeness,
            warnings=warnings,
            status=overall_status,
        )
