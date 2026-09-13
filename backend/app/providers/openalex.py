from typing import Optional, List, Dict, Any
import httpx
from app.core.config import settings
from app.models.canonical_paper import Author
from app.providers.base import BaseHttpProvider
from app.providers.models import RawPaper, Page
from app.resolution.normalizers import classify_identifier


def clean_doi(identifier: str) -> str:
    cleaned = identifier.strip().lower()
    for prefix in ["https://doi.org/", "http://doi.org/", "doi:"]:
        if cleaned.startswith(prefix):
            cleaned = cleaned[len(prefix):]
    return cleaned.strip()


class OpenAlexProvider(BaseHttpProvider):
    """
    Adapter for OpenAlex API.
    Primary scope: Broad academic coverage, concepts/topics, and fallback relationship graphs.
    """
    def __init__(
        self,
        mailto: Optional[str] = None,
        rps: Optional[float] = None,
        client: Optional[httpx.AsyncClient] = None,
    ):
        contact = mailto or settings.OPENALEX_MAILTO
        rate = rps if rps is not None else settings.OPENALEX_RPS
        super().__init__(
            name="openalex",
            base_url="https://api.openalex.org",
            rps=rate,
            timeout_seconds=settings.PROVIDER_TIMEOUT_SECONDS,
            max_retries=settings.PROVIDER_MAX_RETRIES,
            client=client,
        )
        self.contact_email = contact
        self.headers = {
            "User-Agent": f"PaperGraph/1.0 (mailto:{contact})",
            "Accept": "application/json",
        }

    def _parse_work(self, item: Dict[str, Any]) -> RawPaper:
        openalex_id = item.get("id", "")
        clean_id = openalex_id.split("/")[-1] if "/" in openalex_id else openalex_id

        # DOI
        doi_raw = item.get("doi")
        doi = clean_doi(doi_raw) if doi_raw else None

        # PMID
        ids = item.get("ids", {})
        pmid_url = ids.get("pmid")
        pmid = pmid_url.split("/")[-1] if pmid_url else None

        # Authors
        authors: List[Author] = []
        for i, a in enumerate(item.get("authorships", [])):
            author_obj = a.get("author", {})
            institutions = a.get("institutions", [])
            inst_name = institutions[0].get("display_name") if institutions else None
            authors.append(
                Author(
                    id=author_obj.get("id"),
                    name=author_obj.get("display_name", "Unknown Author"),
                    position=i + 1,
                    affiliation=inst_name,
                )
            )

        # Venue / Primary Location
        location = item.get("primary_location", {}) or {}
        source = location.get("source", {}) or {}
        venue = source.get("display_name")

        # Topics / Concepts
        topics = [
            c.get("display_name")
            for c in item.get("concepts", [])
            if c.get("display_name") and c.get("score", 0) > 0.3
        ]

        # References list (IDs)
        referenced_works = item.get("referenced_works", []) or []
        ref_ids = [
            f"openalex:{w.split('/')[-1]}" for w in referenced_works if isinstance(w, str)
        ]

        # Abstract (OpenAlex stores inverted index; reconstruct if available)
        abstract = None
        inverted_index = item.get("abstract_inverted_index")
        if inverted_index and isinstance(inverted_index, dict):
            words = []
            for word, positions in inverted_index.items():
                for pos in positions:
                    words.append((pos, word))
            words.sort(key=lambda x: x[0])
            abstract = " ".join([w[1] for w in words])

        return RawPaper(
            provider="openalex",
            provider_id=clean_id,
            doi=doi,
            pmid=pmid,
            open_alex_id=openalex_id,
            title=item.get("title") or "Untitled OpenAlex Work",
            authors=authors,
            year=item.get("publication_year"),
            venue=venue,
            abstract=abstract,
            citation_count=int(item.get("cited_by_count", 0) or 0),
            reference_count=len(referenced_works),
            reference_ids=ref_ids,
            citation_ids=[],
            topics=topics,
            raw_data=item,
        )

    async def resolve(self, identifier: str) -> Optional[RawPaper]:
        ident = identifier.strip()
        params = {"mailto": self.contact_email}

        kind, value = classify_identifier(ident)

        if kind == "doi":
            endpoint = f"/works/{{https://doi.org/{value}}}"
        elif kind == "openalex":
            endpoint = f"/works/{value}"
        elif kind == "pmid":
            endpoint = f"/works/pmid:{value}"
        elif kind == "pmcid":
            endpoint = f"/works/pmcid:{value}"
        else:
            # Titles, S2 IDs, arXiv IDs, and unrecognized links:
            # best-effort keyword search as fallback.
            res = await self.search(ident, limit=1)
            return res[0] if res else None

        data = await self.request_json(
            method="GET",
            endpoint=endpoint,
            params=params,
            headers=self.headers,
        )
        if not data:
            return None
        return self._parse_work(data)

    async def search(self, query: str, limit: int = 10) -> List[RawPaper]:
        params = {
            "search": query,
            "per-page": min(limit, 50),
            "mailto": self.contact_email,
        }
        data = await self.request_json(
            method="GET",
            endpoint="/works",
            params=params,
            headers=self.headers,
        )
        # OpenAlex may return {"results": null} — reject null payload, not just a missing key.
        if not data or not data.get("results"):
            return []
        return [self._parse_work(w) for w in data["results"] if w]

    async def get_details(self, provider_id: str) -> Optional[RawPaper]:
        return await self.resolve(provider_id)

    async def get_references(
        self, provider_id: str, cursor: Optional[str] = None, limit: int = 50
    ) -> Page[RawPaper]:
        clean_id = provider_id.split("/")[-1]
        work = await self.get_details(clean_id)
        if not work:
            return Page(items=[], total=0, has_more=False)

        ref_papers = [
            RawPaper(
                provider="openalex",
                provider_id=ref_id.replace("openalex:", ""),
                open_alex_id=f"https://openalex.org/{ref_id.replace('openalex:', '')}",
                title=f"Referenced Work {ref_id}",
            )
            for ref_id in work.reference_ids
        ]
        return Page(items=ref_papers[:limit], total=len(ref_papers), has_more=False)

    async def get_citations(
        self, provider_id: str, cursor: Optional[str] = None, limit: int = 50
    ) -> Page[RawPaper]:
        clean_id = provider_id.split("/")[-1]
        target_id = f"https://openalex.org/{clean_id}" if not clean_id.startswith("http") else clean_id
        
        current_cursor = cursor or "*"
        params = {
            "filter": f"cites:{target_id}",
            "per-page": min(limit, 50),
            "cursor": current_cursor,
            "mailto": self.contact_email,
        }
        data = await self.request_json(
            method="GET",
            endpoint="/works",
            params=params,
            headers=self.headers,
        )
        # Same null-payload guard as search().
        if not data or not data.get("results"):
            return Page(items=[], total=0, has_more=False)

        items = [self._parse_work(w) for w in data["results"] if w]
        meta = data.get("meta", {})
        total = meta.get("count", len(items))
        next_cursor = meta.get("next_cursor")
        has_more = bool(next_cursor and len(items) > 0)

        return Page(
            items=items,
            total=total,
            next_cursor=next_cursor,
            has_more=has_more,
        )
