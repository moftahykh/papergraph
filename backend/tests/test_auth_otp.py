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
