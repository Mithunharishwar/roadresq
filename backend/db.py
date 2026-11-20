"""
MongoDB access layer for RoadResQ.

One client, one set of collection handles, one place where indexes are declared.
Both the legacy `roadresq_backend.py` routes and the new `api_v2` blueprint use
this module so there is exactly one connection.

Spec references: §36 (database design + indexes), §38 (database error handling).
"""

from __future__ import annotations

import logging
from typing import Optional

from pymongo import ASCENDING, DESCENDING, GEO2D, MongoClient
from pymongo.errors import PyMongoError, ServerSelectionTimeoutError

from config import Config

log = logging.getLogger("roadresq.db")

_client: Optional[MongoClient] = None
_db = None


def get_client() -> MongoClient:
    """Return the process-wide MongoClient (created lazily)."""
    global _client
    if _client is None:
        _client = MongoClient(
            Config.MONGO_URI,
            serverSelectionTimeoutMS=Config.MONGO_TIMEOUT_MS,
        )
    return _client


def get_db():
    """Return the RoadResQ database handle."""
    global _db
    if _db is None:
        _db = get_client()[Config.DB_NAME]
    return _db


def ping() -> bool:
    """True when MongoDB answers. Used by /health and /db-test."""
    try:
        get_client().admin.command("ping")
        return True
    except (ServerSelectionTimeoutError, PyMongoError) as exc:
        log.warning("MongoDB ping failed: %s", exc)
        return False


# ─────────────────────────────────────────────────────────────────────────────
# Collection handles
# ─────────────────────────────────────────────────────────────────────────────

def users():
    return get_db()["users"]


def mechanics():
    return get_db()["mechanics"]


def garages():
    return get_db()["garages"]


def rescue_requests():
    return get_db()["rescue_requests"]


def regions():
    return get_db()["regions"]


def hubs():
    return get_db()["hubs"]


def allocation_logs():
    return get_db()["allocation_logs"]


def payments():
    return get_db()["payments"]


def ratings():
    return get_db()["ratings"]


def otp_codes():
    """Live login codes, stored as hashes with an expiry. See otp.py."""
    return get_db()["otp_codes"]


def otp_send_log():
    """Per-number send counters, so one number cannot drain the SMS budget."""
    return get_db()["otp_send_log"]


def notifications():
    return get_db()["notifications"]


def admin_users():
    return get_db()["admin_users"]


def support_tickets():
    return get_db()["support_tickets"]


def tokens():
    return get_db()["tokens"]


def zones():
    return get_db()["zones"]


# ─────────────────────────────────────────────────────────────────────────────
# Indexes  (§36)
# ─────────────────────────────────────────────────────────────────────────────

# (collection_name, keys, unique, name)
_INDEX_SPECS = [
    # Users / mechanics identity lookups
    ("users", [("phone", ASCENDING)], True, "uniq_user_phone"),
    ("users", [("email", ASCENDING)], False, "idx_user_email"),
    ("mechanics", [("phone", ASCENDING)], False, "idx_mechanic_phone"),
    ("mechanics", [("email", ASCENDING)], False, "idx_mechanic_email"),
    # Mechanic allocation hot paths: online + region + hub
    ("mechanics", [("online", ASCENDING)], False, "idx_mechanic_online"),
    ("mechanics", [("available", ASCENDING)], False, "idx_mechanic_available"),
    ("mechanics", [("regionId", ASCENDING)], False, "idx_mechanic_region"),
    ("mechanics", [("hubId", ASCENDING)], False, "idx_mechanic_hub"),
    (
        "mechanics",
        [("regionId", ASCENDING), ("online", ASCENDING), ("available", ASCENDING)],
        False,
        "idx_mechanic_region_availability",
    ),
    ("mechanics", [("services", ASCENDING)], False, "idx_mechanic_services"),
    ("mechanics", [("verificationStatus", ASCENDING)], False, "idx_mechanic_verification"),
    # Requests
    ("rescue_requests", [("status", ASCENDING)], False, "idx_request_status"),
    ("rescue_requests", [("createdAt", DESCENDING)], False, "idx_request_created"),
    ("rescue_requests", [("mechanicId", ASCENDING)], False, "idx_request_mechanic"),
    ("rescue_requests", [("phone", ASCENDING)], False, "idx_request_phone"),
    (
        "rescue_requests",
        [("status", ASCENDING), ("createdAt", DESCENDING)],
        False,
        "idx_request_status_created",
    ),
    # Regions / hubs
    ("regions", [("name", ASCENDING)], False, "idx_region_name"),
    ("regions", [("city", ASCENDING)], False, "idx_region_city"),
    ("hubs", [("regionId", ASCENDING)], False, "idx_hub_region"),
    # Allocation evidence  (§19, §46)
    ("allocation_logs", [("requestId", ASCENDING)], False, "idx_alloc_request"),
    ("allocation_logs", [("createdAt", DESCENDING)], False, "idx_alloc_created"),
    (
        "allocation_logs",
        [("status", ASCENDING), ("createdAt", DESCENDING)],
        False,
        "idx_alloc_status_created",
    ),
    # Payments / ratings
    ("payments", [("requestId", ASCENDING)], False, "idx_payment_request"),
    ("payments", [("orderId", ASCENDING)], False, "idx_payment_order"),
    ("payments", [("paymentId", ASCENDING)], False, "idx_payment_id"),
    ("ratings", [("mechanicId", ASCENDING)], False, "idx_rating_mechanic"),
    ("ratings", [("requestId", ASCENDING)], False, "idx_rating_request"),
    # One counter row per phone for the hourly OTP cap
    ("otp_send_log", [("phone", ASCENDING)], True, "uniq_otp_send_phone"),
    # Zones (legacy) keep their bbox fields; a 2d index is added on the
    # optional `center` point so geospatial queries remain possible.
    ("zones", [("center", GEO2D)], False, "idx_zone_center"),
]


def ensure_indexes(verbose: bool = True) -> dict:
    """Create every declared index. Safe to call repeatedly (idempotent).

    Returns a summary dict so the caller can surface what happened.

    A duplicate-key error on a `unique` index is reported, not raised: an
    existing database may legitimately contain duplicate phone numbers created
    by the old unvalidated signup path, and index creation must not prevent the
    server from booting.
    """
    created, failed = [], []

    for coll_name, keys, unique, name in _INDEX_SPECS:
        try:
            get_db()[coll_name].create_index(
                keys, unique=unique, name=name, background=True
            )
            created.append(f"{coll_name}.{name}")
        except PyMongoError as exc:
            failed.append(f"{coll_name}.{name}: {exc}")
            if verbose:
                log.warning("Index %s.%s failed: %s", coll_name, name, exc)

    summary = {
        "created": created,
        "failed": failed,
        "createdCount": len(created),
        "failedCount": len(failed),
    }
    if verbose:
        log.info(
            "Indexes ready: %d created, %d failed", len(created), len(failed)
        )
    return summary
