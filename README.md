# PaperGraph

> Turn one paper into a visual map of its research field.

![Python](https://img.shields.io/badge/python-3.11+-blue) ![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B) ![FastAPI](https://img.shields.io/badge/FastAPI-0.110+-009688) ![License: MIT](https://img.shields.io/badge/license-MIT-green)

PaperGraph is a mobile-first academic discovery engine. Paste a paper's DOI, link, or title, and it builds an interactive literature graph: the works it builds on (prior works), the works that build on it (derivative works), and the most relevant similar research — resolved across four scholarly databases, deduplicated, ranked with explainable scores, and laid out as an explorable map.

<p align="center">
  <img src="flutter_app/assets/images/logo_light.png" width="140" alt="PaperGraph logo" />
</p>

## Features

- **Universal paper resolution** — bare DOI, DOI URL, PMID/PMCID, arXiv ID, Semantic Scholar ID, OpenAlex ID, or a publisher landing-page URL (citation meta-tag scraping as fallback)
- **Multi-provider engine** — Semantic Scholar, OpenAlex, Crossref, and PubMed with per-channel failure isolation, API key pooling with instant 429 rotation, and per-provider rate limiting
- **Explainable hybrid ranking** — semantic score, weighted bibliographic coupling (WBC), normalized co-citation (NCC), and direct-link signals; missing signals are never defaulted to zero (weights renormalize), and every candidate carries a full score breakdown
- **Prior & derivative works** extraction (Connected Papers-style)
- **MMR diversity selection** (λ = 0.70) so the graph shows the breadth of the field, not 40 copies of the same paper
- **Deterministic, force-directed layout** computed server-side: collision-free, prior works to the left, derivative works to the right, similar works clustered by actual similarity
- **Interactive Flutter canvas** — pinch-zoom, draggable nodes, tap for details, year-gradient node colors, directed citation arrows vs. dashed similarity links
- **Offline library** — cached graphs (Hive) with staleness badges, favorites with personal notes, biometric vault unlock
- **One-tap citations** — BibTeX/APA generated per paper
- **Auth** — Firebase email/password, biometric quick-unlock, and email OTP delivered via Gmail SMTP
- **Honest progress** — a 16-stage job lifecycle streamed to the UI with cancellation, backoff polling, and partial-result warnings instead of silent failures

## Architecture

```
┌──────────────┐      REST / JSON       ┌─────────────────────────────────────┐
│  Flutter app │  ◀──────────────────▶  │  FastAPI backend                    │
│  (bloc, dio, │   async graph jobs     │  providers → resolution → candidates│
│  hive, firebase)  (202 + polling)     │  → enrichment (WBC/NCC) → ranking   │
└──────────────┘                        │  → MMR → force-directed layout      │
                                        └─────────────────────────────────────┘
```

## Tech stack

| Layer | Tech |
|---|---|
| Mobile | Flutter / Dart — flutter_bloc + provider, dio, hive, firebase_auth, local_auth, lottie |
| Backend | Python 3.11+ — FastAPI, pydantic v2, httpx |
| Data providers | Semantic Scholar Graph API, OpenAlex, Crossref, NCBI E-Utilities |
| Testing | pytest (backend: providers, resolution, ranking, graph, security) + flutter_test |

## Project structure

```
├── backend/            # FastAPI discovery & ranking engine
│   ├── app/            # api, providers, resolution, candidates, enrichment, ranking, graph, workers
│   └── tests/          # pytest suite with provider fixtures
├── flutter_app/        # Flutter mobile app
│   └── lib/            # views, cubits, models, core (theme, network, services)
└── docs/               # API contract, ranking spec, design decisions, plans
```

## Getting started

### Backend

```
cd backend
python -m venv .venv
.venv\Scripts\activate          # Windows
pip install -r requirements.txt
copy .env.example .env          # then fill in your own API keys
uvicorn app.main:app --reload
```

Interactive API docs: `http://localhost:8000/api/v1/docs`

### Flutter app

```
cd flutter_app
flutter pub get
flutter run --dart-define=PAPERGRAPH_API_URL=http://10.0.2.2:8000/api/v1
```

Release APK against a deployed backend:

```
flutter build apk --release --dart-define=PAPERGRAPH_API_URL=https://<your-backend-host>/api/v1
```

## Testing

```
cd backend && python -m pytest -q
cd flutter_app && flutter test
```

## Design principles

- **Never fabricate** — if every provider fails, the job fails loudly with an honest error; no invented papers, ever
- **Explainability** — every score ships with its signal breakdown and confidence level
- **Resilience** — key rotation on 429s, per-channel isolation (one provider's 500 never aborts the chain), exponential backoff, and graceful partial results with explicit warnings

## Screenshots

<!-- TODO: add real screenshots under docs/screenshots/ and embed them here -->

## License

MIT — see [LICENSE](LICENSE).
