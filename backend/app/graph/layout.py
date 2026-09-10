import math
from typing import List, Dict, Tuple
from app.models.canonical_paper import CanonicalPaper
from app.models.graph import GraphNode
from app.ranking.models import RankedCandidate


def compute_node_radius(citation_count: int, is_origin: bool = False) -> float:
    """
    Computes visual node radius scaled logarithmically by citation count:
      radius in [8.0, 32.0], origin given prominent radius (24.0).
    """
    if is_origin:
        return 24.0
    cites = max(0, citation_count or 0)
    radius = 8.0 + 3.5 * math.log1p(float(cites))
    return round(min(32.0, max(8.0, radius)), 1)


def generate_graph_layout(
    origin: CanonicalPaper,
    selected_candidates: List[RankedCandidate],
    canvas_radius: float = 450.0,
) -> List[GraphNode]:
    """
    Generates deterministic 2D coordinates (x, y) and visual attributes for all graph nodes.
    
    Layout Structure:
      - Origin placed at the center (0.0, 0.0).
      - Prior works placed chronologically in the left quadrant (x < 0).
      - Derivative works placed chronologically in the right quadrant (x > 0).
      - Similar papers distributed radially based on relevance distance:
          distance = canvas_radius * (1.0 - 0.7 * final_score)
      - Angular spacing prevents overlapping nodes.
    """
    nodes: List[GraphNode] = []

    # 1. Add Origin Node
    origin_authors = [a.name for a in origin.authors[:3]] if origin.authors else ["Unknown"]
    origin_node = GraphNode(
        id=origin.canonical_id,
        canonical_id=origin.canonical_id,
        title=origin.title,
        short_title=origin.title[:45] + "..." if len(origin.title) > 45 else origin.title,
        authors=origin_authors,
        year=origin.year,
        venue=origin.venue,
        citation_count=origin.citation_count,
        is_origin=True,
        radius=compute_node_radius(origin.citation_count, is_origin=True),
        x=0.0,
        y=0.0,
        final_score=1.0,
        cluster=0,
        archetype="origin",
    )
    nodes.append(origin_node)

    # 2. Partition candidates into archetypes
    prior_cands = [c for c in selected_candidates if c.archetype == "prior_work"]
    deriv_cands = [c for c in selected_candidates if c.archetype == "derivative_work"]
    similar_cands = [
        c for c in selected_candidates
        if c.archetype not in ("prior_work", "derivative_work")
    ]

    def format_authors(paper: CanonicalPaper) -> List[str]:
        return [a.name for a in paper.authors[:3]] if paper.authors else ["Unknown"]

    def create_node(
        cand: RankedCandidate,
        x: float,
        y: float,
        cluster: int,
    ) -> GraphNode:
        p = cand.paper
        s_title = p.title[:40] + "..." if len(p.title) > 40 else p.title
        score_val = cand.final_score if cand.final_score is not None else 0.50
        rad = compute_node_radius(p.citation_count or 0, is_origin=False)

        # Convert score breakdown metrics to model
        scores_dict = None
        if cand.candidate_record and cand.candidate_record.pre_signals:
            scores_dict = cand.candidate_record.pre_signals

        return GraphNode(
            id=p.canonical_id,
            canonical_id=p.canonical_id,
            title=p.title,
            short_title=s_title,
            authors=format_authors(p),
            year=p.year,
            venue=p.venue,
            citation_count=p.citation_count or 0,
            is_origin=False,
            radius=rad,
            x=round(x, 2),
            y=round(y, 2),
            final_score=cand.final_score,
            confidence=cand.confidence,
            scores=scores_dict,
            cluster=cluster,
            archetype=cand.archetype,
        )

    # 3. Position Prior Works (Left side, x in [-canvas_radius, -80])
    num_prior = len(prior_cands)
    for i, cand in enumerate(prior_cands):
        # Fan across angles from 120 deg to 240 deg (left hemisphere)
        angle = math.pi + (i - (num_prior - 1) / 2.0) * (math.pi / max(3, num_prior))
        dist = 180.0 + (i % 3) * 70.0
        x = dist * math.cos(angle)
        y = dist * math.sin(angle)
        nodes.append(create_node(cand, x, y, cluster=1))

    # 4. Position Derivative Works (Right side, x in [80, canvas_radius])
    num_deriv = len(deriv_cands)
    for i, cand in enumerate(deriv_cands):
        # Fan across angles from -60 deg to +60 deg (right hemisphere)
        angle = 0.0 + (i - (num_deriv - 1) / 2.0) * (math.pi / max(3, num_deriv))
        dist = 180.0 + (i % 3) * 70.0
        x = dist * math.cos(angle)
        y = dist * math.sin(angle)
        nodes.append(create_node(cand, x, y, cluster=2))

    # 5. Position Similar Works (Distributed in upper/lower polar regions)
    num_sim = len(similar_cands)
    for i, cand in enumerate(similar_cands):
        # Alternate top and bottom wedges
        is_top = (i % 2 == 0)
        base_angle = (math.pi / 2.0) if is_top else (-math.pi / 2.0)
        spread = (i // 2 - (num_sim // 4)) * (math.pi / max(4, num_sim // 2))
        angle = base_angle + spread

        score_rel = cand.final_score if cand.final_score is not None else 0.50
        dist = 140.0 + (1.0 - 0.5 * score_rel) * 200.0 + (i % 4) * 35.0

        x = dist * math.cos(angle)
        y = dist * math.sin(angle)
        cluster_id = 3 if is_top else 4
        nodes.append(create_node(cand, x, y, cluster=cluster_id))

    return nodes
