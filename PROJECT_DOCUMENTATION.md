# 📄 PaperGraph — System Architecture & Technical Specification
## Multi-Source Academic Discovery Engine with Hybrid Similarity Ranking & Interactive Literature Graph

> **Document Version:** 4.2 (Implementation Ready Specification)  
> **System Classification:** Distributed Academic Knowledge Graph with Progressive Mobile Rendering  
> **Target Framework:** Flutter 3.44+ / Dart 3.12+ (Android / iOS / Web)  
> **Backend Framework:** FastAPI (Python 3.11+) • PostgreSQL • Redis • Background Workers (Celery / RQ)  
> **Core Architecture:** Client-Orchestrator Pattern • Feature-Scoped BLoC/Cubit State Machines • Multi-Stage Candidate Enrichment Funnel • Epsilon-Protected Hybrid Ranking (WBC + NCC + Embeddings) • Mathematical Weight Renormalization • Two-Tier Notification Architecture  

---

## 1. Final Technology Decisions

| Layer | Decision | Architectural Rationale |
|---|---|---|
| **Mobile client** | **Flutter (Dart 3.12+)** | Cross-platform, high-performance 60fps canvas rendering, rich touch interactivity. |
| **State management** | **`flutter_bloc` / Cubit only** | Strict unidirectional data flow, testable discrete states, no overlapping state mutations. |
| **Backend** | **FastAPI (Python)** | High-throughput asynchronous REST API, native Pydantic validation, scientific library integration. |
| **Primary database** | **PostgreSQL** | Relational integrity for users, saved graphs, paper metadata, and graph snapshots. |
| **Cache & rate limiting** | **Redis** | Sub-millisecond response caching, provider token-bucket rate limiters, session tracking. |
| **Background jobs** | **Celery / RQ / FastAPI Workers** | Non-blocking async graph synthesis, candidate enrichment pipelines, scheduled topic monitors. |
| **Local mobile cache** | **Hive (NoSQL)** | Embedded binary key-value storage for offline graph viewing, reading lists, and personal notes. |
| **Graph renderer** | **Flutter `CustomPainter` + `InteractiveViewer`** | Smooth hardware-accelerated 2D canvas with pan, pinch-zoom, dynamic node halos, and edge styling. |
| **Academic providers** | **Semantic Scholar, OpenAlex, Crossref, PubMed** | Multi-source academic coverage spanning computer science, biomedicine, and multidisciplinary DOI registries. |
| **Local notifications** | **`flutter_local_notifications`** | Device-side reminders and foreground/polled graph completion alerts without server roundtrip. |
| **Push notifications** | **Firebase Cloud Messaging (FCM)** | Phase 2 topic monitoring and literature update push alerts when app is closed. |
| **Vector search** | **`pgvector` or Qdrant** | Phase 2 semantic abstract embedding storage and ANN similarity queries. |

> [!IMPORTANT]
> **Architectural Isolation Mandate:**  
> **Flutter communicates only with the PaperGraph Backend.**  
> **Offline mode supports previously cached and pre-seeded graphs only.**  
> **No third-party provider calls or external discovery logic run inside Flutter.** All external provider requests, candidate generation, and mathematical ranking logic run strictly within the backend.

---

## 2. Final System Architecture

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                             FLUTTER CLIENT                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐  │
│  │ Splash Screen│  │  Search View │  │ Graph Canvas │  │  Library (Hive) │  │
│  │ (Custom Paint│  │ (URL / Title)│  │ (Force-      │  │ (Offline Vault  │  │
│  │   Animation) │  │              │  │  Directed)   │  │   & Notes)      │  │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └────────┬────────┘  │
│         │                 │                 │                   │           │
│         ▼                 ▼                 ▼                   ▼           │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                FEATURE-SCOPED STATE (BLoC / Cubit)                    │  │
│  │   SearchCubit • GraphCubit • PaperDetailsCubit • LibraryCubit        │  │
│  │   ThemeCubit • NotificationCubit                                      │  │
│  └──────────────────────────────────┬────────────────────────────────────┘  │
│                                     │                                       │
│                                     ▼                                       │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                     PaperGraphApiClient Contract                      │  │
│  │  (HTTP Client -> Backend) OR (OfflineFallbackService -> Hive/Seed)   │  │
│  └──────────────────────────────────┬────────────────────────────────────┘  │
└─────────────────────────────────────┼───────────────────────────────────────┘
                                      │ HTTPS / JSON Contract
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          PAPERGRAPH BACKEND (FastAPI)                       │
│  ┌─────────────────────────┐  ┌──────────────────────────────────────────┐  │
│  │ Search & Resolution     │  │ Candidate Generation & Pre-Ranking       │  │
│  │ - Identifier Resolution │  │ - Multi-Provider Aggregator              │  │
│  │ - Title Match Scoring   │  │ - Renormalized PreScore Quota Retention  │  │
│  └────────────┬────────────┘  └────────────────────┬─────────────────────┘  │
│               │                                    │                        │
│               ▼                                    ▼                        │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │ Safe Hybrid Ranking & Topology Synthesis                              │  │
│  │ - Batch Metadata & Paginated Reference Enrichment (Top 60)            │  │
│  │ - Epsilon-Protected Local IDF WBC ($S_{WBC}$)                         │  │
│  │ - Paginated Inbound Citation Enrichment & Safe NCC ($S_{NCC}$)        │  │
│  │ - Mathematical Weight Renormalization & Confidence Reporting          │  │
│  │ - MMR Diversity Pruning (30–50 Nodes)                                 │  │
│  │ - Normalized Prior & Derivative Works Extraction                      │  │
│  │ - Damped Force-Directed Layout Generator                              │  │
│  └──────────────────────────────────┬────────────────────────────────────┘  │
│                                     │                                       │
│                                     ▼                                       │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │ Cache, Persistence & Workers                                          │  │
│  │ - PostgreSQL (Primary DB) • Redis (Cache & Token Bucket Limiting)     │  │
│  │ - Background Task Workers (Celery / RQ)                               │  │
│  └──────────────────────────────────┬────────────────────────────────────┘  │
└─────────────────────────────────────┼───────────────────────────────────────┘
                                      │
              ┌───────────────────────┼───────────────────────┐
              ▼                       ▼                       ▼
    ┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐
    │ Semantic Scholar │    │     OpenAlex     │    │     Crossref     │
    │ (Graph & Recs)   │    │  (Broad Coverage)│    │  (DOI Registry)  │
    └──────────────────┘    └──────────────────┘    └──────────────────┘
                                      │
                                      ▼
                            ┌──────────────────┐
                            │ PubMed / E-Util  │
                            │   (Biomedical)   │
                            └──────────────────┘
```

---

## 3. Provider Responsibilities & Ingestion Policies

### 3.1 Semantic Scholar
* **Primary Scope:** Paper search, paper details, direct references, inbound citations, recommendations API, citation counts, and semantic candidate generation.
* **Usage Policy:**
  * Utilize an authenticated API key.
  * Enforce configurable rate limiting (`SEMANTIC_SCHOLAR_RPS=1` default, configurable via environment).
  * Read and honor `Retry-After` response headers when HTTP 429 occurs.
  * Do not hardcode an undocumented global quota.
  * Prefer batch paper-detail endpoints for metadata, and paginated endpoints for citations/references.
  * Cache payloads in Redis with a 7-day TTL.

### 3.2 OpenAlex
* **Primary Scope:** Broad academic coverage across all scientific disciplines, work metadata, topic/concept hierarchy, fallback citation/reference graphs, and cross-provider identity reconciliation.
* **Usage Policy:** Include `mailto` parameter in polite pool, enforce configurable rate limiting (`OPENALEX_RPS`), request specific `select` fields, and utilize cursor pagination.

### 3.3 Crossref
* **Primary Scope:** Canonical DOI resolution, publisher-verified bibliographic metadata, journal and volume data, license and relation metadata, and fallback bibliographic title search.
* **Usage Policy:** Use descriptive User-Agent with contact email, filter by `select`, handle HTTP 403 and 429. Cache DOI metadata with a long TTL (such as **30–90 days**) with support for explicit refresh or version invalidation. Crossref is **not** used as the primary recommendation or citation-network engine.

### 3.4 PubMed / NCBI E-utilities
* **Primary Scope:** Dedicated biomedical and life sciences literature, PMID resolution, structured medical abstracts, MeSH terms, and clinical publication types.
* **Workflow:** Two-stage retrieval pipeline with configurable rate limits (`PUBMED_RPS=3` unauth / `10` auth):
  ```text
  User Query / PMID ──> ESearch (returns ID list) ──> EFetch (retrieves detailed XML/JSON records)
  ```

---

## 4. Canonical Paper Model & Identity Resolution Priority

### 4.1 Canonical Paper Schema
All raw provider responses are normalized into a single canonical entity before entering the ranking or graph synthesis pipeline:

```json
{
  "canonicalId": "doi:10.1038/example",
  "doi": "10.1038/example",
  "pmid": null,
  "semanticScholarId": "abc123456789",
  "openAlexId": "https://openalex.org/W123456789",
  "title": "Example Paper on Distributed Systems",
  "normalizedTitle": "example paper on distributed systems",
  "authors": [
    {
      "id": "author_1",
      "name": "Leslie Lamport",
      "position": 1
    }
  ],
  "year": 2020,
  "venue": "Nature",
  "abstract": "Normalized text abstract of the paper...",
  "citationCount": 100,
  "referenceIds": ["doi:10.1145/1", "doi:10.1145/2"],
  "citationIds": ["doi:10.1145/3", "doi:10.1145/4"],
  "topics": ["Computer Science", "Distributed Computing"],
  "sourceAvailability": {
    "semanticScholar": true,
    "openAlex": true,
    "crossref": true,
    "pubmed": false
  }
}
```

### 4.2 Identity Resolution Priority
To eliminate duplicate nodes representing the same paper across multiple academic providers:
1. **Exact DOI Match:** Canonical identifier prefix (`doi:...`).
2. **Exact PMID Match:** Canonical identifier prefix (`pmid:...`).
3. **Exact Provider Identifier:** OpenAlex ID or Semantic Scholar Corpus ID.
4. **Normalized Title + First Author Surname + Year:** Deterministic hash match.
5. **Fuzzy Title Matching:** Token Sort Ratio $\ge 92\%$ + Levenshtein distance check.
6. **Manual Disambiguation:** Prompt researcher with disambiguation candidate list when confidence $< 0.85$.

---

## 5. End-to-End Discovery Pipeline (16 Stages)

```text
Stage 1: Normalize input (Strip whitespace, extract DOI/URL/PMID/title)
        ↓
Stage 2: Resolve origin paper (Query priority: Crossref -> Semantic Scholar -> OpenAlex)
        ↓
Stage 3: Disambiguate title results (If query is text title with multiple candidates)
        ↓
Stage 4: Generate bounded candidate pool (~120 raw papers from references, citations, recs)
        ↓
Stage 5: Calculate fast PreScore (Lightweight pre-ranking with missing-signal renormalization)
        ↓
Stage 6: Apply quota-based candidate retention (Select Top 80 diverse papers)
        ↓
Stage 7: Batch metadata enrichment (Fetch title, year, citations, authors for Top 80)
        ↓
Stage 8: Paginated reference enrichment (Fetch outbound reference IDs strictly for Top 60)
        ↓
Stage 9: Calculate WBC (Local IDF-weighted bibliographic coupling with epsilon)
        ↓
Stage 10: Paginated citation enrichment (Fetch inbound citing IDs strictly for Top 30)
        ↓
Stage 11: Calculate NCC (Normalized co-citation with epsilon)
        ↓
Stage 12: Calculate final hybrid score (Apply dynamic profile weights + renormalization)
        ↓
Stage 13: Apply diversity-aware selection (MMR pruning to final 30–50 nodes)
        ↓
Stage 14: Extract Prior and Derivative Works (Normalized frequency, recency, influence in [0,1])
        ↓
Stage 15: Generate graph layout (Damped Fruchterman-Reingold force-directed physics)
        ↓
Stage 16: Return progressive graph response (Phase 1 lightweight topology < 45 KB)
```

---

## 6. Bounded Candidate Generation

The candidate pool is constructed from multiple discovery vectors to avoid citation-count bias:

```text
Candidates =
    References(origin)
  ∪ Citations(origin)
  ∪ Recommendations(origin)
  ∪ OpenAlex Related Works
  ∪ PubMed Search Results (for biomedical queries)
```

### Ingestion Constraints:
* **Target Size:** Initial raw pool bounded to **100–150 candidates** (typical target: ~120).
* **Provider Safeguards:** Strict `limit` parameters, pagination thresholds, field projections, pre-lookup in Redis cache, and batch endpoints.
* **Anti-Bias Rule:** Candidates are never selected solely by citation count; fresh and niche papers survive through recommendation and reference vectors.

---

## 7. Fast Pre-Ranking Before Enrichment (With Renormalization)

Because full reference and citation enrichment is computationally expensive and subject to API rate limits, WBC and NCC cannot be evaluated at this initial stage. The initial ranking uses exclusively fast, zero-enrichment signals:

$$\mathbf{PreScore}(P) = \sum_{i \in A_{\text{pre}}} w'_{i,\text{pre}} S_i$$

### Baseline PreScore Signals & Weights:
* $S_{\text{semantic-candidate}}$ ($w_1 = 0.50$): Ordinal position or relevance score from recommendation engine or semantic search.
* $S_{\text{direct}}$ ($w_2 = 0.20$): Direct bibliographic link to origin ($1.0$ if origin cites $P$, $0.8$ if $P$ cites origin, $0.0$ otherwise).
* $S_{\text{topic/title}}$ ($w_3 = 0.15$): Lexical topic overlap and token match score against origin title.
* $S_{\text{recency}}$ ($w_4 = 0.10$): Gaussian proximity function centered around origin paper publication year.
* $S_{\text{metadata-quality}}$ ($w_5 = 0.05$): Completeness of bibliographic fields (abstract present, DOI verified, venue indexed).

> [!IMPORTANT]
> **PreScore Missing-Signal Handling:**  
> PreScore components are nullable. If the semantic candidate score (or any component signal) is unavailable (e.g., candidate retrieved from Crossref, PubMed, or citation endpoints lacking a semantic score), PreScore weights are **proportionally renormalized** over the available pre-ranking signals:
> $$w'_{i,\text{pre}} = \frac{w_i}{\sum_{j \in A_{\text{pre}}} w_j}$$
> A missing semantic score must **never** be treated as zero, preventing systematic penalization of non-semantic provider candidates.

---

## 8. Quota-Based Candidate Retention

To prevent popular high-citation papers from crowding out foundational niche papers, candidate retention utilizes a **multi-bucket quota strategy**:

```text
EnrichmentPool =
    Top 50 by PreScore
  ∪ Top 10 direct references (Origin -> Paper)
  ∪ Top 10 direct citations  (Paper -> Origin)
  ∪ Top 10 recommendation results (Semantic Scholar / OpenAlex)
```

### Filtering & Pruning Rules:
1. Deduplicate by canonical ID.
2. Remove origin seed paper $P_0$.
3. Remove records lacking title or valid author metadata.
4. Bound the enriched pool to a maximum of **60–80 papers**.

### Universe Scale Parameters:
* **Initial Candidate Pool:** $100 - 150$ candidates.
* **Deep Enrichment Pool:** $60 - 80$ candidates.
* **Final Graph Nodes:** $30 - 50$ nodes.
* **Maximum Initial Graph Cap:** $75$ nodes.

---

## 9. Staged Reference & Citation Enrichment Policy

```text
120 Raw Candidates
        ↓  (Calculate fast PreScore with weight renormalization)
60–80 Candidates
        ↓  (Batch metadata enrichment: titles, authors, citations, years)
Top 60 Candidates
        ↓  (Paginated reference enrichment: Outbound reference IDs for WBC)
Top 30 Candidates
        ↓  (Paginated citation enrichment: Inbound citing IDs for NCC)
Final 30–50 Nodes
```

* **Batch Metadata Endpoints:** Use batch paper-detail endpoints for metadata where supported.
* **Paginated Relationship Endpoints:** Use provider-specific paginated references and citations endpoints for relationship data. Never assume that one batch response contains the complete reference or citation set.
* **Cache Strategy:** Cached in Redis with a 7-day TTL.
* **Deduplication:** Repeated reference IDs across candidates are fetched in a single unified request.

---

## 10. Final Hybrid Similarity Model

All constituent metric scores are strictly bounded in the range $[0, 1]$:

$$\mathbf{FinalScore}(A, B) = w_s S_{\text{semantic}} + w_b S_{\text{WBC}} + w_c S_{\text{NCC}} + w_d S_{\text{direct}}$$

### Standard Default Weights:
* $w_s = 0.35$ (Semantic Similarity / Embeddings)
* $w_b = 0.30$ (Local IDF-Weighted Bibliographic Coupling)
* $w_c = 0.20$ (Normalized Co-Citation Matrix)
* $w_d = 0.15$ (Direct Citation Signal)

$$\sum_{i \in \{s, b, c, d\}} w_i = 1.0$$

* **Co-authorship Signal:** Excluded as shared authorship is empirically a weak indicator of true conceptual similarity.

---

## 11. Safe WBC Formula with Epsilon Protection

Bibliographic Coupling calculates shared references between papers $A$ and $B$, weighted by the specificity of the cited work using **Local Graph Inverse Document Frequency (IDF)**:

$$S_{\text{WBC}}(A, B) = \frac{\sum_{r \in \text{Refs}(A) \cap \text{Refs}(B)} \text{IDF}_{\text{local}}(r)}{\sqrt{\left(\sum_{r_a \in \text{Refs}(A)} \text{IDF}_{\text{local}}(r_a)\right) \cdot \left(\sum_{r_b \in \text{Refs}(B)} \text{IDF}_{\text{local}}(r_b)\right)} + \epsilon}$$

Where:
* $\epsilon = 10^{-8}$ is added to the denominator **after** computing the square root to guarantee prevention of division by zero.
* $\text{IDF}_{\text{local}}(r) = \ln\left(1 + \frac{N_{\text{candidates}}}{\text{df}_{\text{candidates}}(r) + 1}\right)$.

### WBC Data & Availability Rules:
| Condition | Evaluated Value | Signal Availability | Semantic Meaning |
|---|:---:|:---:|---|
| Both reference lists loaded and non-empty | Calculated score $\in [0, 1]$ | `available` | Evaluated coupling score. |
| Both lists loaded, but zero shared references | `0.0` | `available` | Evaluated, no overlap found. |
| One or both papers genuinely cite 0 papers | `0.0` | `available` | `empty_reference_set`: Legitimate 0 references. |
| Reference payload not loaded yet | `null` | `unavailable` | `references_not_loaded`: Enrichment pending. |
| Provider request failed / timed out | `null` | `provider_error` | `references_provider_error`: Network/API failure. |

> [!CAUTION]
> A missing or unloaded reference list must **never** be interpreted as `0.0` similarity. It must be explicitly marked `null` with state `unavailable`.

---

## 12. Safe Normalized Co-Citation (NCC) Formula with Epsilon Protection

Co-Citation measures how frequently papers $A$ and $B$ are cited together by third-party literature:

$$S_{\text{NCC}}(A, B) = \frac{|\text{Citing}(A) \cap \text{Citing}(B)|}{\sqrt{|\text{Citing}(A)| \cdot |\text{Citing}(B)| + \epsilon}}$$

Where:
* $\epsilon = 10^{-8}$ prevents division by zero when citing counts are zero.
* Availability rules identical to Section 11 apply (`empty_citation_set`, `citations_not_loaded`, `citations_provider_error`).

---

## 13. Missing Signal Handling & Availability Tracking

Every component metric is encapsulated as a typed object pairing its numeric value with an explicit availability state:

```json
{
  "value": null,
  "availability": "unavailable",
  "reason": "references_not_loaded"
}
```

### Semantic Distinction:
* `value = 0.0`: The signal was successfully evaluated and determined to have zero relationship.
* `value = null`: The signal could not be evaluated due to missing data or provider error.

### Supported Availability Enum:
* `available`: Metric evaluated successfully.
* `unavailable`: Data not yet loaded (e.g. progressive loading phase 1).
* `provider_error`: Upstream API returned 4xx/5xx or timed out.
* `not_applicable`: Metric not valid for this paper type (e.g. NCC on brand-new paper).

---

## 14. Mathematical Weight Renormalization

When one or more component signals are `unavailable` or `provider_error`, the remaining available signals have their weights **renormalized proportionally** so that their sum remains exactly $1.0$:

Let $A$ be the set of available signals:
$$A = \{i \mid S_i \text{ is available}\}, \quad W_A = \sum_{i \in A} w_i$$

The renormalized weights $w'_i$ are:
$$w'_i = \begin{cases} \frac{w_i}{W_A}, & i \in A \\ 0, & i \notin A \end{cases}$$

The composite score is then:
$$\mathbf{FinalScore} = \sum_{i \in A} w'_i S_i$$

### Concrete Example (NCC Unavailable):
Suppose $S_{\text{NCC}}$ is unavailable because inbound citations are pending enrichment:
* Original weights: $w_s = 0.35, w_b = 0.30, w_c = 0.20, w_d = 0.15$
* Available sum: $W_A = 0.35 + 0.30 + 0.15 = 0.80$
* Renormalized weights:
  * $w'_s = \frac{0.35}{0.80} = 0.4375$
  * $w'_b = \frac{0.30}{0.80} = 0.3750$
  * $w'_c = 0.0000$
  * $w'_d = \frac{0.15}{0.80} = 0.1875$
  * Sum: $0.4375 + 0.3750 + 0.1875 = 1.0000$

### Safety Bounds:
* If $|A| < 2$ (fewer than 2 signals available): `scoreConfidence = "low"`.
* If $|A| == 0$ (no signals available): $\mathbf{FinalScore} = \text{null}$, `status = "insufficient_data"`.

---

## 15. Confidence Level Reporting

Every node relationship reports an explicit confidence classification alongside its final score:

| Confidence Level | Requirement | Meaning |
|---|---|---|
| **`high`** | At least 3 signals available | Robust evaluation across semantic, coupling, and citations. |
| **`medium`** | Exactly 2 signals available | Acceptable evaluation (e.g. Semantic + WBC). |
| **`low`** | Exactly 1 signal available | Degraded evaluation; based on single source. |
| **`insufficient`** | 0 signals available | Score cannot be computed; paper flagged. |

### Canonical Reporting Payload (High Confidence Example: 3 Available Signals):
```json
{
  "targetPaperId": "doi:10.1186/s12879-017-2746-5",
  "finalScore": 0.7606,
  "confidence": "high",
  "availableSignals": ["semantic", "wbc", "direct"],
  "renormalizedWeights": {
    "semantic": 0.4375,
    "wbc": 0.3750,
    "ncc": 0.0,
    "direct": 0.1875
  }
}
```

---

## 16. Dynamic Weight Profiles

To maximize ranking fidelity across distinct paper archetypes, the orchestrator applies specialized baseline weight profiles:

| Profile | Target Category | Semantic ($w_s$) | WBC ($w_b$) | NCC ($w_c$) | Direct ($w_d$) |
|---|---|:---:|:---:|:---:|:---:|
| **New Paper** | Published within last 24 months | 0.50 | 0.30 | 0.05 | 0.15 |
| **Mature Paper** | Published $> 5$ years ago with $> 50$ citations | 0.20 | 0.35 | 0.30 | 0.15 |
| **Review Paper** | Survey/Meta-analysis with $> 100$ references | 0.25 | 0.50 | 0.10 | 0.15 |
| **Standard** | Default baseline | 0.35 | 0.30 | 0.20 | 0.15 |

* Proportional weight renormalization applies uniformly across all profiles.
* Applied profile and weights are persisted with the graph snapshot.

---

## 17. Normalized Prior Works Formulation ($\in [0, 1]$)

Prior Works represent foundational ancestors upon which the current research cluster is built:

$$\mathbf{PriorScore}(R) = \text{FrequencyNorm}(R) \times \text{InfluenceNorm}(R) \times \text{Relevance}(R) \in [0, 1]$$

Where:
* **Normalized Frequency:**
  $$\text{FrequencyNorm}(R) = \frac{\sum_{P \in \text{Network}} \mathbb{I}(R \in \text{Refs}(P))}{\max_{x \in \text{Candidates}} \text{Frequency}(x) + \epsilon}$$
* **Normalized Influence:**
  $$\text{InfluenceNorm}(R) = \frac{\ln(1 + \text{Citations}(R))}{\ln(1 + \text{MaxCitations}_{\text{corpus}}) + \epsilon}$$
* **Relevance:** Average semantic similarity to the top central cluster nodes: $\text{Relevance}(R) \in [0, 1]$.
* **Age Invariance:** Age is **not** penalized by default. Classic foundational literature (e.g. 1970s–1990s seminal algorithms) retains high priority.

---

## 18. Normalized Derivative Works Formulation ($\in [0, 1]$)

Derivative Works represent newer papers that synthesize and advance multiple works from the generated network:

$$\mathbf{DerivativeScore}(D) = \text{OverlapRatio}(D) \times \text{RecencyNorm}(D) \times \text{InfluenceNorm}(D) \in [0, 1]$$

Where:
* **Overlap Ratio:** $\text{OverlapRatio}(D) = \frac{|\text{Refs}(D) \cap \text{Network}|}{|\text{Network}|} \in [0, 1]$, with **mandatory minimum overlap:** $|\text{Refs}(D) \cap \text{Network}| \ge 2$.
* **Normalized Recency (Rewarding subsequent advances):**
  $$\text{RecencyNorm}(D) = \min\left(1.0, \frac{1}{1 + \lambda \cdot \max(0, \text{Year}_{\text{origin}} - \text{Year}(D))}\right) \in [0, 1]$$
* **Normalized Influence:**
  $$\text{InfluenceNorm}(D) = \frac{\ln(1 + \text{Citations}(D))}{\ln(1 + \text{MaxCitations}_{\text{corpus}}) + \epsilon} \in [0, 1]$$
* **Mandatory UI Disclaimer:** The presentation layer must explicitly display:  
  * *"Based on available indexed references across open academic providers."*

---

## 19. Diversity-Aware Final Selection (MMR)

To prevent the final 30–50 graph nodes from collapsing into an uninformative cluster of near-identical papers, Maximum Marginal Relevance (MMR) is applied:

$$\mathbf{MMR}(d) = \lambda \cdot \mathbf{FinalScore}(d, P_0) - (1 - \lambda) \max_{s \in \text{Selected}} \text{Sim}(d, s)$$

* **Balancing Factor:** $\lambda = 0.70$.
* Selection balances high composite similarity to the origin paper $P_0$ against conceptual diversity relative to already selected nodes.

---

## 20. Graph Visual Typology & Non-Directional Similarity Edges

Citation relationships and algorithmic similarity relationships are visually and semantically distinct:

| Element | Semantic Meaning | Weight Formula | Visual Styling | Interaction |
|---|---|---|---|---|
| **Similarity Edge** | Algorithmic relatedness ($S_{\text{WBC}}, S_{\text{NCC}}, S_{\text{semantic}}$) | $\text{renormalize}(w_s S_{\text{semantic}} + w_b S_{\text{WBC}} + w_c S_{\text{NCC}})$ | Transparent dashed line (`#06B6D4`, opacity $\propto \text{Score}$) | Tap displays similarity breakdown dialog |
| **Citation Edge** | Historical explicit citation ($A \to B$) | Discrete direct link ($A \text{ cites } B$) | Solid directed arrow (`#3B82F6`, width: 1.8 dp) | Tap highlights bibliographic citation context |
| **Origin Node** | User-selected seed paper ($P_0$) | Central anchor | Purple amethyst node with glowing halo (`#7C3AED`) | Fixed center / primary anchor |
| **Prior Work** | Foundational root paper | $\text{PriorScore} \in [0, 1]$ | Amber badge / warm golden border (`#F59E0B`) | Opens foundational works bottom sheet |
| **Derivative Work** | Subsequent advance paper | $\text{DerivativeScore} \in [0, 1]$ | Emerald green badge (`#10B981`) | Opens derivative advances bottom sheet |

> [!IMPORTANT]
> **Edge Decoupling Rule:**  
> Similarity edges are generated strictly from available **non-directional similarity signals** (semantic, WBC, NCC) and **exclude direct citation directionality**. Direct citations are rendered exclusively as separate, solid directed citation arrows.

---

## 21. Backend REST API Specification

### 21.1 Live Search Endpoint
```http
GET /api/v1/search?q={query}&limit=10
```

### 21.2 Origin Resolution Endpoint
```http
POST /api/v1/papers/resolve
Content-Type: application/json

{
  "input": "10.1186/s12879-017-2746-5"
}
```

### 21.3 Graph Synthesis Trigger
```http
POST /api/v1/graphs
Content-Type: application/json

{
  "input": "10.1186/s12879-017-2746-5",
  "maxNodes": 50,
  "includePriorWorks": true,
  "includeDerivativeWorks": true
}
```
Response:
```json
{
  "graphId": "graph_9f8d7c6b",
  "status": "queued",
  "pollUrl": "/api/v1/graphs/graph_9f8d7c6b"
}
```

### 21.4 Graph Polling & Data Completeness Response
```http
GET /api/v1/graphs/{graphId}
```
Supported lifecycle statuses:
`queued`, `resolving_origin`, `generating_candidates`, `pre_ranking`, `enriching_metadata`, `enriching_references`, `computing_wbc`, `enriching_citations`, `computing_ncc`, `computing_final_scores`, `extracting_prior_works`, `extracting_derivative_works`, `building_layout`, `completed`, `partial`, `failed`.

#### Partial Graph Payload with Warnings & Data Completeness:
```json
{
  "graphId": "graph_9f8d7c6b",
  "status": "partial",
  "warnings": [
    {
      "code": "ncc_unavailable",
      "message": "Inbound citation data was unavailable for some papers."
    }
  ],
  "dataCompleteness": {
    "metadata": 1.0,
    "references": 0.86,
    "citations": 0.42,
    "semantic": 0.91
  },
  "origin": { "id": "doi:10.1186/s12879-017-2746-5", "title": "..." },
  "nodes": [],
  "similarityEdges": [],
  "citationEdges": []
}
```

### 21.5 On-Demand Paper Details
```http
GET /api/v1/papers/{paperId}/details
```

---

## 22. Progressive Graph Loading Protocol

* **Phase 1: Lightweight Topology Payload (`GET /api/v1/graphs/{id}`)**:
  * **Target Size:** $< 45\text{ KB}$ gzipped.
  * **Contents:** `graphId`, `origin`, 30–50 `nodes` (IDs, short titles, publication year, citation counts, 2D coordinates), `similarityEdges`, `citationEdges`, `yearRange`, `nodeScores`, `algorithmVersion`, `dataCompleteness`.
  * **Excluded:** Full abstracts, extended author affiliations, raw BibTeX, citation contexts.
* **Phase 2: On-Demand Detail Ingestion (`GET /api/v1/papers/{id}/details`)**:
  * Loaded lazily only when researcher taps a specific node.
  * Ingests full abstract, TL;DR, complete author affiliations, open-access PDF links, and citation formats.
* **Performance Benchmark Targets:**
  * Cached graph retrieval: $< 500\text{ ms}$.
  * New graph initial topology: $2 - 5\text{ s}$.
  * Full asynchronous candidate enrichment: $< 15\text{ s}$.

---

## 23. Provider Policy, Rate Limiting & Resilience

| Provider | Authentication | Rate Limiting Policy | Resiliency & Fallback Strategy |
|---|---|---|---|
| **Semantic Scholar** | API Key in headers | Configurable (`SEMANTIC_SCHOLAR_RPS=1` default) | Batch endpoints for metadata, paginated for references; honors `Retry-After`; Redis 7-day cache. |
| **OpenAlex** | Polite Pool (`mailto` param) | Configurable (`OPENALEX_RPS=10` default) | Cursor pagination, fallback for references when Semantic Scholar misses paper. |
| **Crossref** | Descriptive User-Agent | Polite pool | Long TTL caching (30–90 days) with explicit version invalidation; fallback for title resolution. |
| **PubMed** | Optional API Key | Configurable (`PUBMED_RPS=3` unauth / `10` auth) | Two-phase `ESearch` -> `EFetch`, MeSH term caching. |

---

## 24. Flutter State Management (BLoC / Cubit Architecture)

State management is strictly implemented using `flutter_bloc` / Cubits. Every feature maintains its own discrete state machine:

```text
SearchCubit
├── SearchInitial
├── SearchLoading
├── SearchSuccess (Exact paper resolved)
├── SearchAmbiguous (Multiple title matches requiring selection)
└── SearchFailure (Network / not found)

GraphCubit
├── GraphIdle
├── GraphQueued
├── GraphResolving
├── GraphGeneratingCandidates
├── GraphEnriching
├── GraphRanking
├── GraphBuildingLayout
├── GraphCompleted (Full network rendered)
├── GraphPartial (Network rendered with warnings & completeness metadata)
└── GraphFailure (Error message + offline prompt)

PaperDetailsCubit
├── DetailsInitial
├── DetailsLoading
├── DetailsLoaded (Abstract, TL;DR, BibTeX, OpenAccess link)
└── DetailsFailure

LibraryCubit
├── LibraryLoading
├── LibraryLoaded (Saved graphs, bookmarked papers, user notes)
├── LibrarySaving
├── LibraryDeleting
└── LibraryFailure

ThemeCubit
├── ThemeLight
├── ThemeDark
└── ThemeSystem

NotificationCubit
├── NotificationPermissionUnknown
├── NotificationPermissionGranted
├── NotificationPermissionDenied
├── NotificationTokenRegistered
└── NotificationFailure
```

---

## 25. Two-Tier Notification Architecture

### 25.1 Version 1 (Implemented in MVP)
* **Local Notifications:** Triggered via `flutter_local_notifications` for:
  * Foreground/polled completion of graph generation when observed by the client.
  * Scheduled reading reminders for saved library papers.
  * Confirmation of successful offline graph caching in Hive.
* **Background Limitation Reality:** Local notifications alone cannot wake up a terminated mobile client to detect backend job completion. Reliable background completion while the app is closed requires Push Notifications (FCM) and is deferred to Phase 2.
* **Contextual Permission UX:** Permissions are requested strictly when the user activates a notification feature (e.g. taps *"Notify me when complete"* or sets a reading reminder). Never requested on app launch.

### 25.2 Version 2 (Production Expansion)
* **Push Notifications:** Firebase Cloud Messaging (FCM) paired with backend `ResearchMonitorWorker`.
* **Workflow:**
  1. Researcher saves a research topic (e.g. *"Multi-Drug Resistant Tuberculosis"*).
  2. Backend worker runs weekly differential queries against OpenAlex / Semantic Scholar.
  3. New connected literature triggers an FCM push notification deep-linking directly into the updated graph.

---

## 26. Final Project Structure

### 26.1 Flutter Client (`Flutter Pro/`)
```text
lib/
├── core/
│   ├── api/
│   │   └── papergraph_api_client.dart          # Abstract Client Contract (REST Client)
│   ├── cache/
│   │   ├── hive_service.dart                   # Hive NoSQL graph & notes vault
│   │   └── offline_fallback_service.dart       # Reads cached & pre-seeded graphs only (Zero ranking logic)
│   ├── models/
│   │   ├── canonical_paper.dart                # Normalized multi-source paper entity
│   │   └── graph_display_model.dart            # Display layout, node coordinates, edge styling
│   ├── services/
│   │   ├── biometric_service.dart              # local_auth fingerprint/face lock
│   │   └── notification_service.dart           # flutter_local_notifications bridge
│   └── theme/
│       └── app_theme.dart                      # Academic Dark & Paper White
├── features/
│   ├── search/
│   │   ├── presentation/cubit/search_cubit.dart
│   │   └── data/search_repository.dart
│   ├── graph/
│   │   ├── presentation/
│   │   │   ├── cubit/graph_cubit.dart
│   │   │   ├── views/connected_graph_view.dart
│   │   │   └── widgets/graph_canvas_painter.dart
│   │   └── data/graph_repository.dart
│   ├── paper_details/
│   │   ├── presentation/cubit/paper_details_cubit.dart
│   │   └── data/paper_details_repository.dart
│   ├── library/
│   │   ├── presentation/cubit/library_cubit.dart
│   │   └── data/library_repository.dart
│   ├── notifications/
│   │   ├── presentation/cubit/notification_cubit.dart
│   │   └── data/notification_repository.dart
│   └── settings/
│       ├── presentation/cubit/theme_cubit.dart
│       └── data/settings_repository.dart
├── views/
│   ├── splash/splash_view.dart                 # Custom animated force graph splash
│   ├── onboarding/onboarding_view.dart         # Intro walkthrough
│   ├── auth/login_view.dart                    # Login with biometrics
│   ├── auth/register_view.dart                 # Registration screen
│   └── main_nav_view.dart                      # Bottom navigation bar
└── main.dart
```

### 26.2 Backend (`backend/`)
```text
backend/
├── app/
│   ├── api/
│   │   ├── v1/
│   │   │   ├── search.py
│   │   │   ├── papers.py
│   │   │   └── graphs.py
│   ├── models/
│   │   └── paper_entity.py
│   ├── schemas/
│   │   ├── canonical_paper.py
│   │   └── graph_payload.py
│   ├── repositories/
│   │   ├── paper_repository.py
│   │   └── graph_repository.py
│   ├── providers/
│   │   ├── semantic_scholar.py
│   │   ├── openalex.py
│   │   ├── crossref.py
│   │   └── pubmed.py
│   ├── resolution/
│   │   └── identity_resolver.py
│   ├── candidates/
│   │   ├── candidate_generator.py
│   │   └── quota_retention.py
│   ├── ranking/
│   │   ├── pre_scorer.py
│   │   ├── wbc_engine.py
│   │   ├── ncc_engine.py
│   │   ├── hybrid_ranker.py
│   │   ├── mmr_filter.py
│   │   └── prior_derivative_classifier.py
│   ├── graph/
│   │   └── layout_engine.py
│   ├── cache/
│   │   └── redis_cache.py
│   ├── workers/
│   │   └── graph_worker.py
│   └── notifications/
│       ├── token_registry.py
│       └── push_dispatcher.py
├── tests/
│   ├── test_wbc.py
│   ├── test_ncc.py
│   ├── test_renormalization.py
│   └── test_prior_derivative.py
└── main.py
```

---

## 27. Implementation Order & Milestones

1. **Backend Foundation:** FastAPI setup, PostgreSQL models, Redis caching, and environment-configurable provider rate limiters.
2. **Domain Entities:** Implement `CanonicalPaper` and `GraphPayload` schemas with data completeness tracking.
3. **Identity Resolution:** Implement DOI/PMID parser and Crossref/Semantic Scholar resolver.
4. **Provider Adapters:** Implement Semantic Scholar, OpenAlex, Crossref, and PubMed adapters with rate-limiting, retries, and pagination.
5. **Candidate Generation & Quota Retention:** Bounded candidate generator (120 pool $\to$ renormalized PreScore $\to$ Top 80 diverse quota).
6. **Enrichment Engine:** Batch metadata enrichment, paginated reference enrichment (Top 60), and selective citation enrichment (Top 30).
7. **Epsilon-Protected Ranking:** Implement safe WBC, safe NCC, dynamic profiles, and mathematical weight renormalization.
8. **Diversity & Works Classification:** Implement MMR diversity pruning ($\lambda = 0.70$), normalized Prior Works, and normalized Derivative Works rankers ($\in [0, 1]$).
9. **Layout & Physics:** Damped Fruchterman-Reingold force-directed layout engine producing 2D coordinates and non-directional similarity edges.
10. **Flutter API Client & Offline Service:**
    * Implement `PaperGraphApiClient` connecting to FastAPI backend.
    * Implement `OfflineFallbackService` reading cached Hive graphs and pre-seeded bundled landmarks (e.g. MDR-TB paper `10.1186/s12879-017-2746-5`) with zero external discovery logic.
11. **Flutter State Management:**
    * Implement `SearchCubit`, `GraphCubit`, `PaperDetailsCubit`, `LibraryCubit`, `ThemeCubit`, `NotificationCubit`.
12. **Mobile Canvas & UX:**
    * Implement `CustomPainter` with dual-edge visual differentiation (solid blue citation arrow vs. dashed cyan similarity line).
    * Bottom publication year spectrum bar (Mint Teal to Navy).
    * 4-tab sliding bottom sheet (Selected Paper, Prior Works, Derivative Works, List View).
13. **Academic Rubric Verification:**
    * Verify custom animated splash screen, 3-slide onboarding, biometrics (`local_auth`), Hive DB, theme toggle, permissions, and APK build.

---

## 28. Final Acceptance Criteria (Implementation Ready)

```text
[✓] Flutter communicates only with the PaperGraph Backend.
[✓] Offline mode reads cached and pre-seeded data only (zero external provider calls or ranking logic in Flutter).
[✓] All provider responses map cleanly to CanonicalPaper.
[✓] WBC formula has epsilon (1e-8) protection added after the square root.
[✓] NCC formula has epsilon (1e-8) protection in the denominator.
[✓] Missing signals are nullable and explicitly tracked with typed availability states.
[✓] PreScore handles unavailable signals through proportional weight renormalization.
[✓] Candidate retention enforces multi-bucket quotas before deep enrichment.
[✓] WBC and NCC are evaluated strictly after candidate enrichment (Top 60 / Top 30).
[✓] Missing weights are mathematically renormalized proportionally to sum to 1.0.
[✓] PriorScore and DerivativeScore are strictly normalized to [0, 1].
[✓] Confidence level (high >= 3 signals, medium = 2, low = 1, insufficient = 0) is reported correctly with every ranking.
[✓] Similarity edges are generated strictly from non-directional signals (excluding direct citation directionality).
[✓] Direct citation edges (solid blue arrows) and similarity edges (dashed cyan lines) are visually distinct.
[✓] Partial graph responses include warnings and data-completeness metadata.
[✓] Provider requests are cached, rate-limited via configurable RPS, and retried.
[✓] Graph synthesis is asynchronous with typed lifecycle states in GraphCubit.
[Target] University course rubric verified after implementation, testing, and APK build.
```
