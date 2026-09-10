from enum import Enum
from typing import List, Optional, Dict, Any
from pydantic import BaseModel, Field
from app.models.canonical_paper import CanonicalPaper
from app.models.metric import MetricResult
from app.models.enums import MetricAvailability, GraphJobStatus
from app.models.graph import GraphWarning, DataCompleteness
from app.candidates.models import CandidateRecord


class EnrichmentStatusEnum(str, Enum):
    SUCCESS = "success"
    PARTIAL = "partial"
    FAILED = "failed"
    SKIPPED = "skipped"
    EMPTY = "empty"
    NOT_SELECTED = "not_selected"


class CandidateEnrichmentRecord(BaseModel):
    """
    Enrichment lifecycle state, fetched signals, and metric scores for a single candidate.
    """
    candidate: CandidateRecord

    # Metadata enrichment
    metadata_status: EnrichmentStatusEnum = EnrichmentStatusEnum.SKIPPED
    enriched_fields: List[str] = Field(default_factory=list)

    # Reference enrichment (Outbound citations)
    references_status: EnrichmentStatusEnum = EnrichmentStatusEnum.SKIPPED
    references_count: int = Field(default=0, ge=0)
    references_complete: bool = False

    # Citation enrichment (Inbound citations)
    citations_status: EnrichmentStatusEnum = EnrichmentStatusEnum.NOT_SELECTED
    citations_count: int = Field(default=0, ge=0)
    citations_complete: bool = False

    # Computed topological similarity metrics
    wbc: MetricResult = Field(
        default_factory=lambda: MetricResult(
            value=None,
            availability=MetricAvailability.UNAVAILABLE,
            reason="references_not_loaded",
        )
    )
    ncc: MetricResult = Field(
        default_factory=lambda: MetricResult(
            value=None,
            availability=MetricAvailability.NOT_APPLICABLE,
            reason="not_selected_for_citation_enrichment",
        )
    )

    warnings: List[str] = Field(default_factory=list)

    model_config = {
        "arbitrary_types_allowed": True,
    }


class EnrichmentPipelineResult(BaseModel):
    """
    Output payload of the Phase 5 staged enrichment pipeline.
    """
    origin: CanonicalPaper
    candidates: List[CandidateEnrichmentRecord]
    metadata_completeness: float = Field(default=1.0, ge=0.0, le=1.0)
    references_completeness: float = Field(default=1.0, ge=0.0, le=1.0)
    citations_completeness: float = Field(default=1.0, ge=0.0, le=1.0)
    data_completeness: DataCompleteness = Field(default_factory=DataCompleteness)
    warnings: List[GraphWarning] = Field(default_factory=list)
    status: GraphJobStatus = GraphJobStatus.COMPLETED

    model_config = {
        "arbitrary_types_allowed": True,
    }
