from typing import Optional


class ProviderError(Exception):
    """Base exception for all academic provider adapter failures."""
    def __init__(
        self,
        provider: str,
        message: str,
        status_code: Optional[int] = None,
        retry_after: Optional[float] = None,
    ):
        super().__init__(f"[{provider}] {message} (status: {status_code})")
        self.provider = provider
        self.message = message
        self.status_code = status_code
        self.retry_after = retry_after


class ProviderRateLimitError(ProviderError):
    """Raised when upstream API responds with HTTP 429 Too Many Requests."""
    pass


class ProviderTimeoutError(ProviderError):
    """Raised when upstream API request times out."""
    pass


class ProviderUnavailableError(ProviderError):
    """Raised when upstream API responds with 502/503/504 Service Unavailable."""
    pass


class ProviderNotFoundError(ProviderError):
    """Raised when requested identifier is not indexed by this provider (HTTP 404)."""
    pass


class ProviderClientError(ProviderError):
    """Raised for 4xx client errors that should not be retried blindly."""
    pass
