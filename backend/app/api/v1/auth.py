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

# In-memory OTP store: { email: { "code": str, "expires_at": float } }
# OTPs expire in 10 minutes (600 seconds)
_otp_store: Dict[str, Dict[str, Any]] = {}
OTP_EXPIRY_SECONDS = 600


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

        with smtplib.SMTP(smtp_host, smtp_port, timeout=15) as server:
            server.starttls()
            server.login(smtp_user, clean_pass)
            server.send_message(msg)
        logger.info(f"OTP successfully delivered via Gmail SMTP to {to_email}")
        print(f"[SUCCESS] OTP code {code} successfully sent via Gmail to {to_email}!", flush=True)
        return True
    except Exception as e:
        logger.error(f"Failed to send email via SMTP to {to_email}: {e}")
        print(f"[ERROR] Failed to send email via SMTP to {to_email}: {e}", flush=True)
        return False


async def _dispatch_email_task(email: str, code: str):
    loop = asyncio.get_event_loop()
    await loop.run_in_executor(None, _send_smtp_email, email, code)


@router.post("/send-otp")
async def send_otp(req: SendOtpRequest, background_tasks: BackgroundTasks):
    email = req.email.strip().lower()
    # Generate a cryptographically secure 6-digit numeric OTP
    code = f"{secrets.randbelow(900000) + 100000}"
    expires_at = time.time() + OTP_EXPIRY_SECONDS

    _otp_store[email] = {
        "code": code,
        "expires_at": expires_at,
    }

    # Print clearly in terminal for instant dev inspection & testing
    print(f"\n=======================================================", flush=True)
    print(f"[PAPERGRAPH OTP] Code for {email}: {code}", flush=True)
    print(f"=======================================================\n", flush=True)

    # Dispatch email in background so the client receives an immediate response
    background_tasks.add_task(_dispatch_email_task, email, code)

    return {
        "success": True,
        "message": "Verification code generated and sent to your email.",
        "expires_in_seconds": OTP_EXPIRY_SECONDS,
    }


@router.post("/verify-otp")
async def verify_otp(req: VerifyOtpRequest):
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
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Incorrect verification code. Please check your email and try again.",
        )

    # Validated: Remove OTP so it cannot be re-used
    _otp_store.pop(email, None)

    return {
        "success": True,
        "message": "Email verified successfully.",
    }
