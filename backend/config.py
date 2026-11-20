"""
RoadResQ backend configuration — single source of truth.

Every tunable value (hosts, credentials, allocation weights, pricing) is read
from the environment here. No route module may hardcode a secret, a host, or a
weight. See .env.example for the full list.

Spec references: §4 (no hardcoded dev IP), §18 (configurable weights),
§29/§30 (configurable pricing), §39 (no hardcoded secrets), §42 (dev mode).
"""

from __future__ import annotations

import os

try:
    # Optional: lets a local .env file drive development without editing code.
    from dotenv import load_dotenv

    load_dotenv()
except Exception:  # pragma: no cover - dotenv is optional
    pass


def _get_bool(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def _get_int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, str(default)))
    except (TypeError, ValueError):
        return default


def _get_float(name: str, default: float) -> float:
    try:
        return float(os.getenv(name, str(default)))
    except (TypeError, ValueError):
        return default


class Config:
    """Runtime configuration, resolved once at import time."""

    # ── Server ──────────────────────────────────────────────────────────
    # Deliberately NOT named ROADRESQ_HOST: the Flutter client uses
    # `--dart-define=ROADRESQ_HOST=<url>` to point at this server, and the two
    # must never be confused.
    HOST = os.getenv("ROADRESQ_BIND_HOST", "0.0.0.0")
    PORT = _get_int("ROADRESQ_PORT", 5050)
    # debug must be OFF by default: Flask debug enables the Werkzeug console,
    # which is remote code execution if the port is reachable. §39
    DEBUG = _get_bool("ROADRESQ_DEBUG", False)

    # ── Secrets ─────────────────────────────────────────────────────────
    # A random per-boot key is generated when unset so the app never ships a
    # literal secret. Set ROADRESQ_SECRET_KEY in production to keep tokens
    # valid across restarts.
    SECRET_KEY = os.getenv("ROADRESQ_SECRET_KEY") or os.urandom(32).hex()
    TOKEN_TTL_SECONDS = _get_int("ROADRESQ_TOKEN_TTL_SECONDS", 60 * 60 * 24 * 7)

    # ── Database ────────────────────────────────────────────────────────
    MONGO_URI = os.getenv("MONGO_URI", "mongodb://localhost:27017/")
    DB_NAME = os.getenv("ROADRESQ_DB_NAME", "roadresq_db")
    MONGO_TIMEOUT_MS = _get_int("MONGO_TIMEOUT_MS", 3000)

    # ── Development / demo mode ─────────────────────────────────────────
    # When true the backend exposes clearly-labelled demo helpers: the fixed
    # OTP and instant mechanic access. Never enable in production. §7, §42
    DEV_MODE = _get_bool("ROADRESQ_DEV_MODE", True)
    # Fixed OTP used only while DEV_MODE is on.
    DEV_OTP = os.getenv("ROADRESQ_DEV_OTP", "1234")

    # ── OTP ────────────────────────────────────────────────────────────
    # Real codes, held server-side as hashes. Two consecutive logins can no
    # longer share a hardcoded constant. §7, §42
    OTP_LENGTH = _get_int("ROADRESQ_OTP_LENGTH", 6)
    OTP_TTL_SECONDS = _get_int("ROADRESQ_OTP_TTL_SECONDS", 300)
    OTP_MAX_ATTEMPTS = _get_int("ROADRESQ_OTP_MAX_ATTEMPTS", 5)
    OTP_RESEND_COOLDOWN_SECONDS = _get_int("ROADRESQ_OTP_RESEND_SECONDS", 30)
    # Rolling one-hour ceiling on codes issued to a single number. The 30-second
    # cooldown above only stops a client retry loop; this stops the SMS bill from
    # being driven up by someone rotating requests across all four login forms.
    # 0 disables the cap (development only).
    OTP_MAX_PER_HOUR = _get_int("ROADRESQ_OTP_MAX_PER_HOUR", 8)

    # ── SMS delivery ───────────────────────────────────────────────────
    # Empty provider = no SMS. The app then shows the code only while DEV_MODE
    # is on, and the API says `smsSent: false` instead of implying delivery.
    SMS_PROVIDER = os.getenv("SMS_PROVIDER", "").strip().lower()
    SMS_SENDER_NAME = os.getenv("SMS_SENDER_NAME", "RoadResQ")
    SMS_DEFAULT_COUNTRY_CODE = os.getenv("SMS_DEFAULT_COUNTRY_CODE", "91")

    TWILIO_ACCOUNT_SID = os.getenv("TWILIO_ACCOUNT_SID", "")
    TWILIO_AUTH_TOKEN = os.getenv("TWILIO_AUTH_TOKEN", "")
    TWILIO_FROM = os.getenv("TWILIO_FROM", "")

    MSG91_AUTH_KEY = os.getenv("MSG91_AUTH_KEY", "")
    MSG91_TEMPLATE_ID = os.getenv("MSG91_TEMPLATE_ID", "")
    MSG91_SENDER_ID = os.getenv("MSG91_SENDER_ID", "")

    FAST2SMS_API_KEY = os.getenv("FAST2SMS_API_KEY", "")

    @classmethod
    def sms_configured(cls) -> bool:
        """True when the selected provider has everything it needs."""
        if cls.SMS_PROVIDER == "twilio":
            return bool(cls.TWILIO_ACCOUNT_SID and cls.TWILIO_AUTH_TOKEN and cls.TWILIO_FROM)
        if cls.SMS_PROVIDER == "msg91":
            return bool(cls.MSG91_AUTH_KEY and cls.MSG91_TEMPLATE_ID)
        if cls.SMS_PROVIDER == "fast2sms":
            return bool(cls.FAST2SMS_API_KEY)
        return False

    # ── Allocation (region / eligibility / ranking) ─────────────────────
    # Default search radius around the resolved region, in km.
    DEFAULT_SEARCH_RADIUS_KM = _get_float("ALLOC_SEARCH_RADIUS_KM", 10.0)
    # Radius used when no eligible mechanic exists inside the region. §17
    ESCALATION_RADIUS_KM = _get_float("ALLOC_ESCALATION_RADIUS_KM", 25.0)
    # Assumed average travel speed for ETA, km/h. Not a measured value. §22
    ASSUMED_AVG_SPEED_KMH = _get_float("ALLOC_ASSUMED_SPEED_KMH", 30.0)
    # A mechanic whose location is older than this is treated as stale. §17
    LOCATION_STALENESS_SECONDS = _get_int("ALLOC_LOCATION_STALE_SECONDS", 900)

    # Ranking weights — deliberately simple, configurable and inspectable.
    # These are NOT claimed to be scientifically optimal. §18
    W_PROXIMITY = _get_float("ALLOC_W_PROXIMITY", 0.45)
    W_SERVICE = _get_float("ALLOC_W_SERVICE", 0.20)
    W_AVAILABILITY = _get_float("ALLOC_W_AVAILABILITY", 0.15)
    W_VERIFICATION = _get_float("ALLOC_W_VERIFICATION", 0.10)
    W_WORKLOAD = _get_float("ALLOC_W_WORKLOAD", 0.05)
    W_RATING = _get_float("ALLOC_W_RATING", 0.05)

    # ── Domain ──────────────────────────────────────────────────────────
    # Canonical vehicle categories (§11). Additive — new categories can be
    # added without touching the request workflow.
    VEHICLE_CATEGORIES = [
        "Bike", "Scooter", "Car", "SUV", "Van", "Truck",
    ]
    # Canonical service categories (§12).
    SERVICE_CATEGORIES = [
        "Flat Tyre", "Battery Problem", "Fuel Delivery",
        "Engine Trouble", "Towing", "General Service",
    ]
    # Reject an identical open request from the same phone within this window. §40
    DUPLICATE_REQUEST_WINDOW_SECONDS = _get_int(
        "ROADRESQ_DUPLICATE_WINDOW_SECONDS", 120
    )

    # ── Pricing (§30) — configurable, explicitly not market-verified ────
    PRICING_CURRENCY = os.getenv("PRICING_CURRENCY", "INR")
    PRICING_BASE_FEE = _get_float("PRICING_BASE_FEE", 199.0)
    PRICING_PER_KM = _get_float("PRICING_PER_KM", 12.0)
    PRICING_TAX_PERCENT = _get_float("PRICING_TAX_PERCENT", 18.0)
    # Additional per-service surcharge, keyed by canonical service name.
    PRICING_SERVICE_SURCHARGE = {
        "Flat Tyre": _get_float("PRICING_SURCHARGE_FLAT_TYRE", 150.0),
        "Battery Problem": _get_float("PRICING_SURCHARGE_BATTERY", 200.0),
        "Fuel Delivery": _get_float("PRICING_SURCHARGE_FUEL", 100.0),
        "Engine Trouble": _get_float("PRICING_SURCHARGE_ENGINE", 300.0),
        "Towing": _get_float("PRICING_SURCHARGE_TOWING", 500.0),
        "General Service": _get_float("PRICING_SURCHARGE_GENERAL", 100.0),
    }

    # ── Escalation watchdog (§52) ──────────────────────────────────────
    # A request that nobody accepts inside this window is escalated by the
    # SERVER (background thread), not only by a client-side timer.
    ESCALATION_SECONDS = _get_int("ROADRESQ_ESCALATION_SECONDS", 300)
    ESCALATION_SCAN_SECONDS = _get_int("ROADRESQ_ESCALATION_SCAN_SECONDS", 20)

    # ── Crew incentives (§42) ──────────────────────────────────────────
    # Share of a completed job's amount paid to the assisting crew member.
    # Deliberately a configuration value, not a claimed market rate.
    ASSISTANT_INCENTIVE_PERCENT = _get_float(
        "ROADRESQ_ASSISTANT_INCENTIVE_PERCENT", 10.0
    )

    # ── Admin console (§51) ────────────────────────────────────────────
    # The admin console is a separate surface from the four app roles. When the
    # password is unset the console is available only in DEV_MODE, with the
    # clearly-labelled development password below.
    ADMIN_USERNAME = os.getenv("ROADRESQ_ADMIN_USER", "admin")
    ADMIN_PASSWORD = os.getenv("ROADRESQ_ADMIN_PASSWORD", "")

    @classmethod
    def admin_login(cls, username: str, password: str) -> bool:
        """Constant-time-ish credential check for the admin console."""
        import hmac

        if not username or not password:
            return False
        if username != cls.ADMIN_USERNAME:
            return False
        if cls.ADMIN_PASSWORD:
            return hmac.compare_digest(password, cls.ADMIN_PASSWORD)
        # No password configured: allow only in DEV_MODE, with the documented
        # development password. Never a silent bypass in production.
        return cls.DEV_MODE and password == "roadresq"

    # ── Payments (§29) ─────────────────────────────────────────────────
    RAZORPAY_KEY_ID = os.getenv("RAZORPAY_KEY_ID", "")
    RAZORPAY_KEY_SECRET = os.getenv("RAZORPAY_KEY_SECRET", "")
    # Razorpay test mode is used when live keys are absent. §29
    RAZORPAY_TEST_MODE = _get_bool("RAZORPAY_TEST_MODE", True)

    @classmethod
    def payments_enabled(cls) -> bool:
        """True when real Razorpay credentials are configured."""
        return bool(cls.RAZORPAY_KEY_ID and cls.RAZORPAY_KEY_SECRET)

    @classmethod
    def allocation_weights(cls) -> dict:
        """Ranking weights, exposed so every decision can log its factors."""
        return {
            "proximity": cls.W_PROXIMITY,
            "service": cls.W_SERVICE,
            "availability": cls.W_AVAILABILITY,
            "verification": cls.W_VERIFICATION,
            "workload": cls.W_WORKLOAD,
            "rating": cls.W_RATING,
        }
