from typing import List, Dict, Set
from app.models.canonical_paper import CanonicalPaper
from app.candidates.models import CandidateRecord


def is_origin_paper(candidate: CanonicalPaper, origin: CanonicalPaper) -> bool:
    """Checks if candidate matches origin seed paper by canonical ID, DOI, or PMID."""
    if candidate.canonical_id == origin.canonical_id:
        return True
    if candidate.doi and origin.doi and candidate.doi.lower() == origin.doi.lower():
        return True
    if candidate.pmid and origin.pmid and candidate.pmid == origin.pmid:
        return True
    if candidate.normalized_title and origin.normalized_title:
        if candidate.normalized_title == origin.normalized_title:
            if candidate.year == origin.year and candidate.year is not None:
                return True
    return False


def apply_quota_retention(
    candidates: List[CandidateRecord],
    origin: CanonicalPaper,
    max_cap: int = 80,
) -> List[CandidateRecord]:
    """
    Applies multi-bucket quota candidate retention to prevent citation-bias:
    1. Filter out origin paper and malformed records.
    2. Deduplicate candidate records.
    3. Bucket 1: Top 50 by PreScore.
    4. Bucket 2: Top 10 direct references (Origin -> Paper).
    5. Bucket 3: Top 10 direct citations  (Paper -> Origin).
    6. Bucket 4: Top 10 recommendations   (Semantic Scholar / OpenAlex).
    7. Deduplicate combined survivors, record explicit survival reasons, and cap at max_cap (80).
    """
    # 1. Filter out origin and malformed records
    valid_candidates: List[CandidateRecord] = []
    seen_ids: Set[str] = set()

    for cand in candidates:
        # Rule: Origin never appears in candidate set
        if is_origin_paper(cand.paper, origin):
            continue

        # Rule: Remove records lacking title
        if not cand.paper.title or cand.paper.title.strip() == "":
            continue

        cid = cand.paper.canonical_id
        if cid in seen_ids:
            # Merge flags with existing
            for existing in valid_candidates:
                if existing.paper.canonical_id == cid:
                    existing.is_direct_reference = (
                        existing.is_direct_reference or cand.is_direct_reference
                    )
                    existing.is_direct_citation = (
                        existing.is_direct_citation or cand.is_direct_citation
                    )
                    existing.is_recommendation = (
                        existing.is_recommendation or cand.is_recommendation
                    )
                    if cand.pre_score > existing.pre_score:
                        existing.pre_score = cand.pre_score
                        existing.pre_signals = cand.pre_signals
                        existing.renormalized_weights = cand.renormalized_weights
                    break
        else:
            seen_ids.add(cid)
            valid_candidates.append(cand)

    retained_map: Dict[str, CandidateRecord] = {}

    def add_to_retained(candidate: CandidateRecord, reason: str) -> None:
        cid = candidate.paper.canonical_id
        if cid not in retained_map:
            retained_map[cid] = candidate
            candidate.retention_reasons = [reason]
        else:
            if reason not in retained_map[cid].retention_reasons:
                retained_map[cid].retention_reasons.append(reason)

    # 2. Bucket 1: Top 50 by PreScore
    sorted_by_prescore = sorted(
        valid_candidates, key=lambda c: c.pre_score, reverse=True
    )
    for c in sorted_by_prescore[:50]:
        add_to_retained(c, "prescore_top_50")

    # 3. Bucket 2: Top 10 Direct References (Origin -> Paper)
    direct_references = [c for c in valid_candidates if c.is_direct_reference]
    direct_references.sort(key=lambda c: c.pre_score, reverse=True)
    for c in direct_references[:10]:
        add_to_retained(c, "direct_reference_quota")

    # 4. Bucket 3: Top 10 Direct Citations (Paper -> Origin)
    direct_citations = [c for c in valid_candidates if c.is_direct_citation]
    direct_citations.sort(key=lambda c: c.pre_score, reverse=True)
    for c in direct_citations[:10]:
        add_to_retained(c, "direct_citation_quota")

    # 5. Bucket 4: Top 10 Recommendations
    recommendations = [c for c in valid_candidates if c.is_recommendation]
    recommendations.sort(
        key=lambda c: (c.raw_semantic_score or 0.0, c.pre_score), reverse=True
    )
    for c in recommendations[:10]:
        add_to_retained(c, "recommendation_quota")

    # 6. Cap at max_cap (80)
    survivors = list(retained_map.values())
    if len(survivors) > max_cap:
        # Prioritize candidates satisfying multiple quotas or quota guarantees, then PreScore
        survivors.sort(
            key=lambda c: (len(c.retention_reasons), c.pre_score), reverse=True
        )
        survivors = survivors[:max_cap]

    # Mark retention state
    for c in survivors:
        c.is_retained = True

    return survivors
