"""
RoadResQ API v2 — new endpoints added by the audit remediation.

This blueprint is *additive*. It introduces only paths that did not previously
exist, so every URL the current Flutter client already calls keeps working
untouched (§37). The legacy handlers live in `roadresq_backend.py`.

What this module adds:

  Authentication with real tokens          §7, §8, §39
  Unified registration / login             §7, §8
  Mechanic listing + profile + verification§32, §33
  REGIONAL ALLOCATION ENGINE endpoints     §15–§19  ← the research core
  Mechanic accept / decline / arrive / done§33, §14
  Cancellation                             §14, §40
  Pricing + Razorpay order/verify          §29, §30
  Ratings and reviews                      §31
  Admin dashboard metrics + region admin   §34, §16
  Allocation log export (CSV)              §45, §46
"""

from __future__ import annotations

import csv
import io
import logging
import random
import time
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional

from bson import ObjectId
from flask import Blueprint, Response, jsonify, request
from pymongo.errors import PyMongoError

import allocation
import db
import payments as payment_gateway
import pricing
import realtime
import status_machine as sm
from auth import (
    hash_password,
    issue_token,
    needs_rehash,
    require_auth,
    require_role,
    verify_password,
)
from config import Config
from geo import coerce_coordinate, haversine_km
from serializers import (
    error as err_body,
    serialize_allocation_log,
    serialize_mechanic,
    serialize_payment,
    serialize_rating,
    serialize_region,
    serialize_request,
    serialize_user,
)

log = logging.getLogger("roadresq.api_v2")

bp = Blueprint("api_v2", __name__, url_prefix="/api")

# In-memory OTP store: phone -> {otp, expiresAt, attempts, purpose, role}.
# Deliberately process-local — a real deployment replaces this with Redis or an
# SMS provider. Structure is isolated here so that swap is a one-file change. §7
_OTP_STORE: Dict[str, Dict[str, Any]] = {}
_OTP_TTL_SECONDS = 300


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────
def _body() -> Dict[str, Any]:
    data = request.get_json(silent=True)
    return data if isinstance(data, dict) else {}


def _err(message: str, status: int = 400, code: str = ""):
    return jsonify(err_body(message, status, code)), status


def _ok(message: str = "", status: int = 200, **extra):
    body = {"success": True}
    if message:
        body["message"] = message
    body.update(extra)
    return jsonify(body), status


def _oid(value: Any) -> Optional[ObjectId]:
    try:
        return ObjectId(str(value))
    except Exception:
        return None


def _now() -> datetime:
    return datetime.utcnow()


def _as_float(value: Any) -> Optional[float]:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _as_int(value: Any, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def _phone_ok(phone: str) -> bool:
    digits = "".join(ch for ch in str(phone or "") if ch.isdigit())
    return 8 <= len(digits) <= 15


def _find_account(role: str, identifier: str) -> Optional[Dict[str, Any]]:
    """Look an account up by email or phone, scoped to its collection."""
    collection = db.users() if role == "user" else db.mechanics()
    ident = str(identifier or "").strip()
    if not ident:
        return None
    return collection.find_one(
        {"$or": [{"email": ident.lower()}, {"phone": ident}]}
    )


def _issue_login(
    role: str, doc: Dict[str, Any]
) -> Dict[str, Any]:
    """Build the login response for any role."""
    subject_id = str(doc.get("_id"))
    serialized = (
        serialize_user(doc) if role == "user" else serialize_mechanic(doc)
    )
    token = issue_token(subject_id, role)
    return {
        "success": True,
        "message": f"{role.capitalize()} login successful",
        "role": role,
        "user" if role == "user" else "mechanic": serialized,
        **token,
    }


def _classify_issue(issue_text: str) -> Dict[str, Any]:
    """Rule-based fault classification.

    This is explicitly a rule-based prototype, NOT a trained model. It exists so
    the workflow has a stable `FaultDetectionService` contract to upgrade later.
    The confidence figure is a fixed lookup weight for the matched rule — it is
    NOT a model probability and no accuracy is claimed. §27
    """
    text = str(issue_text or "").strip().lower()

    rules = [
        ("Flat Tyre", ["tyre", "tire", "puncture", "flat", "wheel"]),
        ("Battery Problem", ["battery", "batery", "jump", "no start", "dead"]),
        ("Fuel Delivery", ["fuel", "petrol", "diesel", "empty tank", "out of gas"]),
        ("Engine Trouble", ["engine", "overheat", "smoke", "oil", "coolant", "breakdown"]),
        ("Towing", ["tow", "towing", "cannot move", "accident", "stuck"]),
    ]

    for service, keywords in rules:
        for keyword in keywords:
            if keyword in text:
                return {
                    "classification": service,
                    "method": "rule-based-keyword",
                    "matchedKeyword": keyword,
                    "ruleWeight": 0.9,
                    "label": "AI prototype / rule-based fallback",
                    "disclaimer": (
                        "Keyword rule match, not a trained model. "
                        "No accuracy is claimed."
                    ),
                }

    return {
        "classification": "General Service",
        "method": "rule-based-default",
        "matchedKeyword": None,
        "ruleWeight": 0.3,
        "label": "AI prototype / rule-based fallback",
        "disclaimer": (
            "No keyword matched; defaulted to General Service. "
            "Not a model prediction and no accuracy is claimed."
        ),
    }


# ─────────────────────────────────────────────────────────────────────────────
# Platform configuration (§11, §12, §42 — expose categories + mode to the app)
# ─────────────────────────────────────────────────────────────────────────────
@bp.get("/config/public")
def public_config():
    """Public, non-secret configuration the client needs at boot."""
    return jsonify(
        {
            "success": True,
            "devMode": Config.DEV_MODE,
            "vehicleCategories": Config.VEHICLE_CATEGORIES,
            "serviceCategories": Config.SERVICE_CATEGORIES,
            "currency": Config.PRICING_CURRENCY,
            "allocation": {
                "searchRadiusKm": Config.DEFAULT_SEARCH_RADIUS_KM,
                "escalationRadiusKm": Config.ESCALATION_RADIUS_KM,
                "assumedSpeedKmh": Config.ASSUMED_AVG_SPEED_KMH,
                "weights": Config.allocation_weights(),
                "distanceKind": "great-circle (straight line, not road distance)",
            },
            "payments": {
                "enabled": payment_gateway.sdk_available(),
                "testMode": Config.RAZORPAY_TEST_MODE,
                "keyId": Config.RAZORPAY_KEY_ID or None,
            },
            "faultDetection": {
                "implementation": "rule-based",
                "label": "AI prototype / rule-based fallback",
            },
        }
    ), 200


@bp.post("/fault/classify")
def fault_classify():
    """Rule-based fault classifier used by the request wizard. §27"""
    data = _body()
    text = data.get("description") or data.get("issue") or ""
    if not str(text).strip():
        return _err("description is required", 400)
    return jsonify({"success": True, **_classify_issue(text)}), 200


# ─────────────────────────────────────────────────────────────────────────────
# AUTH — registration, login, OTP, session  (§7, §8, §37, §39)
# ─────────────────────────────────────────────────────────────────────────────
@bp.post("/auth/register")
def auth_register():
    """Unified registration for `user` and `mechanic`.

    Passwords are hashed before storage. Mechanics register as UNVERIFIED —
    creating an account never grants verified status. §8
    """
    data = _body()
    role = str(data.get("role", "user")).strip().lower()
    if role not in {"user", "mechanic"}:
        return _err("role must be 'user' or 'mechanic'", 400)

    name = str(data.get("name", "")).strip()
    email = str(data.get("email", "")).strip().lower()
    phone = str(data.get("phone", "")).strip()
    password = str(data.get("password", ""))

    missing = [
        label
        for label, value in (("name", name), ("email", email), ("password", password))
        if not value
    ]
    if missing:
        return _err(f"Missing required field(s): {', '.join(missing)}", 400)

    if len(password) < 6:
        return _err("Password must be at least 6 characters", 400)

    if phone and not _phone_ok(phone):
        return _err("Phone number is not valid", 400)

    collection = db.users() if role == "user" else db.mechanics()

    conflict = collection.find_one(
        {"$or": [{"email": email}] + ([{"phone": phone}] if phone else [])}
    )
    if conflict:
        return _err(
            f"{role.capitalize()} already exists with this email or phone", 409, "DUPLICATE"
        )

    doc: Dict[str, Any] = {
        "name": name,
        "email": email,
        "phone": phone,
        "password": hash_password(password),
        "role": role,
        "createdAt": _now(),
        "updatedAt": _now(),
    }

    if role == "mechanic":
        # A new mechanic is offline, available, and explicitly UNVERIFIED. §8
        doc.update(
            {
                "online": False,
                "available": True,
                "location": {},
                "verified": False,
                "verificationStatus": "pending",
                "services": [],
                "vehicleTypes": [],
                "rating": 0.0,
                "ratingCount": 0,
                "completedRescues": 0,
                "workload": 0,
                "regionId": data.get("regionId"),
                "hubId": data.get("hubId"),
            }
        )

    try:
        result = collection.insert_one(doc)
    except PyMongoError as exc:
        log.exception("register insert failed")
        return _err(f"Database error: {exc}", 500, "DB_ERROR")

    doc["_id"] = result.inserted_id
    return jsonify(_issue_login(role, doc)), 201


@bp.post("/auth/login")
def auth_login():
    """Unified email-or-phone + password login returning a signed token."""
    data = _body()
    role = str(data.get("role", "user")).strip().lower()
    if role not in {"user", "mechanic"}:
        return _err("role must be 'user' or 'mechanic'", 400)

    identifier = data.get("email") or data.get("phone") or ""
    password = str(data.get("password", ""))

    if not identifier or not password:
        return _err("email (or phone) and password are required", 400)

    account = _find_account(role, identifier)
    if not account:
        return _err("Invalid credentials", 401, "INVALID_CREDENTIALS")

    if not verify_password(account.get("password"), password):
        return _err("Invalid credentials", 401, "INVALID_CREDENTIALS")

    if account.get("isBanned"):
        return _err("This account is suspended", 403, "ACCOUNT_SUSPENDED")

    # Transparently upgrade a legacy plaintext password to a hash. §39
    if needs_rehash(account.get("password")):
        try:
            collection = db.users() if role == "user" else db.mechanics()
            collection.update_one(
                {"_id": account["_id"]},
                {"$set": {"password": hash_password(password), "updatedAt": _now()}},
            )
        except PyMongoError:
            log.warning("Password rehash failed for %s", account.get("_id"))

    return jsonify(_issue_login(role, account)), 200


@bp.post("/auth/otp/send")
def auth_otp_send():
    """Send an OTP.

    In `DEV_MODE` the OTP is the fixed development code and is returned in the
    response inside an explicitly-named `devOtp` field so no client can mistake
    it for a real SMS delivery. With `DEV_MODE` off, no code is ever returned.
    §7, §42
    """
    data = _body()
    phone = str(data.get("phone", "")).strip()
    role = str(data.get("role", "user")).strip().lower()

    if not _phone_ok(phone):
        return _err("A valid phone number is required", 400)

    if Config.DEV_MODE:
        otp = Config.DEV_OTP
        delivery = "development (not sent via SMS)"
    else:
        otp = f"{random.randint(0, 999999):06d}"
        delivery = "sms-provider-not-configured"

    _OTP_STORE[phone] = {
        "otp": otp,
        "role": role,
        "expiresAt": time.time() + _OTP_TTL_SECONDS,
        "attempts": 0,
        "issuedAt": time.time(),
    }

    payload = {
        "success": True,
        "message": "OTP generated",
        "phone": phone,
        "expiresInSeconds": _OTP_TTL_SECONDS,
        "delivery": delivery,
        "devMode": Config.DEV_MODE,
    }

    # Dev-only field, clearly named. Absent whenever DEV_MODE is off.
    if Config.DEV_MODE:
        payload["devOtp"] = otp
        payload["devNotice"] = (
            "Development OTP returned for convenience. This is NOT a production "
            "SMS flow. Disable ROADRESQ_DEV_MODE to suppress it."
        )

    return jsonify(payload), 200


@bp.post("/auth/otp/verify")
def auth_otp_verify():
    """Verify an OTP and return a token, creating the account if new."""
    data = _body()
    phone = str(data.get("phone", "")).strip()
    otp = str(data.get("otp", "")).strip()
    role = str(data.get("role", "user")).strip().lower()

    if not _phone_ok(phone) or not otp:
        return _err("phone and otp are required", 400)

    record = _OTP_STORE.get(phone)
    if not record:
        return _err("No OTP was requested for this number", 400, "OTP_NOT_REQUESTED")

    if time.time() > record["expiresAt"]:
        _OTP_STORE.pop(phone, None)
        return _err("OTP has expired", 400, "OTP_EXPIRED")

    record["attempts"] += 1
    if record["attempts"] > 5:
        _OTP_STORE.pop(phone, None)
        return _err("Too many attempts. Request a new OTP.", 429, "OTP_LOCKED")

    if not verify_password(record["otp"], otp) and record["otp"] != otp:
        return _err("Invalid OTP", 401, "INVALID_OTP")

    _OTP_STORE.pop(phone, None)

    collection = db.users() if role == "user" else db.mechanics()
    account = collection.find_one({"phone": phone})

    if not account:
        # Phone-first signup. The account is created without a password and is
        # flagged so a later password can be set deliberately.
        doc: Dict[str, Any] = {
            "name": data.get("name") or role.capitalize(),
            "email": "",
            "phone": phone,
            "password": "",
            "role": role,
            "createdAt": _now(),
            "updatedAt": _now(),
            "phoneVerified": True,
        }
        if role == "mechanic":
            doc.update(
                {
                    "online": False,
                    "available": True,
                    "location": {},
                    "verified": False,
                    "verificationStatus": "pending",
                    "services": [],
                    "vehicleTypes": [],
                    "rating": 0.0,
                    "ratingCount": 0,
                    "completedRescues": 0,
                    "workload": 0,
                }
            )
        try:
            inserted = collection.insert_one(doc)
        except PyMongoError as exc:
            return _err(f"Database error: {exc}", 500, "DB_ERROR")
        doc["_id"] = inserted.inserted_id
        account = doc

    return jsonify(_issue_login(role, account)), 200


@bp.get("/auth/me")
@require_auth
def auth_me():
    """Return the caller's own profile from their token. §39"""
    identity = request.identity  # type: ignore[attr-defined]
    role = identity.get("role")
    subject = identity.get("sub")

    oid = _oid(subject)
    if not oid:
        return _err("Token subject is not a valid id", 400)

    if role == "user":
        doc = db.users().find_one({"_id": oid})
        if not doc:
            return _err("Account not found", 404)
        return jsonify({"success": True, "role": role, "user": serialize_user(doc)}), 200

    if role == "admin":
        doc = db.admin_users().find_one({"_id": oid}) or {"_id": oid, "name": "Admin"}
        return jsonify({"success": True, "role": role, "admin": serialize_user(doc)}), 200

    doc = db.mechanics().find_one({"_id": oid})
    if not doc:
        return _err("Account not found", 404)
    return jsonify(
        {"success": True, "role": role, "mechanic": serialize_mechanic(doc)}
    ), 200


# ─────────────────────────────────────────────────────────────────────────────
# MECHANICS — listing, profile, availability, verification  (§32, §33)
# ─────────────────────────────────────────────────────────────────────────────
@bp.get("/mechanics")
def list_mechanics():
    """List mechanics with optional filters.

    Query params: regionId, hubId, service, vehicleType, online, verified,
    available, limit. Filtering is server-side by design (§47).
    """
    query: Dict[str, Any] = {}
    args = request.args

    for field in ("regionId", "hubId"):
        if args.get(field):
            query[field] = args[field]

    if args.get("service"):
        query["services"] = args["service"]

    if args.get("vehicleType"):
        query["vehicleTypes"] = args["vehicleType"]

    for field in ("online", "verified", "available"):
        raw = args.get(field)
        if raw is not None:
            query[field] = raw.strip().lower() in {"1", "true", "yes"}

    limit = min(max(_as_int(args.get("limit", 100), 100), 1), 500)

    try:
        docs = db.mechanics().find(query).limit(limit)
        mechanics = [serialize_mechanic(d) for d in docs]
    except PyMongoError as exc:
        log.exception("list_mechanics failed")
        return _err(f"Database error: {exc}", 500, "DB_ERROR")

    return jsonify(
        {"success": True, "count": len(mechanics), "mechanics": mechanics}
    ), 200


@bp.patch("/mechanics/<mechanic_id>")
@require_role("mechanic")
def update_mechanic_profile(mechanic_id: str):
    """Update a mechanic's own profile: region, hub, services, vehicle types.

    Verification fields are intentionally NOT writable here — only an admin may
    change them (§32).
    """
    identity = request.identity  # type: ignore[attr-defined]
    if identity.get("role") != "admin" and str(identity.get("sub")) != str(mechanic_id):
        return _err("You may only update your own profile", 403)

    oid = _oid(mechanic_id)
    if not oid:
        return _err("Invalid mechanic id", 400)

    data = _body()
    updates: Dict[str, Any] = {}

    for field in ("name", "phone", "regionId", "hubId", "regionName", "hubName"):
        if field in data:
            updates[field] = data[field]

    for field in ("services", "vehicleTypes"):
        if field in data:
            if not isinstance(data[field], list):
                return _err(f"{field} must be a list", 400)
            updates[field] = [str(v).strip() for v in data[field] if str(v).strip()]

    for field in ("maxConcurrentJobs",):
        if field in data:
            updates[field] = _as_int(data[field], 1)

    if not updates:
        return _err("No updatable fields supplied", 400)

    updates["updatedAt"] = _now()

    try:
        result = db.mechanics().update_one({"_id": oid}, {"$set": updates})
        if result.matched_count == 0:
            return _err("Mechanic not found", 404)
        doc = db.mechanics().find_one({"_id": oid})
    except PyMongoError as exc:
        return _err(f"Database error: {exc}", 500, "DB_ERROR")

    return jsonify(
        {"success": True, "message": "Profile updated", "mechanic": serialize_mechanic(doc)}
    ), 200


@bp.put("/mechanics/<mechanic_id>/availability")
@require_role("mechanic")
def set_availability(mechanic_id: str):
    """Set online/available state.

    Distinct from the legacy `PUT /api/mechanic/<id>/online` (which only toggles
    `online`) because availability drives eligibility (§17). Going offline
    clears location freshness so stale coordinates are not reused.
    """
    identity = request.identity  # type: ignore[attr-defined]
    if identity.get("role") != "admin" and str(identity.get("sub")) != str(mechanic_id):
        return _err("You may only change your own availability", 403)

    oid = _oid(mechanic_id)
    if not oid:
        return _err("Invalid mechanic id", 400)

    data = _body()
    updates: Dict[str, Any] = {"updatedAt": _now()}

    if "online" in data:
        updates["online"] = bool(data["online"])
    if "available" in data:
        updates["available"] = bool(data["available"])

    if updates.get("online") is False:
        # Do not keep a mechanic in the candidate pool while offline.
        updates["available"] = False

    if len(updates) == 1:
        return _err("online or available is required", 400)

    try:
        result = db.mechanics().update_one({"_id": oid}, {"$set": updates})
        if result.matched_count == 0:
            return _err("Mechanic not found", 404)
        doc = db.mechanics().find_one({"_id": oid})
    except PyMongoError as exc:
        return _err(f"Database error: {exc}", 500, "DB_ERROR")

    payload = serialize_mechanic(doc)
    realtime.emit_event(
        "mechanic_online_updated",
        {
            "success": True,
            "mechanicId": mechanic_id,
            "name": payload.get("name", ""),
            "online": payload.get("online", False),
            "isOnline": payload.get("online", False),
            "available": payload.get("available", False),
        },
    )

    return jsonify({"success": True, "mechanic": payload}), 200


@bp.put("/mechanics/<mechanic_id>/location")
def set_mechanic_location_v2(mechanic_id: str):
    """Publish a mechanic location and broadcast it.

    Fixes an inconsistency in the legacy handler, which wrote to MongoDB but
    emitted no socket event — so a user tracking a mechanic saw stale
    coordinates until they refreshed. §22, §23

    A timestamp is always written so the staleness rule in the eligibility
    filter has something to evaluate (§17).
    """
    oid = _oid(mechanic_id)
    if not oid:
        return _err("Invalid mechanic id", 400)

    data = _body()
    coords = coerce_coordinate(data.get("lat"), data.get("lng"))
    if coords is None:
        return _err(
            "Valid lat and lng are required (lat -90..90, lng -180..180)", 400,
            "INVALID_COORDINATES",
        )

    lat, lng = coords
    updates = {
        "location": {"lat": lat, "lng": lng},
        "locationUpdatedAt": _now(),
        "updatedAt": _now(),
    }

    try:
        result = db.mechanics().update_one({"_id": oid}, {"$set": updates})
        if result.matched_count == 0:
            return _err("Mechanic not found", 404)
    except PyMongoError as exc:
        return _err(f"Database error: {exc}", 500, "DB_ERROR")

    payload = {
        "success": True,
        "mechanicId": mechanic_id,
        "requestId": str(data.get("requestId", "")),
        "lat": lat,
        "lng": lng,
    }
    realtime.emit_event("mechanic_location_updated", payload)
    realtime.emit_event("mechanic_location_global_updated", payload)

    return jsonify({"success": True, "message": "Location updated", **payload}), 200


@bp.post("/admin/mechanics/<mechanic_id>/verify")
@require_role("mechanic")
def verify_mechanic(mechanic_id: str):
    """Admin approves or rejects a mechanic's verification. §32"""
    identity = request.identity  # type: ignore[attr-defined]
    if identity.get("role") != "admin":
        return _err("Admin access required", 403)

    oid = _oid(mechanic_id)
    if not oid:
        return _err("Invalid mechanic id", 400)

    data = _body()
    decision = str(data.get("decision", "")).strip().lower()
    if decision not in {"approve", "reject", "suspend"}:
        return _err("decision must be one of: approve, reject, suspend", 400)

    if decision == "approve":
        updates = {"verified": True, "verificationStatus": "verified"}
    elif decision == "reject":
        updates = {"verified": False, "verificationStatus": "rejected"}
    else:
        updates = {"verified": False, "verificationStatus": "suspended"}

    updates.update({"verifiedAt": _now() if decision == "approve" else None, "updatedAt": _now()})

    try:
        result = db.mechanics().update_one({"_id": oid}, {"$set": updates})
        if result.matched_count == 0:
            return _err("Mechanic not found", 404)
        doc = db.mechanics().find_one({"_id": oid})
    except PyMongoError as exc:
        return _err(f"Database error: {exc}", 500, "DB_ERROR")

    return jsonify(
        {
            "success": True,
            "message": f"Mechanic {decision}d",
            "mechanic": serialize_mechanic(doc),
        }
    ), 200


# ─────────────────────────────────────────────────────────────────────────────
# ALLOCATION ENGINE — the research core  (§15, §16, §17, §18, §19, §37)
# ─────────────────────────────────────────────────────────────────────────────
@bp.post("/allocation/find")
def allocation_find():
    """Run the regional allocation pipeline for a rescue request.

    Body:
        requestId (required unless lat/lng supplied) — request to allocate
        lat, lng, issue, vehicle               — for a dry-run allocation
        excludeMechanicIds                     — e.g. mechanics who declined
        radiusKm / escalationRadiusKm          — override the configured radii
        dryRun                                 — evaluate without persisting

    Always returns the full explainability payload: every candidate, its
    eligibility verdict, rejection reasons, score and component breakdown.
    """
    data = _body()
    dry_run = bool(data.get("dryRun", False))
    request_id = str(data.get("requestId") or data.get("request_id") or "").strip()

    request_doc: Dict[str, Any]
    request_oid: Optional[ObjectId] = None

    if request_id:
        request_oid = _oid(request_id)
        if not request_oid:
            return _err("Invalid requestId", 400, "INVALID_ID")
        try:
            found = db.rescue_requests().find_one({"_id": request_oid})
        except PyMongoError as exc:
            return _err(f"Database error: {exc}", 500, "DB_ERROR")
        if not found:
            return _err("Request not found", 404, "NOT_FOUND")
        request_doc = found
    else:
        lat = _as_float(data.get("lat"))
        lng = _as_float(data.get("lng"))
        if lat is None or lng is None:
            return _err(
                "Either requestId, or lat+lng for a dry run, is required", 400
            )
        request_doc = {
            "_id": "",
            "issue": data.get("issue", ""),
            "vehicle": data.get("vehicle", ""),
            "location": {"lat": lat, "lng": lng},
        }

    # Refuse to double-assign a request that already has an active mechanic.
    canonical = sm.normalize(request_doc.get("status")) or sm.CREATED
    if request_doc.get("mechanicId") and canonical not in {
        sm.CREATED,
        sm.SEARCHING,
        sm.MECHANIC_DECLINED,
        sm.NO_MECHANIC_AVAILABLE,
    }:
        return _err(
            "This request already has an assigned mechanic", 409, "ALREADY_ASSIGNED"
        )

    started_at = time.time()

    # Move the request into SEARCHING so the client and the dashboard agree. §14
    if request_oid and not dry_run and canonical != sm.SEARCHING:
        try:
            db.rescue_requests().update_one(
                {"_id": request_oid},
                {"$set": {"status": sm.storage_label(sm.SEARCHING), "statusCanonical": sm.SEARCHING, "updatedAt": _now()}},
            )
        except PyMongoError:
            log.warning("Could not set SEARCHING on request %s", request_id)

    try:
        candidate_pool = list(db.mechanics().find({}).limit(1000))
        regions = list(db.regions().find({}))
    except PyMongoError as exc:
        return _err(f"Database error: {exc}", 500, "DB_ERROR")

    exclude_ids = data.get("excludeMechanicIds") or []
    if not isinstance(exclude_ids, list):
        exclude_ids = []

    decision = allocation.allocate(
        candidate_pool,
        request_doc,
        regions,
        request_lat=_as_float(data.get("lat")),
        request_lng=_as_float(data.get("lng")),
        radius_km=_as_float(data.get("radiusKm")),
        escalation_radius_km=_as_float(data.get("escalationRadiusKm")),
        exclude_mechanic_ids=exclude_ids,
        started_at=started_at,
    )

    if decision["status"] == "INVALID_LOCATION":
        return _err(
            decision["explain"]["message"], 400, "INVALID_COORDINATES"
        )

    selected = decision.get("selected")
    allocation_log_id = ""

    # ── Persist the evidence record + the assignment (§19) ──────────────
    if not dry_run and request_oid:
        log_doc = decision.get("allocationLog") or {}
        log_doc["dryRun"] = False
        try:
            inserted = db.allocation_logs().insert_one(log_doc)
            allocation_log_id = str(inserted.inserted_id)
        except PyMongoError as exc:
            log.warning("Allocation log insert failed: %s", exc)

        try:
            if selected:
                db.rescue_requests().update_one(
                    {"_id": request_oid},
                    {
                        "$set": {
                            "status": sm.storage_label(sm.MECHANIC_ASSIGNED), "statusCanonical": sm.MECHANIC_ASSIGNED,
                            # str(), not the raw value: `selected` comes from the
                            # allocation engine, so this was an ObjectId, while the
                            # admin assign path writes a string. That split (13 str
                            # vs 9 ObjectId in rescue_requests.mechanicId) is why a
                            # string-only lookup hid real jobs from their mechanic.
                            "mechanicId": str(selected["mechanicId"]),
                            "mechanicName": selected.get("name", ""),
                            "distanceKm": selected.get("distanceKm"),
                            "assignedDistanceKm": selected.get("distanceKm"),
                            "etaMinutes": selected.get("etaMinutes"),
                            "regionId": decision["explain"].get("regionId"),
                            "regionName": decision["explain"].get("regionName"),
                            "hubId": decision["explain"].get("hubId"),
                            "allocationLogId": allocation_log_id,
                            "assignmentTimeMs": decision["explain"]["assignmentTimeMs"],
                            "assignedAt": _now(),
                            "updatedAt": _now(),
                        },
                    },
                )

                mech_oid = _oid(selected["mechanicId"])
                if mech_oid:
                    db.mechanics().update_one(
                        {"_id": mech_oid},
                        {
                            "$set": {
                                "currentRequestId": request_id,
                                "available": False,
                                "updatedAt": _now(),
                            },
                            "$inc": {"workload": 1},
                        },
                    )
            else:
                db.rescue_requests().update_one(
                    {"_id": request_oid},
                    {
                        "$set": {
                            "status": sm.storage_label(sm.NO_MECHANIC_AVAILABLE), "statusCanonical": sm.NO_MECHANIC_AVAILABLE,
                            "failureReason": decision["explain"].get("failureReason"),
                            "allocationLogId": allocation_log_id,
                            "assignmentTimeMs": decision["explain"]["assignmentTimeMs"],
                            "updatedAt": _now(),
                        }
                    },
                )
        except PyMongoError as exc:
            log.warning("Allocation persistence failed: %s", exc)

        # Broadcast the outcome. §23
        if selected:
            realtime.emit_event(
                "request_assigned",
                {
                    "success": True,
                    "requestId": request_id,
                    "id": request_id,
                    "mechanicId": selected["mechanicId"],
                    "status": sm.storage_label(sm.MECHANIC_ASSIGNED), "statusCanonical": sm.MECHANIC_ASSIGNED,
                },
            )
            realtime.emit_event(
                "status_updated",
                {
                    "success": True,
                    "requestId": request_id,
                    "id": request_id,
                    "mechanicId": selected["mechanicId"],
                    "status": sm.storage_label(sm.MECHANIC_ASSIGNED), "statusCanonical": sm.MECHANIC_ASSIGNED,
                },
            )

    response = {
        "success": decision["status"] == allocation.A_OK,
        "message": (
            f"Mechanic assigned (rank {selected.get('rank')})"
            if selected
            else "No eligible mechanic available in the selected region"
        ),
        "status": decision["status"],
        "dryRun": dry_run,
        "allocationLogId": allocation_log_id,
        "selected": selected,
        "explain": decision["explain"],
        "rankedMechanics": (decision.get("allocationLog") or {}).get("rankedMechanics", []),
        "candidates": decision.get("candidates", []),
        "readableTrace": allocation.human_readable_decision(decision),
    }

    status_code = 200 if selected else 200
    return jsonify(response), status_code


@bp.get("/allocation/<request_id>")
def allocation_get(request_id: str):
    """Return the allocation record(s) for a request. §19"""
    try:
        docs = list(
            db.allocation_logs()
            .find({"requestId": str(request_id)})
            .sort("createdAt", -1)
            .limit(20)
        )
    except PyMongoError as exc:
        return _err(f"Database error: {exc}", 500, "DB_ERROR")

    if not docs:
        return _err("No allocation record found for this request", 404, "NOT_FOUND")

    latest = docs[0]
    return jsonify(
        {
            "success": True,
            "requestId": str(request_id),
            "count": len(docs),
            "latest": serialize_allocation_log(latest),
            "history": [serialize_allocation_log(d) for d in docs],
            "readableTrace": _trace_from_log(latest),
        }
    ), 200


def _trace_from_log(doc: Dict[str, Any]) -> str:
    """Render a stored allocation log as the §18 style trace."""
    lines: List[str] = [
        f"Request {doc.get('requestId', '-')}",
        f"  region            : {doc.get('regionName') or 'not resolved'}"
        f" ({doc.get('regionId') or '-'})",
        f"  search radius     : {doc.get('radiusKm')} km"
        + (
            f" (escalated to {doc.get('escalationRadiusKm')} km)"
            if doc.get("escalationUsed")
            else ""
        ),
        f"  candidates / eligible : {doc.get('candidateCount')} / {doc.get('eligibleCount')}",
        "",
    ]

    ranked = doc.get("rankedMechanics") or []
    if not ranked:
        lines.append(
            f"  NO MECHANIC ASSIGNED - dominant reason: {doc.get('failureReason')}"
        )
    else:
        for entry in ranked:
            lines.append(f"  Candidate (rank {entry.get('rank')}): {entry.get('name')}")
            lines.append(f"    Distance          = {entry.get('distanceKm')} km")
            lines.append(f"    Score             = {entry.get('score')}")
            lines.append(f"    Components        = {entry.get('components')}")
            lines.append("")
        lines.append("  Selected mechanic  = " + str(doc.get("selectedMechanicId")))

    lines.append("")
    lines.append("  Assignment time   = " + str(doc.get("assignmentTimeMs")) + " ms")
    lines.append("  Acceptance time   = " + str(doc.get("acceptanceTimeMs")) + " ms")
    return "\n".join(lines)


# ─────────────────────────────────────────────────────────────────────────────
# MECHANIC LIFECYCLE  (§14, §33, §37)
# ─────────────────────────────────────────────────────────────────────────────
def _load_request_for_mechanic(request_id: str, mechanic_id: str):
    """Fetch a request and verify it is assigned to this mechanic."""
    oid = _oid(request_id)
    if not oid:
        return None, _err("Invalid requestId", 400, "INVALID_ID")
    try:
        doc = db.rescue_requests().find_one({"_id": oid})
    except PyMongoError as exc:
        return None, _err(f"Database error: {exc}", 500, "DB_ERROR")
    if not doc:
        return None, _err("Request not found", 404, "NOT_FOUND")
    if str(doc.get("mechanicId") or "") != str(mechanic_id):
        return None, _err(
            "This request is not assigned to you", 403, "NOT_YOUR_REQUEST"
        )
    return doc, None


def _transition_request(
    request_doc: Dict[str, Any],
    target_state: str,
    extra_fields: Optional[Dict[str, Any]] = None,
):
    """Validate and apply a lifecycle transition; returns (ok, payload_or_error)."""
    current = request_doc.get("status")
    verdict = sm.validate_transition(current, target_state)

    if not verdict["ok"]:
        return False, _err(verdict["reason"], 409, "ILLEGAL_TRANSITION")

    updates: Dict[str, Any] = {
        "status": sm.storage_label(verdict["to"]), "statusCanonical": verdict["to"],
        "updatedAt": _now(),
    }
    if extra_fields:
        updates.update(extra_fields)

    try:
        db.rescue_requests().update_one(
            {"_id": request_doc["_id"]}, {"$set": updates}
        )
        updated = db.rescue_requests().find_one({"_id": request_doc["_id"]})
    except PyMongoError as exc:
        return False, _err(f"Database error: {exc}", 500, "DB_ERROR")

    payload = serialize_request(updated)
    realtime.emit_event(
        "status_updated",
        {
            "success": True,
            "requestId": str(request_doc["_id"]),
            "id": str(request_doc["_id"]),
            "mechanicId": payload.get("mechanicId", ""),
            "status": sm.storage_label(verdict["to"]), "statusCanonical": verdict["to"],
            "statusLabel": sm.storage_label(verdict["to"]),
            "progressPercent": sm.progress_percent(verdict["to"]),
        },
    )
    return True, payload


@bp.post("/mechanic/<mechanic_id>/accept")
@require_role("mechanic")
def mechanic_accept(mechanic_id: str):
    """Accept an assigned rescue. Records acceptance latency for §44."""
    identity = request.identity  # type: ignore[attr-defined]
    if identity.get("role") != "admin" and str(identity.get("sub")) != str(mechanic_id):
        return _err("You may only accept your own assignments", 403)

    data = _body()
    request_id = str(data.get("requestId") or "").strip()
    if not request_id:
        return _err("requestId is required", 400)

    request_doc, failure = _load_request_for_mechanic(request_id, mechanic_id)
    if failure:
        return failure

    accepted_at = _now()
    assigned_at = request_doc.get("assignedAt")
    acceptance_ms: Optional[int] = None
    if isinstance(assigned_at, datetime):
        acceptance_ms = int((accepted_at - assigned_at).total_seconds() * 1000)

    ok, payload = _transition_request(
        request_doc,
        sm.MECHANIC_ACCEPTED,
        {
            "acceptedAt": accepted_at,
            "acceptanceTimeMs": acceptance_ms,
        },
    )
    if not ok:
        return payload

    # Record the acceptance latency on the allocation evidence record. §19
    # The newest matching log is resolved first and then updated by _id: a sort
    # argument on update_one is not portable across PyMongo versions.
    try:
        log_doc = db.allocation_logs().find_one(
            {"requestId": request_id, "selectedMechanicId": str(mechanic_id)},
            sort=[("createdAt", -1)],
        )
        if log_doc:
            db.allocation_logs().update_one(
                {"_id": log_doc["_id"]},
                {"$set": {"acceptanceTimeMs": acceptance_ms, "acceptedAt": accepted_at}},
            )
    except PyMongoError:
        log.warning("Could not attach acceptance latency for %s", request_id)

    return jsonify(
        {
            "success": True,
            "message": "Rescue accepted",
            "acceptanceTimeMs": acceptance_ms,
            "request": payload,
        }
    ), 200


@bp.post("/mechanic/<mechanic_id>/decline")
@require_role("mechanic")
def mechanic_decline(mechanic_id: str):
    """Decline an assignment and (by default) re-run allocation excluding self."""
    identity = request.identity  # type: ignore[attr-defined]
    if identity.get("role") != "admin" and str(identity.get("sub")) != str(mechanic_id):
        return _err("You may only decline your own assignments", 403)

    data = _body()
    request_id = str(data.get("requestId") or "").strip()
    reason = str(data.get("reason") or "not specified")
    if not request_id:
        return _err("requestId is required", 400)

    request_doc, failure = _load_request_for_mechanic(request_id, mechanic_id)
    if failure:
        return failure

    ok, payload = _transition_request(
        request_doc,
        sm.MECHANIC_DECLINED,
        {"cancellationReason": f"mechanic declined: {reason}"},
    )
    if not ok:
        return payload

    # Release the mechanic so they re-enter the available pool.
    mech_oid = _oid(mechanic_id)
    if mech_oid:
        try:
            db.mechanics().update_one(
                {"_id": mech_oid},
                {
                    "$set": {"currentRequestId": "", "available": True, "updatedAt": _now()},
                    "$inc": {"workload": -1},
                },
            )
        except PyMongoError:
            log.warning("Could not release mechanic %s", mechanic_id)

    # Clear the assignment so a re-allocation is permitted.
    try:
        db.rescue_requests().update_one(
            {"_id": request_doc["_id"]},
            {"$set": {"mechanicId": "", "mechanicName": ""}},
        )
    except PyMongoError:
        pass

    reallocation = None
    if data.get("autoReallocate", True):
        exclude = [str(mechanic_id)]
        try:
            candidate_pool = list(db.mechanics().find({}).limit(1000))
            regions = list(db.regions().find({}))
        except PyMongoError:
            candidate_pool, regions = [], []

        decision = allocation.allocate(
            candidate_pool,
            {**request_doc, "status": sm.MECHANIC_DECLINED},
            regions,
            exclude_mechanic_ids=exclude,
            started_at=time.time(),
        )

        if decision.get("allocationLog"):
            log_doc = decision["allocationLog"]
            log_doc["triggeredBy"] = "MECHANIC_DECLINED"
            log_doc["declinedBy"] = str(mechanic_id)
            try:
                inserted = db.allocation_logs().insert_one(log_doc)
                allocation_log_id = str(inserted.inserted_id)
            except PyMongoError:
                allocation_log_id = ""
        else:
            allocation_log_id = ""

        selected = decision.get("selected")
        if selected:
            try:
                db.rescue_requests().update_one(
                    {"_id": request_doc["_id"]},
                    {
                        "$set": {
                            "status": sm.storage_label(sm.MECHANIC_ASSIGNED), "statusCanonical": sm.MECHANIC_ASSIGNED,
                            # str() for the same reason as the other assignment
                            # site: keep mechanicId a string everywhere.
                            "mechanicId": str(selected["mechanicId"]),
                            "mechanicName": selected.get("name", ""),
                            "distanceKm": selected.get("distanceKm"),
                            "assignedDistanceKm": selected.get("distanceKm"),
                            "etaMinutes": selected.get("etaMinutes"),
                            "allocationLogId": allocation_log_id,
                            "assignedAt": _now(),
                            "updatedAt": _now(),
                        }
                    },
                )
                new_oid = _oid(selected["mechanicId"])
                if new_oid:
                    db.mechanics().update_one(
                        {"_id": new_oid},
                        {
                            "$set": {
                                "currentRequestId": request_id,
                                "available": False,
                                "updatedAt": _now(),
                            },
                            "$inc": {"workload": 1},
                        },
                    )
            except PyMongoError:
                log.warning("Re-allocation persistence failed for %s", request_id)
        else:
            try:
                db.rescue_requests().update_one(
                    {"_id": request_doc["_id"]},
                    {
                        "$set": {
                            "status": sm.storage_label(sm.NO_MECHANIC_AVAILABLE), "statusCanonical": sm.NO_MECHANIC_AVAILABLE,
                            "failureReason": decision["explain"].get("failureReason"),
                            "updatedAt": _now(),
                        }
                    },
                )
            except PyMongoError:
                pass

        reallocation = {
            "status": decision["status"],
            "explain": decision["explain"],
            "selected": selected,
            "allocationLogId": allocation_log_id,
        }

    return jsonify(
        {
            "success": True,
            "message": "Assignment declined",
            "request": payload,
            "reallocation": reallocation,
        }
    ), 200


@bp.post("/mechanic/<mechanic_id>/start")
@require_role("mechanic")
def mechanic_start(mechanic_id: str):
    """Mark travel started (MECHANIC_ACCEPTED → MECHANIC_EN_ROUTE)."""
    identity = request.identity  # type: ignore[attr-defined]
    if identity.get("role") != "admin" and str(identity.get("sub")) != str(mechanic_id):
        return _err("You may only act on your own assignments", 403)

    data = _body()
    request_id = str(data.get("requestId") or "").strip()
    if not request_id:
        return _err("requestId is required", 400)

    request_doc, failure = _load_request_for_mechanic(request_id, mechanic_id)
    if failure:
        return failure

    ok, payload = _transition_request(
        request_doc, sm.MECHANIC_EN_ROUTE, {"enRouteAt": _now()}
    )
    if not ok:
        return payload
    return jsonify({"success": True, "message": "En route", "request": payload}), 200


@bp.post("/mechanic/<mechanic_id>/arrive")
@require_role("mechanic")
def mechanic_arrive(mechanic_id: str):
    """Mark arrival at the breakdown location (→ ARRIVED)."""
    identity = request.identity  # type: ignore[attr-defined]
    if identity.get("role") != "admin" and str(identity.get("sub")) != str(mechanic_id):
        return _err("You may only act on your own assignments", 403)

    data = _body()
    request_id = str(data.get("requestId") or "").strip()
    if not request_id:
        return _err("requestId is required", 400)

    request_doc, failure = _load_request_for_mechanic(request_id, mechanic_id)
    if failure:
        return failure

    ok, payload = _transition_request(request_doc, sm.ARRIVED, {"arrivedAt": _now()})
    if not ok:
        return payload
    return jsonify({"success": True, "message": "Arrived", "request": payload}), 200


@bp.post("/mechanic/<mechanic_id>/complete")
@require_role("mechanic")
def mechanic_complete(mechanic_id: str):
    """Complete the service and release the mechanic.

    The request moves to PAYMENT_PENDING, not straight to closed — payment is a
    separate verified step. §14, §29
    """
    identity = request.identity  # type: ignore[attr-defined]
    if identity.get("role") != "admin" and str(identity.get("sub")) != str(mechanic_id):
        return _err("You may only act on your own assignments", 403)

    data = _body()
    request_id = str(data.get("requestId") or "").strip()
    if not request_id:
        return _err("requestId is required", 400)

    request_doc, failure = _load_request_for_mechanic(request_id, mechanic_id)
    if failure:
        return failure

    # SERVICE_STARTED is required before completion on the happy path; when the
    # mechanic skipped `start`, walk the machine forward explicitly rather than
    # storing an illegal jump.
    canonical = sm.normalize(request_doc.get("status"))
    completed_at = _now()

    if canonical in {sm.ARRIVED, sm.MECHANIC_EN_ROUTE, sm.MECHANIC_ACCEPTED}:
        ok, payload = _transition_request(
            request_doc, sm.SERVICE_STARTED, {"serviceStartedAt": completed_at}
        )
        if not ok:
            return payload
        request_doc = db.rescue_requests().find_one({"_id": request_doc["_id"]})

    started_at = request_doc.get("serviceStartedAt") or request_doc.get("createdAt")
    completion_minutes = None
    if isinstance(started_at, datetime):
        completion_minutes = round((completed_at - started_at).total_seconds() / 60.0, 2)

    # SERVICE_COMPLETED then PAYMENT_PENDING, both recorded.
    ok, payload = _transition_request(
        request_doc,
        sm.SERVICE_COMPLETED,
        {"serviceCompletedAt": completed_at, "completionTimeMinutes": completion_minutes},
    )
    if not ok:
        return payload

    request_doc = db.rescue_requests().find_one({"_id": request_doc["_id"]})
    quote = pricing.quote(
        request_doc.get("issue", ""),
        request_doc.get("assignedDistanceKm") or request_doc.get("distanceKm"),
    )

    ok2, payload2 = _transition_request(
        request_doc,
        sm.PAYMENT_PENDING,
        {
            "amount": quote["total"],
            "pricing": quote,
            "paymentStatus": "pending",
        },
    )
    if not ok2:
        return payload2

    # Release the mechanic and credit the completed job.
    mech_oid = _oid(mechanic_id)
    if mech_oid:
        try:
            db.mechanics().update_one(
                {"_id": mech_oid},
                {
                    "$set": {"currentRequestId": "", "available": True, "updatedAt": _now()},
                    "$inc": {"workload": -1, "completedRescues": 1},
                },
            )
        except PyMongoError:
            log.warning("Could not release mechanic %s after completion", mechanic_id)

    return jsonify(
        {
            "success": True,
            "message": "Service completed; payment pending",
            "completionTimeMinutes": completion_minutes,
            "pricing": quote,
            "request": payload2,
        }
    ), 200


@bp.post("/rescueRequests/<request_id>/cancel")
def cancel_request(request_id: str):
    """Cancel a rescue request.

    Only the requester (or an admin) may cancel, and only before the service has
    started — cancelling mid-service is not a legal transition. §14, §39, §40
    """
    oid = _oid(request_id)
    if not oid:
        return _err("Invalid requestId", 400, "INVALID_ID")

    try:
        request_doc = db.rescue_requests().find_one({"_id": oid})
    except PyMongoError as exc:
        return _err(f"Database error: {exc}", 500, "DB_ERROR")

    if not request_doc:
        return _err("Request not found", 404, "NOT_FOUND")

    data = _body()
    # Ownership: admins freely; otherwise the caller must be the requester.
    identity = request.identity if hasattr(request, "identity") else None
    role = (identity or {}).get("role")
    if role != "admin":
        owner = str(request_doc.get("userId") or request_doc.get("phone") or "")
        subject = str((identity or {}).get("sub") or "")
        if subject and owner and subject != owner:
            return _err("You may only cancel your own request", 403, "NOT_OWNER")

    verdict = sm.validate_transition(request_doc.get("status"), sm.CANCELLED)
    if not verdict["ok"]:
        return _err(
            "This request can no longer be cancelled: " + verdict["reason"],
            409,
            "ILLEGAL_TRANSITION",
        )

    updates = {
        "status": sm.storage_label(sm.CANCELLED), "statusCanonical": sm.CANCELLED,
        "cancelledAt": _now(),
        "cancelledBy": role or data.get("cancelledBy", "user"),
        "cancellationReason": str(data.get("reason", "not specified")),
        "updatedAt": _now(),
    }

    try:
        db.rescue_requests().update_one({"_id": oid}, {"$set": updates})

        # Release the assigned mechanic so they return to the pool.
        mech_id = str(request_doc.get("mechanicId") or "")
        mech_oid = _oid(mech_id) if mech_id else None
        if mech_oid:
            db.mechanics().update_one(
                {"_id": mech_oid},
                {
                    "$set": {"currentRequestId": "", "available": True, "updatedAt": _now()},
                    "$inc": {"workload": -1},
                },
            )

        updated = db.rescue_requests().find_one({"_id": oid})
    except PyMongoError as exc:
        return _err(f"Database error: {exc}", 500, "DB_ERROR")

    payload = serialize_request(updated)
    realtime.emit_event(
        "status_updated",
        {
            "success": True,
            "requestId": request_id,
            "id": request_id,
            "status": sm.storage_label(sm.CANCELLED), "statusCanonical": sm.CANCELLED,
            "mechanicId": mech_id,
        },
    )

    return jsonify(
        {"success": True, "message": "Request cancelled", "request": payload}
    ), 200


# ─────────────────────────────────────────────────────────────────────────────
# PAYMENTS  (§29, §30)
# ─────────────────────────────────────────────────────────────────────────────
def _quote_for_request(request_doc: Dict[str, Any]) -> Dict[str, Any]:
    return pricing.quote(
        request_doc.get("issue", ""),
        request_doc.get("assignedDistanceKm") or request_doc.get("distanceKm"),
    )


@bp.get("/payments/quote")
def payment_quote():
    """Itemised price breakdown shown to the user BEFORE payment. §30"""
    request_id = str(request.args.get("requestId") or "").strip()

    if request_id:
        oid = _oid(request_id)
        if not oid:
            return _err("Invalid requestId", 400, "INVALID_ID")
        try:
            doc = db.rescue_requests().find_one({"_id": oid})
        except PyMongoError as exc:
            return _err(f"Database error: {exc}", 500, "DB_ERROR")
        if not doc:
            return _err("Request not found", 404, "NOT_FOUND")
        quote = _quote_for_request(doc)
    else:
        issue = request.args.get("issue", "")
        if not issue:
            return _err("Either requestId or issue is required", 400)
        quote = pricing.quote(issue, _as_float(request.args.get("distanceKm")))

    return jsonify({"success": True, "quote": quote}), 200


@bp.post("/payments/create")
def payment_create():
    """Create a Razorpay order for a completed rescue.

    Only allowed once the request has reached PAYMENT_PENDING, so an order can
    never be raised for work that was not done. §29
    """
    data = _body()
    request_id = str(data.get("requestId") or "").strip()
    if not request_id:
        return _err("requestId is required", 400)

    oid = _oid(request_id)
    if not oid:
        return _err("Invalid requestId", 400, "INVALID_ID")

    try:
        request_doc = db.rescue_requests().find_one({"_id": oid})
    except PyMongoError as exc:
        return _err(f"Database error: {exc}", 500, "DB_ERROR")

    if not request_doc:
        return _err("Request not found", 404, "NOT_FOUND")

    canonical = sm.normalize(request_doc.get("status"))
    if canonical not in {sm.PAYMENT_PENDING, sm.PAYMENT_FAILED}:
        return _err(
            f"Payment can only be created when the request is PAYMENT_PENDING "
            f"(current: {canonical})",
            409,
            "ILLEGAL_STATE",
        )

    if str(request_doc.get("paymentStatus", "")).lower() == "success":
        return _err("This request is already paid", 409, "ALREADY_PAID")

    quote = _quote_for_request(request_doc)

    order = payment_gateway.create_order(
        quote["totalMinorUnits"],
        receipt=f"rrq_{request_id}",
        notes={"requestId": request_id, "issue": request_doc.get("issue", "")},
    )

    if not order.get("success"):
        return _err(order.get("message", "Order creation failed"), 502, "PAYMENT_ERROR")

    payment_doc = {
        "requestId": request_id,
        "orderId": order.get("orderId"),
        "amount": quote["total"],
        "amountMinorUnits": quote["totalMinorUnits"],
        "currency": quote["currency"],
        "status": "created",
        "mode": order.get("mode"),
        "simulated": bool(order.get("simulated", False)),
        "quote": quote,
        "createdAt": _now(),
        "updatedAt": _now(),
    }

    try:
        db.payments().insert_one(payment_doc)
        db.rescue_requests().update_one(
            {"_id": oid},
            {
                "$set": {
                    "amount": quote["total"],
                    "pricing": quote,
                    "orderId": order.get("orderId"),
                    "paymentStatus": "created",
                    "paymentSimulated": bool(order.get("simulated", False)),
                    "updatedAt": _now(),
                }
            },
        )
    except PyMongoError as exc:
        return _err(f"Database error: {exc}", 500, "DB_ERROR")

    return jsonify(
        {
            "success": True,
            "message": order.get("message", "Payment order created"),
            "orderId": order.get("orderId"),
            "amount": quote["totalMinorUnits"],
            "amountMajor": quote["total"],
            "currency": quote["currency"],
            "keyId": order.get("keyId"),
            "mode": order.get("mode"),
            "simulated": bool(order.get("simulated", False)),
            "quote": quote,
        }
    ), 201


@bp.post("/payments/verify")
def payment_verify():
    """Verify a payment and close the transaction.

    Two distinct paths, never conflated:

      * `signature` supplied → HMAC-SHA256 signature verified against the key
        secret here on the server. Only a valid signature marks the request paid.
      * no signature, `simulate: true`, and `DEV_MODE` on → an explicitly
        SIMULATED completion, recorded with `simulated: true` so it can never be
        presented as a real payment. §29, §42
    """
    data = _body()
    request_id = str(data.get("requestId") or "").strip()
    order_id = str(data.get("razorpayOrderId") or data.get("orderId") or "").strip()
    payment_id = str(data.get("razorpayPaymentId") or data.get("paymentId") or "").strip()
    signature = str(data.get("razorpaySignature") or data.get("signature") or "").strip()
    simulate = bool(data.get("simulate", False))

    if not request_id:
        return _err("requestId is required", 400)

    oid = _oid(request_id)
    if not oid:
        return _err("Invalid requestId", 400, "INVALID_ID")

    try:
        request_doc = db.rescue_requests().find_one({"_id": oid})
    except PyMongoError as exc:
        return _err(f"Database error: {exc}", 500, "DB_ERROR")

    if not request_doc:
        return _err("Request not found", 404, "NOT_FOUND")

    canonical = sm.normalize(request_doc.get("status"))
    if canonical not in {sm.PAYMENT_PENDING, sm.PAYMENT_FAILED}:
        return _err(
            f"Payment cannot be verified in state {canonical}", 409, "ILLEGAL_STATE"
        )

    verified = False
    simulated = False
    note = ""

    if signature:
        check = payment_gateway.verify_signature(order_id, payment_id, signature)
        verified = bool(check.get("verified"))
        note = check.get("reason", "")
        if not verified:
            try:
                db.rescue_requests().update_one(
                    {"_id": oid},
                    {
                        "$set": {
                            "status": sm.storage_label(sm.PAYMENT_FAILED), "statusCanonical": sm.PAYMENT_FAILED,
                            "paymentStatus": "failed",
                            "updatedAt": _now(),
                        }
                    },
                )
            except PyMongoError:
                pass
            return _err(
                f"Payment verification failed: {note}", 400, "SIGNATURE_INVALID"
            )
    elif simulate and Config.DEV_MODE:
        verified = True
        simulated = True
        payment_id = payment_id or f"sim_pay_{int(time.time())}"
        order_id = order_id or str(request_doc.get("orderId") or "")
        note = (
            "SIMULATED payment confirmation (DEV_MODE). This is NOT a real "
            "payment and must not be reported as one."
        )
    else:
        return _err(
            "A razorpaySignature is required to verify a payment. "
            "Set DEV_MODE and pass simulate=true only for development.",
            400,
            "SIGNATURE_REQUIRED",
        )

    amount = request_doc.get("amount") or 0
    try:
        db.rescue_requests().update_one(
            {"_id": oid},
            {
                "$set": {
                    "status": sm.storage_label(sm.PAYMENT_COMPLETED), "statusCanonical": sm.PAYMENT_COMPLETED,
                    "paymentStatus": "success",
                    "paymentId": payment_id,
                    "orderId": order_id,
                    "paymentMethod": data.get("method", "razorpay"),
                    "signatureVerified": bool(signature),
                    "paymentSimulated": simulated,
                    "paidAt": _now(),
                    "updatedAt": _now(),
                }
            },
        )

        # Resolve the newest payment record for this request, then update it by
        # _id (update_one with a sort argument is not version-portable).
        payment_doc = db.payments().find_one(
            {"requestId": request_id, "orderId": order_id},
            sort=[("createdAt", -1)],
        )
        if payment_doc:
            db.payments().update_one(
                {"_id": payment_doc["_id"]},
                {
                    "$set": {
                        "paymentId": payment_id,
                        "status": "captured",
                        "signatureVerified": bool(signature),
                        "simulated": simulated,
                        "updatedAt": _now(),
                        "paidAt": _now(),
                    }
                },
            )
    except PyMongoError as exc:
        return _err(f"Database error: {exc}", 500, "DB_ERROR")

    realtime.emit_event(
        "payment_updated",
        {
            "success": True,
            "requestId": request_id,
            "paymentStatus": "success",
            "paymentId": payment_id,
            "amount": amount,
            "simulated": simulated,
        },
    )

    return jsonify(
        {
            "success": True,
            "message": "Payment verified and recorded" if not simulated else note,
            "verified": verified,
            "simulated": simulated,
            "signatureVerified": bool(signature),
            "paymentId": payment_id,
            "orderId": order_id,
            "amount": amount,
            "request": serialize_request(
                db.rescue_requests().find_one({"_id": oid})
            ),
        }
    ), 200


# ─────────────────────────────────────────────────────────────────────────────
# RATINGS  (§31)
# ─────────────────────────────────────────────────────────────────────────────
@bp.post("/ratings")
def create_rating():
    """Rate the mechanic for a completed rescue.

    The mechanic's aggregate is recomputed from stored ratings only — never
    seeded, never invented. §31
    """
    data = _body()
    request_id = str(data.get("requestId") or "").strip()
    rating_value = _as_float(data.get("rating"))
    review = str(data.get("review") or "").strip()

    if not request_id:
        return _err("requestId is required", 400)
    if rating_value is None or not (1.0 <= rating_value <= 5.0):
        return _err("rating must be a number between 1 and 5", 400)

    oid = _oid(request_id)
    if not oid:
        return _err("Invalid requestId", 400, "INVALID_ID")

    try:
        request_doc = db.rescue_requests().find_one({"_id": oid})
    except PyMongoError as exc:
        return _err(f"Database error: {exc}", 500, "DB_ERROR")

    if not request_doc:
        return _err("Request not found", 404, "NOT_FOUND")

    canonical = sm.normalize(request_doc.get("status"))
    if canonical not in {sm.PAYMENT_COMPLETED, sm.RATED, sm.CLOSED}:
        return _err(
            "A rescue can only be rated after the payment is completed "
            f"(current state: {canonical})",
            409,
            "ILLEGAL_STATE",
        )

    mechanic_id = str(request_doc.get("mechanicId") or "")
    if not mechanic_id:
        return _err("This request has no assigned mechanic to rate", 400)

    existing = db.ratings().find_one({"requestId": request_id})
    if existing:
        return _err("This rescue has already been rated", 409, "ALREADY_RATED")

    rating_doc = {
        "requestId": request_id,
        "mechanicId": mechanic_id,
        "userId": str(request_doc.get("userId") or ""),
        "userPhone": str(request_doc.get("phone") or ""),
        "rating": float(rating_value),
        "review": review,
        "createdAt": _now(),
    }

    try:
        db.ratings().insert_one(rating_doc)

        # Recompute the aggregate from stored ratings only.
        pipeline = [
            {"$match": {"mechanicId": mechanic_id}},
            {
                "$group": {
                    "_id": "$mechanicId",
                    "avg": {"$avg": "$rating"},
                    "count": {"$sum": 1},
                }
            },
        ]
        agg = list(db.ratings().aggregate(pipeline))
        average = round(float(agg[0]["avg"]), 2) if agg else 0.0
        count = int(agg[0]["count"]) if agg else 0

        mech_oid = _oid(mechanic_id)
        if mech_oid:
            db.mechanics().update_one(
                {"_id": mech_oid},
                {
                    "$set": {
                        "rating": average,
                        "ratingCount": count,
                        "updatedAt": _now(),
                    }
                },
            )

        db.rescue_requests().update_one(
            {"_id": oid},
            {
                "$set": {
                    "rating": float(rating_value),
                    "review": review,
                    "ratedAt": _now(),
                    "updatedAt": _now(),
                }
            },
        )

        # RATED → CLOSED completes the lifecycle.
        db.rescue_requests().update_one(
            {"_id": oid}, {"$set": {"status": sm.storage_label(sm.CLOSED), "statusCanonical": sm.CLOSED, "closedAt": _now()}}
        )
    except PyMongoError as exc:
        return _err(f"Database error: {exc}", 500, "DB_ERROR")

    realtime.emit_event(
        "rating_created",
        {
            "success": True,
            "requestId": request_id,
            "mechanicId": mechanic_id,
            "rating": float(rating_value),
        },
    )

    return jsonify(
        {
            "success": True,
            "message": "Rating recorded",
            "mechanicAggregate": {"rating": average, "ratingCount": count},
            "request": serialize_request(
                db.rescue_requests().find_one({"_id": oid})
            ),
        }
    ), 201


@bp.get("/mechanics/<mechanic_id>/ratings")
def mechanic_ratings(mechanic_id: str):
    """List a mechanic's stored ratings plus the computed aggregate. §31"""
    limit = min(max(_as_int(request.args.get("limit", 50), 50), 1), 200)
    try:
        docs = list(
            db.ratings()
            .find({"mechanicId": str(mechanic_id)})
            .sort("createdAt", -1)
            .limit(limit)
        )
        pipeline = [
            {"$match": {"mechanicId": str(mechanic_id)}},
            {
                "$group": {
                    "_id": "$mechanicId",
                    "avg": {"$avg": "$rating"},
                    "count": {"$sum": 1},
                }
            },
        ]
        agg = list(db.ratings().aggregate(pipeline))
    except PyMongoError as exc:
        return _err(f"Database error: {exc}", 500, "DB_ERROR")

    average = round(float(agg[0]["avg"]), 2) if agg else 0.0
    count = int(agg[0]["count"]) if agg else 0

    return jsonify(
        {
            "success": True,
            "mechanicId": str(mechanic_id),
            "aggregate": {"rating": average, "ratingCount": count},
            "ratings": [serialize_rating(d) for d in docs],
        }
    ), 200


# ─────────────────────────────────────────────────────────────────────────────
# ADMIN — dashboard metrics, regions, allocation evidence  (§16, §34, §45, §46)
# ─────────────────────────────────────────────────────────────────────────────
def _count(collection, query: Optional[Dict[str, Any]] = None) -> int:
    try:
        return int(collection.count_documents(query or {}))
    except PyMongoError:
        return 0


def _avg(collection, field: str, query: Optional[Dict[str, Any]] = None) -> Optional[float]:
    """Average a numeric field, ignoring nulls. Returns None when no data."""
    try:
        pipeline = [
            {"$match": {**(query or {}), field: {"$ne": None}}},
            {"$group": {"_id": None, "value": {"$avg": f"${field}"}}},
        ]
        rows = list(collection.aggregate(pipeline))
        if not rows or rows[0].get("value") is None:
            return None
        return round(float(rows[0]["value"]), 2)
    except PyMongoError:
        return None


@bp.get("/admin/dashboard")
def admin_dashboard():
    """Every figure is aggregated from the database.

    There are no hardcoded statistics here. When a metric has no underlying
    data it is returned as `null` rather than as a plausible-looking number, so
    a prototype cannot silently present invented performance. §34, §44 §9
    """
    requests_coll = db.rescue_requests()
    mechanics_coll = db.mechanics()
    logs_coll = db.allocation_logs()

    terminal_states = [sm.CLOSED, sm.SERVICE_COMPLETED, sm.PAYMENT_COMPLETED, sm.RATED]
    active_states = [
        sm.SEARCHING,
        sm.MECHANIC_ASSIGNED,
        sm.MECHANIC_ACCEPTED,
        sm.MECHANIC_EN_ROUTE,
        sm.ARRIVED,
        sm.SERVICE_STARTED,
        sm.PAYMENT_PENDING,
    ]

    # Status is stored in mixed legacy casing, so match on both spellings.
    def _status_filter(states: List[str]) -> Dict[str, Any]:
        variants: List[str] = []
        for state in states:
            variants.extend(
                {
                    state,
                    state.lower(),
                    sm.CANONICAL_TO_LEGACY.get(state, state),
                    sm.CANONICAL_TO_LEGACY.get(state, state).lower(),
                }
            )
        return {"status": {"$in": sorted(set(variants))}}

    overview = {
        "totalUsers": _count(db.users()),
        "totalMechanics": _count(mechanics_coll),
        "verifiedMechanics": _count(
            mechanics_coll, {"$or": [{"verified": True}, {"verificationStatus": "verified"}]}
        ),
        "onlineMechanics": _count(mechanics_coll, {"online": True}),
        "availableMechanics": _count(
            mechanics_coll, {"online": True, "available": True}
        ),
        "totalRequests": _count(requests_coll),
        "activeRequests": _count(requests_coll, _status_filter(active_states)),
        "completedRescues": _count(requests_coll, _status_filter(terminal_states)),
        "cancelledRequests": _count(requests_coll, _status_filter([sm.CANCELLED])),
        "unassignedRequests": _count(
            requests_coll, _status_filter([sm.NO_MECHANIC_AVAILABLE])
        ),
    }

    # ── Regional monitoring ─────────────────────────────────────────────
    regions_docs = list(db.regions().find({}))
    per_region: List[Dict[str, Any]] = []
    for region in regions_docs:
        region_id = str(region.get("_id"))
        per_region.append(
            {
                "regionId": region_id,
                "regionName": region.get("name", ""),
                "mechanics": _count(mechanics_coll, {"regionId": region_id}),
                "onlineMechanics": _count(
                    mechanics_coll, {"regionId": region_id, "online": True}
                ),
                "availableMechanics": _count(
                    mechanics_coll,
                    {"regionId": region_id, "online": True, "available": True},
                ),
                "requests": _count(requests_coll, {"regionId": region_id}),
            }
        )

    unassigned_mechanics = _count(
        mechanics_coll, {"$or": [{"regionId": None}, {"regionId": {"$exists": False}}]}
    )

    # ── Allocation metrics — measured from allocation_logs ──────────────
    total_attempts = _count(logs_coll)
    successful = _count(logs_coll, {"status": allocation.A_OK})
    no_mechanic = _count(logs_coll, {"status": allocation.A_NO_ELIGIBLE})
    escalated = _count(logs_coll, {"escalationUsed": True})

    accepted = _count(logs_coll, {"acceptanceTimeMs": {"$ne": None}})

    allocation_metrics = {
        "totalAllocationAttempts": total_attempts,
        "successfulAssignments": successful,
        "noMechanicCases": no_mechanic,
        "escalatedCases": escalated,
        # Rates are null, not 0, when there is nothing to divide by.
        "assignmentSuccessRate": (
            round(successful / total_attempts, 4) if total_attempts else None
        ),
        "mechanicAcceptanceRate": (
            round(accepted / successful, 4) if successful else None
        ),
        "avgAssignmentTimeMs": _avg(logs_coll, "assignmentTimeMs"),
        "avgAcceptanceTimeMs": _avg(logs_coll, "acceptanceTimeMs"),
        "avgAssignedDistanceKm": _avg(logs_coll, "selectedDistanceKm"),
        "avgEtaMinutes": _avg(logs_coll, "selectedEtaMinutes"),
        "avgEligibleCount": _avg(logs_coll, "eligibleCount"),
        "avgCandidateCount": _avg(logs_coll, "candidateCount"),
    }

    # ── Operations ──────────────────────────────────────────────────────
    payments_coll = db.payments()
    captured_total = list(
        payments_coll.aggregate(
            [
                {"$match": {"status": {"$in": ["captured", "success"]}}},
                {"$group": {"_id": None, "total": {"$sum": "$amount"}, "count": {"$sum": 1}}},
            ]
        )
    )
    payments_summary = {
        "capturedCount": int(captured_total[0]["count"]) if captured_total else 0,
        "capturedAmount": round(float(captured_total[0]["total"]), 2) if captured_total else 0.0,
        "pendingCount": _count(payments_coll, {"status": "created"}),
        "currency": Config.PRICING_CURRENCY,
    }

    operations = {
        "payments": payments_summary,
        "avgRating": _avg(db.ratings(), "rating"),
        "ratingsCount": _count(db.ratings()),
        "openSupportTickets": _count(db.support_tickets(), {"status": {"$ne": "closed"}}),
        "networkFailureRequests": _count(requests_coll, _status_filter([sm.NETWORK_FAILURE])),
        "paymentFailedRequests": _count(requests_coll, _status_filter([sm.PAYMENT_FAILED])),
    }

    return jsonify(
        {
            "success": True,
            "generatedAt": _now().isoformat(),
            "note": (
                "All figures are aggregated from the live database. Metrics with "
                "no underlying data are returned as null, never estimated."
            ),
            "overview": overview,
            "regional": {
                "activeRegions": len(regions_docs),
                "mechanicsPerRegion": per_region,
                "mechanicsWithoutRegion": unassigned_mechanics,
                "requestsPerRegion": [
                    {"regionId": r["regionId"], "regionName": r["regionName"], "requests": r["requests"]}
                    for r in per_region
                ],
            },
            "allocation": allocation_metrics,
            "operations": operations,
        }
    ), 200


@bp.get("/admin/regions")
def admin_list_regions():
    """List configured regions and hubs. §16"""
    try:
        regions = list(db.regions().find({}))
        hubs = list(db.hubs().find({}))
    except PyMongoError as exc:
        return _err(f"Database error: {exc}", 500, "DB_ERROR")

    return jsonify(
        {
            "success": True,
            "count": len(regions),
            "regions": [serialize_region(r) for r in regions],
            "hubs": [
                {
                    "_id": str(h.get("_id")),
                    "name": h.get("name", ""),
                    "regionId": str(h.get("regionId") or ""),
                    "location": h.get("location") or {},
                    "services": h.get("services") or [],
                }
                for h in hubs
            ],
        }
    ), 200


@bp.post("/admin/regions")
@require_role("mechanic")
def admin_create_region():
    """Create a region. Admin only (reuses the mechanic role guard + check). §16"""
    identity = request.identity  # type: ignore[attr-defined]
    if identity.get("role") != "admin":
        return _err("Admin access required", 403)

    data = _body()
    name = str(data.get("name", "")).strip()
    if not name:
        return _err("name is required", 400)

    doc: Dict[str, Any] = {
        "name": name,
        "city": str(data.get("city", "")).strip(),
        "radiusKm": _as_float(data.get("radiusKm")),
        "createdAt": _now(),
        "updatedAt": _now(),
    }

    # Accept either a GeoJSON boundary or a flat bounding box.
    if isinstance(data.get("boundary"), dict):
        doc["boundary"] = data["boundary"]
    for field in ("latMin", "latMax", "lngMin", "lngMax"):
        if data.get(field) is not None:
            doc[field] = _as_float(data.get(field))

    if isinstance(data.get("center"), dict):
        center = coerce_coordinate(
            (data["center"] or {}).get("lat"), (data["center"] or {}).get("lng")
        )
        if center:
            doc["center"] = {"lat": center[0], "lng": center[1]}
            # 2d index target expects [lng, lat] or {lat, lng}; store the pair
            # explicitly so geospatial queries remain possible.
            doc["centerPoint"] = [center[1], center[0]]

    if not any(
        key in doc
        for key in ("boundary", "latMin", "latMax", "center")
    ):
        return _err(
            "A region needs a boundary, a lat/lng bounding box, or a center "
            "with radiusKm",
            400,
        )

    try:
        inserted = db.regions().insert_one(doc)
    except PyMongoError as exc:
        return _err(f"Database error: {exc}", 500, "DB_ERROR")

    doc["_id"] = inserted.inserted_id
    return jsonify(
        {"success": True, "message": "Region created", "region": serialize_region(doc)}
    ), 201


@bp.get("/admin/allocation-logs")
def admin_allocation_logs():
    """Raw allocation evidence for inspection and experiment review. §19, §45"""
    query: Dict[str, Any] = {}
    if request.args.get("requestId"):
        query["requestId"] = request.args["requestId"]
    if request.args.get("status"):
        query["status"] = request.args["status"]
    if request.args.get("regionId"):
        query["regionId"] = request.args["regionId"]

    limit = min(max(_as_int(request.args.get("limit", 50), 50), 1), 500)
    include_candidates = request.args.get("includeCandidates", "false").lower() in {
        "1",
        "true",
        "yes",
    }

    try:
        docs = list(
            db.allocation_logs().find(query).sort("createdAt", -1).limit(limit)
        )
    except PyMongoError as exc:
        return _err(f"Database error: {exc}", 500, "DB_ERROR")

    serialized = []
    for doc in docs:
        payload = serialize_allocation_log(doc)
        if not include_candidates:
            # Candidate-level detail is large; omit it unless asked for.
            payload.pop("candidates", None)
        serialized.append(payload)

    return jsonify(
        {"success": True, "count": len(serialized), "logs": serialized}
    ), 200


@bp.get("/admin/experiments/summary")
def admin_experiments_summary():
    """Aggregate the metrics the journal evaluation needs. §44, §45, §46

    Every value is computed from stored allocation logs. When a scenario has no
    runs yet, the group is simply absent — nothing is fabricated.
    """
    try:
        logs = list(db.allocation_logs().find({}))
    except PyMongoError as exc:
        return _err(f"Database error: {exc}", 500, "DB_ERROR")

    def _summarise(group: List[Dict[str, Any]]) -> Dict[str, Any]:
        if not group:
            return {"runs": 0}

        def _nums(field: str) -> List[float]:
            return [
                float(g[field])
                for g in group
                if isinstance(g.get(field), (int, float))
            ]

        assignment_times = _nums("assignmentTimeMs")
        acceptance_times = _nums("acceptanceTimeMs")
        distances = _nums("selectedDistanceKm")
        etas = _nums("selectedEtaMinutes")
        eligible_counts = _nums("eligibleCount")
        candidate_counts = _nums("candidateCount")

        successes = sum(1 for g in group if g.get("status") == allocation.A_OK)
        no_mech = sum(1 for g in group if g.get("status") == allocation.A_NO_ELIGIBLE)
        accepted = len(acceptance_times)

        def _mean(values: List[float]) -> Optional[float]:
            return round(sum(values) / len(values), 2) if values else None

        return {
            "runs": len(group),
            "successfulAssignments": successes,
            "noMechanicCases": no_mech,
            "assignmentSuccessRate": round(successes / len(group), 4),
            "mechanicAcceptanceRate": (
                round(accepted / successes, 4) if successes else None
            ),
            "avgAssignmentTimeMs": _mean(assignment_times),
            "avgAcceptanceTimeMs": _mean(acceptance_times),
            "avgAssignedDistanceKm": _mean(distances),
            "avgEtaMinutes": _mean(etas),
            "avgEligibleCount": _mean(eligible_counts),
            "avgCandidateCount": _mean(candidate_counts),
        }

    # Group by scenario, inferred from the observable shape of each run. §45
    by_scenario: Dict[str, List[Dict[str, Any]]] = {}
    for doc in logs:
        candidates = int(doc.get("candidateCount") or 0)
        eligible = int(doc.get("eligibleCount") or 0)

        if candidates == 0:
            scenario = "I_no_mechanic_available"
        elif eligible == 0:
            scenario = "F_no_eligible_in_region"
        elif doc.get("escalationUsed"):
            scenario = "F_region_escalation_used"
        elif eligible == 1:
            scenario = "A_single_eligible_mechanic"
        elif eligible <= 3:
            scenario = "B_three_available_mechanics"
        elif eligible <= 5:
            scenario = "C_five_available_mechanics"
        else:
            scenario = "D_ten_or_more_mechanics"

        by_scenario.setdefault(scenario, []).append(doc)

    return jsonify(
        {
            "success": True,
            "generatedAt": _now().isoformat(),
            "metricNote": (
                "Derived from stored allocation logs only. Distances are "
                "great-circle. No improvement percentage is reported because "
                "no baseline was measured."
            ),
            "overall": _summarise(logs),
            "byScenario": {
                name: _summarise(group) for name, group in sorted(by_scenario.items())
            },
        }
    ), 200


@bp.get("/admin/export/allocation")
def admin_export_allocation():
    """Export anonymised allocation records as CSV. §46

    Identifier fields (mechanic ids/names, phone numbers, GPS coordinates) are
    replaced by stable hashes or omitted so the dataset can be shared for
    research without exposing personal data.
    """
    import hashlib

    def _pseudonym(value: Any) -> str:
        if value is None or value == "":
            return ""
        return "M" + hashlib.sha256(str(value).encode()).hexdigest()[:10]

    try:
        docs = list(db.allocation_logs().find({}).sort("createdAt", 1).limit(5000))
    except PyMongoError as exc:
        return _err(f"Database error: {exc}", 500, "DB_ERROR")

    columns = [
        "request_id",
        "region",
        "hub",
        "vehicle_type",
        "issue_type",
        "candidate_count",
        "eligible_count",
        "selected_mechanic",
        "selected_distance_m",
        "selected_distance_km",
        "assignment_time_ms",
        "acceptance_time_ms",
        "eta_minutes",
        "completion_time_minutes",
        "allocation_status",
        "failure_reason",
        "escalation_used",
        "network_status",
        "timestamp",
    ]

    buffer = io.StringIO()
    writer = csv.DictWriter(buffer, fieldnames=columns)
    writer.writeheader()

    for doc in docs:
        created = doc.get("createdAt")
        writer.writerow(
            {
                "request_id": "R" + hashlib.sha256(
                    str(doc.get("requestId", "")).encode()
                ).hexdigest()[:10],
                "region": doc.get("regionName") or doc.get("regionId") or "",
                "hub": doc.get("hubId") or "",
                "vehicle_type": doc.get("vehicleType", ""),
                "issue_type": doc.get("issueType", ""),
                "candidate_count": doc.get("candidateCount", 0),
                "eligible_count": doc.get("eligibleCount", 0),
                "selected_mechanic": _pseudonym(doc.get("selectedMechanicId")),
                "selected_distance_m": (
                    round(float(doc["selectedDistanceKm"]) * 1000, 1)
                    if isinstance(doc.get("selectedDistanceKm"), (int, float))
                    else ""
                ),
                "selected_distance_km": doc.get("selectedDistanceKm", ""),
                "assignment_time_ms": doc.get("assignmentTimeMs", ""),
                "acceptance_time_ms": doc.get("acceptanceTimeMs", ""),
                "eta_minutes": doc.get("selectedEtaMinutes", ""),
                "completion_time_minutes": doc.get("completionTimeMinutes", ""),
                "allocation_status": doc.get("status", ""),
                "failure_reason": doc.get("failureReason", "") or "",
                "escalation_used": bool(doc.get("escalationUsed", False)),
                "network_status": doc.get("networkStatus", "unknown"),
                "timestamp": (
                    created.isoformat()
                    if isinstance(created, datetime)
                    else str(created or "")
                ),
            }
        )

    filename = f"roadresq_allocation_export_{_now().strftime('%Y%m%d_%H%M%S')}.csv"
    return Response(
        buffer.getvalue(),
        mimetype="text/csv",
        headers={
            "Content-Disposition": f"attachment; filename={filename}",
            "X-Record-Count": str(len(docs)),
            "X-Anonymised": "true",
        },
    )


@bp.get("/admin/system/health")
def admin_system_health():
    """Database connectivity, index status and configured feature flags. §34"""
    index_summary = db.ensure_indexes(verbose=False)
    return jsonify(
        {
            "success": True,
            "database": {
                "connected": db.ping(),
                "name": Config.DB_NAME,
                "collections": {
                    "users": _count(db.users()),
                    "mechanics": _count(db.mechanics()),
                    "rescue_requests": _count(db.rescue_requests()),
                    "regions": _count(db.regions()),
                    "hubs": _count(db.hubs()),
                    "allocation_logs": _count(db.allocation_logs()),
                    "payments": _count(db.payments()),
                    "ratings": _count(db.ratings()),
                },
                "indexes": {
                    "created": index_summary["createdCount"],
                    "failed": index_summary["failedCount"],
                    "failures": index_summary["failed"][:10],
                },
            },
            "features": {
                "devMode": Config.DEV_MODE,
                "realtime": realtime.is_available(),
                "payments": {
                    "enabled": payment_gateway.sdk_available(),
                    "testMode": Config.RAZORPAY_TEST_MODE,
                },
            },
            "allocation": {
                "searchRadiusKm": Config.DEFAULT_SEARCH_RADIUS_KM,
                "escalationRadiusKm": Config.ESCALATION_RADIUS_KM,
                "assumedSpeedKmh": Config.ASSUMED_AVG_SPEED_KMH,
                "weights": Config.allocation_weights(),
            },
        }
    ), 200


# ─────────────────────────────────────────────────────────────────────────────
# Utility: haversine sanity endpoint used by tests and manual verification
# ─────────────────────────────────────────────────────────────────────────────
@bp.get("/geo/distance")
def geo_distance():
    """Great-circle distance between two points, for verification. §22"""
    try:
        lat1 = float(request.args.get("lat1", ""))
        lng1 = float(request.args.get("lng1", ""))
        lat2 = float(request.args.get("lat2", ""))
        lng2 = float(request.args.get("lng2", ""))
    except (TypeError, ValueError):
        return _err("lat1, lng1, lat2, lng2 are required numeric values", 400)

    coords = coerce_coordinate(lat1, lng1) and coerce_coordinate(lat2, lng2)
    if not coords:
        return _err("Coordinates are outside valid latitude/longitude bounds", 400)

    km = haversine_km(lat1, lng1, lat2, lng2)
    return jsonify(
        {
            "success": True,
            "distanceKm": round(km, 3),
            "distanceMeters": round(km * 1000, 1),
            "etaMinutes": round(km / Config.ASSUMED_AVG_SPEED_KMH * 60, 1),
            "kind": "great-circle (straight line, not road distance)",
            "assumedSpeedKmh": Config.ASSUMED_AVG_SPEED_KMH,
        }
    ), 200
