from enum import Enum


class GraphJobStatus(str, Enum):
    """Exact lifecycle statuses for PaperGraph asynchronous jobs."""
    QUEUED = "queued"
    RESOLVING_ORIGIN = "resolving_origin"
    GENERATING_CANDIDATES = "generating_candidates"
    PRE_RANKING = "pre_ranking"
    ENRICHING_METADATA = "enriching_metadata"
    ENRICHING_REFERENCES = "enriching_references"
    COMPUTING_WBC = "computing_wbc"
    ENRICHING_CITATIONS = "enriching_citations"
    COMPUTING_NCC = "computing_ncc"
    COMPUTING_FINAL_SCORES = "computing_final_scores"
    EXTRACTING_PRIOR_WORKS = "extracting_prior_works"
    EXTRACTING_DERIVATIVE_WORKS = "extracting_derivative_works"
    BUILDING_LAYOUT = "building_layout"
    COMPLETED = "completed"
    PARTIAL = "partial"
    FAILED = "failed"


class MetricAvailability(str, Enum):
    """Explicit evaluation status for nullable ranking signals."""
    AVAILABLE = "available"
    UNAVAILABLE = "unavailable"
    PROVIDER_ERROR = "provider_error"
    NOT_APPLICABLE = "not_applicable"


class EdgeType(str, Enum):
    """Strict differentiation between directed citation and undirected similarity."""
    CITATION = "citation"
    SIMILARITY = "similarity"


class ConfidenceLevel(str, Enum):
    """Confidence classification based on available signal count."""
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"
    INSUFFICIENT = "insufficient"
