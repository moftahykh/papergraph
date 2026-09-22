import math
from typing import List, Dict, Tuple
from app.models.canonical_paper import CanonicalPaper
from app.models.graph import GraphNode
from app.models.metric import MetricResult
from app.models.enums import MetricAvailability
from app.ranking.models import RankedCandidate
from app.graph.mmr import compute_pairwise_similarity
from app.graph.identifiers import identifier_aliases, relationship_target_map


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


def apply_force_directed_pass(
    nodes: List[GraphNode],
    papers_by_id: Dict[str, CanonicalPaper],
    bounds: float = 850.0,
    iterations: int = 100,
    ideal_distance: float = 240.0,
    similarity_threshold: float = 0.15,
    gravity: float = 0.04,
    start_temperature: float = 55.0,
) -> None:
    """
    Refines the deterministic archetype placement with a lightweight
    Fruchterman–Reingold style pass driven by pairwise paper similarity:

      - Similar pairs (sim >= similarity_threshold) attract like springs, so
        genuine research sub-communities visibly cluster together instead of
        rendering as a pure starburst around the origin.
      - All pairs repel (F_r = k^2 / d) to preserve readability.
      - Weak gravity toward each node's original archetype position keeps the
        prior-left / derivative-right semantics from dissolving.
      - The origin stays anchored at (0, 0) and hemisphere signs are enforced.

    Fully deterministic: fixed iteration order, linear cooling, no randomness.
    Runs in O(iterations x n^2); at n <= ~50 nodes this is well under 10ms.
    Mutates node.x / node.y in place.
    """
    n = len(nodes)
    if n <= 2:
        return

    # Snapshot the archetype placement as the gravity anchor for each node.
    anchors: Dict[str, Tuple[float, float]] = {nd.id: (nd.x, nd.y) for nd in nodes}

    # Precompute pairwise similarity once (cached across all iterations).
    sim_weights: Dict[Tuple[int, int], float] = {}
    for i in range(n):
        pi = papers_by_id.get(nodes[i].id)
        if pi is None:
            continue
        for j in range(i + 1, n):
            pj = papers_by_id.get(nodes[j].id)
            if pj is None:
                continue
            sim = compute_pairwise_similarity(pi, pj)
            if sim >= similarity_threshold:
                sim_weights[(i, j)] = sim

    # Direct citation links are the strongest semantic bond: add them as
    # springs too (same 3-way ID matching as edge synthesis). Without this,
    # a node whose only link is a citation gets exiled to the canvas edge
    # by pure repulsion, dragging an ugly long edge behind it.
    id_to_idx = {nd.id: i for i, nd in enumerate(nodes)}
    target_map = relationship_target_map(papers_by_id.values())

    linked_nodes: set = set()
    for i, nd in enumerate(nodes):
        p = papers_by_id.get(nd.id)
        if p is None:
            continue
        for ref in p.reference_ids:
            target_id = next(
                (
                    target_map[alias]
                    for alias in identifier_aliases(ref)
                    if alias in target_map
                ),
                None,
            )
            j = id_to_idx.get(target_id)
            if j is None or j == i:
                continue
            pair = (i, j) if i < j else (j, i)
            if sim_weights.get(pair, 0.0) < 0.90:
                sim_weights[pair] = 0.90
            linked_nodes.add(i)
            linked_nodes.add(j)

    for (i, j) in sim_weights:
        linked_nodes.add(i)
        linked_nodes.add(j)

    k = float(ideal_distance)

    for it in range(iterations):
        disp = [[0.0, 0.0] for _ in range(n)]

        # Repulsive force between every pair.
        for i in range(n):
            xi, yi = nodes[i].x, nodes[i].y
            for j in range(i + 1, n):
                dx = xi - nodes[j].x
                dy = yi - nodes[j].y
                dist = math.hypot(dx, dy)
                if dist < 0.01:
                    dx, dy, dist = 0.01, 0.0, 0.01
                force = (k * k) / dist
                fx = (dx / dist) * force
                fy = (dy / dist) * force
                disp[i][0] += fx
                disp[i][1] += fy
                disp[j][0] -= fx
                disp[j][1] -= fy

        # Attractive force along similarity springs (F_a = w * d^2 / k).
        for (i, j), w in sim_weights.items():
            dx = nodes[i].x - nodes[j].x
            dy = nodes[i].y - nodes[j].y
            dist = math.hypot(dx, dy)
            if dist < 0.01:
                continue
            force = w * (dist * dist) / k
            fx = (dx / dist) * force
            fy = (dy / dist) * force
            disp[i][0] -= fx
            disp[i][1] -= fy
            disp[j][0] += fx
            disp[j][1] += fy

        temperature = start_temperature * (1.0 - it / iterations)

        for i in range(n):
            nd = nodes[i]
            if nd.is_origin:
                continue  # origin anchored at (0, 0)

            # Weak linear gravity back toward the archetype anchor position.
            # Nodes with no spring at all (neither similarity nor citation)
            # get 4x gravity so pure repulsion cannot exile them to the edge.
            ax, ay = anchors[nd.id]
            g = gravity if i in linked_nodes else gravity * 4.0
            disp[i][0] += g * (ax - nd.x)
            disp[i][1] += g * (ay - nd.y)

            step = math.hypot(disp[i][0], disp[i][1])
            if step < 1e-6:
                continue
            capped = min(step, temperature)
            nd.x += (disp[i][0] / step) * capped
            nd.y += (disp[i][1] / step) * capped

            # Preserve hemisphere semantics.
            if nd.archetype == "prior_work":
                nd.x = min(-60.0, nd.x)
            elif nd.archetype == "derivative_work":
                nd.x = max(60.0, nd.x)

            # Keep everything inside the canvas bounds.
            nd.x = max(-bounds, min(bounds, nd.x))
            nd.y = max(-bounds, min(bounds, nd.y))


def generate_graph_layout(
    origin: CanonicalPaper,
    selected_candidates: List[RankedCandidate],
    canvas_radius: float = 650.0,
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

        # Convert all computed score signals to the node payload. The early
        # pre-signals map does not contain WBC/NCC; those are calculated later
        # by the enrichment pipeline and must be copied from the enrichment
        # record or the app will display "Not enough data" for every paper.
        scores_dict = {}
        if cand.candidate_record and cand.candidate_record.pre_signals:
            scores_dict.update(cand.candidate_record.pre_signals)
        if cand.enrichment_record is not None:
            scores_dict["wbc"] = cand.enrichment_record.wbc
            scores_dict["ncc"] = cand.enrichment_record.ncc

        # Expose the two derived classification signals as well so the list
        # and details views can explain prior/follow-up classification.
        scores_dict["prior_score"] = MetricResult(
            value=cand.prior_score,
            availability=MetricAvailability.AVAILABLE,
        )
        scores_dict["derivative_score"] = MetricResult(
            value=cand.derivative_score,
            availability=MetricAvailability.AVAILABLE,
        )

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
            scores=scores_dict or None,
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

    # 6. Force-directed refinement: pull genuinely similar papers together so
    # research sub-communities cluster visually instead of a pure starburst.
    papers_by_id: Dict[str, CanonicalPaper] = {origin.canonical_id: origin}
    for cand in selected_candidates:
        papers_by_id[cand.paper.canonical_id] = cand.paper
    apply_force_directed_pass(nodes, papers_by_id, bounds=canvas_radius + 150.0)

    # 7. Collision Avoidance & Relaxation Pass
    # Ensures nodes maintain clear breathing room and never overlap
    for _ in range(20):
        for i in range(1, len(nodes)):  # Origin (index 0) remains anchored at (0,0)
            n1 = nodes[i]
            for j in range(len(nodes)):
                if i == j:
                    continue
                n2 = nodes[j]
                dx = n1.x - n2.x
                dy = n1.y - n2.y
                dist = math.hypot(dx, dy)
                min_gap = (n1.radius + n2.radius) + 20.0

                if dist < min_gap:
                    overlap = min_gap - dist
                    if dist > 0.001:
                        nx = dx / dist
                        ny = dy / dist
                    else:
                        nx = 1.0
                        ny = 0.0

                    push = overlap * 0.4
                    new_x = n1.x + nx * push
                    new_y = n1.y + ny * push

                    # Preserve hemisphere boundaries
                    if n1.archetype == "prior_work":
                        new_x = min(-60.0, new_x)
                    elif n1.archetype == "derivative_work":
                        new_x = max(60.0, new_x)

                    # Respect the same canvas bounds used by the force pass,
                    # so collision pushes can never push a node out of range.
                    bound = canvas_radius + 150.0
                    new_x = max(-bound, min(bound, new_x))
                    new_y = max(-bound, min(bound, new_y))

                    n1.x = round(new_x, 2)
                    n1.y = round(new_y, 2)

    return nodes
