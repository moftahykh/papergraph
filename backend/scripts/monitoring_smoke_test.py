"""Manual end-to-end smoke test for the Research Monitoring API.

Requires a running backend, migrated PostgreSQL database, and a valid Firebase
ID token. This creates one temporary monitored graph and removes it in finally.
"""

from __future__ import annotations

import argparse
import os
import sys
import uuid
from typing import Any

import httpx


SAMPLE_PAPER = {
    "canonical_id": "smoke-paper-001",
    "title": "PaperGraph monitoring smoke-test paper",
    "doi": "10.5555/papergraph-smoke-test",
    "openalex_id": "https://openalex.org/SMOKE001",
    "semantic_scholar_id": "smoke-s2-001",
    "year": 2026,
}


def request(
    client: httpx.Client,
    method: str,
    path: str,
    expected: set[int],
    **kwargs: Any,
) -> httpx.Response:
    response = client.request(method, path, **kwargs)
    if response.status_code not in expected:
        raise RuntimeError(
            f"{method} {path} returned {response.status_code}: "
            f"{response.text[:500]}"
        )
    return response


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--base-url",
        default=os.getenv("PAPERGRAPH_API_URL", "http://127.0.0.1:8000"),
        help="Backend origin, without /api/v1 (default: PAPERGRAPH_API_URL or localhost)",
    )
    parser.add_argument(
        "--token",
        default=os.getenv("PAPERGRAPH_FIREBASE_ID_TOKEN"),
        help="Firebase ID token (default: PAPERGRAPH_FIREBASE_ID_TOKEN)",
    )
    args = parser.parse_args()

    if not args.token:
        print(
            "Missing Firebase token. Set PAPERGRAPH_FIREBASE_ID_TOKEN or pass --token.",
            file=sys.stderr,
        )
        return 2

    api_root = args.base_url.rstrip("/") + "/api/v1"
    headers = {"Authorization": f"Bearer {args.token}"}
    local_graph_id = f"smoke-{uuid.uuid4().hex}"
    monitor_id: str | None = None

    with httpx.Client(base_url=api_root, headers=headers, timeout=15.0) as client:
        try:
            created = request(
                client,
                "POST",
                "/monitoring/graphs",
                {201},
                json={
                    "local_graph_id": local_graph_id,
                    "graph_title": "Monitoring API smoke test",
                    "papers": [SAMPLE_PAPER],
                    "frequency": "daily",
                    "timezone": "Asia/Riyadh",
                },
            ).json()
            monitor_id = created["id"]
            assert created["status"] == "active"
            assert created["frequency"] == "daily"
            print("PASS create monitored graph")

            listed = request(client, "GET", "/monitoring/graphs", {200}).json()
            assert any(item["id"] == monitor_id for item in listed)
            print("PASS list owned monitored graphs")

            paused = request(
                client,
                "PATCH",
                f"/monitoring/graphs/{monitor_id}",
                {200},
                json={"status": "paused"},
            ).json()
            assert paused["status"] == "paused"
            print("PASS pause monitoring")

            resumed = request(
                client,
                "PATCH",
                f"/monitoring/graphs/{monitor_id}",
                {200},
                json={"status": "active", "frequency": "weekly"},
            ).json()
            assert resumed["status"] == "active"
            assert resumed["frequency"] == "weekly"
            print("PASS resume and change frequency")

            updates = request(
                client,
                "GET",
                f"/monitoring/graphs/{monitor_id}/updates",
                {200},
            ).json()
            assert updates == []
            print("PASS list research updates (empty baseline)")
        finally:
            if monitor_id is not None:
                request(
                    client,
                    "DELETE",
                    f"/monitoring/graphs/{monitor_id}",
                    {204},
                )
                print("PASS delete monitored graph (cleanup)")

    print("Monitoring API smoke test passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
