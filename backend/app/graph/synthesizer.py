import uuid
from typing import List, Optional
from app.models.canonical_paper import CanonicalPaper
from app.models.enums import GraphJobStatus
from app.models.graph import (
    GraphSnapshot,
    GraphOrigin,
    GraphWarning,
    DataCompleteness,
    GraphNode,
)
from app.ranking.models import RankingResult, RankedCandidate
from app.graph.mmr import select_diverse_nodes_mmr
from app.graph.layout import generate_graph_layout
from app.graph.edges import synthesize_citation_edges, synthesize_similarity_edges


def _bounded_candidates(
    ranked_candidates: List[RankedCandidate],
    max_nodes: int,
) -> List[RankedCandidate]:
    """Prevent recommendation-only papers from dominating a graph.

    Direct references and direct citations are evidence-backed and remain
    eligible regardless of publication year. Recommendation-only papers are
    useful discovery signals, but they must not consume the whole graph before
    relationships are validated.
    """
    recommendation_only: List[RankedCandidate] = []
    evidence_backed: List[RankedCandidate] = []

    for candidate in ranked_candidates:
        record = candidate.candidate_record
        is_recommendation_only = (
            record is not None
            and record.is_recommendation
            and not record.is_direct_reference
            and not record.is_direct_citation
        )
        if is_recommendation_only:
            recommendation_only.append(candidate)
        else:
            evidence_backed.append(candidate)

    # Keep a small discovery lane without allowing current recommendations to
    # drown out the citation/reference neighborhood of an older origin.
    recommendation_cap = max(3, int(max_nodes * 0.20))
    return evidence_backed + recommendation_only[:recommendation_cap]


def _origin_component_ids(
    origin_id: str,
    citation_edges,
    similarity_edges,
) -> set[str]:
    """Return the undirected component containing the origin node."""
    adjacency: dict[str, set[str]] = {}
    for edge in [*citation_edges, *similarity_edges]:
        adjacency.setdefault(edge.source, set()).add(edge.target)
        adjacency.setdefault(edge.target, set()).add(edge.source)

    reachable = {origin_id}
    pending = [origin_id]
    while pending:
        current = pending.pop()
        for neighbor in adjacency.get(current, ()):
            if neighbor not in reachable:
                reachable.add(neighbor)
                pending.append(neighbor)
    return reachable


class GraphSynthesizer:
    """
    Synthesizes diverse literature graph snapshots implementing PLAN.md Phase 7:
      - MMR diversity selection with lambda = 0.70.
      - 30–50 bounded nodes with origin at center.
      - Enforces Non-Negotiable Rule #9 (directed citation edges vs undirected similarity edges).
      - Strictly prevents self-edges and duplicate nodes.
      - Computes server-side 2D layout for immediate, lag-free Flutter canvas rendering.
    """
    def __init__(
        self,
        default_max_nodes: int = 40,
        lambda_mmr: float = 0.70,
        similarity_threshold: float = 0.20,
    ):
        self.default_max_nodes = default_max_nodes
        self.lambda_mmr = lambda_mmr
        self.similarity_threshold = similarity_threshold

    def synthesize_snapshot(
        self,
        origin: CanonicalPaper,
        ranking_result: RankingResult,
        graph_id: Optional[str] = None,
        max_nodes: Optional[int] = None,
        data_completeness: Optional[DataCompleteness] = None,
        warnings: Optional[List[GraphWarning]] = None,
    ) -> GraphSnapshot:
        """
        Builds the complete GraphSnapshot from ranked candidates.
        """
        gid = graph_id or f"graph_{uuid.uuid4().hex[:12]}"
        limit = max_nodes or self.default_max_nodes
        completeness = data_completeness or DataCompleteness()
        warn_list = list(warnings) if warnings else []

        # 1. Apply MMR to select diverse candidates (target: 30–50 nodes).
        # Recommendation-only candidates get a bounded discovery quota.
        bounded_candidates = _bounded_candidates(
            ranking_result.ranked_candidates,
            limit,
        )
        selected_candidates = select_diverse_nodes_mmr(
            origin=origin,
            ranked_candidates=bounded_candidates,
            max_nodes=limit,
            lambda_param=self.lambda_mmr,
        )

        # 2. Generate 2D coordinates & node objects (Origin + Selected Candidates)
        nodes: List[GraphNode] = generate_graph_layout(
            origin=origin,
            selected_candidates=selected_candidates,
        )

        # Deduplicate nodes by ID if necessary (enforce unique nodes)
        seen_node_ids = set()
        unique_nodes: List[GraphNode] = []
        for n in nodes:
            if n.id not in seen_node_ids:
                seen_node_ids.add(n.id)
                unique_nodes.append(n)

        # 3. Collect papers for edge synthesis
        all_papers: List[CanonicalPaper] = [origin] + [c.paper for c in selected_candidates]
        # Deduplicate papers list
        seen_paper_ids = set()
        unique_papers: List[CanonicalPaper] = []
        for p in all_papers:
            if p.canonical_id not in seen_paper_ids:
                seen_paper_ids.add(p.canonical_id)
                unique_papers.append(p)

        # 4. Synthesize Directed Citation Edges (A -> B)
        citation_edges = synthesize_citation_edges(unique_papers)

        # 5. Synthesize Undirected Similarity Edges (A <-> B, directed=False)
        similarity_edges = synthesize_similarity_edges(
            unique_papers,
            min_threshold=self.similarity_threshold,
        )

        # 6. Keep only the connected component containing the origin. A paper
        # selected by ranking but lacking any validated path to the origin is
        # not part of this graph and must not render as a floating node.
        origin_component = _origin_component_ids(
            origin.canonical_id,
            citation_edges,
            similarity_edges,
        )
        removed_node_count = sum(
            1 for node in unique_nodes if node.id not in origin_component
        )
        if removed_node_count:
            warn_list.append(
                GraphWarning(
                    code="disconnected_nodes_excluded",
                    message=(
                        f"Excluded {removed_node_count} selected paper(s) "
                        "without a validated path to the origin."
                    ),
                    severity="warning",
                )
            )
            unique_nodes = [
                node for node in unique_nodes if node.id in origin_component
            ]
            citation_edges = [
                edge
                for edge in citation_edges
                if edge.source in origin_component
                and edge.target in origin_component
            ]
            similarity_edges = [
                edge
                for edge in similarity_edges
                if edge.source in origin_component
                and edge.target in origin_component
            ]
            # Recompute coordinates after pruning so excluded recommendation
            # nodes cannot repel valid nodes during the force-directed pass.
            selected_candidates = [
                candidate
                for candidate in selected_candidates
                if candidate.paper.canonical_id in origin_component
            ]
            nodes = generate_graph_layout(
                origin=origin,
                selected_candidates=selected_candidates,
            )
            unique_nodes = []
            seen_node_ids = set()
            for node in nodes:
                if node.id not in seen_node_ids:
                    seen_node_ids.add(node.id)
                    unique_nodes.append(node)

        # 7. Status determination: Check for warnings or low completeness
        has_warnings = any(w.severity in ("warning", "error") for w in warn_list)
        is_partial = has_warnings or (completeness.references < 0.70) or (completeness.citations < 0.70)
        status = GraphJobStatus.PARTIAL if is_partial else GraphJobStatus.COMPLETED

        origin_info = GraphOrigin(
            id=origin.canonical_id,
            canonical_id=origin.canonical_id,
            title=origin.title,
            year=origin.year,
            doi=origin.doi,
        )

        return GraphSnapshot(
            graph_id=gid,
            origin=origin_info,
            status=status,
            nodes=unique_nodes,
            similarity_edges=similarity_edges,
            citation_edges=citation_edges,
            data_completeness=completeness,
            warnings=warn_list,
            algorithm_version="v1.1",
        )
