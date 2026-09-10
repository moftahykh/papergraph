import re
from typing import TypeVar, Generic, List, Optional, Dict, Any
from pydantic import BaseModel, Field
from app.models.canonical_paper import CanonicalPaper, Author, SourceAvailability

T = TypeVar("T")


class Page(BaseModel, Generic[T]):
    """Generic paginated container for references, citations, and search results."""
    items: List[T] = Field(default_factory=list)
    total: Optional[int] = Field(default=None)
    next_cursor: Optional[str] = Field(default=None)
    has_more: bool = Field(default=False)


def normalize_title(title: str) -> str:
    """Normalize paper title for deterministic deduplication."""
    if not title:
        return ""
    # Lowercase, strip punctuation and extra whitespace
    cleaned = re.sub(r"[^\w\s]", "", title.lower())
    return " ".join(cleaned.split())


class RawPaper(BaseModel):
    """
    Standardized intermediate paper model directly emitted by an academic provider adapter.
    Preserves raw data and provider provenance before canonical deduplication.
    """
    provider: str = Field(..., description="Provider name: crossref, semantic_scholar, openalex, pubmed")
    provider_id: str = Field(..., description="Provider-specific ID (DOI, CorpusID, W-ID, PMID)")
    doi: Optional[str] = Field(default=None)
    pmid: Optional[str] = Field(default=None)
    semantic_scholar_id: Optional[str] = Field(default=None)
    open_alex_id: Optional[str] = Field(default=None)
    
    title: str = Field(..., min_length=1)
    normalized_title: Optional[str] = Field(default=None)
    authors: List[Author] = Field(default_factory=list)
    year: Optional[int] = Field(default=None)
    venue: Optional[str] = Field(default=None)
    abstract: Optional[str] = Field(default=None)
    citation_count: int = Field(default=0, ge=0)
    reference_count: int = Field(default=0, ge=0)
    
    reference_ids: List[str] = Field(default_factory=list)
    citation_ids: List[str] = Field(default_factory=list)
    topics: List[str] = Field(default_factory=list)
    raw_data: Dict[str, Any] = Field(default_factory=dict)

    def model_post_init(self, __context: Any) -> None:
        if not self.normalized_title:
            self.normalized_title = normalize_title(self.title)

    def to_canonical(self) -> CanonicalPaper:
        """
        Converts RawPaper into CanonicalPaper, determining canonical ID and recording provenance.
        """
        # Canonical ID priority: DOI -> PMID -> OpenAlex -> SemanticScholar -> ProviderID
        if self.doi:
            canonical_id = f"doi:{self.doi.lower().strip()}"
        elif self.pmid:
            canonical_id = f"pmid:{self.pmid.strip()}"
        elif self.open_alex_id:
            clean_openalex = self.open_alex_id.split("/")[-1]
            canonical_id = f"openalex:{clean_openalex}"
        elif self.semantic_scholar_id:
            canonical_id = f"s2:{self.semantic_scholar_id}"
        else:
            canonical_id = f"{self.provider}:{self.provider_id}"

        source_avail = SourceAvailability(
            semantic_scholar=(self.provider == "semantic_scholar"),
            open_alex=(self.provider == "openalex"),
            crossref=(self.provider == "crossref"),
            pubmed=(self.provider == "pubmed"),
        )

        # Calculate basic metadata completeness (0.0 to 1.0)
        fields_present = sum([
            bool(self.title),
            bool(self.authors),
            bool(self.year),
            bool(self.venue),
            bool(self.abstract),
            bool(self.doi),
            bool(self.topics),
        ])
        completeness = round(fields_present / 7.0, 2)

        return CanonicalPaper(
            canonical_id=canonical_id,
            doi=self.doi,
            pmid=self.pmid,
            semantic_scholar_id=self.semantic_scholar_id,
            open_alex_id=self.open_alex_id,
            title=self.title,
            normalized_title=self.normalized_title or normalize_title(self.title),
            authors=self.authors,
            year=self.year,
            venue=self.venue,
            abstract=self.abstract,
            citation_count=self.citation_count,
            reference_count=self.reference_count,
            reference_ids=self.reference_ids,
            citation_ids=self.citation_ids,
            topics=self.topics,
            source_availability=source_avail,
            provenance={
                "primary_provider": self.provider,
                "provider_id": self.provider_id,
            },
            completeness=completeness,
        )
