from typing import List, Optional, Dict, Any
from pydantic import BaseModel, Field, field_validator


class Author(BaseModel):
    id: Optional[str] = None
    name: str
    position: Optional[int] = None
    affiliation: Optional[str] = None


class SourceAvailability(BaseModel):
    semantic_scholar: bool = False
    open_alex: bool = False
    crossref: bool = False
    pubmed: bool = False


class CanonicalPaper(BaseModel):
    """
    Unified canonical representation of an academic work across all upstream providers.
    Every external paper is normalized into this structure before candidate selection or ranking.
    """
    canonical_id: str = Field(
        ...,
        description="Globally unique canonical identifier prefixed by scheme (e.g. 'doi:10.1038/...', 'pmid:...').",
    )
    doi: Optional[str] = Field(default=None, description="Bare normalized DOI without URL prefix.")
    pmid: Optional[str] = Field(default=None, description="Bare PubMed ID.")
    semantic_scholar_id: Optional[str] = Field(default=None, description="Semantic Scholar Corpus/Paper ID.")
    open_alex_id: Optional[str] = Field(default=None, description="OpenAlex Work ID or canonical URL.")
    
    title: str = Field(..., min_length=1, description="Primary title of the publication.")
    normalized_title: Optional[str] = Field(default=None, description="Lowercased, punctuation-stripped title used for deduplication.")

    def model_post_init(self, __context: Any) -> None:
        if not self.normalized_title and self.title:
            import re
            cleaned = re.sub(r"<[^>]+>", "", self.title)
            cleaned = re.sub(r"[^\w\s]", " ", cleaned.lower())
            self.normalized_title = " ".join(cleaned.split())
    
    authors: List[Author] = Field(default_factory=list, description="Ordered list of paper authors.")
    year: Optional[int] = Field(default=None, ge=1800, le=2100, description="Publication year.")
    venue: Optional[str] = Field(default=None, description="Journal, conference, or repository venue.")
    abstract: Optional[str] = Field(default=None, description="Abstract text.")
    
    citation_count: int = Field(default=0, ge=0, description="Aggregated inbound citation count.")
    reference_count: Optional[int] = Field(default=0, ge=0, description="Outbound reference count.")
    
    reference_ids: List[str] = Field(
        default_factory=list,
        description="List of canonical paper IDs cited by this work.",
    )
    citation_ids: List[str] = Field(
        default_factory=list,
        description="List of canonical paper IDs citing this work.",
    )
    topics: List[str] = Field(default_factory=list, description="Academic fields, concepts, or MeSH terms.")
    
    source_availability: SourceAvailability = Field(
        default_factory=SourceAvailability,
        description="Flags indicating which upstream providers confirmed or enriched this record.",
    )
    provenance: Dict[str, Any] = Field(
        default_factory=dict,
        description="Field-level source attribution and ingestion timestamps.",
    )
    completeness: float = Field(
        default=0.0,
        ge=0.0,
        le=1.0,
        description="Completeness metric (0.0 to 1.0) indicating metadata richness.",
    )

    @field_validator("doi", mode="before")
    @classmethod
    def clean_doi(cls, v: Optional[str]) -> Optional[str]:
        if not v:
            return None
        doi_clean = v.strip().lower()
        for prefix in ["https://doi.org/", "http://doi.org/", "doi:"]:
            if doi_clean.startswith(prefix):
                doi_clean = doi_clean[len(prefix):]
        return doi_clean.strip()

    model_config = {
        "populate_by_name": True,
        "json_schema_extra": {
            "example": {
                "canonical_id": "doi:10.1038/nature12373",
                "doi": "10.1038/nature12373",
                "title": "A Distributed Consensus Protocol",
                "normalized_title": "a distributed consensus protocol",
                "authors": [{"name": "Leslie Lamport", "position": 1}],
                "year": 2020,
                "venue": "Nature",
                "citation_count": 142,
                "reference_ids": ["doi:10.1145/1", "doi:10.1145/2"],
                "topics": ["Distributed Systems", "Computer Science"],
                "completeness": 0.95,
            }
        },
    }
