import math
from typing import Set, Optional, Iterable
from app.models.canonical_paper import CanonicalPaper
from app.models.metric import MetricResult
from app.models.enums import MetricAvailability
from app.core.config import settings


def compute_ncc(
    origin_citations: Optional[Iterable[str]],
    candidate_citations: Optional[Iterable[str]],
    is_selected_for_citations: bool = True,
    origin_cite_status: str = "success",
    cand_cite_status: str = "success",
    epsilon: float = settings.ENRICHMENT_EPSILON,
) -> MetricResult:
    """
    Computes Normalized Co-Citation (NCC) between origin paper and candidate paper.
    
    Formula:
      NCC(u, v) = |Cu cap Cv| / (sqrt(|Cu| * |Cv|) + epsilon)
      
    Availability contract:
      - If candidate not in top 30: MetricResult(value=None, availability="not_applicable")
      - If provider error occurred: MetricResult(value=None, availability="provider_error")
      - If citations not loaded / missing: MetricResult(value=None, availability="unavailable")
      - If both sets evaluated: MetricResult(value=score in [0, 1], availability="available")
    """
    # 1. Candidate selection check
    if not is_selected_for_citations:
        return MetricResult(
            value=None,
            availability=MetricAvailability.NOT_APPLICABLE,
            reason="not_selected_for_citation_enrichment",
        )

    # 2. Provider error check
    if origin_cite_status == "failed" or cand_cite_status == "failed":
        return MetricResult(
            value=None,
            availability=MetricAvailability.PROVIDER_ERROR,
            reason="provider_error",
        )

    # 3. Availability check
    if origin_citations is None or candidate_citations is None:
        return MetricResult(
            value=None,
            availability=MetricAvailability.UNAVAILABLE,
            reason="citations_not_loaded",
        )

    if origin_cite_status == "skipped" or cand_cite_status == "skipped":
        return MetricResult(
            value=None,
            availability=MetricAvailability.UNAVAILABLE,
            reason="citations_not_loaded",
        )

    cu: Set[str] = set(origin_citations)
    cv: Set[str] = set(candidate_citations)

    # If either set is empty, co-citation is 0.0 with available status
    if not cu or not cv:
        return MetricResult(
            value=0.0,
            availability=MetricAvailability.AVAILABLE,
            reason=None,
        )

    intersection = cu.intersection(cv)
    if not intersection:
        return MetricResult(
            value=0.0,
            availability=MetricAvailability.AVAILABLE,
            reason=None,
        )

    num = float(len(intersection))
    denominator = math.sqrt(float(len(cu)) * float(len(cv))) + epsilon

    if denominator <= 0.0 or math.isnan(denominator) or math.isinf(denominator):
        return MetricResult(
            value=0.0,
            availability=MetricAvailability.AVAILABLE,
            reason=None,
        )

    score = num / denominator
    clamped_score = min(1.0, max(0.0, score))

    return MetricResult(
        value=round(clamped_score, 6),
        availability=MetricAvailability.AVAILABLE,
        reason=None,
    )
