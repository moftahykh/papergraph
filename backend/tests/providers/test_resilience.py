import asyncio
import time
import pytest
import httpx
from app.providers.base import BaseHttpProvider
from app.providers.exceptions import (
    ProviderRateLimitError,
    ProviderUnavailableError,
    ProviderClientError,
    ProviderTimeoutError,
)


class DummyProvider(BaseHttpProvider):
    def __init__(self, client: httpx.AsyncClient, rps: float = 100.0, max_retries: int = 2):
        super().__init__(
            name="dummy",
            base_url="https://api.example.com",
            rps=rps,
            timeout_seconds=2.0,
            max_retries=max_retries,
            client=client,
        )


@pytest.mark.asyncio
async def test_404_returns_none():
    transport = httpx.MockTransport(lambda req: httpx.Response(404, text="Not Found"))
    async with httpx.AsyncClient(transport=transport) as client:
        provider = DummyProvider(client=client)
        res = await provider.request_json("GET", "/item/missing")
        assert res is None


@pytest.mark.asyncio
async def test_4xx_client_error_not_retried():
    call_count = 0

    def handle(req):
        nonlocal call_count
        call_count += 1
        return httpx.Response(401, json={"error": "Unauthorized"})

    transport = httpx.MockTransport(handle)
    async with httpx.AsyncClient(transport=transport) as client:
        provider = DummyProvider(client=client, max_retries=3)
        with pytest.raises(ProviderClientError) as exc_info:
            await provider.request_json("GET", "/protected")
        assert exc_info.value.status_code == 401
        # Crucial check: 4xx must not be retried blindly!
        assert call_count == 1


@pytest.mark.asyncio
async def test_5xx_retries_and_raises_unavailable():
    call_count = 0

    def handle(req):
        nonlocal call_count
        call_count += 1
        return httpx.Response(503, text="Service Unavailable")

    transport = httpx.MockTransport(handle)
    async with httpx.AsyncClient(transport=transport) as client:
        provider = DummyProvider(client=client, max_retries=2)
        with pytest.raises(ProviderUnavailableError) as exc_info:
            await provider.request_json("GET", "/unstable")
        assert exc_info.value.status_code == 503
        assert call_count == 2


@pytest.mark.asyncio
async def test_429_rate_limit_backoff():
    call_count = 0

    def handle(req):
        nonlocal call_count
        call_count += 1
        if call_count == 1:
            return httpx.Response(429, headers={"Retry-After": "0.1"})
        return httpx.Response(200, json={"status": "recovered"})

    transport = httpx.MockTransport(handle)
    async with httpx.AsyncClient(transport=transport) as client:
        provider = DummyProvider(client=client, max_retries=3)
        res = await provider.request_json("GET", "/throttled")
        assert res == {"status": "recovered"}
        assert call_count == 2


@pytest.mark.asyncio
async def test_in_memory_cache():
    call_count = 0

    def handle(req):
        nonlocal call_count
        call_count += 1
        return httpx.Response(200, json={"data": "cached_value"})

    transport = httpx.MockTransport(handle)
    async with httpx.AsyncClient(transport=transport) as client:
        provider = DummyProvider(client=client)
        res1 = await provider.request_json("GET", "/resource", ttl_seconds=60)
        res2 = await provider.request_json("GET", "/resource", ttl_seconds=60)
        assert res1 == {"data": "cached_value"}
        assert res2 == {"data": "cached_value"}
        # HTTP client should only be contacted once!
        assert call_count == 1
