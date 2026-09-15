import asyncio
import hashlib
import logging
import uuid
from datetime import datetime, timezone
from typing import Dict, Optional, List
from app.models.enums import GraphJobStatus, MetricAvailability
from app.models.graph import GraphJob, GraphSnapshot, GraphWarning, DataCompleteness
from app.schemas.graph import CreateGraphRequest
from app.resolution.resolver import IdentityResolver
from app.resolution.normalizers import classify_identifier
from app.candidates.generator import CandidatePoolGenerator
from app.enrichment.pipeline import EnrichmentPipeline
from app.ranking.engine import SafeRankingEngine
from app.graph.synthesizer import GraphSynthesizer
from app.providers.semantic_scholar import SemanticScholarProvider
from app.providers.openalex import OpenAlexProvider

logger = logging.getLogger("papergraph.workers.jobs")


class GraphJobManager:
    """
    Manages asynchronous PaperGraph synthesis jobs, idempotency hashing,
    stage progression through all 16 lifecycle stages, and snapshot caching.
    """
    _instance: Optional["GraphJobManager"] = None

    @classmethod
    def get_instance(cls) -> "GraphJobManager":
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    def __init__(
        self,
        resolver: Optional[IdentityResolver] = None,
        candidate_generator: Optional[CandidatePoolGenerator] = None,
        enrichment_pipeline: Optional[EnrichmentPipeline] = None,
        ranking_engine: Optional[SafeRankingEngine] = None,
        graph_synthesizer: Optional[GraphSynthesizer] = None,
        s2_provider=None,
        openalex_provider=None,
    ):
        self.jobs: Dict[str, GraphJob] = {}
        self.idempotency_map: Dict[str, str] = {}
        self.max_stored_jobs = 200
        self.job_ttl_seconds = 14400  # 4 hours
        self._lock = asyncio.Lock()

        # Engine dependencies
        self.resolver = resolver or IdentityResolver()
        self.candidate_generator = candidate_generator or CandidatePoolGenerator(resolver=self.resolver)
        self.s2_provider = s2_provider or SemanticScholarProvider()
        self.openalex_provider = openalex_provider or OpenAlexProvider()
        self.enrichment_pipeline = enrichment_pipeline or EnrichmentPipeline(
            s2_provider=self.s2_provider,
            openalex_provider=self.openalex_provider,
        )
        self.ranking_engine = ranking_engine or SafeRankingEngine()
        self.graph_synthesizer = graph_synthesizer or GraphSynthesizer()

    def _evict_stale_jobs(self) -> None:
        """
        Evicts expired jobs (> 4 hours old) and enforces MAX_STORED_JOBS bounds
        to prevent memory leakage.
        """
        now = datetime.now(timezone.utc)
        stale_job_ids = [
            jid for jid, job in self.jobs.items()
            if (now - job.updated_at).total_seconds() > self.job_ttl_seconds
        ]
        for jid in stale_job_ids:
            self.jobs.pop(jid, None)

        if len(self.jobs) > self.max_stored_jobs:
            sorted_jobs = sorted(self.jobs.values(), key=lambda j: j.updated_at)
            overflow = len(self.jobs) - self.max_stored_jobs
            for job in sorted_jobs[:overflow]:
                self.jobs.pop(job.job_id, None)

        # Synchronize idempotency_map to evict dangling keys
        active_ids = set(self.jobs.keys())
        dangling_keys = [k for k, jid in self.idempotency_map.items() if jid not in active_ids]
        for k in dangling_keys:
            self.idempotency_map.pop(k, None)

    @staticmethod
    def compute_idempotency_key(request: CreateGraphRequest) -> str:
        """Computes deterministic hash for request parameters."""
        raw = f"{request.origin_id.strip().lower()}:{request.max_nodes}:{request.weight_profile}:{request.algorithm_version}"
        return hashlib.sha256(raw.encode("utf-8")).hexdigest()

    async def get_or_create_job(self, request: CreateGraphRequest) -> GraphJob:
        """
        Creates a new asynchronous graph generation job or returns existing job
        if an identical request was already submitted (Idempotency).
        """
        key = self.compute_idempotency_key(request)

        async with self._lock:
            self._evict_stale_jobs()

            if key in self.idempotency_map:
                existing_id = self.idempotency_map[key]
                existing_job = self.jobs.get(existing_id)
                if existing_job and existing_job.status != GraphJobStatus.FAILED:
                    logger.info(f"Reusing existing graph job {existing_id} for key {key}")
                    return existing_job

            # Create new job
            job_id = f"graph_{uuid.uuid4().hex[:10]}"
            poll_url = f"/api/v1/graphs/{job_id}"

            job = GraphJob(
                job_id=job_id,
                origin_query=request.origin_id,
                status=GraphJobStatus.QUEUED,
                current_stage=GraphJobStatus.QUEUED,
                progress=0.0,
                poll_url=poll_url,
                created_at=datetime.now(timezone.utc),
                updated_at=datetime.now(timezone.utc),
            )
            self.jobs[job_id] = job
            self.idempotency_map[key] = job_id

        # Launch background pipeline asynchronously
        asyncio.create_task(self._execute_pipeline(job, request))
        return job

    def get_job(self, job_id: str) -> Optional[GraphJob]:
        """Retrieves current job status by identifier."""
        return self.jobs.get(job_id)

    async def _update_stage(
        self,
        job: GraphJob,
        stage: GraphJobStatus,
        progress: float,
    ) -> None:
        """Updates job stage and progress atomically."""
        job.status = stage
        job.current_stage = stage
        job.progress = round(min(1.0, max(0.0, progress)), 2)
        job.updated_at = datetime.now(timezone.utc)
        # Yield control briefly to allow polling handlers to read intermediate states
        await asyncio.sleep(0.01)

    async def _execute_pipeline(
        self,
        job: GraphJob,
        request: CreateGraphRequest,
    ) -> None:
        """
        Executes the 16-stage asynchronous literature discovery and synthesis pipeline.
        """
        import time
        from app.core.metrics import metrics

        pipeline_start = time.monotonic()
        try:
            # Stage 1: Queued
            await self._update_stage(job, GraphJobStatus.QUEUED, 0.0)

            # Stage 2: Resolving Origin
            await self._update_stage(job, GraphJobStatus.RESOLVING_ORIGIN, 0.05)
            origin_raw = None
            attempted_channels: List[str] = []

            async def _try_channel(label: str, identifier: str, provider) -> None:
                """Resolves via a single channel. A failure in one channel must
                NEVER abort the rest of the fallback chain — that is the whole
                point of having multiple providers."""
                nonlocal origin_raw
                if origin_raw is not None or provider is None:
                    return
                attempted_channels.append(label)
                try:
                    origin_raw = await provider.resolve(identifier)
                except Exception as e:
                    logger.warning(f"Origin resolution via {label} failed: {e}")

            # 1) Primary providers — isolated so one provider's 5xx does not
            #    skip the other (previously a single shared try block aborted
            #    the whole chain on the first exception).
            await _try_channel("semantic_scholar", request.origin_id, self.s2_provider)
            await _try_channel("openalex", request.origin_id, self.openalex_provider)

            # 2) Universal fallback chain for links/IDs the providers did not
            #    resolve directly. Each step is logged so backend logs
            #    self-describe which channel was attempted.
            if not origin_raw:
                from app.resolution.link_resolver import (
                    resolve_ncbi_idconv,
                    resolve_url_to_identifier,
                )

                kind, value = classify_identifier(request.origin_id)

                # 2a) NCBI's official ID converter: PMCID/PMID -> DOI.
                #     Authoritative for fresh biomedical papers that S2 /
                #     OpenAlex have not indexed under the PMCID yet.
                if kind in ("pmcid", "pmid"):
                    try:
                        mapped_id = await resolve_ncbi_idconv(kind, value)
                    except Exception as e:
                        logger.warning(f"NCBI idconv failed for {value}: {e}")
                        mapped_id = None
                    if mapped_id:
                        logger.info(
                            f"Origin resolution: NCBI idconv mapped {value} -> {mapped_id}"
                        )
                        await _try_channel("semantic_scholar", mapped_id, self.s2_provider)
                        await _try_channel("openalex", mapped_id, self.openalex_provider)

                # 2b) Any http(s) landing page usually carries citation_*
                #     meta tags (the metadata Zotero/Mendeley rely on).
                if not origin_raw and request.origin_id.lower().startswith(
                    ("http://", "https://")
                ):
                    try:
                        extracted = await resolve_url_to_identifier(request.origin_id)
                    except Exception as e:
                        logger.warning(f"Landing-page metadata scrape failed: {e}")
                        extracted = None
                    if extracted:
                        logger.info(
                            f"Origin resolution: scraped {extracted[0]} from landing page"
                        )
                        await _try_channel("semantic_scholar", extracted[1], self.s2_provider)
                        await _try_channel("openalex", extracted[1], self.openalex_provider)

            if not origin_raw:
                # Never fabricate an origin paper. Fail loudly instead of presenting
                # synthesized data as real (academic integrity + honest failure states).
                channels = ", ".join(attempted_channels) or "none"
                raise ValueError(
                    f"Could not resolve origin paper '{request.origin_id}' "
                    f"(channels attempted: {channels}). The paper may be too new "
                    "to be indexed — try its DOI or full title instead."
                )
            origin_paper = self.resolver.ingest(origin_raw.to_canonical())

            # Stage 3: Generating Candidates
            await self._update_stage(job, GraphJobStatus.GENERATING_CANDIDATES, 0.15)
            raw_refs, raw_cites, raw_recs = [], [], []
            if origin_paper.semantic_scholar_id:
                try:
                    ref_page = await self.s2_provider.get_references(origin_paper.semantic_scholar_id, limit=30)
                    raw_refs = ref_page.items
                except Exception as e:
                    logger.warning(f"S2 references error: {e}")
                try:
                    cite_page = await self.s2_provider.get_citations(origin_paper.semantic_scholar_id, limit=30)
                    raw_cites = cite_page.items
                except Exception as e:
                    logger.warning(f"S2 citations error: {e}")
                try:
                    raw_recs = await self.s2_provider.get_recommendations(origin_paper.semantic_scholar_id, limit=20)
                except Exception as e:
                    logger.warning(f"S2 recommendations error: {e}")
            
            # Fallback to OpenAlex if S2 returned completely empty pools
            if not raw_refs and not raw_cites and self.openalex_provider and getattr(origin_paper, 'open_alex_id', None):
                try:
                    oa_ref_page = await self.openalex_provider.get_references(origin_paper.open_alex_id, limit=30)
                    raw_refs = oa_ref_page.items
                except Exception as e:
                    logger.warning(f"OA references error: {e}")
                try:
                    oa_cite_page = await self.openalex_provider.get_citations(origin_paper.open_alex_id, limit=30)
                    raw_cites = oa_cite_page.items
                except Exception as e:
                    logger.warning(f"OA citations error: {e}")

            if not raw_refs and not raw_cites and not raw_recs:
                job.warnings.append(
                    GraphWarning(
                        code="candidate_generation_warning",
                        message="Candidate retrieval encountered partial failure across providers.",
                        severity="warning",
                    )
                )

            # Stage 4: Pre-Ranking & Quota Retention
            await self._update_stage(job, GraphJobStatus.PRE_RANKING, 0.25)
            retained_candidates = self.candidate_generator.process_raw_candidates(
                origin=origin_paper,
                raw_references=raw_refs,
                raw_citations=raw_cites,
                raw_recommendations=raw_recs,
            )

            # Never fabricate candidates. An empty pool means the graph is honestly
            # impossible for this origin right now — fail with a clear message instead
            # of showing invented papers as real related work.
            if not retained_candidates:
                raise ValueError(
                    "No candidate papers could be retrieved for this origin. "
                    "The paper may lack references/citations in upstream providers, "
                    "or providers may be unavailable."
                )

            metrics.record_candidate_pool_size(len(retained_candidates))

            # Stage 5: Enriching Metadata
            await self._update_stage(job, GraphJobStatus.ENRICHING_METADATA, 0.35)
            # Stage 6: Enriching References
            await self._update_stage(job, GraphJobStatus.ENRICHING_REFERENCES, 0.45)
            # Stage 7: Computing WBC
            await self._update_stage(job, GraphJobStatus.COMPUTING_WBC, 0.55)
            # Stage 8: Enriching Citations
            await self._update_stage(job, GraphJobStatus.ENRICHING_CITATIONS, 0.65)
            # Stage 9: Computing NCC
            await self._update_stage(job, GraphJobStatus.COMPUTING_NCC, 0.75)

            enrichment_result = await self.enrichment_pipeline.run(origin_paper, retained_candidates)
            job.warnings.extend(enrichment_result.warnings)
            if enrichment_result.data_completeness:
                dc = enrichment_result.data_completeness
                # DataCompleteness carries per-dimension ratios, not a single
                # score — record the mean across its four dimensions.
                metrics.record_enrichment_completeness(
                    (dc.metadata + dc.references + dc.citations + dc.semantic) / 4.0
                )

            # Stage 10: Computing Final Scores
            await self._update_stage(job, GraphJobStatus.COMPUTING_FINAL_SCORES, 0.85)
            ranking_result = self.ranking_engine.rank_candidates(
                origin=origin_paper,
                candidates=enrichment_result.candidates,
            )

            for cand in ranking_result.ranked_candidates:
                if cand.confidence:
                    metrics.record_confidence(cand.confidence.value)

            # Stage 11: Extracting Prior Works
            await self._update_stage(job, GraphJobStatus.EXTRACTING_PRIOR_WORKS, 0.88)
            # Stage 12: Extracting Derivative Works
            await self._update_stage(job, GraphJobStatus.EXTRACTING_DERIVATIVE_WORKS, 0.92)

            # Stage 13: Building Layout
            await self._update_stage(job, GraphJobStatus.BUILDING_LAYOUT, 0.96)
            snapshot = self.graph_synthesizer.synthesize_snapshot(
                origin=origin_paper,
                ranking_result=ranking_result,
                graph_id=job.job_id,
                max_nodes=request.max_nodes,
                data_completeness=enrichment_result.data_completeness,
                warnings=job.warnings,
            )

            # Stage 14: Completed or Partial
            job.result = snapshot
            final_status = snapshot.status  # COMPLETED or PARTIAL
            job.status = final_status
            job.current_stage = final_status
            job.progress = 1.0
            job.updated_at = datetime.now(timezone.utc)
            duration = time.monotonic() - pipeline_start
            metrics.record_job_duration(duration)
            logger.info(f"Graph job {job.job_id} finished successfully with status {final_status} in {duration:.2f}s")

        except Exception as exc:
            duration = time.monotonic() - pipeline_start
            metrics.record_job_duration(duration)
            logger.error(f"Graph job {job.job_id} failed with unhandled exception: {exc}", exc_info=True)
            job.status = GraphJobStatus.FAILED
            job.current_stage = GraphJobStatus.FAILED
            job.error = str(exc)
            job.updated_at = datetime.now(timezone.utc)
