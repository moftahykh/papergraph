from typing import Dict, List, Optional, Any
from pydantic import BaseModel, Field
from app.models.canonical_paper import CanonicalPaper
from app.models.enums import MetricAvailability, ConfidenceLevel
from app.candidates.models import CandidateRecord
from app.enrichment.models import CandidateEnrichmentRecord


class BaselineWeights(BaseModel):
    """
    Baseline ranking signal weights defined in PLAN.md Phase 6:
      semantic: 0.35
      wbc:      0.30
      ncc:      0.20
      direct:   0.15
    """
    semantic: float = 0.35
    wbc: float = 0.30
    ncc: float = 0.20
    direct: float = 0.15

    def get_weight(self, signal_name: str) -> float:
        return getattr(self, signal_name, 0.0)

    def as_dict(self) -> Dict[str, float]:
        return {
            "semantic": self.semantic,
            "wbc": self.wbc,
            "ncc": self.ncc,
            "direct": self.direct,
        }


class SignalContribution(BaseModel):
    """
    Detailed explainability breakdown for an individual ranking signal.
    """
    name: str
    raw_value: Optional[float] = None
    availability: MetricAvailability = MetricAvailability.UNAVAILABLE
    original_weight: float
    normalized_weight: Optional[float] = None
    weighted_score: Optional[float] = None
    reason: Optional[str] = None


class ScoreBreakdown(BaseModel):
    """
    Explainability summary documenting how all signals were combined.
    """
    signals: Dict[str, SignalContribution] = Field(default_factory=dict)
    available_weight_sum: float = 0.0
    final_score: Optional[float] = None
    confidence: ConfidenceLevel = ConfidenceLevel.INSUFFICIENT
    available_signals_count: int = 0


class RankedCandidate(BaseModel):
    """
    A candidate paper evaluated, scored, categorized, and ranked.
    """
    paper: CanonicalPaper
    candidate_record: Optional[CandidateRecord] = None
    enrichment_record: Optional[CandidateEnrichmentRecord] = None

    final_score: Optional[float] = Field(
        default=None,
        ge=0.0,
        le=1.0,
        description="Composite score normalized over available signals in [0.0, 1.0].",
    )
    confidence: ConfidenceLevel = ConfidenceLevel.INSUFFICIENT
    score_breakdown: ScoreBreakdown

    prior_score: float = Field(
        default=0.0,
        ge=0.0,
        le=1.0,
        description="Foundational influence score in [0.0, 1.0].",
    )
    derivative_score: float = Field(
        default=0.0,
        ge=0.0,
        le=1.0,
        description="Downstream evolution score in [0.0, 1.0].",
    )
    archetype: str = Field(
        default="similar",
        description="Archetype: 'origin', 'prior_work', 'derivative_work', or 'similar'.",
    )
    rank: int = Field(default=0, ge=0)

    model_config = {
        "arbitrary_types_allowed": True,
    }


class RankingResult(BaseModel):
    """
    Aggregated output from SafeRankingEngine.
    """
    origin: CanonicalPaper
    ranked_candidates: List[RankedCandidate] = Field(default_factory=list)
    prior_works: List[RankedCandidate] = Field(default_factory=list)
    derivative_works: List[RankedCandidate] = Field(default_factory=list)
    confidence_distribution: Dict[str, int] = Field(default_factory=dict)
    algorithm_version: str = "v1.0"

    model_config = {
        "arbitrary_types_allowed": True,
    }
