import asyncio
import logging
import time
from typing import Optional, List, Dict, Any, Union
from urllib.parse import quote
import httpx
from app.core.config import settings
from app.models.canonical_paper import Author
from app.providers.base import BaseHttpProvider
from app.providers.key_pool import ApiKeyPool
from app.providers.exceptions import (
    ProviderError,
    ProviderRateLimitError,
    ProviderTimeoutError,
    ProviderUnavailableError,
    ProviderClientError,
)
from app.resolution.normalizers import classify_identifier
from app.providers.models import RawPaper, Page

logger = logging.getLogger("papergraph.providers.semantic_scholar")

PAPER_FIELDS = "title,abstract,authors,year,venue,citationCount,referenceCount,externalIds,s2FieldsOfStudy"


class SemanticScholarProvider(BaseHttpProvider):
    """
    Adapter for Semantic Scholar Academic Graph API.
    Primary scope: Search, paper details, recommendations, paginated references, and citations.
    Supports API Key pooling and instant key rotation on HTTP 429.
    """
    def __init__(
        self,
        api_key: Optional[str] = None,
        api_keys: Optional[Union[List[str], str]] = None,
        key_pool: Optional[ApiKeyPool] = None,
        rps: Optional[float] = None,
        client: Optional[httpx.AsyncClient] = None,
    ):
        # Build key pool from provided arguments or configuration
        if key_pool:
            self.key_pool = key_pool
        else:
            raw_keys: List[str] = []
            if api_keys:
                if isinstance(api_keys, str):
                    raw_keys.extend([k.strip() for k in api_keys.split(",") if k.strip()])
                else:
                    raw_keys.extend([str(k).strip() for k in api_keys if str(k).strip()])
            if api_key and api_key.strip():
                raw_keys.append(api_key.strip())
            if settings.SEMANTIC_SCHOLAR_API_KEYS:
                if isinstance(settings.SEMANTIC_SCHOLAR_API_KEYS, str):
                    raw_keys.extend([k.strip() for k in settings.SEMANTIC_SCHOLAR_API_KEYS.split(",") if k.strip()])
                else:
                    raw_keys.extend([str(k).strip() for k in settings.SEMANTIC_SCHOLAR_API_KEYS if str(k).strip()])
            if settings.SEMANTIC_SCHOLAR_API_KEY and settings.SEMANTIC_SCHOLAR_API_KEY.strip():
                raw_keys.append(settings.SEMANTIC_SCHOLAR_API_KEY.strip())

            self.key_pool = ApiKeyPool(raw_keys)

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

    async def request_json(
        self,
        method: str,
        endpoint: str,
        params: Optional[Dict[str, Any]] = None,
        headers: Optional[Dict[str, str]] = None,
        json_data: Optional[Any] = None,
        ttl_seconds: int = 3600,
    ) -> Optional[Any]:
        """
        Executes an HTTP request with API key rotation, instant 429 failover, caching, and retry policies.
        """
        from app.core.metrics import metrics

        url = endpoint if endpoint.startswith("http") else f"{self.base_url}/{endpoint.lstrip('/')}"
        cache_key = f"{self.name}:{method}:{url}:{str(sorted(params.items()) if params else '')}:{str(json_data)}"

        cached = self._get_from_cache(cache_key)
        if cached is not None:
            metrics.record_cache_hit()
            return cached
        metrics.record_cache_miss()

        req_headers = dict(headers or self.headers)
        active_key = await self.key_pool.get_next_key()
        if active_key:
            req_headers["x-api-key"] = active_key
        elif "x-api-key" in req_headers and not active_key:
            del req_headers["x-api-key"]

        attempt = 0
        backoff_delay = 0.5
        client = await self._get_client()
        max_attempts = max(self.max_retries, self.key_pool.total_keys * 2 if self.key_pool.total_keys > 0 else self.max_retries)

        while attempt < max_attempts:
            attempt += 1
            await self._rate_limit()

            req_start = time.monotonic()
            try:
                response = await client.request(
                    method=method,
                    url=url,
                    params=params,
                    headers=req_headers,
                    json=json_data,
                )
                elapsed = time.monotonic() - req_start
                metrics.record_provider_latency(self.name, elapsed)

                if response.status_code == 200:
                    data = response.json()
                    self._set_cache(cache_key, data, ttl_seconds=ttl_seconds)
                    return data

                if response.status_code == 404:
                    return None

                if response.status_code == 429:
                    metrics.record_429(self.name)
                    metrics.record_provider_error(self.name)
                    await self.key_pool.mark_cooldown(active_key, duration_seconds=30.0)

                    # If another active key is available in the pool, switch immediately without waiting!
                    if self.key_pool.has_alternative(active_key):
                        active_key = await self.key_pool.get_next_key()
                        if active_key:
                            req_headers["x-api-key"] = active_key
                        logger.info(f"[{self.name}] Switched to alternative API key on 429. Retrying immediately...")
                        continue

                    # Otherwise wait
                    retry_after_header = response.headers.get("Retry-After")
                    wait_time = backoff_delay
                    if retry_after_header:
                        try:
                            wait_time = min(30.0, float(retry_after_header))
                        except ValueError:
                            pass
                    logger.warning(
                        f"[{self.name}] HTTP 429 encountered. Waiting {wait_time:.1f}s (attempt {attempt}/{max_attempts})"
                    )
                    if attempt >= max_attempts:
                        raise ProviderRateLimitError(
                            provider=self.name,
                            message="Rate limit exceeded across all available keys",
                            status_code=429,
                            retry_after=wait_time,
                        )
                    await asyncio.sleep(wait_time)
                    backoff_delay *= 2
                    active_key = await self.key_pool.get_next_key()
                    if active_key:
                        req_headers["x-api-key"] = active_key
                    continue

                if 400 <= response.status_code < 500:
                    metrics.record_provider_error(self.name)
                    raise ProviderClientError(
                        provider=self.name,
                        message=f"Client error response: {response.text[:200]}",
                        status_code=response.status_code,
                    )

                if 500 <= response.status_code < 600:
                    metrics.record_provider_error(self.name)
                    logger.warning(
                        f"[{self.name}] Server error {response.status_code}. Retrying in {backoff_delay:.1f}s..."
                    )
                    if attempt >= max_attempts:
                        raise ProviderUnavailableError(
                            provider=self.name,
                            message=f"Upstream server error: {response.status_code}",
                            status_code=response.status_code,
                        )
                    await asyncio.sleep(backoff_delay)
                    backoff_delay *= 2
                    continue

            except httpx.TimeoutException as e:
                metrics.record_provider_error(self.name)
                logger.warning(f"[{self.name}] Request timed out (attempt {attempt}/{max_attempts})")
                if attempt >= max_attempts:
                    raise ProviderTimeoutError(
                        provider=self.name,
                        message="Request timed out",
                    ) from e
                await asyncio.sleep(backoff_delay)
                backoff_delay *= 2
            except httpx.RequestError as e:
                metrics.record_provider_error(self.name)
                if attempt >= max_attempts:
                    raise ProviderError(
                        provider=self.name,
                        message=f"Transport error: {str(e)}",
                    ) from e
                await asyncio.sleep(backoff_delay)
                backoff_delay *= 2

        raise ProviderError(
            provider=self.name,
            message="Exceeded max retries without successful response",
        )

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
        """Formats any supported identifier or paper link into S2's prefixed ID syntax."""
        kind, value = classify_identifier(identifier)
        if kind == "doi":
            return f"DOI:{value}"
        if kind == "pmid":
            return f"PMID:{value}"
        if kind == "pmcid":
            return f"PMCID:{value}"
        if kind == "arxiv":
            return f"ARXIV:{value}"
        if kind == "corpusid":
            return f"CorpusID:{value}"
        if kind == "s2":
            return value
        # Titles and unrecognized links pass through unchanged (S2 will 404,
        # and the caller's fallback chain takes over from there).
        return identifier.strip()

    async def resolve(self, identifier: str) -> Optional[RawPaper]:
        formatted = self._format_identifier(identifier)
        data = await self.request_json(
            method="GET",
            endpoint=f"/paper/{quote(formatted, safe='')}",
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
        if not data or not data.get("data"):
            return []
        return [self._parse_paper(p) for p in data["data"] if p]

    async def get_details(self, provider_id: str) -> Optional[RawPaper]:
        return await self.resolve(provider_id)

    async def get_references(
        self, provider_id: str, cursor: Optional[str] = None, limit: int = 50
    ) -> Page[RawPaper]:
        offset = int(cursor) if cursor and cursor.isdigit() else 0
        formatted = self._format_identifier(provider_id)
        data = await self.request_json(
            method="GET",
            endpoint=f"/paper/{quote(formatted, safe='')}/references",
            params={
                "fields": "citedPaper.title,citedPaper.authors,citedPaper.year,citedPaper.externalIds,citedPaper.citationCount",
                "offset": offset,
                "limit": min(limit, 100),
            },
            headers=self.headers,
        )
        # S2 returns {"data": null} for papers without reference data —
        # the guard must reject a null payload, not just a missing key.
        if not data or not data.get("data"):
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
            endpoint=f"/paper/{quote(formatted, safe='')}/citations",
            params={
                "fields": "citingPaper.title,citingPaper.authors,citingPaper.year,citingPaper.externalIds,citingPaper.citationCount",
                "offset": offset,
                "limit": min(limit, 100),
            },
            headers=self.headers,
        )
        # Same null-payload guard as get_references.
        if not data or not data.get("data"):
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
        url = f"https://api.semanticscholar.org/recommendations/v1/papers/forpaper/{quote(formatted, safe='')}"
        data = await self.request_json(
            method="GET",
            endpoint=url,
            params={
                "limit": min(limit, 50),
                "fields": PAPER_FIELDS,
            },
            headers=self.headers,
        )
        if not data or not data.get("recommendedPapers"):
            return []
        return [self._parse_paper(p) for p in data["recommendedPapers"] if p]

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
