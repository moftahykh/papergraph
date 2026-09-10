import asyncio
import hashlib
import logging
import time
from typing import Any, Optional, Dict, Tuple, Callable, Awaitable

logger = logging.getLogger("papergraph.cache")


class ResponseCache:
    """
    High-performance response and artifact cache.
    Provides in-memory TTL caching with optional Redis connectivity,
    plus in-flight request collapsing (single-flight / coalesce) to prevent
    duplicate concurrent requests for the same resource.
    """
    def __init__(self, default_ttl: int = 86400):
        self.default_ttl = default_ttl
        self._memory_cache: Dict[str, Tuple[float, Any]] = {}
        self._lock = asyncio.Lock()
        self._inflight: Dict[str, asyncio.Future] = {}
        self._redis_client = None

    @staticmethod
    def generate_key(namespace: str, identifier: str) -> str:
        """Generates deterministic cache key for a namespace and identifier."""
        clean_id = identifier.strip().lower()
        hashed = hashlib.sha256(clean_id.encode("utf-8")).hexdigest()[:16]
        return f"{namespace}:{clean_id}:{hashed}"

    async def get(self, key: str) -> Optional[Any]:
        """Retrieves an unexpired value from cache."""
        async with self._lock:
            if key in self._memory_cache:
                expiry, val = self._memory_cache[key]
                if time.time() < expiry:
                    return val
                del self._memory_cache[key]
        return None

    async def set(self, key: str, value: Any, ttl_seconds: Optional[int] = None) -> None:
        """Stores a value in cache with explicit expiration."""
        ttl = ttl_seconds if ttl_seconds is not None else self.default_ttl
        expiry = time.time() + ttl
        async with self._lock:
            self._memory_cache[key] = (expiry, value)

    async def delete(self, key: str) -> None:
        """Removes a key from cache."""
        async with self._lock:
            self._memory_cache.pop(key, None)

    async def clear(self) -> None:
        """Clears all stored entries."""
        async with self._lock:
            self._memory_cache.clear()
            self._inflight.clear()

    async def get_or_fetch(
        self,
        key: str,
        fetcher: Callable[[], Awaitable[Any]],
        ttl_seconds: Optional[int] = None,
    ) -> Any:
        """
        Collapses concurrent duplicate requests for the same key.
        If multiple callers request the same key concurrently, only one invocation of `fetcher`
        is made, and all callers await and receive the same resulting value.
        """
        # 1. Check existing cache
        cached = await self.get(key)
        if cached is not None:
            return cached

        # 2. Check if a request for this key is already in-flight
        future = None
        is_leader = False
        async with self._lock:
            # Re-check cache under lock
            if key in self._memory_cache:
                expiry, val = self._memory_cache[key]
                if time.time() < expiry:
                    return val

            if key in self._inflight:
                future = self._inflight[key]
            else:
                loop = asyncio.get_running_loop()
                future = loop.create_future()
                self._inflight[key] = future
                is_leader = True

        if not is_leader and future is not None:
            # Another task is fetching this data; await its result
            return await future

        # 3. We are the leader: execute the fetcher
        try:
            result = await fetcher()
            await self.set(key, result, ttl_seconds=ttl_seconds)
            if not future.done():
                future.set_result(result)
            return result
        except Exception as exc:
            if not future.done():
                future.set_exception(exc)
            raise
        finally:
            async with self._lock:
                self._inflight.pop(key, None)
