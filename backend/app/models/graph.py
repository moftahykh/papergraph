from datetime import datetime, timezone
from typing import List, Optional, Dict, Any, Literal
from pydantic import BaseModel, Field, field_validator
from app.models.enums import GraphJobStatus, EdgeType, ConfidenceLevel
from app.models.metric import MetricResult


class GraphWarning(BaseModel):
    code: str = Field(..., description="Machine-readable error/warning code.")
    message: str = Field(..., description="Human-readable explanation of the warning.")
    severity: Literal["info", "warning", "error"] = "warning"


class DataCompleteness(BaseModel):
    """
    Ratios of successfully ingested data across enrichment dimensions (0.0 to 1.0).
    Exposed in partial graph payloads to reflect incomplete upstream provider state.
    """
    metadata: float = Field(default=1.0, ge=0.0, le=1.0)
    references: float = Field(default=1.0, ge=0.0, le=1.0)
    citations: float = Field(default=1.0, ge=0.0, le=1.0)
    semantic: float = Field(default=1.0, ge=0.0, le=1.0)


class GraphNode(BaseModel):
    id: str = Field(..., description="Node identifier (matches canonical_id).")
    canonical_id: str = Field(..., description="Full canonical ID of the paper.")
    title: str = Field(..., description="Full publication title.")
    short_title: Optional[str] = Field(default=None, description="Truncated title for graph label display.")
    authors: List[str] = Field(default_factory=list, description="Author display names.")
    year: Optional[int] = Field(default=None, description="Publication year.")
    venue: Optional[str] = Field(default=None, description="Publication venue.")
    citation_count: int = Field(default=0, ge=0, description="Total citation count.")
    
    is_origin: bool = Field(default=False, description="Flag indicating if this node is the search origin.")
    radius: float = Field(default=12.0, ge=4.0, le=60.0, description="Visual node radius based on log citations.")
    x: float = Field(default=0.0, description="Layout X coordinate in 2D space.")
    y: float = Field(default=0.0, description="Layout Y coordinate in 2D space.")
    
    final_score: Optional[float] = Field(default=None, ge=0.0, le=1.0, description="Composite ranking score.")
    confidence: Optional[ConfidenceLevel] = Field(default=None, description="Confidence in final score.")
    scores: Optional[Dict[str, MetricResult]] = Field(default=None, description="Component metric scores.")
    
    cluster: Optional[int] = Field(default=None, description="Community cluster index.")
    archetype: Optional[str] = Field(
        default=None,
        description="Relationship classification: origin, prior_work, derivative_work, similar.",
    )


class GraphEdge(BaseModel):
    """
    Graph edge representation.
    Enforces Non-Negotiable Rule #9: Citation edges and similarity edges are separate relationship types.
    Citation edges are directional (directed=True).
    Similarity edges are non-directional (directed=False) and must never be rendered as arrows.
    """
    source: str = Field(..., description="Source node ID.")
    target: str = Field(..., description="Target node ID.")
    type: EdgeType = Field(..., description="Strictly 'citation' or 'similarity'.")
    weight: float = Field(default=1.0, ge=0.0, le=1.0, description="Normalized edge weight / score.")
    directed: bool = Field(default=False, description="True for citation edges, False for similarity edges.")
    label: Optional[str] = Field(default=None, description="Optional label for edge display.")
    metadata: Optional[Dict[str, Any]] = Field(default=None, description="Detailed signal breakdown.")

    @field_validator("directed", mode="after")
    @classmethod
    def validate_directed_by_type(cls, v: bool, info) -> bool:
        edge_type = info.data.get("type")
        if edge_type == EdgeType.SIMILARITY and v is True:
            raise ValueError("Similarity edges are non-directional and must have directed=False.")
        return v


class GraphOrigin(BaseModel):
    id: str
    canonical_id: str
    title: str
    year: Optional[int] = None
    doi: Optional[str] = None


class GraphSnapshot(BaseModel):
    """
    Immutable snapshot of a synthesized literature graph network.
    """
    graph_id: str = Field(..., description="Unique graph session identifier.")
    origin: GraphOrigin = Field(..., description="Origin paper information.")
    status: GraphJobStatus = Field(..., description="Completion state: completed or partial.")
    nodes: List[GraphNode] = Field(default_factory=list, description="Synthesized graph nodes (30-50 nodes).")
    similarity_edges: List[GraphEdge] = Field(default_factory=list, description="Non-directional similarity links.")
    citation_edges: List[GraphEdge] = Field(default_factory=list, description="Directional citation arrows.")
    data_completeness: DataCompleteness = Field(default_factory=DataCompleteness)
    warnings: List[GraphWarning] = Field(default_factory=list, description="Warnings if job finished as partial.")
    algorithm_version: str = Field(default="v1.0", description="Ranking and layout algorithm version.")
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    expires_at: Optional[datetime] = None


class GraphJob(BaseModel):
    """
    Lifecycle tracking model for asynchronous graph synthesis pipeline.
    """
    job_id: str = Field(..., description="Asynchronous task identifier.")
    origin_query: str = Field(..., description="Input query, DOI, or title.")
    status: GraphJobStatus = Field(default=GraphJobStatus.QUEUED)
    progress: float = Field(default=0.0, ge=0.0, le=1.0, description="Progress indicator in [0.0, 1.0].")
    current_stage: GraphJobStatus = Field(default=GraphJobStatus.QUEUED)
    poll_url: str = Field(..., description="Relative API polling endpoint.")
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    result: Optional[GraphSnapshot] = None
    error: Optional[str] = None
    warnings: List[GraphWarning] = Field(default_factory=list)
