import math
from typing import Set, Optional, Dict, Iterable
from app.models.canonical_paper import CanonicalPaper
from app.models.metric import MetricResult
from app.models.enums import MetricAvailability
from app.core.config import settings


def compute_wbc(
    origin_references: Optional[Iterable[str]],
    candidate_references: Optional[Iterable[str]],
    origin_ref_status: str = "success",
    cand_ref_status: str = "success",
    weights: Optional[Dict[str, float]] = None,
    epsilon: float = settings.ENRICHMENT_EPSILON,
) -> MetricResult:
    """
    Computes Weighted Bibliographic Coupling (WBC) between origin paper and candidate paper.
    
    Formula:
      WBC(u, v) = sum_{k in Ru cap Rv} w_k / (sqrt(sum_{k in Ru} w_k * sum_{k in Rv} w_k) + epsilon)
      
    Availability contract:
      - If provider error occurred: MetricResult(value=None, availability="provider_error")
      - If references not loaded / missing: MetricResult(value=None, availability="unavailable")
      - If both sets evaluated: MetricResult(value=score in [0, 1], availability="available")
    """
    # 1. Provider error check
    if origin_ref_status == "failed" or cand_ref_status == "failed":
        return MetricResult(
            value=None,
            availability=MetricAvailability.PROVIDER_ERROR,
            reason="provider_error",
        )

    # 2. Availability check
    if origin_references is None or candidate_references is None:
        return MetricResult(
            value=None,
            availability=MetricAvailability.UNAVAILABLE,
            reason="references_not_loaded",
        )

    if origin_ref_status == "skipped" or cand_ref_status == "skipped":
        return MetricResult(
            value=None,
            availability=MetricAvailability.UNAVAILABLE,
            reason="references_not_loaded",
        )

    # Convert to set
    ru: Set[str] = set(origin_references)
    rv: Set[str] = set(candidate_references)

    # If either set is empty, coupling is 0.0 with available status
    if not ru or not rv:
        return MetricResult(
            value=0.0,
            availability=MetricAvailability.AVAILABLE,
            reason=None,
        )

    intersection = ru.intersection(rv)
    if not intersection:
        return MetricResult(
            value=0.0,
            availability=MetricAvailability.AVAILABLE,
            reason=None,
        )

    # Weighted calculation
    if weights:
        num = sum(weights.get(k, 1.0) for k in intersection)
        sum_a = sum(weights.get(k, 1.0) for k in ru)
        sum_b = sum(weights.get(k, 1.0) for k in rv)
    else:
        num = float(len(intersection))
        sum_a = float(len(ru))
        sum_b = float(len(rv))

    denominator = math.sqrt(sum_a * sum_b) + epsilon
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
