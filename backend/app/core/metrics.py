import time
from typing import Dict, Any, Optional
from collections import defaultdict
from pydantic import BaseModel, Field


class LatencySummary(BaseModel):
    count: int = 0
    total_seconds: float = 0.0
    avg_seconds: float = 0.0
    min_seconds: float = 0.0
    max_seconds: float = 0.0


class MetricsResponse(BaseModel):
    provider_latency: Dict[str, LatencySummary] = Field(default_factory=dict)
    provider_errors: Dict[str, int] = Field(default_factory=dict)
    http_429_counts: Dict[str, int] = Field(default_factory=dict)
    cache_metrics: Dict[str, Any] = Field(default_factory=dict)
    graph_job_duration: LatencySummary = Field(default_factory=LatencySummary)
    candidate_pool_size: Dict[str, Any] = Field(default_factory=dict)
    enrichment_completeness: Dict[str, Any] = Field(default_factory=dict)
    ranking_confidence_distribution: Dict[str, int] = Field(default_factory=dict)
    system_uptime_seconds: float = 0.0


class MetricsCollector:
    """
    In-memory thread-safe metrics collector tracking key system observability signals:
      1. provider latency (per provider)
      2. provider errors (per provider)
      3. 429 rate-limit counts (upstream & downstream)
      4. cache hit ratio
      5. graph job duration
      6. candidate pool size distribution
      7. enrichment completeness ratio
      8. ranking confidence distribution (HIGH, MEDIUM, LOW, INSUFFICIENT)
    """
    _instance: Optional["MetricsCollector"] = None

    @classmethod
    def get_instance(cls) -> "MetricsCollector":
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    def __init__(self):
        self._start_time = time.time()
        
        # 1. Provider Latency: provider -> list of durations
        self._provider_latencies: Dict[str, list[float]] = defaultdict(list)
        
        # 2. Provider Errors: provider -> count
        self._provider_errors: Dict[str, int] = defaultdict(int)
        
        # 3. 429 counts: source -> count
        self._429_counts: Dict[str, int] = defaultdict(int)
        
        # 4. Cache metrics
        self._cache_hits: int = 0
        self._cache_misses: int = 0
        
        # 5. Graph job durations
        self._job_durations: list[float] = []
        
        # 6. Candidate pool sizes
        self._candidate_pool_sizes: list[int] = []
        
        # 7. Enrichment completeness scores
        self._completeness_scores: list[float] = []
        
        # 8. Ranking confidence distribution
        self._confidence_counts: Dict[str, int] = {
            "HIGH": 0,
            "MEDIUM": 0,
            "LOW": 0,
            "INSUFFICIENT": 0,
        }

    def record_provider_latency(self, provider: str, duration_seconds: float) -> None:
        self._provider_latencies[provider].append(max(0.0, duration_seconds))
        if len(self._provider_latencies[provider]) > 1000:
            self._provider_latencies[provider] = self._provider_latencies[provider][-1000:]

    def record_provider_error(self, provider: str) -> None:
        self._provider_errors[provider] += 1

    def record_429(self, source: str) -> None:
        self._429_counts[source] += 1

    def record_cache_hit(self) -> None:
        self._cache_hits += 1

    def record_cache_miss(self) -> None:
        self._cache_misses += 1

    def record_job_duration(self, duration_seconds: float) -> None:
        self._job_durations.append(max(0.0, duration_seconds))
        if len(self._job_durations) > 500:
            self._job_durations = self._job_durations[-500:]

    def record_candidate_pool_size(self, size: int) -> None:
        self._candidate_pool_sizes.append(size)
        if len(self._candidate_pool_sizes) > 500:
            self._candidate_pool_sizes = self._candidate_pool_sizes[-500:]

    def record_enrichment_completeness(self, score: float) -> None:
        self._completeness_scores.append(round(min(1.0, max(0.0, score)), 4))
        if len(self._completeness_scores) > 500:
            self._completeness_scores = self._completeness_scores[-500:]

    def record_confidence(self, level: str) -> None:
        level_key = level.upper()
        if level_key in self._confidence_counts:
            self._confidence_counts[level_key] += 1
        else:
            self._confidence_counts[level_key] = 1

    def _summarize_floats(self, values: list[float]) -> LatencySummary:
        if not values:
            return LatencySummary()
        total = sum(values)
        return LatencySummary(
            count=len(values),
            total_seconds=round(total, 4),
            avg_seconds=round(total / len(values), 4),
            min_seconds=round(min(values), 4),
            max_seconds=round(max(values), 4),
        )

    def get_metrics(self) -> MetricsResponse:
        latency_summary = {
            provider: self._summarize_floats(durations)
            for provider, durations in self._provider_latencies.items()
        }

        total_cache_requests = self._cache_hits + self._cache_misses
        cache_hit_ratio = (
            round(self._cache_hits / total_cache_requests, 4)
            if total_cache_requests > 0
            else 0.0
        )

        pool_sizes = self._candidate_pool_sizes
        candidate_summary = {
            "count": len(pool_sizes),
            "avg_size": round(sum(pool_sizes) / len(pool_sizes), 1) if pool_sizes else 0.0,
            "min_size": min(pool_sizes) if pool_sizes else 0,
            "max_size": max(pool_sizes) if pool_sizes else 0,
        }

        completeness = self._completeness_scores
        completeness_summary = {
            "count": len(completeness),
            "avg_score": round(sum(completeness) / len(completeness), 4) if completeness else 0.0,
            "min_score": min(completeness) if completeness else 0.0,
            "max_score": max(completeness) if completeness else 0.0,
        }

        uptime = round(time.time() - self._start_time, 2)

        return MetricsResponse(
            provider_latency=latency_summary,
            provider_errors=dict(self._provider_errors),
            http_429_counts=dict(self._429_counts),
            cache_metrics={
                "hits": self._cache_hits,
                "misses": self._cache_misses,
                "total_requests": total_cache_requests,
                "hit_ratio": cache_hit_ratio,
            },
            graph_job_duration=self._summarize_floats(self._job_durations),
            candidate_pool_size=candidate_summary,
            enrichment_completeness=completeness_summary,
            ranking_confidence_distribution=dict(self._confidence_counts),
            system_uptime_seconds=uptime,
        )

    def reset(self) -> None:
        """Resets all metrics counters for testing."""
        self._start_time = time.time()
        self._provider_latencies.clear()
        self._provider_errors.clear()
        self._429_counts.clear()
        self._cache_hits = 0
        self._cache_misses = 0
        self._job_durations.clear()
        self._candidate_pool_sizes.clear()
        self._completeness_scores.clear()
        self._confidence_counts = {
            "HIGH": 0,
            "MEDIUM": 0,
            "LOW": 0,
            "INSUFFICIENT": 0,
        }


metrics = MetricsCollector.get_instance()
