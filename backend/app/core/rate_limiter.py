import time
from typing import Dict, List
import asyncio
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.requests import Request
from starlette.responses import Response, JSONResponse
from app.core.config import settings
from app.core.metrics import metrics


class InMemoryRateLimiter:
    """
    Sliding window in-memory rate limiter per client IP address.
    """
    def __init__(self, requests_per_minute: int = settings.RATE_LIMIT_PER_MINUTE):
        self.requests_per_minute = requests_per_minute
        self.window_seconds = 60.0
        self._history: Dict[str, List[float]] = {}
        self._lock = asyncio.Lock()

    async def is_allowed(self, client_ip: str) -> tuple[bool, int]:
        """
        Returns (is_allowed: bool, retry_after_seconds: int).
        """
        if not settings.RATE_LIMIT_ENABLED:
            return True, 0

        now = time.time()
        cutoff = now - self.window_seconds

        async with self._lock:
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


rate_limiter = InMemoryRateLimiter()


class RateLimitMiddleware(BaseHTTPMiddleware):
    """
    ASGI middleware that validates client request velocity and enforces HTTP 429.
    """
    def __init__(self, app, limiter: InMemoryRateLimiter = rate_limiter):
        super().__init__(app)
        self.limiter = limiter

    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        # Exempt health check and documentation endpoints
        path = request.url.path
        if path.endswith("/health") or "/docs" in path or "/redoc" in path or "/openapi.json" in path:
            return await call_next(request)

        # Determine client identifier
        client_ip = request.client.host if request.client else "unknown"
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
