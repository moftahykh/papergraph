from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.requests import Request
from starlette.responses import Response, JSONResponse
from app.core.config import settings


class ContentLengthLimitMiddleware(BaseHTTPMiddleware):
    """
    Protects the backend against payload flooding/DoS by rejecting requests
    exceeding the configured maximum payload size with HTTP 413 Payload Too Large.
    """
    def __init__(self, app, max_content_length: int = settings.MAX_REQUEST_BODY_BYTES):
        super().__init__(app)
        self.max_content_length = max_content_length

    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        content_length = request.headers.get("content-length")
        if content_length:
            try:
                length = int(content_length)
                if length > self.max_content_length:
                    return JSONResponse(
                        status_code=413,
                        content={
                            "error": {
                                "code": "PAYLOAD_TOO_LARGE",
                                "message": f"Request payload size of {length} bytes exceeds maximum allowed limit ({self.max_content_length} bytes).",
                                "status": 413,
                            }
                        },
                    )
            except ValueError:
                pass

        return await call_next(request)
