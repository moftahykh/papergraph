import pytest
from starlette.testclient import TestClient
from app.main import app
from app.api.v1.auth import _otp_store

client = TestClient(app)


def test_send_and_verify_otp():
    email = "researcher.test@example.com"
    # 1. Send OTP
    response = client.post("/api/v1/auth/send-otp", json={"email": email})
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert email in _otp_store
    code = _otp_store[email]["code"]
    assert len(code) == 6
    assert code.isdigit()

    # 2. Verify with wrong code
    wrong_resp = client.post("/api/v1/auth/verify-otp", json={"email": email, "code": "000000"})
    assert wrong_resp.status_code == 400

    # 3. Verify with correct code
    correct_resp = client.post("/api/v1/auth/verify-otp", json={"email": email, "code": code})
    assert correct_resp.status_code == 200
    assert correct_resp.json()["success"] is True
    # Should be removed from store after successful verification
    assert email not in _otp_store


def test_otp_brute_force_protection():
    email = "bruteforce.target@example.com"
    client.post("/api/v1/auth/send-otp", json={"email": email})
    assert email in _otp_store
    real_code = _otp_store[email]["code"]

    # Try 4 wrong attempts
    for i in range(1, 5):
        resp = client.post("/api/v1/auth/verify-otp", json={"email": email, "code": "999999"})
        assert resp.status_code == 400
        assert f"{5 - i} attempt(s) remaining" in resp.json()["detail"]

    # 5th wrong attempt triggers 429 and invalidates OTP
    resp_locked = client.post("/api/v1/auth/verify-otp", json={"email": email, "code": "999999"})
    assert resp_locked.status_code == 429
    assert "invalidated" in resp_locked.json()["detail"].lower()

    # Even the correct code should now fail because it was purged
    resp_retry = client.post("/api/v1/auth/verify-otp", json={"email": email, "code": real_code})
    assert resp_retry.status_code == 400
    assert "no verification code found" in resp_retry.json()["detail"].lower()


def test_otp_expiration():
    import time
    email = "expired.otp@example.com"
    client.post("/api/v1/auth/send-otp", json={"email": email})
    # Force expiry timestamp into the past
    _otp_store[email]["expires_at"] = time.time() - 100

    resp = client.post("/api/v1/auth/verify-otp", json={"email": email, "code": "123456"})
    assert resp.status_code == 400
    detail = resp.json()["detail"].lower()
    assert "expired" in detail or "no verification code found" in detail
    assert email not in _otp_store
