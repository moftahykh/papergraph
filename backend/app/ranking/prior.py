import math
from typing import List, Dict, Optional
from app.models.canonical_paper import CanonicalPaper
from app.core.config import settings


def compute_prior_scores(
    origin: CanonicalPaper,
    papers: List[CanonicalPaper],
    relevance_scores: Optional[Dict[str, float]] = None,
    epsilon: float = settings.ENRICHMENT_EPSILON,
) -> Dict[str, float]:
    """
    Computes normalized PriorScore for candidates to identify foundational works:
    
      frequency_norm = frequency / (max_frequency + epsilon)
      influence_norm = log1p(citations) / (log1p(max_citations) + epsilon)
      prior_score = frequency_norm * influence_norm * relevance
      
    Guarantees:
      - All scores are strictly in [0.0, 1.0].
      - No NaN or infinity values under any input condition.
    """
    if not papers:
        return {}

    relevance_scores = relevance_scores or {}

    # 1. Compute reference frequency across the candidate network
    # Frequency: How many papers in the network cite this candidate
    frequencies: Dict[str, int] = {}
    citations_map: Dict[str, int] = {}

    for p in papers:
        pid = p.canonical_id
        citations_map[pid] = max(0, p.citation_count or 0)
        
        # Count how many other candidates cite p
        count = 0
        p_doi = p.doi.lower().strip() if p.doi else None
        p_s2 = p.semantic_scholar_id
        
        for other in papers:
            if other.canonical_id == pid:
                continue
            other_refs = set(other.reference_ids)
            if pid in other_refs or (p_doi and p_doi in other_refs) or (p_s2 and p_s2 in other_refs):
                count += 1
                
        # Also check if origin cites p
        origin_refs = set(origin.reference_ids)
        if pid in origin_refs or (p_doi and p_doi in origin_refs) or (p_s2 and p_s2 in origin_refs):
            count += 2  # Origin direct reference gives stronger foundational weight

        frequencies[pid] = count

    max_frequency = max(frequencies.values()) if frequencies else 1
    max_citations = max(citations_map.values()) if citations_map else 1

    log_max_citations = math.log1p(float(max_citations)) + epsilon

    prior_scores: Dict[str, float] = {}

    for p in papers:
        pid = p.canonical_id
        freq = float(frequencies[pid])
        freq_norm = freq / (float(max_frequency) + epsilon)
        
        cites = float(citations_map[pid])
        influence_norm = math.log1p(cites) / log_max_citations
        
        # Relevance: use provided score, default to 0.50 if not specified
        rel = relevance_scores.get(pid, 0.50)
        rel_clamped = min(1.0, max(0.0, rel if rel is not None else 0.50))
        
        score = freq_norm * influence_norm * rel_clamped

        if math.isnan(score) or math.isinf(score):
            score = 0.0

        prior_scores[pid] = round(min(1.0, max(0.0, score)), 6)

    return prior_scores
