import re
from typing import Optional, List, Dict, Any
import httpx
from app.core.config import settings
from app.models.canonical_paper import Author
from app.providers.base import BaseHttpProvider
from app.providers.models import RawPaper, Page


def clean_doi(identifier: str) -> str:
    """Strips URL wrappers and protocol prefixes to isolate bare DOI."""
    cleaned = identifier.strip().lower()
    for prefix in ["https://doi.org/", "http://doi.org/", "dx.doi.org/", "doi:"]:
        if cleaned.startswith(prefix):
            cleaned = cleaned[len(prefix):]
    return cleaned.strip()


class CrossRefProvider(BaseHttpProvider):
    """
    Adapter for Crossref API.
    Primary scope: Canonical DOI resolution, publisher-verified bibliographic metadata.
    """
    def __init__(
        self,
        mailto: Optional[str] = None,
        rps: Optional[float] = None,
        client: Optional[httpx.AsyncClient] = None,
    ):
        contact = mailto or settings.CROSSREF_MAILTO
        rate = rps if rps is not None else settings.CROSSREF_RPS
        super().__init__(
            name="crossref",
            base_url="https://api.crossref.org",
            rps=rate,
            timeout_seconds=settings.PROVIDER_TIMEOUT_SECONDS,
            max_retries=settings.PROVIDER_MAX_RETRIES,
            client=client,
        )
        self.headers = {
            "User-Agent": f"PaperGraph/1.0 (mailto:{contact})",
            "Accept": "application/json",
        }

    def _parse_work(self, item: Dict[str, Any]) -> RawPaper:
        doi = item.get("DOI", "").lower().strip()
        
        # Parse titles
        titles = item.get("title", [])
        title = titles[0] if titles else "Untitled Crossref Work"

        # Parse authors
        authors: List[Author] = []
        for i, a in enumerate(item.get("author", [])):
            name = f"{a.get('given', '')} {a.get('family', '')}".strip()
            if not name:
                name = a.get("name", "Unknown Author")
            affils = a.get("affiliation", [])
            affil_name = affils[0].get("name") if affils and isinstance(affils[0], dict) else None
            authors.append(Author(name=name, position=i + 1, affiliation=affil_name))

        # Parse publication year
        year = None
        for date_field in ["published-print", "published-online", "created"]:
            parts = item.get(date_field, {}).get("date-parts", [[]])
            if parts and parts[0]:
                year = parts[0][0]
                break

        # Venue
        containers = item.get("container-title", [])
        venue = containers[0] if containers else None

        # Citations & References
        citation_count = int(item.get("is-referenced-by-count", 0) or 0)
        reference_count = int(item.get("references-count", 0) or 0)

        # Parse cited DOIs from reference list
        reference_ids: List[str] = []
        for ref in item.get("reference", []):
            ref_doi = ref.get("DOI")
            if ref_doi:
                reference_ids.append(f"doi:{ref_doi.lower().strip()}")

        # Clean abstract (Crossref occasionally embeds JATS XML tags in abstract)
        abstract = item.get("abstract")
        if abstract:
            abstract = re.sub(r"<[^>]+>", "", abstract).strip()

        return RawPaper(
            provider="crossref",
            provider_id=doi,
            doi=doi,
            title=title,
            authors=authors,
            year=year,
            venue=venue,
            abstract=abstract,
            citation_count=citation_count,
            reference_count=reference_count,
            reference_ids=reference_ids,
            citation_ids=[],
            topics=item.get("subject", []),
            raw_data=item,
        )

    async def resolve(self, identifier: str) -> Optional[RawPaper]:
        doi = clean_doi(identifier)
        if not ("/" in doi and not doi.startswith("http")):
            # If identifier is not a valid DOI structure (e.g. general title), search instead
            return None

        data = await self.request_json(
            method="GET",
            endpoint=f"/works/{doi}",
            headers=self.headers,
        )
        # CrossRef may return {"message": null} — guard the null payload too.
        if not data or not data.get("message"):
            return None
        return self._parse_work(data["message"])

    async def search(self, query: str, limit: int = 10) -> List[RawPaper]:
        params = {
            "query.bibliographic": query,
            "rows": min(limit, 50),
        }
        data = await self.request_json(
            method="GET",
            endpoint="/works",
            params=params,
            headers=self.headers,
        )
        # Guard both a null "message" and null "items" (and non-dict entries).
        if not data or not data.get("message") or not data["message"].get("items"):
            return []

        results: List[RawPaper] = []
        for item in data["message"]["items"]:
            if isinstance(item, dict) and item.get("DOI"):
                results.append(self._parse_work(item))
        return results

    async def get_details(self, provider_id: str) -> Optional[RawPaper]:
        return await self.resolve(provider_id)

    async def get_references(
        self, provider_id: str, cursor: Optional[str] = None, limit: int = 50
    ) -> Page[RawPaper]:
        paper = await self.get_details(provider_id)
        if not paper:
            return Page(items=[], total=0, has_more=False)
        
        # Transform reference_ids into minimal RawPaper stubs
        ref_papers = [
            RawPaper(
                provider="crossref",
                provider_id=ref_id.replace("doi:", ""),
                doi=ref_id.replace("doi:", ""),
                title=f"Cited Reference {ref_id}",
            )
            for ref_id in paper.reference_ids
        ]
        return Page(items=ref_papers[:limit], total=len(ref_papers), has_more=False)

    async def get_citations(
        self, provider_id: str, cursor: Optional[str] = None, limit: int = 50
    ) -> Page[RawPaper]:
        # Crossref only reports count; full inbound citing list is deferred to Semantic Scholar / OpenAlex
        paper = await self.get_details(provider_id)
        total = paper.citation_count if paper else 0
        return Page(items=[], total=total, has_more=False)
