from typing import Optional, List, Dict, Any
import httpx
from app.core.config import settings
from app.models.canonical_paper import Author
from app.providers.base import BaseHttpProvider
from app.providers.models import RawPaper, Page


class PubMedProvider(BaseHttpProvider):
    """
    Adapter for NCBI PubMed E-Utilities.
    Two-stage pipeline: ESearch (retrieve PMIDs) -> ESummary (retrieve detailed records).
    Primary scope: Dedicated biomedical literature and PMID resolution.
    """
    def __init__(
        self,
        api_key: Optional[str] = None,
        rps: Optional[float] = None,
        client: Optional[httpx.AsyncClient] = None,
    ):
        key = api_key or settings.NCBI_API_KEY
        rate = rps if rps is not None else settings.PUBMED_RPS
        super().__init__(
            name="pubmed",
            base_url="https://eutils.ncbi.nlm.nih.gov/entrez/eutils",
            rps=rate,
            timeout_seconds=settings.PROVIDER_TIMEOUT_SECONDS,
            max_retries=settings.PROVIDER_MAX_RETRIES,
            client=client,
        )
        self.api_key = key

    def _apply_auth(self, params: Dict[str, Any]) -> Dict[str, Any]:
        params["retmode"] = "json"
        if self.api_key:
            params["api_key"] = self.api_key
        return params

    def _parse_summary_item(self, pmid: str, item: Dict[str, Any]) -> RawPaper:
        title = item.get("title", "").strip().rstrip(".")
        if not title:
            title = "Untitled PubMed Record"

        # Authors
        authors: List[Author] = []
        for i, a in enumerate(item.get("authors", [])):
            authors.append(
                Author(
                    name=a.get("name", "Unknown Author"),
                    position=i + 1,
                )
            )

        # Publication year
        pubdate = item.get("pubdate", "")
        year = None
        for part in pubdate.split():
            if part.isdigit() and len(part) == 4:
                year = int(part)
                break

        # DOI extraction from articleids
        doi = None
        for aid in item.get("articleids", []):
            if aid.get("idtype") == "doi":
                doi = aid.get("value", "").lower().strip()
                break

        venue = item.get("source") or item.get("fulljournalname")

        return RawPaper(
            provider="pubmed",
            provider_id=pmid,
            pmid=pmid,
            doi=doi,
            title=title,
            authors=authors,
            year=year,
            venue=venue,
            abstract=None,  # ESummary does not include full abstract; efetch is used for on-demand details
            citation_count=0,
            reference_count=0,
            reference_ids=[],
            citation_ids=[],
            topics=["Biomedicine", "Life Sciences"],
            raw_data=item,
        )

    async def _fetch_summaries(self, pmid_list: List[str]) -> List[RawPaper]:
        if not pmid_list:
            return []
        params = self._apply_auth({
            "db": "pubmed",
            "id": ",".join(pmid_list),
        })
        data = await self.request_json(
            method="GET",
            endpoint="/esummary.fcgi",
            params=params,
        )
        if not data or "result" not in data:
            return []

        result_dict = data["result"]
        papers: List[RawPaper] = []
        for pmid in pmid_list:
            if pmid in result_dict:
                papers.append(self._parse_summary_item(pmid, result_dict[pmid]))
        return papers

    async def search(self, query: str, limit: int = 10) -> List[RawPaper]:
        params = self._apply_auth({
            "db": "pubmed",
            "term": query,
            "retmax": min(limit, 50),
        })
        search_data = await self.request_json(
            method="GET",
            endpoint="/esearch.fcgi",
            params=params,
        )
        if not search_data or "esearchresult" not in search_data:
            return []

        id_list = search_data["esearchresult"].get("idlist", [])
        return await self._fetch_summaries(id_list)

    async def resolve(self, identifier: str) -> Optional[RawPaper]:
        ident = identifier.strip()
        # Direct PMID match
        clean_pmid = ident[5:].strip() if ident.lower().startswith("pmid:") else ident
        if clean_pmid.isdigit():
            summaries = await self._fetch_summaries([clean_pmid])
            return summaries[0] if summaries else None

        # Resolve via ESearch by DOI or title
        params = self._apply_auth({
            "db": "pubmed",
            "term": f"{ident}[doi]" if "/" in ident else ident,
            "retmax": 1,
        })
        search_data = await self.request_json(
            method="GET",
            endpoint="/esearch.fcgi",
            params=params,
        )
        if not search_data or "esearchresult" not in search_data:
            return None
        id_list = search_data["esearchresult"].get("idlist", [])
        if not id_list:
            return None
        summaries = await self._fetch_summaries(id_list)
        return summaries[0] if summaries else None

    async def get_details(self, provider_id: str) -> Optional[RawPaper]:
        return await self.resolve(provider_id)

    async def get_references(
        self, provider_id: str, cursor: Optional[str] = None, limit: int = 50
    ) -> Page[RawPaper]:
        # Outbound references in PubMed rely on PMC or e-link
        return Page(items=[], total=0, has_more=False)

    async def get_citations(
        self, provider_id: str, cursor: Optional[str] = None, limit: int = 50
    ) -> Page[RawPaper]:
        return Page(items=[], total=0, has_more=False)
