import asyncio
import logging
import time
from typing import Protocol, runtime_checkable, Optional, Dict, Any, List
import httpx
from app.providers.models import RawPaper, Page
from app.providers.exceptions import (
    ProviderError,
    ProviderRateLimitError,
    ProviderTimeoutError,
    ProviderUnavailableError,
    ProviderNotFoundError,
    ProviderClientError,
)

logger = logging.getLogger("papergraph.providers")


@runtime_checkable
class AcademicProvider(Protocol):
    """Common interface for all academic literature provider adapters."""
    name: str

    async def search(self, query: str, limit: int = 10) -> List[RawPaper]:
        ...

    async def resolve(self, identifier: str) -> Optional[RawPaper]:
        ...

    async def get_details(self, provider_id: str) -> Optional[RawPaper]:
        ...

    async def get_references(
        self, provider_id: str, cursor: Optional[str] = None, limit: int = 50
    ) -> Page[RawPaper]:
        ...

    async def get_citations(
        self, provider_id: str, cursor: Optional[str] = None, limit: int = 50
    ) -> Page[RawPaper]:
        ...


class BaseHttpProvider:
    """
    Base HTTP adapter providing:
    - Configurable rate limiting (RPS)
    - Exponential backoff retry with Retry-After honoring for HTTP 429
    - Bounded retries for 5xx/timeouts
    - Classification of 4xx client errors (avoiding blind retries)
    - In-memory response cache with TTL
    """
    def __init__(
        self,
        name: str,
        base_url: str,
        rps: float = 2.0,
        timeout_seconds: float = 10.0,
        max_retries: int = 3,
        client: Optional[httpx.AsyncClient] = None,
    ):
        self.name = name
        self.base_url = base_url.rstrip("/")
        self.rps = max(0.1, rps)
        self.min_interval = 1.0 / self.rps
        self.timeout_seconds = timeout_seconds
        self.max_retries = max_retries
        self._custom_client = client
        self._last_request_time: float = 0.0
        self._lock = asyncio.Lock()
        self._cache: Dict[str, tuple[float, Any]] = {}  # key -> (expiry_time, data)

    async def _get_client(self) -> httpx.AsyncClient:
        if self._custom_client:
            return self._custom_client
        return httpx.AsyncClient(timeout=self.timeout_seconds)

    async def _rate_limit(self) -> None:
        """Enforces minimum time interval between consecutive outbound API requests."""
        async with self._lock:
            now = time.monotonic()
            elapsed = now - self._last_request_time
            if elapsed < self.min_interval:
                await asyncio.sleep(self.min_interval - elapsed)
            self._last_request_time = time.monotonic()

    def _get_from_cache(self, key: str) -> Optional[Any]:
        if key in self._cache:
            exp, data = self._cache[key]
            if time.time() < exp:
                return data
            del self._cache[key]
        return None

    def _set_cache(self, key: str, data: Any, ttl_seconds: int = 3600) -> None:
        self._cache[key] = (time.time() + ttl_seconds, data)

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
        Executes an HTTP request returning parsed JSON with rate limiting, caching, and retry policies.
        """
        url = endpoint if endpoint.startswith("http") else f"{self.base_url}/{endpoint.lstrip('/')}"
        cache_key = f"{self.name}:{method}:{url}:{str(sorted(params.items()) if params else '')}:{str(json_data)}"
        
        cached = self._get_from_cache(cache_key)
        if cached is not None:
            return cached

        attempt = 0
        backoff_delay = 0.5
        client = await self._get_client()

        while attempt < self.max_retries:
            attempt += 1
            await self._rate_limit()

            try:
                response = await client.request(
                    method=method,
                    url=url,
                    params=params,
                    headers=headers,
                    json=json_data,
                )

                # Classify response
                if response.status_code == 200:
                    data = response.json()
                    self._set_cache(cache_key, data, ttl_seconds=ttl_seconds)
                    return data

                if response.status_code == 404:
                    # Item not found in this provider
                    return None

                if response.status_code == 429:
                    # Rate limit encountered: read Retry-After if available
                    retry_after_header = response.headers.get("Retry-After")
                    wait_time = backoff_delay
                    if retry_after_header:
                        try:
                            wait_time = min(30.0, float(retry_after_header))
                        except ValueError:
                            pass
                    logger.warning(
                        f"[{self.name}] HTTP 429 encountered. Waiting {wait_time:.1f}s (attempt {attempt}/{self.max_retries})"
                    )
                    if attempt >= self.max_retries:
                        raise ProviderRateLimitError(
                            provider=self.name,
                            message="Rate limit exceeded",
                            status_code=429,
                            retry_after=wait_time,
                        )
                    await asyncio.sleep(wait_time)
                    backoff_delay *= 2
                    continue

                if 400 <= response.status_code < 500:
                    # 4xx client errors (400, 401, 403, etc.): do not blind retry
                    raise ProviderClientError(
                        provider=self.name,
                        message=f"Client error response: {response.text[:200]}",
                        status_code=response.status_code,
                    )

                if 500 <= response.status_code < 600:
                    # 5xx server errors: retry with exponential backoff
                    logger.warning(
                        f"[{self.name}] Server error {response.status_code}. Retrying in {backoff_delay:.1f}s..."
                    )
                    if attempt >= self.max_retries:
                        raise ProviderUnavailableError(
                            provider=self.name,
                            message=f"Upstream server error: {response.status_code}",
                            status_code=response.status_code,
                        )
                    await asyncio.sleep(backoff_delay)
                    backoff_delay *= 2
                    continue

            except httpx.TimeoutException as e:
                logger.warning(f"[{self.name}] Request timed out (attempt {attempt}/{self.max_retries})")
                if attempt >= self.max_retries:
                    raise ProviderTimeoutError(
                        provider=self.name,
                        message="Request timed out",
                    ) from e
                await asyncio.sleep(backoff_delay)
                backoff_delay *= 2
            except httpx.RequestError as e:
                if attempt >= self.max_retries:
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
