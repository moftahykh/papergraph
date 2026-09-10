import math
from typing import List, Set, Dict, Optional
from app.models.canonical_paper import CanonicalPaper
from app.ranking.models import RankedCandidate
from app.core.config import settings


def compute_pairwise_similarity(
    paper_a: CanonicalPaper,
    paper_b: CanonicalPaper,
    epsilon: float = settings.ENRICHMENT_EPSILON,
) -> float:
    """
    Computes a symmetric, multi-factor pairwise similarity score in [0.0, 1.0]
    between two academic papers for diversity penalty in MMR:
      1. Reference overlap (WBC signal)
      2. Citation overlap (NCC signal)
      3. Direct citation relationship
      4. Topic concept overlap (Jaccard similarity)
    """
    if paper_a.canonical_id == paper_b.canonical_id:
        return 1.0

    scores: List[float] = []
    weights: List[float] = []

    # 1. Reference overlap
    refs_a = set(paper_a.reference_ids)
    refs_b = set(paper_b.reference_ids)
    if refs_a and refs_b:
        ref_overlap = len(refs_a.intersection(refs_b))
        ref_sim = ref_overlap / (math.sqrt(len(refs_a) * len(refs_b)) + epsilon)
        scores.append(min(1.0, max(0.0, ref_sim)))
        weights.append(0.35)

    # 2. Inbound citation overlap
    cites_a = set(paper_a.citation_ids)
    cites_b = set(paper_b.citation_ids)
    if cites_a and cites_b:
        cite_overlap = len(cites_a.intersection(cites_b))
        cite_sim = cite_overlap / (math.sqrt(len(cites_a) * len(cites_b)) + epsilon)
        scores.append(min(1.0, max(0.0, cite_sim)))
        weights.append(0.35)

    # 3. Direct citation link
    is_direct = (
        paper_b.canonical_id in refs_a
        or paper_a.canonical_id in refs_b
        or (paper_b.doi and paper_b.doi in refs_a)
        or (paper_a.doi and paper_a.doi in refs_b)
    )
    if is_direct:
        scores.append(1.0)
        weights.append(0.15)
    else:
        scores.append(0.0)
        weights.append(0.15)

    # 4. Topic overlap (Jaccard)
    topics_a = {t.lower().strip() for t in paper_a.topics if t}
    topics_b = {t.lower().strip() for t in paper_b.topics if t}
    if topics_a and topics_b:
        jaccard = len(topics_a.intersection(topics_b)) / float(len(topics_a.union(topics_b)))
        scores.append(jaccard)
        weights.append(0.15)

    if not scores or sum(weights) <= 0.0:
        return 0.0

    weighted_sim = sum(s * w for s, w in zip(scores, weights)) / sum(weights)
    return round(min(1.0, max(0.0, weighted_sim)), 6)


def select_diverse_nodes_mmr(
    origin: CanonicalPaper,
    ranked_candidates: List[RankedCandidate],
    max_nodes: int = 40,
    lambda_param: float = 0.70,
) -> List[RankedCandidate]:
    """
    Applies Maximal Marginal Relevance (MMR) with lambda = 0.70 to select a diverse,
    informative subgraph (30–50 nodes), preventing redundancy.
    
    Formula:
      MMR(d) = lambda * Relevance(d) - (1 - lambda) * max_{s in S} Similarity(d, s)
    """
    if not ranked_candidates:
        return []

    target_count = min(max_nodes, len(ranked_candidates))
    if target_count <= 0:
        return []

    # Filter out any accidental origin duplicate in candidate list
    filtered_candidates = [
        rc for rc in ranked_candidates
        if rc.paper.canonical_id != origin.canonical_id
        and (not origin.doi or rc.paper.doi != origin.doi)
    ]

    if not filtered_candidates:
        return []

    selected: List[RankedCandidate] = []
    selected_papers: List[CanonicalPaper] = [origin]
    remaining = list(filtered_candidates)

    # Greedily pick the first paper (highest ranked)
    first_choice = remaining.pop(0)
    selected.append(first_choice)
    selected_papers.append(first_choice.paper)

    # Iteratively select candidates maximizing MMR score
    while len(selected) < target_count and remaining:
        best_candidate = None
        best_candidate_idx = -1
        best_mmr_score = -float("inf")

        for idx, cand in enumerate(remaining):
            rel_score = cand.final_score if cand.final_score is not None else 0.50

            # Compute maximum similarity to any already-selected node (including origin)
            max_sim = max(
                compute_pairwise_similarity(cand.paper, s_paper)
                for s_paper in selected_papers
            )

            # MMR formula
            mmr_score = (lambda_param * rel_score) - ((1.0 - lambda_param) * max_sim)

            if mmr_score > best_mmr_score:
                best_mmr_score = mmr_score
                best_candidate = cand
                best_candidate_idx = idx

        if best_candidate is not None:
            selected.append(best_candidate)
            selected_papers.append(best_candidate.paper)
            remaining.pop(best_candidate_idx)
        else:
            break

    return selected
