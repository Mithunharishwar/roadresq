"""
Razorpay integration for RoadResQ.

Two rules from the master prompt drive this module:

  * §29 — never implement a fake "Payment Successful" button and call it a
    payment. Order creation and verification both happen here, server-side.
  * §29/§39 — the key secret never reaches the Flutter app and is never a
    literal in source.

The `razorpay` SDK is optional: when it is not installed, or when credentials
are absent, the module enters an explicitly-labelled *simulation* mode so the
rest of the platform stays testable. Simulation mode marks every record with
`simulated: true`, and `/api/payments/verify` refuses to mark a request as paid
on the strength of a simulated payment while `DEV_MODE` is off.
"""

from __future__ import annotations

import hashlib
import hmac
import logging
from typing import Any, Dict, Optional

from config import Config

log = logging.getLogger("roadresq.payments")

try:  # pragma: no cover - depends on environment
    import razorpay  # type: ignore

    _RAZORPAY_SDK = True
except Exception:  # pragma: no cover
    razorpay = None  # type: ignore
    _RAZORPAY_SDK = False


def sdk_available() -> bool:
    return _RAZORPAY_SDK and Config.payments_enabled()


def get_client():
    """Return a configured Razorpay client, or None when unavailable."""
    if not sdk_available():
        return None
    try:
        return razorpay.Client(  # type: ignore[union-attr]
            auth=(Config.RAZORPAY_KEY_ID, Config.RAZORPAY_KEY_SECRET)
        )
    except Exception as exc:  # pragma: no cover
        log.warning("Razorpay client init failed: %s", exc)
        return None


def create_order(
    amount_minor_units: int,
    receipt: str,
    notes: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """Create a Razorpay order (real when configured, simulated otherwise).

    Returns a dict always containing `success`, `mode` ("live" | "test" |
    "simulated") and, on success, `orderId`, `amount`, `currency`.
    """
    if amount_minor_units <= 0:
        return {
            "success": False,
            "message": "Amount must be greater than zero",
            "mode": "invalid",
        }

    client = get_client()

    if client is None:
        # Explicit simulation. Clearly flagged — never presented as a real order.
        simulated_id = "sim_order_" + hashlib.sha256(
            f"{receipt}:{amount_minor_units}:{Config.SECRET_KEY[:12]}".encode()
        ).hexdigest()[:20]
        return {
            "success": True,
            "mode": "simulated",
            "simulated": True,
            "orderId": simulated_id,
            "amount": amount_minor_units,
            "currency": Config.PRICING_CURRENCY,
            "receipt": receipt,
            "notes": notes or {},
            "message": (
                "SIMULATED order — Razorpay credentials are not configured. "
                "Set RAZORPAY_KEY_ID / RAZORPAY_KEY_SECRET for test-mode orders."
            ),
        }

    try:
        order = client.order.create(
            {
                "amount": int(amount_minor_units),
                "currency": Config.PRICING_CURRENCY,
                "receipt": receipt,
                "notes": notes or {},
            }
        )
        return {
            "success": True,
            "mode": "test" if Config.RAZORPAY_TEST_MODE else "live",
            "simulated": False,
            "orderId": order.get("id"),
            "amount": order.get("amount"),
            "currency": order.get("currency"),
            "receipt": order.get("receipt", receipt),
            "status": order.get("status"),
            # The publishable key id is safe for the client; the secret is not.
            "keyId": Config.RAZORPAY_KEY_ID,
        }
    except Exception as exc:
        log.warning("Razorpay order creation failed: %s", exc)
        return {"success": False, "message": f"Order creation failed: {exc}", "mode": "error"}


def verify_signature(
    order_id: str, payment_id: str, signature: str
) -> Dict[str, Any]:
    """Verify a Razorpay checkout signature server-side.

    Razorpay signs `"{order_id}|{payment_id}"` with HMAC-SHA256 using the key
    secret. A client cannot forge this without the secret. §29
    """
    if not order_id or not payment_id or not signature:
        return {
            "verified": False,
            "reason": "orderId, paymentId and signature are all required",
        }

    if not Config.RAZORPAY_KEY_SECRET:
        return {
            "verified": False,
            "simulated": True,
            "reason": (
                "RAZORPAY_KEY_SECRET is not configured, so no signature can be "
                "verified. Payment is NOT confirmed."
            ),
        }

    expected = hmac.new(
        Config.RAZORPAY_KEY_SECRET.encode("utf-8"),
        f"{order_id}|{payment_id}".encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()

    if hmac.compare_digest(expected, str(signature)):
        return {"verified": True, "reason": "signature valid"}

    return {"verified": False, "reason": "signature mismatch"}


def fetch_payment(payment_id: str) -> Dict[str, Any]:
    """Fetch a payment from Razorpay to confirm its captured status."""
    client = get_client()
    if client is None:
        return {
            "success": False,
            "message": "Razorpay is not configured; cannot fetch payment",
        }
    try:
        payment = client.payment.fetch(payment_id)
        return {"success": True, "payment": payment}
    except Exception as exc:
        return {"success": False, "message": str(exc)}
