# Architecture Decision Records (ADR)

## ADR-0001: Monorepo Structure

- **Status:** Accepted
- **Context:** The system consists of a Python FastAPI backend and a Flutter client.
- **Decision:** Use a single monorepo with `backend/` and `flutter_app/` subdirectories to keep contract specifications, docker services, and documentation synchronized.

## ADR-0002: Architectural Isolation

- **Status:** Accepted
- **Context:** Direct calls from client to academic providers cause rate limiting, secret exposure, and unmanageable state in mobile.
- **Decision:** Flutter communicates exclusively with the PaperGraph backend. No third-party provider calls or API keys may exist in Flutter.
