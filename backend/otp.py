"""
Real OTP issue/verify with expiry, attempt limits and resend throttling.

WHY THIS EXISTS
---------------
Every login accepted the same fixed development code (`1234`), for ever, for
every phone. That is not an OTP: it cannot expire, cannot be wrong, and gives
whatever protection a hardcoded constant gives. Real SMS delivery needs the
server to hold a secret per phone that only the SMS recipient can read.

Design notes:
  * The code is random (secrets), never derived from the phone.
  * Only a SHA-256 hash is stored, so a database dump does not reveal live codes.
  * Codes expire (OTP_TTL_SECONDS) and are deleted on success.
  * Wrong attempts are counted per code, and the code is destroyed at the limit,
    so online guessing is bounded.
  * A resend inside OTP_RESEND_COOLDOWN_SECONDS is refused, which also protects
    the SMS bill from a retry loop in any client.
  * Nothing here is claimed to be an SMS gateway; delivery is sms.send().
"""

from __future__ import annotations

import hashlib
import hmac
import logging
import secrets
from datetime import datetime, timedelta

from pymongo.errors import PyMongoError

import db
from config import Config

log = logging.getLogger("roadresq.otp")


class OtpError(Exception):
    """A refusal the caller should surface to the user as-is."""

    def __init__(self, message: str, status: int = 400):
        super().__init__(message)
        self.message = message
        self.status = status


def _collection():
    return db.otp_codes()


def _pepper() -> bytes:
    return (Config.SECRET_KEY or "roadresq").encode()


def _hash(phone: str, purpose: str, code: str) -> str:
    """Bind the hash to the phone and purpose so a code cannot be replayed."""
    material = f"{phone}|{purpose}|{code}".encode()
    return hmac.new(_pepper(), material, hashlib.sha256).hexdigest()


def _now() -> datetime:
    return datetime.utcnow()


def _enforce_hour_cap(phone: str, now: datetime) -> None:
    """Refuse to issue more than OTP_MAX_PER_HOUR codes to one number.

    The 30-second resend cooldown only stops a client retry loop. It does not
    stop someone numbering through all four login forms, so a single phone could
    otherwise generate far more paid SMS than one person needs. The counter is
    kept in its own collection and deliberately NOT reset by a successful
    verification: a resolved code must not refill the hourly budget.
    """
    cap = Config.OTP_MAX_PER_HOUR
    if cap <= 0:
        return

    collection = db.otp_send_log()
    window_start = now - timedelta(hours=1)

    try:
        record = collection.find_one({"phone": phone})
        if record and record.get("windowStart") and record["windowStart"] > window_start:
            used = int(record.get("count") or 0)
            if used >= cap:
                minutes = 1 + int(
                    (record["windowStart"] + timedelta(hours=1) - now).total_seconds() // 60
                )
                raise OtpError(
                    "Too many codes were requested for this number. "
                    f"Try again in about {minutes} minute(s).",
                    429,
                )
            collection.update_one({"phone": phone}, {"$inc": {"count": 1}})
        else:
            collection.update_one(
                {"phone": phone},
                {"$set": {"windowStart": now, "count": 1}},
                upsert=True,
            )
    except PyMongoError as exc:
        # Never block a login because the counter is unavailable; the cooldown
        # still applies.
        log.warning("Could not enforce OTP hourly cap: %s", exc)


def issue(phone: str, purpose: str) -> str:
    """Create and store a fresh code. Returns the plaintext code to be sent."""
    collection = _collection()
    now = _now()

    try:
        existing = collection.find_one({"phone": phone, "purpose": purpose})
    except PyMongoError as exc:
        raise OtpError(f"Could not read OTP state: {exc}", 500) from exc

    if existing and existing.get("createdAt"):
        elapsed = now - existing["createdAt"]
        wait = Config.OTP_RESEND_COOLDOWN_SECONDS - int(elapsed.total_seconds())
        if wait > 0:
            raise OtpError(
                f"Please wait {wait}s before requesting another code.", 429
            )

    _enforce_hour_cap(phone, now)

    code = f"{secrets.randbelow(10 ** Config.OTP_LENGTH):0{Config.OTP_LENGTH}d}"
    document = {
        "phone": phone,
        "purpose": purpose,
        "codeHash": _hash(phone, purpose, code),
        "attempts": 0,
        "createdAt": now,
        "expiresAt": now + timedelta(seconds=Config.OTP_TTL_SECONDS),
        "delivered": False,
    }

    try:
        collection.update_one(
            {"phone": phone, "purpose": purpose},
            {"$set": document},
            upsert=True,
        )
    except PyMongoError as exc:
        raise OtpError(f"Could not store OTP: {exc}", 500) from exc

    return code


def mark_delivered(phone: str, purpose: str, provider: str) -> None:
    try:
        _collection().update_one(
            {"phone": phone, "purpose": purpose},
            {"$set": {"delivered": True, "provider": provider}},
        )
    except PyMongoError as exc:  # non-fatal: the code is already valid
        log.warning("Could not mark OTP delivered: %s", exc)


def verify(phone: str, purpose: str, code: str) -> bool:
    """True only for the live code of this phone/purpose, within limits."""
    collection = _collection()
    try:
        record = collection.find_one({"phone": phone, "purpose": purpose})
    except PyMongoError as exc:
        raise OtpError(f"Could not read OTP: {exc}", 500) from exc

    if not record:
        raise OtpError("No code was requested for this number. Request one first.", 400)

    if record.get("expiresAt") and _now() > record["expiresAt"]:
        collection.delete_one({"_id": record["_id"]})
        raise OtpError("That code has expired. Request a new one.", 401)

    if record.get("attempts", 0) >= Config.OTP_MAX_ATTEMPTS:
        collection.delete_one({"_id": record["_id"]})
        raise OtpError("Too many wrong attempts. Request a new code.", 429)

    expected = record.get("codeHash", "")
    if not hmac.compare_digest(expected, _hash(phone, purpose, code or "")):
        collection.update_one({"_id": record["_id"]}, {"$inc": {"attempts": 1}})
        remaining = Config.OTP_MAX_ATTEMPTS - (record.get("attempts", 0) + 1)
        if remaining <= 0:
            collection.delete_one({"_id": record["_id"]})
            raise OtpError("Too many wrong attempts. Request a new code.", 429)
        raise OtpError(f"Incorrect code. {remaining} attempt(s) left.", 401)

    collection.delete_one({"_id": record["_id"]})
    return True


def ensure_indexes() -> None:
    """Called at boot; a duplicate OTP row for one phone must be impossible."""
    try:
        _collection().create_index(
            [("phone", 1), ("purpose", 1)], unique=True, name="uniq_phone_purpose"
        )
    except PyMongoError as exc:
        log.warning("Could not create OTP index: %s", exc)
