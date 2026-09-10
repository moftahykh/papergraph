from typing import List, Optional
from pydantic import BaseModel, Field
from app.models.canonical_paper import CanonicalPaper


class PaperDetailsResponse(BaseModel):
    """
    On-demand deep metadata response for GET /api/v1/papers/{id}/details.
    Fetched lazily when a researcher taps a node in Flutter canvas.
    """
    paper: CanonicalPaper = Field(..., description="Canonical paper record.")
    tldr: Optional[str] = Field(default=None, description="One-sentence AI/Semantic Scholar generated summary.")
    open_access_url: Optional[str] = Field(default=None, description="Direct PDF link if open access.")
    bibtex: Optional[str] = Field(default=None, description="Formatted BibTeX citation entry.")
    affiliations: List[str] = Field(default_factory=list, description="Author institutional affiliations.")
    is_saved: bool = Field(default=False, description="Whether paper is bookmarked by researcher.")
