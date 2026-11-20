"""
SMS delivery for login OTPs.

WHY THIS EXISTS
---------------
Until now every OTP was the fixed development code printed on the phone screen:
no SMS was ever attempted. That is unusable in the field — a rider cannot log in
from a phone they have not seen before, and a demo that shows the code on screen
is not a real login.

This module sends a real message when a provider is configured and reports
honestly when it is not. It never pretends a message was delivered.

Providers (pick one with SMS_PROVIDER):

  twilio    TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_FROM
  msg91     MSG91_AUTH_KEY, MSG91_TEMPLATE_ID   (India)
  fast2sms  FAST2SMS_API_KEY                    (India)

Only the standard library is used, so enabling a provider needs no new
dependency — set the variables and restart the backend.

Nothing here is claimed to be a production SMS gateway integration with delivery
receipts: `send` returns whether the provider API accepted the message.
"""

from __future__ import annotations

import base64
import json
import logging
import re
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass

from config import Config

log = logging.getLogger("roadresq.sms")


# ── Phone numbers ──────────────────────────────────────────────────────────
def normalize_phone(raw: str) -> str | None:
    """Return an E.164 number, or None when the input cannot be one.

    Accepts what people actually type: '9876543210', '+91 98765 43210',
    '09876543210'. Defaults to +91 because this deployment is India-only; the
    country code is a configuration value, not an assumption baked into a route.
    """
    digits = re.sub(r"\D", "", raw or "")
    if not digits:
        return None

    cc = re.sub(r"\D", "", Config.SMS_DEFAULT_COUNTRY_CODE) or "91"

    if digits.startswith("00"):
        digits = digits[2:]
    if digits.startswith(cc) and len(digits) > 10:
        return "+" + digits
    if digits.startswith("0") and len(digits) == 11:
        digits = digits[1:]
    if len(digits) == 10:
        return "+" + cc + digits
    if 8 <= len(digits) <= 15:
        return "+" + digits
    return None


def _digits(phone: str) -> str:
    return re.sub(r"\D", "", phone)


# ── Result ─────────────────────────────────────────────────────────────────
@dataclass
class SmsResult:
    ok: bool
    provider: str
    detail: str = ""

    def as_dict(self) -> dict:
        return {"sent": self.ok, "provider": self.provider, "detail": self.detail}


def _not_configured() -> SmsResult:
    return SmsResult(
        ok=False,
        provider="none",
        # Deliberately states only the fact. Whether the code reaches the app is
        # decided by the caller (DEV_MODE), so this message must not claim it did.
        detail="No SMS provider is configured, so the login code could not be "
               "delivered by SMS. Set SMS_PROVIDER and its credentials.",
    )


def _post_json(url: str, payload: dict, headers: dict, timeout: float = 10.0):
    body = json.dumps(payload).encode()
    request = urllib.request.Request(url, data=body, method="POST")
    request.add_header("Content-Type", "application/json")
    for key, value in headers.items():
        request.add_header(key, value)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        text = response.read().decode("utf-8", "replace")
        return response.status, text


def _post_form(url: str, fields: dict, headers: dict, timeout: float = 10.0):
    body = urllib.parse.urlencode(fields).encode()
    request = urllib.request.Request(url, data=body, method="POST")
    request.add_header("Content-Type", "application/x-www-form-urlencoded")
    for key, value in headers.items():
        request.add_header(key, value)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        text = response.read().decode("utf-8", "replace")
        return response.status, text


# ── Providers ──────────────────────────────────────────────────────────────
def _send_twilio(phone: str, message: str) -> SmsResult:
    sid = Config.TWILIO_ACCOUNT_SID
    token = Config.TWILIO_AUTH_TOKEN
    sender = Config.TWILIO_FROM
    if not (sid and token and sender):
        return SmsResult(False, "twilio", "TWILIO_ACCOUNT_SID/AUTH_TOKEN/FROM incomplete")

    url = f"https://api.twilio.com/2010-04-01/Accounts/{sid}/Messages.json"
    auth = base64.b64encode(f"{sid}:{token}".encode()).decode()
    status, text = _post_form(
        url,
        {"To": phone, "From": sender, "Body": message},
        {"Authorization": f"Basic {auth}"},
    )
    if 200 <= status < 300:
        return SmsResult(True, "twilio")
    return SmsResult(False, "twilio", f"HTTP {status}: {text[:160]}")


def _send_msg91(phone: str, message: str, code: str) -> SmsResult:
    key = Config.MSG91_AUTH_KEY
    template = Config.MSG91_TEMPLATE_ID
    if not (key and template):
        return SmsResult(False, "msg91", "MSG91_AUTH_KEY / MSG91_TEMPLATE_ID missing")

    query = urllib.parse.urlencode({
        "template_id": template,
        "mobile": _digits(phone),
        "authkey": key,
        "otp": code,
        "otp_expiry": str(max(1, Config.OTP_TTL_SECONDS // 60)),
    })
    request = urllib.request.Request(
        f"https://control.msg91.com/api/v5/otp?{query}",
        data=b"",
        method="POST",
    )
    request.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(request, timeout=10) as response:
        text = response.read().decode("utf-8", "replace")
        status = response.status
    if 200 <= status < 300 and '"type":"success"' in text.replace(" ", ""):
        return SmsResult(True, "msg91")
    return SmsResult(False, "msg91", f"HTTP {status}: {text[:160]}")


def _send_fast2sms(phone: str, message: str) -> SmsResult:
    key = Config.FAST2SMS_API_KEY
    if not key:
        return SmsResult(False, "fast2sms", "FAST2SMS_API_KEY missing")

    status, text = _post_json(
        "https://www.fast2sms.com/dev/bulkV2",
        {
            "route": "q",
            "message": message,
            "numbers": _digits(phone)[-10:],
            "flash": 0,
        },
        {"authorization": key},
    )
    if 200 <= status < 300 and '"return":true' in text.replace(" ", "").lower():
        return SmsResult(True, "fast2sms")
    return SmsResult(False, "fast2sms", f"HTTP {status}: {text[:160]}")


def send(phone: str, message: str, code: str = "") -> SmsResult:
    """Send one SMS. Never raises: a delivery failure must not break login."""
    if not Config.sms_configured():
        return _not_configured()

    provider = Config.SMS_PROVIDER
    try:
        if provider == "twilio":
            return _send_twilio(phone, message)
        if provider == "msg91":
            return _send_msg91(phone, message, code)
        if provider == "fast2sms":
            return _send_fast2sms(phone, message)
        return SmsResult(False, provider, f"Unknown SMS_PROVIDER '{provider}'")
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")[:160]
        log.warning("SMS via %s failed: HTTP %s %s", provider, exc.code, detail)
        return SmsResult(False, provider, f"HTTP {exc.code}: {detail}")
    except Exception as exc:  # network, DNS, timeout
        log.warning("SMS via %s failed: %s", provider, exc)
        return SmsResult(False, provider, str(exc)[:160])


def otp_message(code: str) -> str:
    minutes = max(1, Config.OTP_TTL_SECONDS // 60)
    return (
        f"{code} is your RoadResQ verification code. "
        f"Valid for {minutes} minutes. Do not share it with anyone."
    )


def send_otp(phone: str, code: str) -> SmsResult:
    return send(phone, otp_message(code), code)


def status() -> dict:
    """What the app/admin can show about SMS configuration."""
    return {
        "configured": Config.sms_configured(),
        "provider": Config.SMS_PROVIDER or "none",
        "senderConfigured": bool(
            Config.TWILIO_FROM or Config.MSG91_SENDER_ID or Config.FAST2SMS_API_KEY
        ),
        "devFallback": not Config.sms_configured() and Config.DEV_MODE,
    }
