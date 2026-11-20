"""
Authentication, password storage and authorisation for RoadResQ.

Replaces the previous scheme, which:
  * stored passwords in plaintext,
  * echoed the stored password back in API responses,
  * and let any unauthenticated caller mutate any rescue request.

Provides:
  * PBKDF2-SHA256 password hashing with per-password salt and constant-time
    verification, plus transparent upgrade of legacy plaintext rows,
  * stateless HMAC-SHA256 signed bearer tokens (no extra dependency),
  * Flask decorators `require_auth` / `require_role` / `require_self_or_admin`.

Spec references: §7, §8 (auth), §39 (security, ownership checks).
"""

from __future__ import annotations

import base64
import functools
import hashlib
import hmac
import json
import os
import time
from typing import Any, Callable, Dict, Optional

from flask import jsonify, request

from config import Config

# ── Password hashing ────────────────────────────────────────────────────────
_ALGO = "pbkdf2_sha256"
_ITERATIONS = 120_000
_SALT_BYTES = 16

# Fields that must never leave the backend in a response.
SENSITIVE_FIELDS = ("password", "passwordHash", "password_hash", "passwordSalt")


def hash_password(plain: str) -> str:
    """Hash a password into `pbkdf2_sha256$iterations$salt$digest` form."""
    if not isinstance(plain, str):
        plain = str(plain)
    salt = os.urandom(_SALT_BYTES)
    digest = hashlib.pbkdf2_hmac(
        "sha256", plain.encode("utf-8"), salt, _ITERATIONS
    )
    return "{}${}${}${}".format(
        _ALGO,
        _ITERATIONS,
        base64.b64encode(salt).decode("ascii"),
        base64.b64encode(digest).decode("ascii"),
    )


def is_hashed(stored: Any) -> bool:
    """True when `stored` already looks like a value produced by hash_password."""
    return isinstance(stored, str) and stored.startswith(_ALGO + "$")


def verify_password(stored: Any, candidate: str) -> bool:
    """Constant-time password check.

    Supports legacy plaintext rows so existing demo accounts keep working; the
    caller may then re-save using `hash_password` (see `needs_rehash`).
    """
    if stored is None or candidate is None:
        return False

    if not is_hashed(stored):
        # Legacy plaintext comparison — constant time to avoid leaking length.
        return hmac.compare_digest(str(stored), str(candidate))

    try:
        _, iterations, salt_b64, digest_b64 = str(stored).split("$", 3)
        salt = base64.b64decode(salt_b64)
        expected = base64.b64decode(digest_b64)
        actual = hashlib.pbkdf2_hmac(
            "sha256", str(candidate).encode("utf-8"), salt, int(iterations)
        )
        return hmac.compare_digest(expected, actual)
    except Exception:
        return False


def needs_rehash(stored: Any) -> bool:
    """True when the stored password should be re-saved as a hash."""
    return not is_hashed(stored)


def sanitize_document(doc: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    """Return a copy of `doc` with every sensitive field removed."""
    if not doc:
        return {}
    cleaned = {}
    for key, value in doc.items():
        if key in SENSITIVE_FIELDS:
            continue
        cleaned[key] = value
    return cleaned


# ── Tokens ──────────────────────────────────────────────────────────────────
def _b64url_encode(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")


def _b64url_decode(text: str) -> bytes:
    padding = "=" * (-len(text) % 4)
    return base64.urlsafe_b64decode(text + padding)


def _sign(payload_b64: str) -> str:
    mac = hmac.new(
        Config.SECRET_KEY.encode("utf-8"),
        payload_b64.encode("ascii"),
        hashlib.sha256,
    )
    return _b64url_encode(mac.digest())


def issue_token(
    subject_id: str,
    role: str,
    extra: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """Mint a signed token for `subject_id` acting as `role`.

    Returns a dict with the token, its expiry and the role so the client can
    store everything it needs in one step.
    """
    issued_at = int(time.time())
    expires_at = issued_at + Config.TOKEN_TTL_SECONDS

    payload: Dict[str, Any] = {
        "sub": str(subject_id),
        "role": role,
        "iat": issued_at,
        "exp": expires_at,
    }
    if extra:
        payload.update(extra)

    payload_b64 = _b64url_encode(
        json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8")
    )
    token = f"{payload_b64}.{_sign(payload_b64)}"

    return {
        "token": token,
        "tokenType": "Bearer",
        "role": role,
        "subjectId": str(subject_id),
        "issuedAt": issued_at,
        "expiresAt": expires_at,
        "expiresIn": Config.TOKEN_TTL_SECONDS,
    }


def decode_token(token: str) -> Optional[Dict[str, Any]]:
    """Verify signature + expiry and return the payload, or None."""
    if not token or not isinstance(token, str):
        return None

    if token.count(".") != 1:
        return None

    payload_b64, signature = token.split(".", 1)
    if not hmac.compare_digest(_sign(payload_b64), signature):
        return None

    try:
        payload = json.loads(_b64url_decode(payload_b64).decode("utf-8"))
    except Exception:
        return None

    if not isinstance(payload, dict):
        return None

    if int(payload.get("exp", 0)) < int(time.time()):
        return None

    return payload


def token_from_request() -> Optional[str]:
    """Extract a bearer token from the Authorization header or `token` field."""
    header = request.headers.get("Authorization", "")
    if header.lower().startswith("bearer "):
        return header[7:].strip()

    # Fallback: allow ?token= for quick manual testing / curl.
    token = request.args.get("token")
    if token:
        return token.strip()

    body = request.get_json(silent=True)
    if isinstance(body, dict) and body.get("token"):
        return str(body["token"]).strip()

    return None


def current_identity() -> Optional[Dict[str, Any]]:
    """Return the decoded token payload for the current request, or None."""
    return decode_token(token_from_request() or "")


# ── Decorators ──────────────────────────────────────────────────────────────
def _auth_error(message: str, status: int = 401):
    return jsonify({"success": False, "message": message, "code": status}), status


def require_auth(view: Callable):
    """Reject the request unless a valid, unexpired token is presented."""

    @functools.wraps(view)
    def wrapper(*args, **kwargs):
        identity = current_identity()
        if not identity:
            return _auth_error("Authentication required")
        request.identity = identity  # type: ignore[attr-defined]
        return view(*args, **kwargs)

    return wrapper


def require_role(*roles: str):
    """Reject unless the caller holds one of `roles` (admins always pass)."""

    def decorator(view: Callable):
        @functools.wraps(view)
        def wrapper(*args, **kwargs):
            identity = current_identity()
            if not identity:
                return _auth_error("Authentication required")
            role = str(identity.get("role", ""))
            if role != "admin" and role not in roles:
                return _auth_error(
                    f"This action requires role: {', '.join(roles)}", 403
                )
            request.identity = identity  # type: ignore[attr-defined]
            return view(*args, **kwargs)

        return wrapper

    return decorator


def require_self_or_admin(id_kwarg: str = "mechanic_id"):
    """Allow only the caller acting as themselves, or an admin.

    Used so a mechanic can only accept/arrive/complete their own job, and a
    user can only cancel their own request. §39
    """

    def decorator(view: Callable):
        @functools.wraps(view)
        def wrapper(*args, **kwargs):
            identity = current_identity()
            if not identity:
                return _auth_error("Authentication required")

            role = str(identity.get("role", ""))
            if role == "admin":
                request.identity = identity  # type: ignore[attr-defined]
                return view(*args, **kwargs)

            target_id = (
                kwargs.get(id_kwarg)
                or (request.view_args or {}).get(id_kwarg)
            )
            if target_id and str(identity.get("sub")) != str(target_id):
                return _auth_error(
                    "You may only act on your own record", 403
                )

            request.identity = identity  # type: ignore[attr-defined]
            return view(*args, **kwargs)

        return wrapper

    return decorator


def verify_webhook_signature(body: bytes, signature: str, secret: str) -> bool:
    """HMAC-SHA256 check for gateway webhooks (Razorpay uses this scheme)."""
    if not body or not signature or not secret:
        return False
    expected = hmac.new(
        secret.encode("utf-8"), body, hashlib.sha256
    ).hexdigest()
    return hmac.compare_digest(expected, signature)
