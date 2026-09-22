from typing import List, Tuple, Set, Dict
from app.models.canonical_paper import CanonicalPaper
from app.models.enums import EdgeType
from app.models.graph import GraphEdge
from app.graph.mmr import compute_pairwise_similarity
from app.graph.identifiers import identifier_aliases, relationship_target_map


def synthesize_citation_edges(
    nodes: List[CanonicalPaper],
) -> List[GraphEdge]:
    """
    Synthesizes directed citation edges (A -> B means A cites B).
    Enforces Non-Negotiable Rule #9:
      - type = EdgeType.CITATION
      - directed = True
      - Strictly no self-edges (source != target)
    """
    citation_edges: List[GraphEdge] = []
    target_map = relationship_target_map(nodes)

    seen_pairs: Set[Tuple[str, str]] = set()

    for paper in nodes:
        source_id = paper.canonical_id
        for ref_id in paper.reference_ids:
            target_id = next(
                (
                    target_map[alias]
                    for alias in identifier_aliases(ref_id)
                    if alias in target_map
                ),
                None,
            )
            # Rule: No self-edges and no edges to papers outside this snapshot.
            if target_id is None or source_id == target_id:
                continue

            pair = (source_id, target_id)
            if pair in seen_pairs:
                continue
            seen_pairs.add(pair)
            citation_edges.append(
                GraphEdge(
                    source=source_id,
                    target=target_id,
                    type=EdgeType.CITATION,
                    weight=1.0,
                    directed=True,  # Directional arrow
                    label="cites",
                )
            )

    return citation_edges


def synthesize_similarity_edges(
    nodes: List[CanonicalPaper],
    min_threshold: float = 0.42,
    max_neighbors_per_node: int = 2,
) -> List[GraphEdge]:
    """
    Synthesizes non-directional similarity edges based on multi-factor similarity.
    Enforces Non-Negotiable Rule #9:
      - type = EdgeType.SIMILARITY
      - directed = False (CRITICAL: Never rendered as arrows)
      - Strictly no self-edges
      - Single edge per pair (source < target canonical ordering)
    """
    similarity_edges: List[GraphEdge] = []
    n = len(nodes)
    if n < 2:
        return []

    # Calculate pairwise similarities
    pair_weights: Dict[Tuple[str, str], float] = {}
    node_neighbors: Dict[str, List[Tuple[str, float]]] = {p.canonical_id: [] for p in nodes}

    for i in range(n):
        for j in range(i + 1, n):
            p1 = nodes[i]
            p2 = nodes[j]

            sim = compute_pairwise_similarity(p1, p2)
            if sim >= min_threshold:
                # Canonical ordering so (A, B) is identical to (B, A)
                id_a, id_b = sorted([p1.canonical_id, p2.canonical_id])
                pair = (id_a, id_b)
                pair_weights[pair] = sim
                node_neighbors[p1.canonical_id].append((p2.canonical_id, sim))
                node_neighbors[p2.canonical_id].append((p1.canonical_id, sim))

    # Keep top-k neighbors per node to maintain visual readability in UI
    selected_pairs: Set[Tuple[str, str]] = set()
    for cid, neighbors in node_neighbors.items():
        # Sort descending by similarity
        neighbors.sort(key=lambda x: x[1], reverse=True)
        for neighbor_id, sim in neighbors[:max_neighbors_per_node]:
            pair = tuple(sorted([cid, neighbor_id]))
            selected_pairs.add(pair)

    for id_a, id_b in selected_pairs:
        weight = pair_weights.get((id_a, id_b), min_threshold)
        similarity_edges.append(
            GraphEdge(
                source=id_a,
                target=id_b,
                type=EdgeType.SIMILARITY,
                weight=round(weight, 4),
                directed=False,  # Non-directional link
                label=f"sim: {weight:.2f}",
            )
        )

    return similarity_edges
