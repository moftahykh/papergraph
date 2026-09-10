from typing import List, Optional
from pydantic import BaseModel, Field


class SearchRequest(BaseModel):
    query: str = Field(..., min_length=2, max_length=500, description="Search query string or keywords.")
    limit: int = Field(default=10, ge=1, le=50, description="Maximum results per page.")
    offset: int = Field(default=0, ge=0, description="Offset for pagination.")
    provider: Optional[str] = Field(default=None, description="Optional provider filter (e.g. 'semantic_scholar', 'openalex').")


class SearchResultItem(BaseModel):
    canonical_id: str = Field(..., description="Canonical identifier (e.g. 'doi:...').")
    title: str = Field(..., description="Paper title.")
    authors: List[str] = Field(default_factory=list, description="Author names.")
    year: Optional[int] = Field(default=None, description="Publication year.")
    venue: Optional[str] = Field(default=None, description="Venue or journal.")
    citation_count: int = Field(default=0, ge=0, description="Citation count.")
    doi: Optional[str] = Field(default=None, description="Normalized DOI if available.")
    score: Optional[float] = Field(default=None, description="Search relevance score.")


class SearchResponse(BaseModel):
    query: str
    total: int = Field(default=0, ge=0)
    items: List[SearchResultItem] = Field(default_factory=list)
    disambiguation_needed: bool = Field(
        default=False,
        description="True if query was ambiguous (e.g. generic title) requiring researcher disambiguation.",
    )
    candidates: List[SearchResultItem] = Field(
        default_factory=list,
        description="Candidate matches if disambiguation is needed.",
    )
