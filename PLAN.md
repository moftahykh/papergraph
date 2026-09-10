# PaperGraph — Antigravity Execution Plan

## Purpose

This document is the execution contract for building PaperGraph in small, verifiable stages. Antigravity must not attempt to build the entire product in one pass. Each phase must be implemented, tested, reviewed, and committed before the next phase begins.

## Non-Negotiable Architecture Rules

1. Flutter communicates only with the PaperGraph Backend.
2. Flutter must never call Semantic Scholar, OpenAlex, Crossref, or PubMed directly.
3. All external provider adapters and ranking algorithms live in the FastAPI backend.
4. Flutter uses `flutter_bloc`/Cubit only. Do not add Provider or GetX.
5. Every external paper is normalized into `CanonicalPaper` before ranking.
6. WBC and NCC signals are nullable and have explicit availability states.
7. WBC and NCC are calculated only after their required enrichment has completed.
8. Missing metric weights are renormalized proportionally over available signals.
9. Citation edges and similarity edges are different relationship types.
10. Offline mode reads cached or pre-seeded data only. It must not call third-party APIs.
11. No secrets may be stored in Flutter, committed to Git, or exposed in API responses.
12. Do not claim a feature is complete until its acceptance criteria and tests pass.

## Target Repository Structure

```text
papergraph/
├── PLAN.md
├── README.md
├── .gitignore
├── docker-compose.yml
├── backend/
│   ├── app/
│   │   ├── api/v1/
│   │   ├── models/
│   │   ├── schemas/
│   │   ├── repositories/
│   │   ├── providers/
│   │   ├── resolution/
│   │   ├── candidates/
│   │   ├── ranking/
│   │   ├── graph/
│   │   ├── cache/
│   │   └── workers/
│   ├── tests/
│   ├── alembic/
│   ├── pyproject.toml
│   └── main.py
├── flutter_app/
│   ├── lib/
│   ├── test/
│   ├── pubspec.yaml
│   └── README.md
└── docs/
    ├── api-contract.md
    ├── ranking-spec.md
    └── decisions.md
```

## Phase 0 — Repository and Development Contract

### Goal

Create a clean monorepo and a repeatable local development environment.

### Antigravity tasks

1. Inspect the existing repository before changing anything.
2. Preserve existing user files unless they conflict with this plan.
3. Create `backend/`, `flutter_app/`, and `docs/` directories.
4. Create a root README explaining the system boundary.
5. Add `.gitignore` for Python, Flutter, IDE files, `.env`, secrets, build outputs, and local databases.
6. Add `docker-compose.yml` with PostgreSQL and Redis only.
7. Add `.env.example`; never create committed real credentials.
8. Create a basic backend health endpoint.
9. Create a basic Flutter app shell that can run without the backend.

### Verification

```bash
docker compose config
cd backend && python -m pytest
cd ../flutter_app && flutter analyze && flutter test
```

### Acceptance criteria

- PostgreSQL and Redis start locally.
- Backend health endpoint returns HTTP 200.
- Flutter starts successfully.
- No provider API key exists in source code.
- The repository contains this plan and a README.

### Commit

`chore: initialize PaperGraph monorepo and local services`

## Phase 1 — Domain Models and API Contracts

### Goal

Define stable internal models before implementing providers or UI.

### Backend tasks

1. Implement `CanonicalPaper` with provider IDs, metadata, references, citations, topics, provenance, and completeness.
2. Implement `MetricResult`:

```python
class MetricResult:
    value: float | None
    availability: Literal["available", "unavailable", "provider_error", "not_applicable"]
    reason: str | None
```

3. Implement graph models: `GraphNode`, `GraphEdge`, `GraphSnapshot`, `GraphJob`.
4. Define `GraphJobStatus` exactly:

```text
queued
resolving_origin
generating_candidates
pre_ranking
enriching_metadata
enriching_references
computing_wbc
enriching_citations
computing_ncc
computing_final_scores
extracting_prior_works
extracting_derivative_works
building_layout
completed
partial
failed
```

5. Add Pydantic schemas for:
   - `GET /api/v1/search`
   - `POST /api/v1/papers/resolve`
   - `POST /api/v1/graphs`
   - `GET /api/v1/graphs/{id}`
   - `GET /api/v1/papers/{id}/details`
6. Document all contracts in `docs/api-contract.md`.

### Flutter tasks

1. Create equivalent immutable display models.
2. Create API response parsers.
3. Do not implement provider logic in Flutter.

### Verification

```bash
cd backend && python -m pytest backend/tests/test_schemas.py
cd ../flutter_app && flutter analyze && flutter test
```

### Acceptance criteria

- Backend schemas validate valid and invalid payloads.
- `null` metrics are distinguishable from zero metrics.
- Graph payload includes warnings and data completeness for partial results.
- API contracts are documented before endpoint implementation.

### Commit

`feat: define canonical paper and graph API contracts`

## Phase 2 — Provider Adapters

### Goal

Implement isolated, testable adapters for academic providers.

### Tasks

1. Create a common provider interface:

```python
class AcademicProvider(Protocol):
    async def search(self, query: str, limit: int) -> list[RawPaper]: ...
    async def resolve(self, identifier: str) -> RawPaper | None: ...
    async def get_details(self, provider_id: str) -> RawPaper | None: ...
    async def get_references(self, provider_id: str, cursor: str | None) -> Page[RawPaper]: ...
    async def get_citations(self, provider_id: str, cursor: str | None) -> Page[RawPaper]: ...
```

2. Implement `crossref.py` for DOI resolution and metadata search.
3. Implement `semantic_scholar.py` for search, details, recommendations, references, citations, and batch metadata.
4. Implement `openalex.py` for metadata and fallback graph data.
5. Implement `pubmed.py` with `ESearch -> EFetch` for biomedical queries.
6. Put all provider keys and contact emails in environment variables.
7. Add per-provider timeout, retry, cache, and configurable rate limiter.
8. Respect provider pagination. Never assume one response contains the complete graph.
9. Add mocked tests; tests must not call live providers by default.
10. Add an optional manual integration test command guarded by environment variables.

### Required provider behavior

- HTTP 429: honor `Retry-After` when present, otherwise bounded exponential backoff.
- HTTP 5xx/timeouts: bounded retry.
- HTTP 4xx: classify and avoid blind retry.
- Empty result: return an empty result with provenance, not an exception.
- Provider failure: return a typed provider error.

### Verification

```bash
cd backend && python -m pytest backend/tests/providers -q
```

### Acceptance criteria

- Each adapter can be tested with fixtures.
- No provider code appears under `flutter_app/`.
- Provider responses are normalized into raw models and then `CanonicalPaper`.
- Cross-provider provenance is preserved.

### Commit

`feat: add isolated academic provider adapters`

## Phase 3 — Identity Resolution and Deduplication

### Goal

Ensure one real paper becomes one canonical record.

### Tasks

1. Normalize DOI forms to lowercase bare DOI without URL wrappers.
2. Normalize PMID and provider IDs with explicit prefixes.
3. Implement identity priority:

```text
exact DOI
exact PMID
exact provider identifier
normalized title + first author + year
fuzzy title matching
manual disambiguation
```

4. Merge metadata without overwriting better existing values with nulls.
5. Track source provenance and field-level completeness.
6. Add deterministic tests for duplicates and near-duplicates.

### Acceptance criteria

- DOI URL, `doi:...`, and bare DOI resolve to the same record.
- The same work found in four providers creates one canonical paper.
- Ambiguous title results are returned to the client instead of being silently selected.

### Commit

`feat: implement canonical identity resolution and deduplication`

## Phase 4 — Candidate Generation and PreScore

### Goal

Generate a bounded candidate pool without early bias toward highly cited papers.

### Candidate sources

```text
origin references
origin citations
Semantic Scholar recommendations
OpenAlex related works
PubMed results for biomedical searches
```

### Tasks

1. Generate an initial pool of 100–150 candidates.
2. Deduplicate and remove the origin.
3. Compute nullable pre-ranking signals:
   - semantic candidate score
   - direct relation
   - topic/title relevance
   - recency
   - metadata quality
4. Apply proportional renormalization to PreScore if a pre-signal is unavailable.
5. Retain candidates using:

```text
Top 50 by PreScore
+ Top 10 direct references
+ Top 10 direct citations
+ Top 10 recommendation results
```

6. Deduplicate again and cap at 80.
7. Store the reason each candidate survived.

### PreScore acceptance tests

- A candidate without a semantic score is not treated as semantic score zero automatically.
- A low-citation direct reference can survive quota retention.
- A recommendation result can survive even if its citation count is low.
- The origin never appears in the retained candidate set.

### Commit

`feat: add bounded candidate generation and quota retention`

## Phase 5 — Enrichment Pipeline

### Goal

Fetch only the data required at each stage and make partial data explicit.

### Tasks

1. Batch-enrich metadata for 60–80 retained candidates.
2. Fetch outbound references for up to 60 candidates with provider-specific pagination.
3. Compute WBC after reference enrichment.
4. Select the top 30 candidates for inbound citation enrichment.
5. Fetch citing IDs with pagination and bounded limits.
6. Compute NCC after citation enrichment.
7. Store enrichment status for every candidate and metric.
8. Cache raw provider responses with explicit TTLs.

### Important rule

Do not claim that references or citations are complete unless all required pages were retrieved successfully. Mark partial data as partial.

### Acceptance criteria

- API limits are respected.
- Duplicate reference requests are collapsed.
- A failed provider does not crash the whole graph job.
- Graph jobs can complete as `partial` with warnings.

### Commit

`feat: implement staged metadata reference and citation enrichment`

## Phase 6 — Safe Ranking Engine

### Goal

Implement deterministic, safe, explainable ranking.

### WBC

```text
if references_not_loaded:
    value = null
    availability = unavailable
elif provider_error:
    value = null
    availability = provider_error
elif both reference sets are loaded:
    denominator = sqrt(sum_a * sum_b) + 1e-8
    value = numerator / denominator
```

Clamp final metric values to `[0, 1]` after numerical validation.

### NCC

```text
if citing sets are unavailable:
    value = null
else:
    denominator = sqrt(len(citing_a) * len(citing_b) + 1e-8)
    value = intersection / denominator
```

### FinalScore

Use baseline weights:

```text
semantic = 0.35
wbc      = 0.30
ncc      = 0.20
direct   = 0.15
```

For available signal set `A`:

```text
available_weight_sum = sum(original_weight[i] for i in A)
normalized_weight[i] = original_weight[i] / available_weight_sum
final_score = sum(normalized_weight[i] * score[i] for i in A)
```

If zero signals are available, return `insufficient_data`. If one signal is available, return low confidence.

### Confidence

```text
3+ available signals = high
2 available signals  = medium
1 available signal   = low
0 available signals  = insufficient
```

### PriorScore

Normalize frequency and influence before multiplication:

```text
frequency_norm = frequency / (max_frequency + epsilon)
influence_norm = log1p(citations) / (log1p(max_citations) + epsilon)
prior_score = frequency_norm * influence_norm * relevance
```

### DerivativeScore

Normalize every factor:

```text
overlap_ratio = overlap_count / network_size
recency = min(1.0, 1.0 / (1.0 + lambda * max(0, origin_year - paper_year)))
influence = log1p(citations) / (log1p(max_citations) + epsilon)
derivative_score = overlap_ratio * recency * influence
```

Require `overlap_count >= 2`.

### Acceptance tests

- WBC never returns NaN or infinity.
- NCC never returns NaN or infinity.
- Missing signals are not treated as zero.
- Renormalized weights sum to exactly 1 within tolerance.
- All scores are in `[0, 1]`.
- Prior and derivative scores are in `[0, 1]`.
- Ranking is deterministic for identical inputs.

### Commit

`feat: implement safe hybrid ranking with nullable signals`

## Phase 7 — MMR and Graph Synthesis

### Goal

Create an informative graph, not merely the highest-citation list.

### Tasks

1. Implement MMR with `lambda = 0.70`.
2. Select 30–50 final nodes, respecting `maxNodes`.
3. Create similarity edges from non-directional signals: semantic, WBC, and NCC.
4. Create citation edges separately with direction.
5. Never render similarity as an arrow.
6. Extract Prior and Derivative Works using normalized scores.
7. Add warnings and data-completeness metrics.
8. Generate layout server-side or in a worker.
9. Store `algorithmVersion`, `dataSnapshot`, score weights, and provider provenance.

### Acceptance criteria

- A similarity edge cannot be mistaken for a citation edge.
- Graph includes no duplicate nodes or self-edges.
- Partial data is visible in warnings.
- The graph is stable enough for Flutter rendering.

### Commit

`feat: synthesize diverse graph topology and relationship edges`

## Phase 8 — Backend API and Async Jobs

### Goal

Expose the engine through stable REST endpoints.

### Tasks

1. Implement search endpoint.
2. Implement paper resolve endpoint.
3. Implement asynchronous graph creation endpoint.
4. Implement graph polling endpoint.
5. Implement on-demand paper details endpoint.
6. Add idempotency for repeated graph requests with the same origin, options, and algorithm version.
7. Add authorization placeholder, even if authentication is deferred.
8. Add structured error responses.
9. Add OpenAPI documentation.

### Acceptance criteria

- `POST /graphs` returns a job ID quickly.
- Polling exposes typed lifecycle states.
- A failed stage produces a useful error code and warning.
- Repeating the same request can reuse a cached or active job.

### Commit

`feat: expose asynchronous PaperGraph backend API`

## Phase 9 — Flutter Client and Cubit State

### Goal

Build the client against the internal backend only.

### Tasks

1. Implement `PaperGraphApiClient` using Dio.
2. Implement SearchCubit.
3. Implement GraphCubit with polling and cancellation.
4. Implement PaperDetailsCubit.
5. Implement LibraryCubit using Hive.
6. Implement ThemeCubit.
7. Implement NotificationCubit.
8. Add loading, empty, error, partial, and offline states.
9. Add retry actions.
10. Keep all provider names and provider-specific IDs out of the UI where possible.

### Acceptance criteria

- Flutter can build a graph from a DOI through the backend.
- Flutter shows progress for each graph lifecycle stage.
- Partial graphs display warnings.
- Offline mode opens cached graphs and does not call third-party providers.

### Commit

`feat: add Flutter Cubit client for PaperGraph backend`

## Phase 10 — Graph UI and User Experience

### Goal

Render a readable, touch-friendly graph.

### Tasks

1. Add `CustomPainter` graph canvas.
2. Add pan and pinch zoom.
3. Add node selection and dragging.
4. Add distinct citation and similarity styles.
5. Add bottom sheet with Details, Prior Works, Derivative Works, and List View.
6. Add year legend.
7. Add node radius based on bounded logarithmic citation scale.
8. Add loading and empty states.
9. Test Arabic RTL and English LTR.
10. Test small screens and large text sizes.

### Acceptance criteria

- No overflow on supported screen sizes.
- Graph remains usable with 30–50 nodes.
- Node selection opens details without blocking the entire UI.
- Citation direction is visible.
- Similarity lines are not confused with citations.

### Commit

`feat: implement interactive literature graph UI`

## Phase 11 — Offline Cache and Local Notifications

### Goal

Provide reliable local access without pretending to provide full offline discovery.

### Tasks

1. Store graph snapshots with schema version, algorithm version, generated time, and expiration.
2. Store saved papers and notes in Hive.
3. Add local notification only when active polling or an approved background task observes completion.
4. Request notification permission contextually.
5. Do not claim that local notifications work reliably while the app is force-closed.

### Acceptance criteria

- Previously cached graphs open offline.
- Corrupt or old cache entries are handled safely.
- Notification permissions are not requested on first launch.
- No third-party provider calls occur in offline mode.

### Commit

`feat: add offline graph cache and contextual local notifications`

## Phase 12 — Tests, Security, Observability, and Release

### Tests

1. Unit tests for normalization and identity resolution.
2. Provider fixture tests.
3. WBC edge cases: empty, missing, provider error, no overlap, zero denominator.
4. NCC edge cases.
5. PreScore missing-signal tests.
6. Weight renormalization tests.
7. Prior/Derivative normalization tests.
8. MMR tests.
9. API contract tests.
10. Flutter Cubit tests.
11. Widget tests for loading, error, partial, and offline states.
12. Release build smoke test.

### Security

- Validate all user input.
- Keep provider keys server-side.
- Apply request size limits.
- Add backend rate limiting.
- Avoid logging abstracts or user notes unnecessarily.
- Add CORS restrictions for deployed environments.
- Add secret scanning to CI.

### Observability

Track:

```text
provider latency
provider errors
429 counts
cache hit ratio
graph job duration
candidate pool size
enrichment completeness
ranking confidence distribution
```

### Release verification

```bash
cd backend && python -m pytest
cd ../flutter_app && flutter analyze
cd ../flutter_app && flutter test
cd ../flutter_app && flutter build apk --release
```

### Acceptance criteria

- All automated tests pass.
- No analyzer errors.
- Release APK builds.
- Provider secrets are absent from the app bundle.
- Documentation matches the implementation.
- University rubric items are marked verified only after actual demonstration.

### Commit

`release: verify PaperGraph MVP and production safeguards`

# How to Instruct Antigravity

Use the following master prompt at the beginning of the project:

```text
You are the implementation agent for PaperGraph. Read PLAN.md completely before modifying files. Build the system phase by phase. Do not skip phases, combine unrelated phases, or claim completion without running the listed verification commands. Follow these rules strictly:

1. Flutter communicates only with the PaperGraph FastAPI backend.
2. Never place Semantic Scholar, OpenAlex, Crossref, or PubMed API calls in Flutter.
3. Keep provider adapters and ranking algorithms in backend/app only.
4. Use flutter_bloc/Cubit only.
5. Normalize all papers into CanonicalPaper.
6. Treat missing metric data as null with an availability state, never as zero.
7. Add epsilon protection to WBC and NCC.
8. Renormalize weights proportionally over available signals.
9. Keep similarity and citation edges separate.
10. Use mocks/fixtures for tests; never require live API access for the default test suite.
11. Do not expose secrets or commit .env files.
12. After every phase, report: files changed, tests run, results, known limitations, and the commit message.

Start with Phase 0 only. Inspect the repository first, then implement Phase 0, run its verification commands, and stop for review.
```

# How to Run Antigravity Phase by Phase

After Phase 0 is verified, send one prompt per phase:

```text
Read PLAN.md. Implement Phase 1 only. Do not begin Phase 2. Inspect existing code first, implement the phase, run every verification command listed for Phase 1, fix failures, and report changed files, test output summary, acceptance criteria status, and remaining limitations.
```

Replace `Phase 1` with the desired phase number. Use the same pattern for every phase.

# Required Antigravity Report Format

At the end of every phase, require this exact structure:

```text
## Phase Report

### Implemented
- ...

### Files Changed
- ...

### Verification Commands
- `...`

### Verification Results
- PASS/FAIL: ...

### Acceptance Criteria
- [x] ...
- [ ] ...

### Known Limitations
- ...

### Recommended Next Phase
- ...
```

# Rules for Handling Blockers

Antigravity must stop and report instead of guessing when:

- A required credential is missing.
- A provider contract is ambiguous.
- An existing file conflicts with this architecture.
- A database migration would delete or alter user data.
- A package is incompatible with the installed Flutter/Python version.
- A test requires network access but no fixture exists.
- A requested feature would put provider credentials in Flutter.

For ordinary implementation choices, choose the least complex reversible option and document the decision in `docs/decisions.md`.

# Definition of Done for MVP

The MVP is complete only when this path works end to end:

```text
Flutter input DOI/title
→ backend resolves CanonicalPaper
→ backend generates bounded candidates
→ backend applies PreScore and quotas
→ backend enriches references/citations
→ backend computes safe WBC/NCC/final score
→ backend returns graph topology
→ Flutter renders graph
→ user opens paper details
→ graph can be cached and reopened offline
```

The following are not required for MVP completion:

- Full SPECTER/SciBERT vector database.
- Push notifications.
- Saved-topic monitoring.
- Cloud account synchronization.
- Full local Semantic Scholar datasets.
- PDF annotation synchronization.
