import logging
import secrets
import time
from typing import Dict, Any
import httpx
from fastapi import APIRouter, BackgroundTasks, HTTPException, status
from pydantic import BaseModel
from app.core.config import settings

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/auth", tags=["Authentication"])

# In-memory OTP store: { email: { "code": str, "expires_at": float, "attempts": int } }
# OTPs expire in 10 minutes (600 seconds)
_otp_store: Dict[str, Dict[str, Any]] = {}
OTP_EXPIRY_SECONDS = 600
MAX_OTP_ATTEMPTS = 5
MAX_STORED_OTPS = 2000


def _prune_expired_otps() -> None:
    """Removes expired OTP records to prevent in-memory accumulation."""
    now = time.time()
    expired_keys = [k for k, v in _otp_store.items() if now > v.get("expires_at", 0)]
    for k in expired_keys:
        _otp_store.pop(k, None)

    # If still oversized (e.g., active burst), evict oldest
    if len(_otp_store) > MAX_STORED_OTPS:
        sorted_keys = sorted(_otp_store.keys(), key=lambda k: _otp_store[k].get("expires_at", 0))
        for k in sorted_keys[: len(_otp_store) - MAX_STORED_OTPS]:
            _otp_store.pop(k, None)


class SendOtpRequest(BaseModel):
    email: str


class VerifyOtpRequest(BaseModel):
    email: str
    code: str


def _generate_otp_html(code: str) -> str:
    return f"""
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>PaperGraph Verification Code</title>
      <style>
        body {{
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
          background-color: #f8fafc;
          margin: 0;
          padding: 24px;
        }}
        .container {{
          max-width: 480px;
          margin: 0 auto;
          background: #ffffff;
          border-radius: 16px;
          padding: 36px 28px;
          box-shadow: 0 4px 16px rgba(0, 0, 0, 0.06);
          border: 1px solid #e2e8f0;
          text-align: center;
        }}
        .logo {{
          font-size: 24px;
          font-weight: 800;
          color: #2563eb;
          margin-bottom: 20px;
          display: inline-block;
        }}
        h2 {{
          color: #0f172a;
          font-size: 20px;
          margin-bottom: 8px;
        }}
        p {{
          color: #64748b;
          font-size: 14px;
          line-height: 1.5;
          margin-bottom: 24px;
        }}
        .otp-box {{
          background: #f1f5f9;
          border: 2px dashed #93c5fd;
          border-radius: 12px;
          padding: 16px 24px;
          font-size: 32px;
          font-weight: 800;
          letter-spacing: 8px;
          color: #1d4ed8;
          display: inline-block;
          margin: 8px 0 24px 0;
        }}
        .footer {{
          font-size: 12px;
          color: #94a3b8;
          margin-top: 24px;
          border-top: 1px solid #f1f5f9;
          padding-top: 16px;
        }}
      </style>
    </head>
    <body>
      <div class="container">
        <div class="logo">✦ PaperGraph</div>
        <h2>Verify Your Email</h2>
        <p>Use the verification code below to complete your researcher account registration. This code is valid for 10 minutes.</p>
        <div class="otp-box">{code}</div>
        <p>If you didn't request this code, you can safely ignore this email.</p>
        <div class="footer">
          PaperGraph Research Literature Platform
        </div>
      </div>
    </body>
    </html>
    """


import asyncio
import os
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText


async def _send_resend_email(to_email: str, code: str) -> bool:
    api_key = settings.RESEND_API_KEY or os.getenv("RESEND_API_KEY")
    if not api_key:
        return False
    try:
        from_email = settings.EMAILS_FROM_EMAIL or os.getenv("EMAILS_FROM_EMAIL") or "PaperGraph <onboarding@resend.dev>"
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.post(
                "https://api.resend.com/emails",
                headers={
                    "Authorization": f"Bearer {api_key.strip()}",
                    "Content-Type": "application/json",
                },
                json={
                    "from": from_email,
                    "to": [to_email],
                    "subject": f"PaperGraph Verification Code: {code}",
                    "html": _generate_otp_html(code),
                },
            )
            if resp.is_success:
                logger.info(f"OTP successfully delivered via Resend HTTPS API to {to_email}")
                return True
            else:
                logger.warning(f"Resend API returned non-success: {resp.status_code} - {resp.text}")
                return False
    except Exception as e:
        logger.warning(f"Failed to deliver email via Resend API: {e}")
        return False


def _send_smtp_email(to_email: str, code: str) -> bool:
    smtp_user = settings.SMTP_USER or os.getenv("SMTP_USER")
    smtp_pass = settings.SMTP_PASSWORD or os.getenv("SMTP_PASSWORD")
    smtp_host = settings.SMTP_HOST or os.getenv("SMTP_HOST", "smtp.gmail.com")
    smtp_port = int(settings.SMTP_PORT or os.getenv("SMTP_PORT", 587))

    if not smtp_user or not smtp_pass:
        logger.error("Gmail SMTP credentials (SMTP_USER/SMTP_PASSWORD) are not configured!")
        return False
    try:
        from_email = settings.EMAILS_FROM_EMAIL or os.getenv("EMAILS_FROM_EMAIL") or smtp_user
        clean_pass = smtp_pass.replace(" ", "").strip()

        msg = MIMEMultipart("alternative")
        msg["Subject"] = f"PaperGraph Verification Code: {code}"
        msg["From"] = f"PaperGraph <{from_email}>"
        msg["To"] = to_email

        html_part = MIMEText(_generate_otp_html(code), "html")
        msg.attach(html_part)

        with smtplib.SMTP(smtp_host, smtp_port, timeout=8) as server:
            server.starttls()
            server.login(smtp_user, clean_pass)
            server.send_message(msg)
        logger.info(f"OTP successfully delivered via Gmail SMTP to {to_email}")
        return True
    except Exception as e:
        logger.warning(f"Failed to send email via SMTP to {to_email}: {e}")
        return False


async def _dispatch_email_task(email: str, code: str):
    loop = asyncio.get_event_loop()
    await loop.run_in_executor(None, _send_smtp_email, email, code)


@router.post("/send-otp")
async def send_otp(req: SendOtpRequest):
    _prune_expired_otps()
    email = req.email.strip().lower()

    smtp_user = settings.SMTP_USER or os.getenv("SMTP_USER")
    smtp_pass = settings.SMTP_PASSWORD or os.getenv("SMTP_PASSWORD")
    resend_key = settings.RESEND_API_KEY or os.getenv("RESEND_API_KEY")

    # Generate a cryptographically secure 6-digit numeric OTP
    code = f"{secrets.randbelow(900000) + 100000}"
    expires_at = time.time() + OTP_EXPIRY_SECONDS

    _otp_store[email] = {
        "code": code,
        "expires_at": expires_at,
        "attempts": 0,
    }

    # Prominently log unmasked OTP to stdout (Immediately accessible in Render Dashboard -> Logs):
    print(
        f"\n"
        f"====================================================\n"
        f"[PAPERGRAPH AUTH] OTP GENERATED FOR: {email}\n"
        f"VERIFICATION CODE: {code}\n"
        f"====================================================\n",
        flush=True,
    )

    # Safe masked log for internal loggers
    masked_code = f"{code[:2]}****"
    logger.info(f"[PAPERGRAPH OTP] Generated verification code for {email}: {masked_code}")

    # For mock/test domains, avoid sending real emails
    if email.endswith("@example.com") or email.endswith("@test.com"):
        return {
            "success": True,
            "message": "Verification code generated for test account.",
            "expires_in_seconds": OTP_EXPIRY_SECONDS,
        }

    email_delivered = False

    # 1. Attempt delivery via Resend HTTPS API (Port 443 - NEVER blocked by Render)
    if resend_key:
        email_delivered = await _send_resend_email(email, code)

    # 2. Attempt delivery via SMTP if not delivered and credentials are provided
    if not email_delivered and smtp_user and smtp_pass:
        loop = asyncio.get_event_loop()
        try:
            email_delivered = await asyncio.wait_for(
                loop.run_in_executor(None, _send_smtp_email, email, code),
                timeout=7.0,
            )
        except asyncio.TimeoutError:
            logger.warning(f"SMTP timeout sending code to {email}. Outbound port 587 is likely blocked by Render free tier.")
        except Exception as e:
            logger.warning(f"SMTP error sending code to {email}: {e}")

    if email_delivered:
        return {
            "success": True,
            "message": "Verification code sent to your email inbox.",
            "expires_in_seconds": OTP_EXPIRY_SECONDS,
        }

    # If neither delivery method succeeded (e.g. Render port 587 block without Resend):
    # Log clear diagnostic instructions to Render Logs and allow the user to complete verification
    logger.warning(
        f"[PAPERGRAPH AUTH] Outbound email could not be delivered to {email}. "
        f"Note: Render Free Tier blocks outbound SMTP port 587. "
        f"The valid verification code is logged above in server stdout for immediate use."
    )

    return {
        "success": True,
        "message": "Verification code generated! (If email is delayed by cloud port limits, view the code in Render Logs).",
        "delivery_status": "console_fallback",
        "expires_in_seconds": OTP_EXPIRY_SECONDS,
    }


@router.post("/verify-otp")
async def verify_otp(req: VerifyOtpRequest):
    _prune_expired_otps()
    email = req.email.strip().lower()
    code = req.code.strip()

    record = _otp_store.get(email)
    if not record:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No verification code found for this email. Please request a new code.",
        )

    if time.time() > record["expires_at"]:
        _otp_store.pop(email, None)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Verification code has expired. Please request a new code.",
        )

    if record["code"] != code:
        record["attempts"] = record.get("attempts", 0) + 1
        if record["attempts"] >= MAX_OTP_ATTEMPTS:
            _otp_store.pop(email, None)
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Too many incorrect attempts. This verification code has been invalidated. Please request a new one.",
            )

        remaining = MAX_OTP_ATTEMPTS - record["attempts"]
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Incorrect verification code. {remaining} attempt(s) remaining.",
        )

    # Validated: Remove OTP so it cannot be re-used
    _otp_store.pop(email, None)

    return {
        "success": True,
        "message": "Email verified successfully.",
    }
