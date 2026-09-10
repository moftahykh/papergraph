from enum import Enum
from typing import List, Optional, Dict, Set
from pydantic import BaseModel, Field
from app.models.canonical_paper import CanonicalPaper
from app.models.metric import MetricResult


class CandidateSourceType(str, Enum):
    REFERENCE = "reference"          # Outbound citation from origin
    CITATION = "citation"            # Inbound citation to origin
    RECOMMENDATION = "recommendation" # S2 recommendations or OpenAlex related
    SEARCH = "search"                # Topic / lexical search match


class CandidateRecord(BaseModel):
    """
    Tracks a candidate paper through generation, pre-ranking, and quota retention.
    """
    paper: CanonicalPaper
    sources: Set[CandidateSourceType] = Field(default_factory=set)
    
    # Discovery flags
    is_direct_reference: bool = Field(
        default=False,
        description="True if origin explicitly cites this paper (Origin -> Candidate).",
    )
    is_direct_citation: bool = Field(
        default=False,
        description="True if this paper cites the origin (Candidate -> Origin).",
    )
    is_recommendation: bool = Field(
        default=False,
        description="True if retrieved from recommendations or related works vector.",
    )
    
    # Pre-ranking signals
    raw_semantic_score: Optional[float] = Field(
        default=None,
        ge=0.0,
        le=1.0,
        description="Raw similarity or recommendation score from provider if available.",
    )
    pre_score: float = Field(
        default=0.0,
        ge=0.0,
        le=1.0,
        description="Fast composite score computed with missing-signal weight renormalization.",
    )
    pre_signals: Dict[str, MetricResult] = Field(default_factory=dict)
    renormalized_weights: Dict[str, float] = Field(default_factory=dict)

    # Retention tracking
    retention_reasons: List[str] = Field(
        default_factory=list,
        description="Specific quotas and criteria that caused this candidate to survive.",
    )
    is_retained: bool = Field(
        default=False,
        description="True if paper survived quota filtering into the deep enrichment pool.",
    )

    model_config = {
        "arbitrary_types_allowed": True,
    }
