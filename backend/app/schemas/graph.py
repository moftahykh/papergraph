from datetime import datetime, timezone
from typing import List, Optional
from pydantic import BaseModel, Field
from app.models.enums import GraphJobStatus
from app.models.graph import GraphSnapshot, GraphWarning, DataCompleteness


class CreateGraphRequest(BaseModel):
    origin_id: str = Field(
        ...,
        min_length=2,
        max_length=500,
        description="Canonical paper ID or DOI of the seed/origin paper.",
    )
    max_nodes: int = Field(
        default=40,
        ge=10,
        le=75,
        description="Maximum synthesized nodes in the final graph topology (target: 30-50).",
    )
    include_prior_works: bool = Field(
        default=True,
        description="Extract and score foundational prior works.",
    )
    include_derivative_works: bool = Field(
        default=True,
        description="Extract and score subsequent derivative works.",
    )
    weight_profile: str = Field(
        default="default",
        description="Ranking weight preset profile ('default', 'recent', 'classic').",
    )
    algorithm_version: str = Field(
        default="v1.0",
        description="Target algorithm version for ranking and layout calculation.",
    )


class CreateGraphResponse(BaseModel):
    graph_id: str = Field(..., description="Unique graph job identifier.")
    status: GraphJobStatus = Field(default=GraphJobStatus.QUEUED, description="Initial job status.")
    poll_url: str = Field(..., description="URL endpoint to poll for status and final graph topology.")
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class GraphStatusResponse(BaseModel):
    """
    Response returned by polling GET /api/v1/graphs/{id}.
    Exposes typed lifecycle states, progress, warnings, completeness, and snapshot.
    """
    graph_id: str = Field(..., description="Graph identifier.")
    status: GraphJobStatus = Field(..., description="Current job lifecycle status.")
    progress: float = Field(default=0.0, ge=0.0, le=1.0, description="Float progress indicator.")
    current_stage: GraphJobStatus = Field(..., description="Detailed execution stage.")
    poll_url: str = Field(..., description="Endpoint to poll while active.")
    
    snapshot: Optional[GraphSnapshot] = Field(
        default=None,
        description="Synthesized graph topology (present when status is 'completed' or 'partial').",
    )
    warnings: List[GraphWarning] = Field(
        default_factory=list,
        description="Warnings detailing missing signals or upstream provider errors for partial results.",
    )
    data_completeness: Optional[DataCompleteness] = Field(
        default=None,
        description="Completeness ratios for metadata, references, citations, and embeddings.",
    )
    error: Optional[str] = Field(
        default=None,
        description="Error details if status is 'failed'.",
    )
