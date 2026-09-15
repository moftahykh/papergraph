import time
from typing import Dict, List
import asyncio
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.requests import Request
from starlette.responses import Response, JSONResponse
from app.core.config import settings
from app.core.metrics import metrics


# Configured trusted proxies/internal gateways allowed to assert X-Forwarded-For
TRUSTED_PROXIES = {
    "127.0.0.1",
    "::1",
    "localhost",
    "testclient",
}
MAX_TRACKED_CLIENTS = 10000
PRUNE_INTERVAL_REQUESTS = 100


class InMemoryRateLimiter:
    """
    Sliding window in-memory rate limiter per client IP address with
    bounded memory size and automatic eviction of expired entries.
    """
    def __init__(self, requests_per_minute: int = settings.RATE_LIMIT_PER_MINUTE):
        self.requests_per_minute = requests_per_minute
        self.window_seconds = 60.0
        self._history: Dict[str, List[float]] = {}
        self._request_counter = 0
        self._lock = asyncio.Lock()

    def _prune_expired_entries(self, cutoff: float) -> None:
        """Evicts expired client entries to prevent memory leaks."""
        expired_ips = [
            ip for ip, timestamps in self._history.items()
            if not timestamps or timestamps[-1] <= cutoff
        ]
        for ip in expired_ips:
            self._history.pop(ip, None)

        if len(self._history) > MAX_TRACKED_CLIENTS:
            # Evict oldest entries to maintain memory safety
            sorted_ips = sorted(
                self._history.keys(),
                key=lambda ip: self._history[ip][-1] if self._history[ip] else 0,
            )
            overflow = len(self._history) - MAX_TRACKED_CLIENTS
            for ip in sorted_ips[:overflow]:
                self._history.pop(ip, None)

    async def is_allowed(self, client_ip: str) -> tuple[bool, int]:
        """
        Returns (is_allowed: bool, retry_after_seconds: int).
        """
        if not settings.RATE_LIMIT_ENABLED:
            return True, 0

        now = time.time()
        cutoff = now - self.window_seconds

        async with self._lock:
            self._request_counter += 1
            if self._request_counter >= PRUNE_INTERVAL_REQUESTS or len(self._history) > MAX_TRACKED_CLIENTS:
                self._request_counter = 0
                self._prune_expired_entries(cutoff)

            timestamps = self._history.get(client_ip, [])
            # Filter out timestamps older than sliding window
            timestamps = [t for t in timestamps if t > cutoff]

            if len(timestamps) >= self.requests_per_minute:
                # Rate limit exceeded
                oldest = timestamps[0]
                retry_after = max(1, int(self.window_seconds - (now - oldest)))
                self._history[client_ip] = timestamps
                return False, retry_after

            timestamps.append(now)
            self._history[client_ip] = timestamps
            return True, 0

    def reset(self) -> None:
        """Resets rate limiting records (useful for test suites)."""
        self._history.clear()
        self._request_counter = 0


rate_limiter = InMemoryRateLimiter()


def _is_trusted_proxy(ip: str) -> bool:
    """Checks if the direct peer is a trusted reverse proxy / internal interface."""
    if ip in TRUSTED_PROXIES:
        return True
    if ip.startswith(("10.", "192.168.", "172.16.", "172.17.", "172.18.", "172.19.", "172.20.",
                      "172.21.", "172.22.", "172.23.", "172.24.", "172.25.", "172.26.", "172.27.",
                      "172.28.", "172.29.", "172.30.", "172.31.")):
        return True
    return False


class RateLimitMiddleware(BaseHTTPMiddleware):
    """
    ASGI middleware that validates client request velocity and enforces HTTP 429.
    Prevents IP spoofing via unverified X-Forwarded-For headers.
    """
    def __init__(self, app, limiter: InMemoryRateLimiter = rate_limiter):
        super().__init__(app)
        self.limiter = limiter

    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        # Exempt health check and documentation endpoints
        path = request.url.path
        if path.endswith("/health") or "/docs" in path or "/redoc" in path or "/openapi.json" in path:
            return await call_next(request)

        # Determine verified client identifier
        direct_ip = request.client.host if request.client else "unknown"
        client_ip = direct_ip

        # Only trust X-Forwarded-For if incoming connection is from a known reverse proxy
        if _is_trusted_proxy(direct_ip):
            forwarded_for = request.headers.get("x-forwarded-for")
            if forwarded_for:
                client_ip = forwarded_for.split(",")[0].strip()

        allowed, retry_after = await self.limiter.is_allowed(client_ip)
        if not allowed:
            metrics.record_429("client_rate_limit")
            return JSONResponse(
                status_code=429,
                headers={"Retry-After": str(retry_after)},
                content={
                    "error": {
                        "code": "RATE_LIMIT_EXCEEDED",
                        "message": f"Too many requests. Please retry after {retry_after} seconds.",
                        "status": 429,
                    }
                },
            )

        return await call_next(request)
