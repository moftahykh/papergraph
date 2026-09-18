"""Monitoring API route-level tests.

These tests use FastAPI *dependency overrides* for ``get_required_auth_user``
so that every HTTP path — serialisation, ownership filtering, status codes —
is exercised without weakening production Firebase authentication.

Real Firebase-authenticated end-to-end coverage is provided by the separate
``scripts/monitoring_smoke_test.py`` script, which must be run against a live
backend with a valid Firebase ID token.
"""

from __future__ import annotations

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.auth import AuthenticatedUser, get_required_auth_user
from app.core.config import settings
from app.db.session import engine
from app.main import app


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_user(uid: str) -> AuthenticatedUser:
    return AuthenticatedUser(user_id=uid, role="researcher", claims={})


def _auth_override(uid: str = "test-user-alice"):
    """Return an async dependency that always yields a fixed user."""
    async def _dep():
        return _make_user(uid)
    return _dep


def _set_user(uid: str):
    """Shortcut: override the auth dependency to return *uid*."""
    app.dependency_overrides[get_required_auth_user] = _auth_override(uid)


SAMPLE_CREATE_PAYLOAD = {
    "local_graph_id": "local-graph-001",
    "graph_title": "Monitoring Test Graph",
    "papers": [
        {
            "canonical_id": "test-paper-001",
            "title": "Test Paper Alpha",
            "doi": "10.5555/test-001",
            "year": 2025,
        }
    ],
    "frequency": "daily",
    "timezone": "Asia/Riyadh",
}

PREFIX = settings.API_V1_STR


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture(autouse=True)
def _cleanup_overrides():
    """Remove dependency overrides after every test."""
    yield
    app.dependency_overrides.pop(get_required_auth_user, None)


@pytest.fixture()
async def client():
    """Async test client that correctly handles the event loop for asyncpg."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c
    # Dispose pooled connections so the next test gets a fresh pool.
    await engine.dispose()


# ---------------------------------------------------------------------------
# 1. Unauthenticated requests are rejected
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_unauthenticated_monitoring_request_rejected(client):
    """Without an override or token, monitoring routes must reject the request."""
    app.dependency_overrides.pop(get_required_auth_user, None)
    res = await client.get(f"{PREFIX}/monitoring/graphs")
    # 401 (no token) or 503 (FIREBASE_PROJECT_ID missing in test env)
    assert res.status_code in {401, 503}


# ---------------------------------------------------------------------------
# 2. Create monitored graph
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_create_monitored_graph(client):
    """POST /monitoring/graphs returns 201 with correct fields."""
    _set_user("alice-create")
    res = await client.post(
        f"{PREFIX}/monitoring/graphs", json=SAMPLE_CREATE_PAYLOAD,
    )
    assert res.status_code == 201, res.text
    data = res.json()
    assert data["graph_title"] == "Monitoring Test Graph"
    assert data["status"] == "active"
    assert data["frequency"] == "daily"
    assert "id" in data
    assert "next_check_at" in data

    # Cleanup
    await client.delete(f"{PREFIX}/monitoring/graphs/{data['id']}")


# ---------------------------------------------------------------------------
# 3. List only the current user's graphs
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_list_only_current_user_graphs(client):
    """Each user sees only their own monitored graphs."""
    # Alice creates a graph
    _set_user("alice-list")
    r1 = await client.post(
        f"{PREFIX}/monitoring/graphs",
        json={**SAMPLE_CREATE_PAYLOAD, "local_graph_id": "alice-g1"},
    )
    assert r1.status_code == 201
    alice_id = r1.json()["id"]

    # Bob creates a different graph
    _set_user("bob-list")
    r2 = await client.post(
        f"{PREFIX}/monitoring/graphs",
        json={**SAMPLE_CREATE_PAYLOAD, "local_graph_id": "bob-g1"},
    )
    assert r2.status_code == 201
    bob_id = r2.json()["id"]

    # Bob lists — should see only his graph
    bob_list = await client.get(f"{PREFIX}/monitoring/graphs")
    bob_ids = {g["id"] for g in bob_list.json()}
    assert bob_id in bob_ids
    assert alice_id not in bob_ids

    # Alice lists — should see only her graph
    _set_user("alice-list")
    alice_list = await client.get(f"{PREFIX}/monitoring/graphs")
    alice_ids = {g["id"] for g in alice_list.json()}
    assert alice_id in alice_ids
    assert bob_id not in alice_ids

    # Cleanup
    await client.delete(f"{PREFIX}/monitoring/graphs/{alice_id}")
    _set_user("bob-list")
    await client.delete(f"{PREFIX}/monitoring/graphs/{bob_id}")


# ---------------------------------------------------------------------------
# 4. Pause monitoring
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_pause_monitoring(client):
    """PATCH with status=paused sets the graph to paused."""
    _set_user("alice-pause")
    r = await client.post(
        f"{PREFIX}/monitoring/graphs",
        json={**SAMPLE_CREATE_PAYLOAD, "local_graph_id": "pause-g1"},
    )
    mid = r.json()["id"]

    patched = await client.patch(
        f"{PREFIX}/monitoring/graphs/{mid}", json={"status": "paused"},
    )
    assert patched.status_code == 200
    assert patched.json()["status"] == "paused"

    # Cleanup
    await client.delete(f"{PREFIX}/monitoring/graphs/{mid}")


# ---------------------------------------------------------------------------
# 5. Resume monitoring
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_resume_monitoring(client):
    """PATCH with status=active resumes a paused graph."""
    _set_user("alice-resume")
    r = await client.post(
        f"{PREFIX}/monitoring/graphs",
        json={**SAMPLE_CREATE_PAYLOAD, "local_graph_id": "resume-g1"},
    )
    mid = r.json()["id"]

    # Pause then resume
    await client.patch(
        f"{PREFIX}/monitoring/graphs/{mid}", json={"status": "paused"},
    )
    resumed = await client.patch(
        f"{PREFIX}/monitoring/graphs/{mid}", json={"status": "active"},
    )
    assert resumed.status_code == 200
    assert resumed.json()["status"] == "active"

    # Cleanup
    await client.delete(f"{PREFIX}/monitoring/graphs/{mid}")


# ---------------------------------------------------------------------------
# 6. Update frequency
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_update_frequency(client):
    """PATCH with frequency=weekly changes the check cadence."""
    _set_user("alice-freq")
    r = await client.post(
        f"{PREFIX}/monitoring/graphs",
        json={**SAMPLE_CREATE_PAYLOAD, "local_graph_id": "freq-g1"},
    )
    mid = r.json()["id"]

    patched = await client.patch(
        f"{PREFIX}/monitoring/graphs/{mid}", json={"frequency": "weekly"},
    )
    assert patched.status_code == 200
    assert patched.json()["frequency"] == "weekly"

    # Cleanup
    await client.delete(f"{PREFIX}/monitoring/graphs/{mid}")


# ---------------------------------------------------------------------------
# 7. List research updates (empty baseline)
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_list_research_updates_empty(client):
    """GET updates for a new graph returns an empty list."""
    _set_user("alice-updates")
    r = await client.post(
        f"{PREFIX}/monitoring/graphs",
        json={**SAMPLE_CREATE_PAYLOAD, "local_graph_id": "updates-g1"},
    )
    mid = r.json()["id"]

    updates = await client.get(f"{PREFIX}/monitoring/graphs/{mid}/updates")
    assert updates.status_code == 200
    assert updates.json() == []

    # Cleanup
    await client.delete(f"{PREFIX}/monitoring/graphs/{mid}")


# ---------------------------------------------------------------------------
# 8. Delete monitoring
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_delete_monitoring(client):
    """DELETE returns 204 and the graph is no longer listed."""
    _set_user("alice-del")
    r = await client.post(
        f"{PREFIX}/monitoring/graphs",
        json={**SAMPLE_CREATE_PAYLOAD, "local_graph_id": "del-g1"},
    )
    mid = r.json()["id"]

    del_res = await client.delete(f"{PREFIX}/monitoring/graphs/{mid}")
    assert del_res.status_code == 204

    # Confirm it's gone — PATCH should return 404
    patch_res = await client.patch(
        f"{PREFIX}/monitoring/graphs/{mid}", json={"status": "paused"},
    )
    assert patch_res.status_code == 404


# ---------------------------------------------------------------------------
# 9. Device-token registration and deactivation
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_device_token_register_and_deactivate(client):
    """POST then DELETE /device-token both return 204."""
    _set_user("alice-device")
    token_payload = {"fcm_token": "test-fcm-token-abc123", "platform": "android"}

    reg = await client.post(f"{PREFIX}/monitoring/device-token", json=token_payload)
    assert reg.status_code == 204

    dereg = await client.request(
        "DELETE", f"{PREFIX}/monitoring/device-token", json=token_payload,
    )
    assert dereg.status_code == 204


# ---------------------------------------------------------------------------
# 10. Ownership isolation between two users
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_ownership_isolation_between_users(client):
    """User B cannot PATCH or DELETE User A's monitored graph."""
    # Alice creates
    _set_user("alice-iso")
    r = await client.post(
        f"{PREFIX}/monitoring/graphs",
        json={**SAMPLE_CREATE_PAYLOAD, "local_graph_id": "iso-g1"},
    )
    assert r.status_code == 201
    alice_mid = r.json()["id"]

    # Bob tries to patch Alice's graph → 404 (ownership filter)
    _set_user("bob-iso")
    patch_res = await client.patch(
        f"{PREFIX}/monitoring/graphs/{alice_mid}", json={"status": "paused"},
    )
    assert patch_res.status_code == 404

    # Bob tries to delete Alice's graph → 404
    del_res = await client.delete(f"{PREFIX}/monitoring/graphs/{alice_mid}")
    assert del_res.status_code == 404

    # Bob tries to read Alice's updates → 404
    upd_res = await client.get(
        f"{PREFIX}/monitoring/graphs/{alice_mid}/updates",
    )
    assert upd_res.status_code == 404

    # Cleanup — Alice deletes her own graph
    _set_user("alice-iso")
    await client.delete(f"{PREFIX}/monitoring/graphs/{alice_mid}")
