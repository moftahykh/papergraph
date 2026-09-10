import math
from typing import List, Dict, Optional, Set
from app.models.canonical_paper import CanonicalPaper
from app.core.config import settings


def compute_derivative_scores(
    origin: CanonicalPaper,
    papers: List[CanonicalPaper],
    decay_lambda: float = 0.20,
    epsilon: float = settings.ENRICHMENT_EPSILON,
) -> Dict[str, float]:
    """
    Computes normalized DerivativeScore for candidates to identify downstream evolution works:
    
      overlap_ratio = overlap_count / network_size
      recency = min(1.0, 1.0 / (1.0 + lambda * max(0, origin_year - paper_year)))
      influence = log1p(citations) / (log1p(max_citations) + epsilon)
      derivative_score = overlap_ratio * recency * influence
      
    Rule: Require overlap_count >= 2. Otherwise derivative_score = 0.0.
    Guarantees:
      - All scores are strictly in [0.0, 1.0].
      - No NaN or infinity values under any input condition.
    """
    if not papers:
        return {}

    origin_refs: Set[str] = set(origin.reference_ids)
    network_size = max(1, len(origin_refs))

    citations_map = {p.canonical_id: max(0, p.citation_count or 0) for p in papers}
    max_citations = max(citations_map.values()) if citations_map else 1
    log_max_citations = math.log1p(float(max_citations)) + epsilon

    origin_year = origin.year

    derivative_scores: Dict[str, float] = {}

    for p in papers:
        pid = p.canonical_id
        cand_refs = set(p.reference_ids)
        
        # Overlap with origin references
        overlap_count = len(origin_refs.intersection(cand_refs))

        # Check if candidate directly cites origin as well
        p_doi = p.doi.lower().strip() if p.doi else None
        p_s2 = p.semantic_scholar_id
        if origin.canonical_id in cand_refs or (origin.doi and origin.doi in cand_refs):
            overlap_count += 1

        # Strict requirement: overlap_count >= 2
        if overlap_count < 2:
            derivative_scores[pid] = 0.0
            continue

        overlap_ratio = min(1.0, float(overlap_count) / float(network_size))

        # Recency calculation
        if origin_year is not None and p.year is not None:
            year_diff = max(0, origin_year - p.year)
            recency = min(1.0, 1.0 / (1.0 + decay_lambda * float(year_diff)))
        else:
            recency = 1.0

        # Influence calculation
        cites = float(citations_map[pid])
        influence = math.log1p(cites) / log_max_citations

        score = overlap_ratio * recency * influence

        if math.isnan(score) or math.isinf(score):
            score = 0.0

        derivative_scores[pid] = round(min(1.0, max(0.0, score)), 6)

    return derivative_scores
