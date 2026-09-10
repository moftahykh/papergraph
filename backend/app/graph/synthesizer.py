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

        # 1. Apply MMR to select diverse candidates (target: 30–50 nodes)
        selected_candidates = select_diverse_nodes_mmr(
            origin=origin,
            ranked_candidates=ranking_result.ranked_candidates,
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

        # 6. Status determination: Check for warnings or low completeness
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
            algorithm_version="v1.0",
        )
