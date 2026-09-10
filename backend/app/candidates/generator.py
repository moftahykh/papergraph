from typing import List, Optional
from app.models.canonical_paper import CanonicalPaper
from app.providers.models import RawPaper
from app.resolution.resolver import IdentityResolver
from app.candidates.models import CandidateRecord, CandidateSourceType
from app.candidates.prescore import compute_prescore
from app.candidates.quota import apply_quota_retention


class CandidatePoolGenerator:
    """
    Generates an initial bounded candidate pool (100–150 papers) across multiple discovery
    vectors, applies fast PreScore with weight renormalization, and executes quota retention.
    """
    def __init__(self, resolver: Optional[IdentityResolver] = None):
        self.resolver = resolver or IdentityResolver()

    def process_raw_candidates(
        self,
        origin: CanonicalPaper,
        raw_references: List[RawPaper] = None,
        raw_citations: List[RawPaper] = None,
        raw_recommendations: List[RawPaper] = None,
        raw_related_works: List[RawPaper] = None,
    ) -> List[CandidateRecord]:
        """
        Ingests multi-source raw candidate lists, registers direct link flags,
        computes renormalized PreScore, and filters via quota retention.
        """
        raw_references = raw_references or []
        raw_citations = raw_citations or []
        raw_recommendations = raw_recommendations or []
        raw_related_works = raw_related_works or []

        records_map: dict[str, CandidateRecord] = {}

        def register_raw(raw: RawPaper, source_type: CandidateSourceType, is_ref=False, is_cite=False, is_rec=False, sem_score=None):
            canonical = raw.to_canonical()
            # Ingest through resolver for deduplication
            canonical = self.resolver.ingest(canonical)
            cid = canonical.canonical_id

            if cid not in records_map:
                record = CandidateRecord(
                    paper=canonical,
                    sources={source_type},
                    is_direct_reference=is_ref,
                    is_direct_citation=is_cite,
                    is_recommendation=is_rec,
                    raw_semantic_score=sem_score,
                )
                records_map[cid] = record
            else:
                existing = records_map[cid]
                existing.sources.add(source_type)
                if is_ref:
                    existing.is_direct_reference = True
                if is_cite:
                    existing.is_direct_citation = True
                if is_rec:
                    existing.is_recommendation = True
                if sem_score is not None:
                    existing.raw_semantic_score = max(
                        existing.raw_semantic_score or 0.0, sem_score
                    )

        # 1. Register direct references
        for r in raw_references:
            register_raw(r, CandidateSourceType.REFERENCE, is_ref=True)

        # 2. Register direct citations
        for c in raw_citations:
            register_raw(c, CandidateSourceType.CITATION, is_cite=True)

        # 3. Register recommendations
        for i, rec in enumerate(raw_recommendations):
            # Positional decay for ordinal recommendation rank if no raw score
            sim_score = max(0.2, 1.0 - (i * 0.03))
            register_raw(rec, CandidateSourceType.RECOMMENDATION, is_rec=True, sem_score=sim_score)

        # 4. Register related works
        for i, rel in enumerate(raw_related_works):
            sim_score = max(0.15, 0.85 - (i * 0.03))
            register_raw(rel, CandidateSourceType.RELATED_WORK, is_rec=True, sem_score=sim_score)

        candidate_list = list(records_map.values())

        # 5. Compute PreScore for each candidate with weight renormalization
        for cand in candidate_list:
            pre_score, pre_signals, renorm_weights = compute_prescore(cand, origin)
            cand.pre_score = pre_score
            cand.pre_signals = pre_signals
            cand.renormalized_weights = renorm_weights

        # 6. Apply multi-bucket quota retention (capped at 80)
        retained = apply_quota_retention(candidate_list, origin, max_cap=80)
        return retained
