# PaperGraph API Contract Specification

> **Specification Version:** 1.0 (Phase 1 Approved Contract)  
> **Base URL:** `/api/v1`  
> **Communication Policy:** Flutter communicates exclusively with this FastAPI gateway. No third-party academic provider APIs may be contacted directly by the client.

---

## 1. Global Standards & Protocols

### 1.1 Content Types & Headers
- All requests containing a body must provide `Content-Type: application/json`.
- All responses return `application/json; charset=utf-8`.
- Date and time fields use ISO-8601 UTC format (e.g. `2026-09-10T20:15:30Z`).

### 1.2 Null vs. Zero Semantics
In accordance with Non-Negotiable Rule #6, missing or uncomputed metrics are explicitly distinguished from evaluated zero values:
- `value = null`: The signal could not be evaluated (e.g. data pending enrichment or upstream provider error).
- `value = 0.0`: The signal was successfully evaluated and determined to have zero bibliographic coupling or co-citation overlap.

```json
{
  "value": null,
  "availability": "unavailable",
  "reason": "references_not_loaded"
}
```

Availability states:
- `available`: Successfully computed.
- `unavailable`: Data enrichment pending or not yet loaded.
- `provider_error`: Upstream API failure, timeout, or rate-limited.
- `not_applicable`: Signal not valid for target paper.

---

## 2. Endpoints Specification

### 2.1 Health Check
Check operational readiness of backend services.

- **URL:** `GET /api/v1/health` (or `GET /health`)
- **Query Parameters:** None
- **Response (200 OK):**
```json
{
  "status": "ok",
  "app": "PaperGraph Backend",
  "version": "0.1.0"
}
```

---

### 2.2 Academic Search
Performs multi-provider academic literature search with query debouncing.

- **URL:** `GET /api/v1/search`
- **Query Parameters:**
  - `query` (string, required): Free-text title, topic, or author query (min 2 chars).
  - `limit` (integer, optional, default: 10, range: 1–50): Results per page.
  - `offset` (integer, optional, default: 0): Pagination offset.
  - `provider` (string, optional): Restrict search to specific provider (`semantic_scholar`, `openalex`, `crossref`, `pubmed`).
- **Response (200 OK):**
```json
{
  "query": "distributed consensus raft",
  "total": 42,
  "items": [
    {
      "canonical_id": "doi:10.5555/2643634.2643666",
      "title": "In Search of an Understandable Consensus Algorithm",
      "authors": ["Diego Ongaro", "John Ousterhout"],
      "year": 2014,
      "venue": "USENIX Annual Technical Conference",
      "citation_count": 3520,
      "doi": "10.5555/2643634.2643666",
      "score": 0.985
    }
  ],
  "disambiguation_needed": false,
  "candidates": []
}
```

---

### 2.3 Paper Resolution
Resolves any raw identifier (bare DOI, DOI URL, PMID, OpenAlex ID, or paper title) into a canonical record.

- **URL:** `POST /api/v1/papers/resolve`
- **Request Body:**
```json
{
  "identifier": "10.1145/357172.357176"
}
```
- **Response (200 OK — Exact Match):**
```json
{
  "resolved": true,
  "paper": {
    "canonical_id": "doi:10.1145/357172.357176",
    "doi": "10.1145/357172.357176",
    "pmid": null,
    "semantic_scholar_id": "b3e9e30a5e8c71b6",
    "open_alex_id": "https://openalex.org/W2147152072",
    "title": "The Byzantine Generals Problem",
    "normalized_title": "the byzantine generals problem",
    "authors": [
      {
        "name": "Leslie Lamport",
        "position": 1,
        "affiliation": "SRI International"
      }
    ],
    "year": 1982,
    "venue": "ACM TOPLAS",
    "abstract": "Reliable computer systems must handle malfunctioning components...",
    "citation_count": 8940,
    "reference_count": 18,
    "reference_ids": ["doi:10.1145/359545.359563"],
    "citation_ids": [],
    "topics": ["Computer Science", "Fault Tolerance", "Distributed Systems"],
    "source_availability": {
      "semantic_scholar": true,
      "open_alex": true,
      "crossref": true,
      "pubmed": false
    },
    "completeness": 0.95
  },
  "ambiguous_candidates": [],
  "confidence": 1.0,
  "message": "Resolved via exact DOI match."
}
```
- **Response (200 OK — Ambiguous Title Requiring Disambiguation):**
```json
{
  "resolved": false,
  "paper": null,
  "ambiguous_candidates": [
    {
      "canonical_id": "doi:10.1016/j.jbi.2018.07.017",
      "title": "Clinical Information Extraction...",
      "year": 2018,
      "authors": [{"name": "A. Author"}]
    }
  ],
  "confidence": 0.65,
  "message": "Multiple publications matched title. Disambiguation required."
}
```

---

### 2.4 Asynchronous Graph Generation Dispatch
Dispatches an asynchronous pipeline to synthesize a multi-stage literature graph.

- **URL:** `POST /api/v1/graphs`
- **Request Body:**
```json
{
  "origin_id": "doi:10.5555/2643634.2643666",
  "max_nodes": 40,
  "include_prior_works": true,
  "include_derivative_works": true,
  "weight_profile": "default",
  "algorithm_version": "v1.0"
}
```
- **Response (202 Accepted):**
```json
{
  "graph_id": "graph_8a7d9f2c",
  "status": "queued",
  "poll_url": "/api/v1/graphs/graph_8a7d9f2c",
  "created_at": "2026-09-10T20:20:00Z"
}
```

---

### 2.5 Graph Polling & Progressive Snapshot Retrieval
Polls status or retrieves the synthesized graph topology.

- **URL:** `GET /api/v1/graphs/{id}`
- **Lifecycle Statuses (16 Exact Stages):**
  1. `queued`
  2. `resolving_origin`
  3. `generating_candidates`
  4. `pre_ranking`
  5. `enriching_metadata`
  6. `enriching_references`
  7. `computing_wbc`
  8. `enriching_citations`
  9. `computing_ncc`
  10. `computing_final_scores`
  11. `extracting_prior_works`
  12. `extracting_derivative_works`
  13. `building_layout`
  14. `completed`
  15. `partial`
  16. `failed`

- **Response (In-Progress Polling):**
```json
{
  "graph_id": "graph_8a7d9f2c",
  "status": "computing_wbc",
  "progress": 0.55,
  "current_stage": "computing_wbc",
  "poll_url": "/api/v1/graphs/graph_8a7d9f2c",
  "snapshot": null,
  "warnings": [],
  "data_completeness": null,
  "error": null
}
```

- **Response (Completed / Partial Topology Snapshot):**
```json
{
  "graph_id": "graph_8a7d9f2c",
  "status": "completed",
  "progress": 1.0,
  "current_stage": "completed",
  "poll_url": "/api/v1/graphs/graph_8a7d9f2c",
  "snapshot": {
    "graph_id": "graph_8a7d9f2c",
    "origin": {
      "id": "doi:10.5555/2643634.2643666",
      "canonical_id": "doi:10.5555/2643634.2643666",
      "title": "In Search of an Understandable Consensus Algorithm",
      "year": 2014,
      "doi": "10.5555/2643634.2643666"
    },
    "status": "completed",
    "nodes": [
      {
        "id": "doi:10.5555/2643634.2643666",
        "canonical_id": "doi:10.5555/2643634.2643666",
        "title": "In Search of an Understandable Consensus Algorithm",
        "short_title": "Raft Consensus",
        "authors": ["Diego Ongaro", "John Ousterhout"],
        "year": 2014,
        "venue": "USENIX ATC",
        "citation_count": 3520,
        "is_origin": true,
        "radius": 24.0,
        "x": 0.0,
        "y": 0.0,
        "final_score": 1.0,
        "confidence": "high",
        "archetype": "origin"
      }
    ],
    "similarity_edges": [
      {
        "source": "doi:10.5555/2643634.2643666",
        "target": "doi:10.1145/357172.357176",
        "type": "similarity",
        "weight": 0.82,
        "directed": false,
        "label": "Conceptual Similarity"
      }
    ],
    "citation_edges": [
      {
        "source": "doi:10.5555/2643634.2643666",
        "target": "doi:10.1145/357172.357176",
        "type": "citation",
        "weight": 1.0,
        "directed": true,
        "label": "Cites"
      }
    ],
    "data_completeness": {
      "metadata": 1.0,
      "references": 0.95,
      "citations": 0.88,
      "semantic": 1.0
    },
    "warnings": [],
    "algorithm_version": "v1.0"
  },
  "warnings": [],
  "data_completeness": {
    "metadata": 1.0,
    "references": 0.95,
    "citations": 0.88,
    "semantic": 1.0
  },
  "error": null
}
```

---

### 2.6 On-Demand Paper Details
Retrieved lazily when a researcher selects a specific paper in the Flutter client.

- **URL:** `GET /api/v1/papers/{id}/details`
- **Path Parameters:**
  - `id` (string, required): Canonical paper identifier (e.g. `doi:10.1145/357172.357176`).
- **Response (200 OK):**
```json
{
  "paper": {
    "canonical_id": "doi:10.1145/357172.357176",
    "doi": "10.1145/357172.357176",
    "title": "The Byzantine Generals Problem",
    "normalized_title": "the byzantine generals problem",
    "authors": [
      {
        "name": "Leslie Lamport",
        "position": 1,
        "affiliation": "SRI International"
      }
    ],
    "year": 1982,
    "venue": "ACM TOPLAS",
    "abstract": "Reliable computer systems must handle malfunctioning components...",
    "citation_count": 8940,
    "reference_count": 18,
    "topics": ["Computer Science", "Fault Tolerance", "Distributed Systems"],
    "completeness": 0.95
  },
  "tldr": "Presents the classic Byzantine generals problem and proves solution bounds using signed messages.",
  "open_access_url": "https://lamport.azurewebsites.net/pubs/byz.pdf",
  "bibtex": "@article{lamport1982byzantine,\n  title={The Byzantine Generals Problem},\n  author={Lamport, Leslie and Shostak, Robert and Pease, Marshall},\n  journal={ACM TOPLAS},\n  year={1982}\n}",
  "affiliations": ["SRI International"],
  "is_saved": false
}
```
