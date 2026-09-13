import asyncio
import logging
import time
from typing import List, Optional, Dict, Union

logger = logging.getLogger("papergraph.providers.key_pool")


class ApiKeyPool:
    """
    Manages a pool of API keys with round-robin rotation and automatic cooldowns
    when encountering HTTP 429 rate limit responses.
    """
    def __init__(self, keys: Optional[Union[List[str], str]] = None):
        self._keys: List[str] = []
        self._index: int = 0
        self._cooldowns: Dict[str, float] = {}  # key -> cooldown_until (monotonic)
        self._lock = asyncio.Lock()

        if keys:
            self.set_keys(keys)

    def set_keys(self, raw_keys: Union[List[str], str]) -> None:
        """Parses and sets active keys from a list or comma-separated string."""
        if isinstance(raw_keys, str):
            parts = [k.strip() for k in raw_keys.split(",") if k.strip()]
        else:
            parts = [str(k).strip() for k in raw_keys if str(k).strip()]

        # Deduplicate preserving order
        seen = set()
        cleaned = []
        for k in parts:
            if k not in seen:
                seen.add(k)
                cleaned.append(k)

        self._keys = cleaned
        self._index = 0
        self._cooldowns.clear()
        logger.info(f"ApiKeyPool initialized with {len(self._keys)} keys.")

    @property
    def total_keys(self) -> int:
        return len(self._keys)

    def is_empty(self) -> bool:
        return len(self._keys) == 0

    async def get_next_key(self) -> Optional[str]:
        """
        Returns the next available API key via round-robin.
        If a key is in cooldown, attempts to find an active alternative.
        If all keys are in cooldown, returns the one closest to expiry.
        """
        if not self._keys:
            return None

        async with self._lock:
            now = time.monotonic()
            n = len(self._keys)

            # 1. Search for next key that is not in cooldown
            for _ in range(n):
                candidate = self._keys[self._index]
                self._index = (self._index + 1) % n

                cooldown_until = self._cooldowns.get(candidate, 0.0)
                if now >= cooldown_until:
                    # Clear expired cooldown
                    if candidate in self._cooldowns:
                        del self._cooldowns[candidate]
                    return candidate

            # 2. All keys are currently in cooldown: pick the one expiring earliest
            earliest_key = min(self._keys, key=lambda k: self._cooldowns.get(k, 0.0))
            return earliest_key

    async def mark_cooldown(self, key: Optional[str], duration_seconds: float = 30.0) -> None:
        """Puts a specific key into temporary cooldown (e.g. after receiving HTTP 429)."""
        if not key or key not in self._keys:
            return

        async with self._lock:
            self._cooldowns[key] = time.monotonic() + max(1.0, duration_seconds)
            masked = f"{key[:6]}...{key[-4:]}" if len(key) > 10 else "***"
            logger.warning(
                f"API key [{masked}] put in cooldown for {duration_seconds:.1f}s. "
                f"Active keys remaining: {self.active_count()}"
            )

    def has_alternative(self, current_key: Optional[str]) -> bool:
        """Checks if there is an alternative key not in cooldown."""
        if not current_key or len(self._keys) <= 1:
            return False

        now = time.monotonic()
        for k in self._keys:
            if k != current_key:
                cooldown_until = self._cooldowns.get(k, 0.0)
                if now >= cooldown_until:
                    return True
        return False

    def active_count(self) -> int:
        now = time.monotonic()
        return sum(1 for k in self._keys if now >= self._cooldowns.get(k, 0.0))
