from typing import Optional, List, Dict, Any
import httpx
from app.core.config import settings
from app.models.canonical_paper import Author
from app.providers.base import BaseHttpProvider
from app.providers.models import RawPaper, Page

PAPER_FIELDS = "title,abstract,authors,year,venue,citationCount,referenceCount,externalIds,s2FieldsOfStudy"


class SemanticScholarProvider(BaseHttpProvider):
    """
    Adapter for Semantic Scholar Academic Graph API.
    Primary scope: Search, paper details, recommendations, paginated references, and citations.
    """
    def __init__(
        self,
        api_key: Optional[str] = None,
        rps: Optional[float] = None,
        client: Optional[httpx.AsyncClient] = None,
    ):
        key = api_key or settings.SEMANTIC_SCHOLAR_API_KEY
        rate = rps if rps is not None else settings.SEMANTIC_SCHOLAR_RPS
        super().__init__(
            name="semantic_scholar",
            base_url="https://api.semanticscholar.org/graph/v1",
            rps=rate,
            timeout_seconds=settings.PROVIDER_TIMEOUT_SECONDS,
            max_retries=settings.PROVIDER_MAX_RETRIES,
            client=client,
        )
        self.headers = {"Accept": "application/json"}
        if key:
            self.headers["x-api-key"] = key

    def _parse_paper(self, item: Dict[str, Any]) -> RawPaper:
        paper_id = item.get("paperId", "")
        external_ids = item.get("externalIds", {}) or {}
        doi = external_ids.get("DOI")
        if doi:
            doi = doi.lower().strip()
        pmid = external_ids.get("PubMed")

        # Authors
        authors: List[Author] = []
        for i, a in enumerate(item.get("authors", []) or []):
            authors.append(
                Author(
                    id=a.get("authorId"),
                    name=a.get("name", "Unknown Author"),
                    position=i + 1,
                )
            )

        # Fields of study
        topics = [f.get("category") for f in item.get("s2FieldsOfStudy", []) if f.get("category")]

        return RawPaper(
            provider="semantic_scholar",
            provider_id=paper_id,
            doi=doi,
            pmid=pmid,
            semantic_scholar_id=paper_id,
            title=item.get("title") or "Untitled S2 Work",
            authors=authors,
            year=item.get("year"),
            venue=item.get("venue"),
            abstract=item.get("abstract"),
            citation_count=int(item.get("citationCount", 0) or 0),
            reference_count=int(item.get("referenceCount", 0) or 0),
            topics=topics,
            raw_data=item,
        )

    def _format_identifier(self, identifier: str) -> str:
        ident = identifier.strip()
        if ident.lower().startswith("10.") or "doi.org" in ident.lower():
            clean = ident
            for prefix in ["https://doi.org/", "http://doi.org/", "doi:"]:
                if clean.lower().startswith(prefix):
                    clean = clean[len(prefix):]
            return f"DOI:{clean.strip()}"
        if ident.lower().startswith("pmid:"):
            return f"PMID:{ident[5:].strip()}"
        return ident

    async def resolve(self, identifier: str) -> Optional[RawPaper]:
        formatted = self._format_identifier(identifier)
        data = await self.request_json(
            method="GET",
            endpoint=f"/paper/{formatted}",
            params={"fields": PAPER_FIELDS},
            headers=self.headers,
        )
        if not data:
            return None
        return self._parse_paper(data)

    async def search(self, query: str, limit: int = 10) -> List[RawPaper]:
        data = await self.request_json(
            method="GET",
            endpoint="/paper/search",
            params={
                "query": query,
                "limit": min(limit, 50),
                "fields": PAPER_FIELDS,
            },
            headers=self.headers,
        )
        if not data or "data" not in data:
            return []
        return [self._parse_paper(p) for p in data["data"]]

    async def get_details(self, provider_id: str) -> Optional[RawPaper]:
        return await self.resolve(provider_id)

    async def get_references(
        self, provider_id: str, cursor: Optional[str] = None, limit: int = 50
    ) -> Page[RawPaper]:
        offset = int(cursor) if cursor and cursor.isdigit() else 0
        formatted = self._format_identifier(provider_id)
        data = await self.request_json(
            method="GET",
            endpoint=f"/paper/{formatted}/references",
            params={
                "fields": "citedPaper.title,citedPaper.authors,citedPaper.year,citedPaper.externalIds,citedPaper.citationCount",
                "offset": offset,
                "limit": min(limit, 100),
            },
            headers=self.headers,
        )
        if not data or "data" not in data:
            return Page(items=[], total=0, has_more=False)

        items: List[RawPaper] = []
        for ref_entry in data["data"]:
            cited = ref_entry.get("citedPaper")
            if cited and cited.get("paperId"):
                items.append(self._parse_paper(cited))

        total = data.get("total", len(items) + offset)
        has_more = (offset + len(items)) < total
        next_cursor = str(offset + len(items)) if has_more else None

        return Page(
            items=items,
            total=total,
            next_cursor=next_cursor,
            has_more=has_more,
        )

    async def get_citations(
        self, provider_id: str, cursor: Optional[str] = None, limit: int = 50
    ) -> Page[RawPaper]:
        offset = int(cursor) if cursor and cursor.isdigit() else 0
        formatted = self._format_identifier(provider_id)
        data = await self.request_json(
            method="GET",
            endpoint=f"/paper/{formatted}/citations",
            params={
                "fields": "citingPaper.title,citingPaper.authors,citingPaper.year,citingPaper.externalIds,citingPaper.citationCount",
                "offset": offset,
                "limit": min(limit, 100),
            },
            headers=self.headers,
        )
        if not data or "data" not in data:
            return Page(items=[], total=0, has_more=False)

        items: List[RawPaper] = []
        for cite_entry in data["data"]:
            citing = cite_entry.get("citingPaper")
            if citing and citing.get("paperId"):
                items.append(self._parse_paper(citing))

        total = data.get("total", len(items) + offset)
        has_more = (offset + len(items)) < total
        next_cursor = str(offset + len(items)) if has_more else None

        return Page(
            items=items,
            total=total,
            next_cursor=next_cursor,
            has_more=has_more,
        )

    async def get_recommendations(
        self, provider_id: str, limit: int = 20
    ) -> List[RawPaper]:
        formatted = self._format_identifier(provider_id)
        url = f"https://api.semanticscholar.org/recommendations/v1/papers/forpaper/{formatted}"
        data = await self.request_json(
            method="GET",
            endpoint=url,
            params={
                "limit": min(limit, 50),
                "fields": PAPER_FIELDS,
            },
            headers=self.headers,
        )
        if not data or "recommendedPapers" not in data:
            return []
        return [self._parse_paper(p) for p in data["recommendedPapers"]]

    async def get_batch_details(
        self, provider_ids: List[str]
    ) -> List[Optional[RawPaper]]:
        """
        Batch resolves metadata for a list of papers using Semantic Scholar's /paper/batch API.
        Chunks IDs into groups of 100 to stay within provider limits.
        """
        if not provider_ids:
            return []

        formatted_ids = [self._format_identifier(pid) for pid in provider_ids]
        results: List[Optional[RawPaper]] = []
        chunk_size = 100

        for i in range(0, len(formatted_ids), chunk_size):
            chunk = formatted_ids[i:i + chunk_size]
            data = await self.request_json(
                method="POST",
                endpoint="/paper/batch",
                params={"fields": PAPER_FIELDS},
                json_data={"ids": chunk},
                headers=self.headers,
            )
            if not data or not isinstance(data, list):
                results.extend([None] * len(chunk))
                continue

            for item in data:
                if item and isinstance(item, dict) and item.get("paperId"):
                    results.append(self._parse_paper(item))
                else:
                    results.append(None)

        return results
