from typing import Dict, Tuple
from app.models.canonical_paper import CanonicalPaper
from app.models.metric import MetricResult
from app.models.enums import MetricAvailability
from app.candidates.models import CandidateRecord
from app.resolution.similarity import token_sort_ratio

BASELINE_PRESCORE_WEIGHTS = {
    "semantic": 0.50,
    "direct": 0.20,
    "topic_title": 0.15,
    "recency": 0.10,
    "metadata_quality": 0.05,
}


def calculate_topic_title_relevance(
    origin: CanonicalPaper, candidate: CanonicalPaper
) -> float:
    """Computes title lexical similarity and topic set overlap in [0.0, 1.0]."""
    # Title token match
    title_score = token_sort_ratio(origin.title, candidate.title, filter_stopwords=True)
    
    # Topic overlap
    topic_score = 0.0
    if origin.topics and candidate.topics:
        set_origin = {t.lower().strip() for t in origin.topics}
        set_cand = {t.lower().strip() for t in candidate.topics}
        intersection = set_origin.intersection(set_cand)
        union = set_origin.union(set_cand)
        if union:
            topic_score = len(intersection) / len(union)

    # 70% title relevance, 30% topic overlap
    return round(0.70 * title_score + 0.30 * topic_score, 4)


def calculate_recency_proximity(
    origin_year: int | None, candidate_year: int | None
) -> float:
    """
    Computes publication year proximity score in [0.0, 1.0].
    Smoothly decays as publication year distance increases.
    """
    if origin_year is None or candidate_year is None:
        return 0.5
    diff = abs(origin_year - candidate_year)
    return round(1.0 / (1.0 + 0.08 * diff), 4)


def compute_prescore(
    candidate: CandidateRecord,
    origin: CanonicalPaper,
) -> Tuple[float, Dict[str, MetricResult], Dict[str, float]]:
    """
    Calculates composite PreScore using proportional weight renormalization over available signals.
    Guarantees: Missing semantic score or year is NEVER treated as zero.
    """
    signals: Dict[str, MetricResult] = {}

    # 1. Semantic Candidate Signal (w = 0.50)
    if candidate.raw_semantic_score is not None:
        signals["semantic"] = MetricResult(
            value=max(0.0, min(1.0, candidate.raw_semantic_score)),
            availability=MetricAvailability.AVAILABLE,
        )
    else:
        signals["semantic"] = MetricResult(
            value=None,
            availability=MetricAvailability.UNAVAILABLE,
            reason="semantic_score_not_provided",
        )

    # 2. Direct Relation Signal (w = 0.20)
    # 1.0 if origin cites candidate (direct reference)
    # 0.8 if candidate cites origin (direct citation)
    # 0.0 if not directly linked
    if candidate.is_direct_reference:
        direct_val = 1.0
    elif candidate.is_direct_citation:
        direct_val = 0.8
    else:
        direct_val = 0.0
    signals["direct"] = MetricResult(
        value=direct_val,
        availability=MetricAvailability.AVAILABLE,
    )

    # 3. Topic/Title Relevance Signal (w = 0.15)
    relevance_val = calculate_topic_title_relevance(origin, candidate.paper)
    signals["topic_title"] = MetricResult(
        value=relevance_val,
        availability=MetricAvailability.AVAILABLE,
    )

    # 4. Recency Proximity Signal (w = 0.10)
    if origin.year is not None and candidate.paper.year is not None:
        recency_val = calculate_recency_proximity(origin.year, candidate.paper.year)
        signals["recency"] = MetricResult(
            value=recency_val,
            availability=MetricAvailability.AVAILABLE,
        )
    else:
        signals["recency"] = MetricResult(
            value=None,
            availability=MetricAvailability.UNAVAILABLE,
            reason="publication_year_missing",
        )

    # 5. Metadata Quality Signal (w = 0.05)
    signals["metadata_quality"] = MetricResult(
        value=max(0.0, min(1.0, candidate.paper.completeness)),
        availability=MetricAvailability.AVAILABLE,
    )

    # ==========================================================================
    # Proportional Weight Renormalization
    # ==========================================================================
    available_keys = [
        k for k, sig in signals.items()
        if sig.availability == MetricAvailability.AVAILABLE and sig.value is not None
    ]

    if not available_keys:
        return 0.0, signals, {}

    sum_available_weights = sum(BASELINE_PRESCORE_WEIGHTS[k] for k in available_keys)
    renormalized_weights: Dict[str, float] = {}

    pre_score = 0.0
    for k in available_keys:
        norm_w = BASELINE_PRESCORE_WEIGHTS[k] / sum_available_weights
        renormalized_weights[k] = round(norm_w, 4)
        pre_score += norm_w * signals[k].value

    final_prescore = max(0.0, min(1.0, round(pre_score, 4)))
    return final_prescore, signals, renormalized_weights
