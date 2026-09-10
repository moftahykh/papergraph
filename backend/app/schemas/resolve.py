from typing import List, Optional
from pydantic import BaseModel, Field
from app.models.canonical_paper import CanonicalPaper


class PaperResolveRequest(BaseModel):
    identifier: str = Field(
        ...,
        min_length=2,
        max_length=500,
        description="Identifier to resolve: DOI URL, bare DOI, PMID, OpenAlex ID, or paper title.",
    )


class PaperResolveResponse(BaseModel):
    resolved: bool = Field(..., description="True if an exact canonical record was resolved.")
    paper: Optional[CanonicalPaper] = Field(
        default=None,
        description="Resolved canonical paper record.",
    )
    ambiguous_candidates: List[CanonicalPaper] = Field(
        default_factory=list,
        description="Disambiguation candidates if confidence < 0.85 or title matched multiple works.",
    )
    confidence: float = Field(
        default=1.0,
        ge=0.0,
        le=1.0,
        description="Resolution confidence score.",
    )
    message: Optional[str] = Field(
        default=None,
        description="Informative message regarding resolution status.",
    )
