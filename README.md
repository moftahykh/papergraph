# 📄 PaperGraph

> **Multi-Source Academic Discovery Engine with Hybrid Similarity Ranking & Interactive Literature Graph**

PaperGraph is a research discovery platform designed to explore scientific literature through connected knowledge graphs. It combines multi-source metadata retrieval, identity deduplication, and mathematical ranking (incorporating bibliographic coupling and co-citation analysis) to deliver an interactive visual map of scientific works.

---

## 🏛️ System Boundary & Architectural Isolation Rules

To maintain high reliability, maintainability, and clean separation of concerns, the project enforces strict architectural boundaries:

1. **Backend as Sole Gateway:** The Flutter client communicates **exclusively** with the PaperGraph FastAPI backend.
2. **No Direct Provider Access in Client:** Flutter **never** calls third-party academic APIs (Semantic Scholar, OpenAlex, Crossref, PubMed).
3. **Engine Isolation:** All provider normalization, caching, candidate pooling, and ranking algorithms reside entirely inside the `backend/` service.
4. **State Management:** Flutter uses `flutter_bloc` / Cubit exclusively for deterministic state transitions.
5. **Offline Operation:** The client operates offline using cached graphs and local storage (Hive) only, never attempting ad-hoc third-party queries.
6. **Zero Secrets in Client:** No provider API keys or sensitive credentials exist within the Flutter application bundle or repository.

---

## 📁 Repository Structure

```text
papergraph/
├── PLAN.md                  # Master execution contract & phased implementation plan
├── PROJECT_DOCUMENTATION.md # Detailed technical specification v4.2
├── README.md                # Root system documentation and boundary guide
├── .gitignore               # Monorepo gitignore (Python, Flutter, IDEs, envs)
├── docker-compose.yml       # Local PostgreSQL & Redis infrastructure
├── .env.example             # Safe template for local environment variables
├── backend/                 # FastAPI backend application
│   ├── app/
│   │   ├── api/v1/          # REST endpoints (health, search, resolve, graphs)
│   │   ├── core/            # Configuration and system settings
│   │   ├── models/          # Domain and database models
│   │   ├── schemas/         # Pydantic validation schemas
│   │   ├── repositories/    # Data persistence layer
│   │   ├── providers/       # Academic provider adapters (isolated & testable)
│   │   ├── resolution/      # Canonical identity resolution & deduplication
│   │   ├── candidates/      # Candidate generation & pre-ranking pools
│   │   ├── ranking/         # Safe ranking engine (WBC, NCC, MMR)
│   │   ├── graph/           # Topology synthesis and relationship edge typing
│   │   ├── cache/           # Redis caching layer
│   │   └── workers/         # Asynchronous background graph generation
│   ├── tests/               # Pytest suite with fixtures & mock responses
│   ├── alembic/             # Database migrations
│   ├── pyproject.toml       # Backend package configuration and dependencies
│   └── main.py              # Application entrypoint
├── flutter_app/             # Flutter mobile / web application
│   ├── lib/                 # Dart source code (views, cubits, models, painters)
│   ├── test/                # Unit and widget tests
│   ├── pubspec.yaml         # Flutter dependencies
│   └── README.md            # Flutter-specific documentation
└── docs/                    # Architectural decisions & protocol contracts
    ├── api-contract.md      # REST and job polling contract specification
    ├── ranking-spec.md      # Hybrid ranking mathematics & formulas
    └── decisions.md         # Architecture Decision Records (ADRs)
```

---

## 🚀 Local Development Setup

### 1. Prerequisites
- **Python:** 3.11+ (Python 3.13 supported)
- **Flutter SDK:** 3.44+ (Dart 3.12+)
- **Docker & Docker Compose:** For PostgreSQL & Redis

### 2. Infrastructure (Docker)
Start the local PostgreSQL and Redis instances:
```bash
docker compose up -d
```
Verify status:
```bash
docker compose ps
```

### 3. Backend Setup
```bash
cd backend
# Run test suite
python -m pytest

# Run local development server
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```
Interactive API documentation is available at:
- Swagger UI: `http://localhost:8000/api/v1/docs`
- Health check: `http://localhost:8000/api/v1/health`

### 4. Flutter Setup
```bash
cd flutter_app
# Fetch dependencies
flutter pub get

# Static analysis and tests
flutter analyze
flutter test

# Run application locally
flutter run
```

---

## 🧪 Phase 0 Verification

Run the Phase 0 verification suite:
```bash
# 1. Verify Docker compose syntax
docker compose config

# 2. Run backend test suite
cd backend && python -m pytest

# 3. Run Flutter analyzer and tests
cd ../flutter_app && flutter analyze && flutter test
```
