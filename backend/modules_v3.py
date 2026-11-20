"""RoadResQ completion modules — additive blueprint.

Every route here is NEW. Nothing in `roadresq_backend.py` or `api_v2.py` is
replaced, so the existing contract the Flutter app already uses keeps working.

Covers the modules that were audited as empty or half-built:

  * §7  / §28 / §33  file uploads (profile photo, repair photos, KYC documents)
  * §18              in-job chat (Socket.IO `chat_message` + REST history)
  * §38 / §39        6-digit arrival token, generated and verified server-side
  * §41              assistant attendance (check-in / check-out)
  * §42 / §30        assistant incentives and mechanic earnings breakdown
  * §48              feedback / complaints with status tracking
  * §51              admin console login + revenue metrics
  * §52              server-side escalation watchdog (5-minute window)

The blueprint is registered by `roadresq_backend.py` via `init_app()`.
"""

from __future__ import annotations

import logging
import os
import random
import threading
import time
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional

from bson import ObjectId
from flask import Blueprint, jsonify, request, send_from_directory
from werkzeug.utils import secure_filename

import realtime
import status_machine as sm
from config import Config
from db import get_db

log = logging.getLogger("roadresq.modules")

bp = Blueprint("modules_v3", __name__, url_prefix="/api")

# ── Uploads ────────────────────────────────────────────────────────────────
UPLOAD_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "uploads")
ALLOWED_EXT = {".png", ".jpg", ".jpeg", ".webp", ".pdf"}
MAX_UPLOAD_BYTES = 8 * 1024 * 1024


def _ensure_upload_dir() -> str:
    os.makedirs(UPLOAD_DIR, exist_ok=True)
    return UPLOAD_DIR


# ── Helpers ────────────────────────────────────────────────────────────────
def _coll(name: str):
    return get_db()[name]


def _oid(value: Any) -> Optional[ObjectId]:
    if value is None:
        return None
    if isinstance(value, ObjectId):
        return value
    try:
        return ObjectId(str(value))
    except Exception:
        return None


def _iso(value: Any) -> Optional[str]:
    if isinstance(value, datetime):
        return value.replace(microsecond=0).isoformat() + "Z"
    return None


def _ok(message: str = "", status: int = 200, **extra):
    payload: Dict[str, Any] = {"success": True}
    if message:
        payload["message"] = message
    payload.update(extra)
    return jsonify(payload), status


def _err(message: str, status: int = 400, code: str = ""):
    payload: Dict[str, Any] = {"success": False, "message": message}
    if code:
        payload["code"] = code
    return jsonify(payload), status


def _body() -> Dict[str, Any]:
    return request.get_json(silent=True) or {}


def _find_request(request_id: Any) -> Optional[Dict[str, Any]]:
    oid = _oid(request_id)
    if oid is None:
        return None
    return _coll("rescue_requests").find_one({"_id": oid})


def _id_match(value: str) -> Dict[str, Any]:
    """Match a linkage id stored either as a string or as an ObjectId."""
    candidates: List[Any] = [value]
    if ObjectId.is_valid(str(value)):
        candidates.append(ObjectId(str(value)))
    return {"$in": candidates}


# ══════════════════════════════════════════════════════════════════════════
# §7 / §28 / §33 — uploads
# ══════════════════════════════════════════════════════════════════════════
@bp.post("/uploads")
def upload_file():
    """Multipart upload for avatars, repair photos and KYC documents.

    Returns an absolute URL the Flutter client can render directly and store on
    the owning document (`photoUrl`, `repairPhotos`, `documents`).
    """
    if "file" not in request.files:
        return _err("No file was sent. Attach it as multipart field 'file'.", 400,
                    "NO_FILE")

    incoming = request.files["file"]
    if not incoming or not incoming.filename:
        return _err("The uploaded file has no filename.", 400, "EMPTY_FILENAME")

    ext = os.path.splitext(incoming.filename)[1].lower()
    if ext not in ALLOWED_EXT:
        return _err(
            f"Unsupported file type '{ext}'. Allowed: "
            + ", ".join(sorted(ALLOWED_EXT)),
            415,
            "UNSUPPORTED_TYPE",
        )

    data = incoming.read()
    if not data:
        return _err("The uploaded file is empty.", 400, "EMPTY_FILE")
    if len(data) > MAX_UPLOAD_BYTES:
        return _err(
            f"File is {len(data) // 1024} KB; the limit is "
            f"{MAX_UPLOAD_BYTES // 1024} KB.",
            413,
            "FILE_TOO_LARGE",
        )

    kind = secure_filename(str(request.form.get("kind") or "misc"))[:32] or "misc"
    safe_stem = secure_filename(os.path.splitext(incoming.filename)[0])[:40]
    name = f"{kind}_{int(time.time() * 1000)}_{random.randint(1000, 9999)}" \
           f"_{safe_stem}{ext}"

    directory = _ensure_upload_dir()
    with open(os.path.join(directory, name), "wb") as handle:
        handle.write(data)

    url = request.url_root.rstrip("/") + f"/api/uploads/{name}"
    return _ok(
        "File uploaded",
        201,
        url=url,
        path=f"/api/uploads/{name}",
        kind=kind,
        bytes=len(data),
    )


@bp.get("/uploads/<path:name>")
def serve_upload(name: str):
    """Serve an uploaded file. Traversal-safe: `send_from_directory` only."""
    directory = _ensure_upload_dir()
    try:
        return send_from_directory(directory, name)
    except Exception:
        return _err("File not found", 404, "NOT_FOUND")


# ══════════════════════════════════════════════════════════════════════════
# §18 — chat (Socket.IO `chat_message` + REST history)
# ══════════════════════════════════════════════════════════════════════════
def _serialize_message(doc: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "id": str(doc.get("_id", "")),
        "requestId": str(doc.get("requestId", "")),
        "senderId": str(doc.get("senderId", "")),
        "senderRole": doc.get("senderRole", ""),
        "senderName": doc.get("senderName", ""),
        "text": doc.get("text", ""),
        "createdAt": _iso(doc.get("createdAt")),
    }


@bp.get("/rescueRequests/<request_id>/messages")
def list_messages(request_id: str):
    doc = _find_request(request_id)
    if doc is None:
        return _err("Request not found", 404, "NOT_FOUND")

    rows = (
        _coll("messages")
        .find({"requestId": request_id})
        .sort("createdAt", 1)
        .limit(200)
    )
    return _ok(messages=[_serialize_message(r) for r in rows])


@bp.post("/rescueRequests/<request_id>/messages")
def post_message(request_id: str):
    doc = _find_request(request_id)
    if doc is None:
        return _err("Request not found", 404, "NOT_FOUND")

    data = _body()
    text = str(data.get("text", "")).strip()
    if not text:
        return _err("text is required", 400, "VALIDATION")
    if len(text) > 1000:
        return _err("text is limited to 1000 characters", 400, "VALIDATION")

    record = {
        "requestId": request_id,
        "senderId": str(data.get("senderId", "")),
        "senderRole": str(data.get("senderRole", "")),
        "senderName": str(data.get("senderName", "")),
        "text": text,
        "createdAt": datetime.utcnow(),
    }
    inserted = _coll("messages").insert_one(record)
    record["_id"] = inserted.inserted_id
    payload = _serialize_message(record)

    realtime.emit_event("chat_message", payload)
    return _ok("Message sent", 201, data=payload)


def handle_chat_message(data: Any) -> None:
    """Socket.IO `chat_message` — persist then fan out to every client.

    The client already filters on `requestId`, so a single broadcast keeps both
    the user and the crew screen in sync without room bookkeeping.
    """
    try:
        data = data or {}
        request_id = str(data.get("requestId", ""))
        text = str(data.get("text", "")).strip()
        if not request_id or not text:
            return
        if len(text) > 1000:
            text = text[:1000]

        record = {
            "requestId": request_id,
            "senderId": str(data.get("senderId", "")),
            "senderRole": str(data.get("senderRole", "")),
            "senderName": str(data.get("senderName", "")),
            "text": text,
            "createdAt": datetime.utcnow(),
        }
        inserted = _coll("messages").insert_one(record)
        record["_id"] = inserted.inserted_id
        realtime.emit_event("chat_message", _serialize_message(record))
    except Exception as exc:  # never let a socket handler kill the connection
        log.warning("chat_message failed: %s", exc)


# ══════════════════════════════════════════════════════════════════════════
# §38 / §39 — arrival token (server-generated, server-verified)
# ══════════════════════════════════════════════════════════════════════════
TOKEN_TTL_MINUTES = 30


@bp.post("/tokens/generate")
def generate_arrival_token():
    """Create a 6-digit arrival token and store it ON THE JOB.

    Generating it server-side means the code the customer is shown is the same
    code the backend later verifies; a client-side token cannot be trusted.
    """
    data = _body()
    request_id = str(data.get("requestId", "")).strip()
    doc = _find_request(request_id)
    if doc is None:
        return _err("Request not found", 404, "NOT_FOUND")

    code = f"{random.randint(0, 999999):06d}"
    expires = datetime.utcnow() + timedelta(minutes=TOKEN_TTL_MINUTES)

    _coll("rescue_requests").update_one(
        {"_id": doc["_id"]},
        {
            "$set": {
                "arrivalToken": code,
                "arrivalTokenExpiresAt": expires,
                "arrivalTokenGeneratedAt": datetime.utcnow(),
                "arrivalTokenGeneratedBy": str(data.get("mechanicId", "")),
                "arrivalTokenVerifiedAt": None,
                "updatedAt": datetime.utcnow(),
            }
        },
    )

    return _ok(
        "Arrival token generated",
        201,
        requestId=request_id,
        token=code,
        expiresAt=_iso(expires),
        qrPayload=f"ROADRESQ|{request_id}|{code}",
    )


@bp.post("/tokens/verify")
def verify_arrival_token():
    """Verify the customer-entered 6-digit token against the stored job token."""
    data = _body()
    request_id = str(data.get("requestId", "")).strip()
    code = str(data.get("token") or data.get("code") or "").strip()

    doc = _find_request(request_id)
    if doc is None:
        return _err("Request not found", 404, "NOT_FOUND")
    if not code:
        return _err("token is required", 400, "VALIDATION")

    stored = str(doc.get("arrivalToken") or "")
    if not stored:
        return _err(
            "No arrival token has been generated for this job yet.",
            409,
            "NO_TOKEN",
        )
    if doc.get("arrivalTokenVerifiedAt"):
        return _err("This token has already been used.", 409, "ALREADY_USED")

    expires = doc.get("arrivalTokenExpiresAt")
    if isinstance(expires, datetime) and expires < datetime.utcnow():
        return _err("The token has expired. Ask the crew for a new one.", 409,
                    "EXPIRED")

    if code != stored:
        return _err("That token does not match this job.", 400, "TOKEN_MISMATCH")

    updates: Dict[str, Any] = {
        "arrivalTokenVerifiedAt": datetime.utcnow(),
        "arrivalVerified": True,
        "updatedAt": datetime.utcnow(),
    }

    # Advance the lifecycle when the state machine allows it. If it does not,
    # the verification still stands — the token is evidence, not a transition.
    current = doc.get("status")
    if sm.can_transition(current, sm.ARRIVED):
        updates["status"] = sm.storage_label(sm.ARRIVED) or sm.ARRIVED
        updates["arrivedAt"] = datetime.utcnow()

    _coll("rescue_requests").update_one({"_id": doc["_id"]}, {"$set": updates})

    realtime.emit_event(
        "status_updated",
        {"requestId": request_id, "status": updates.get("status", current),
         "arrivalVerified": True},
    )
    return _ok("Arrival confirmed", requestId=request_id, verified=True)


# ══════════════════════════════════════════════════════════════════════════
# §41 — assistant attendance
# ══════════════════════════════════════════════════════════════════════════
def _today_key() -> str:
    return datetime.utcnow().strftime("%Y-%m-%d")


def _serialize_attendance(doc: Dict[str, Any]) -> Dict[str, Any]:
    minutes = doc.get("minutes") or 0
    return {
        "id": str(doc.get("_id", "")),
        "assistantId": str(doc.get("assistantId", "")),
        "date": doc.get("date", ""),
        "checkInAt": _iso(doc.get("checkInAt")),
        "checkOutAt": _iso(doc.get("checkOutAt")),
        "minutes": minutes,
        "hours": round(minutes / 60.0, 2),
        "status": doc.get("status", "open"),
        "jobId": doc.get("jobId", ""),
    }


@bp.post("/attendance/checkin")
def attendance_checkin():
    data = _body()
    assistant_id = str(data.get("assistantId", "")).strip()
    if not assistant_id:
        return _err("assistantId is required", 400, "VALIDATION")

    day = _today_key()
    existing = _coll("attendance").find_one(
        {"assistantId": assistant_id, "date": day, "status": "open"}
    )
    if existing:
        return _ok("Already checked in today", attendance=_serialize_attendance(existing))

    record = {
        "assistantId": assistant_id,
        "date": day,
        "checkInAt": datetime.utcnow(),
        "checkOutAt": None,
        "minutes": 0,
        "status": "open",
        "jobId": str(data.get("jobId", "")),
    }
    inserted = _coll("attendance").insert_one(record)
    record["_id"] = inserted.inserted_id
    return _ok("Checked in", 201, attendance=_serialize_attendance(record))


@bp.post("/attendance/checkout")
def attendance_checkout():
    data = _body()
    assistant_id = str(data.get("assistantId", "")).strip()
    if not assistant_id:
        return _err("assistantId is required", 400, "VALIDATION")

    record = _coll("attendance").find_one(
        {"assistantId": assistant_id, "status": "open"},
        sort=[("checkInAt", -1)],
    )
    if not record:
        return _err("No open check-in found for today.", 409, "NOT_CHECKED_IN")

    now = datetime.utcnow()
    started = record.get("checkInAt") or now
    minutes = max(0, int((now - started).total_seconds() // 60))

    _coll("attendance").update_one(
        {"_id": record["_id"]},
        {"$set": {"checkOutAt": now, "minutes": minutes, "status": "closed"}},
    )
    record.update({"checkOutAt": now, "minutes": minutes, "status": "closed"})
    return _ok("Checked out", attendance=_serialize_attendance(record))


@bp.get("/assistant/<assistant_id>/attendance")
def attendance_list(assistant_id: str):
    days = max(1, min(60, int(request.args.get("days", 14))))
    cutoff = datetime.utcnow() - timedelta(days=days)
    rows = (
        _coll("attendance")
        .find({"assistantId": assistant_id, "checkInAt": {"$gte": cutoff}})
        .sort("checkInAt", -1)
    )
    records = [_serialize_attendance(r) for r in rows]
    total_minutes = sum(r["minutes"] for r in records)
    return _ok(
        days=days,
        records=records,
        totalMinutes=total_minutes,
        totalHours=round(total_minutes / 60.0, 2),
    )


# ══════════════════════════════════════════════════════════════════════════
# §30 / §42 — earnings
# ══════════════════════════════════════════════════════════════════════════
def _job_amount(doc: Dict[str, Any]) -> float:
    try:
        return float(doc.get("amount") or 0)
    except (TypeError, ValueError):
        return 0.0


def _is_completed(doc: Dict[str, Any]) -> bool:
    canonical = sm.normalize(doc.get("status"))
    return canonical == sm.SERVICE_COMPLETED or canonical in {
        sm.PAYMENT_PENDING, sm.PAYMENT_COMPLETED, sm.RATED, sm.CLOSED,
    }


def _bucket_by_day(jobs: List[Dict[str, Any]], days: int = 7) -> List[Dict[str, Any]]:
    today = datetime.utcnow().date()
    buckets: Dict[str, Dict[str, Any]] = {}
    for offset in range(days):
        day = today - timedelta(days=offset)
        buckets[day.strftime("%Y-%m-%d")] = {
            "date": day.strftime("%Y-%m-%d"),
            "amount": 0.0,
            "jobs": 0,
        }

    for job in jobs:
        created = job.get("createdAt")
        if not isinstance(created, datetime):
            continue
        key = created.strftime("%Y-%m-%d")
        if key in buckets:
            buckets[key]["amount"] += _job_amount(job)
            buckets[key]["jobs"] += 1

    ordered = [buckets[k] for k in sorted(buckets.keys(), reverse=True)]
    for bucket in ordered:
        bucket["amount"] = round(bucket["amount"], 2)
    return ordered


@bp.get("/mechanic/<mechanic_id>/earnings")
def mechanic_earnings(mechanic_id: str):
    rows = list(
        _coll("rescue_requests")
        .find({"mechanicId": _id_match(mechanic_id)})
        .sort("createdAt", -1)
        .limit(500)
    )
    completed = [r for r in rows if _is_completed(r)]
    amounts = [_job_amount(r) for r in completed]

    today_key = datetime.utcnow().strftime("%Y-%m-%d")
    today_total = sum(
        _job_amount(r) for r in completed
        if isinstance(r.get("createdAt"), datetime)
        and r["createdAt"].strftime("%Y-%m-%d") == today_key
    )

    buckets = _bucket_by_day(completed, 7)
    week_total = sum(b["amount"] for b in buckets)

    return _ok(
        mechanicId=mechanic_id,
        currency=Config.PRICING_CURRENCY,
        today=round(today_total, 2),
        week=round(week_total, 2),
        total=round(sum(amounts), 2),
        totalJobs=len(completed),
        assignedJobs=len(rows),
        averageJobValue=round(sum(amounts) / len(amounts), 2) if amounts else 0.0,
        daily=buckets,
        # Earnings are the amounts recorded on completed jobs. Nothing here is
        # an estimate, a projection, or a payout promise.
        basis="Sum of `amount` on completed rescue requests assigned to this mechanic.",
    )


@bp.get("/assistant/<assistant_id>/earnings")
def assistant_earnings(assistant_id: str):
    rows = list(
        _coll("rescue_requests")
        .find({"assistantId": _id_match(assistant_id)})
        .sort("createdAt", -1)
        .limit(500)
    )
    completed = [r for r in rows if _is_completed(r)]

    percent = Config.ASSISTANT_INCENTIVE_PERCENT
    earned = [round(_job_amount(r) * percent / 100.0, 2) for r in completed]

    today_key = datetime.utcnow().strftime("%Y-%m-%d")
    today_total = sum(
        incentive for job, incentive in zip(completed, earned)
        if isinstance(job.get("createdAt"), datetime)
        and job["createdAt"].strftime("%Y-%m-%d") == today_key
    )

    return _ok(
        assistantId=assistant_id,
        currency=Config.PRICING_CURRENCY,
        incentivePercent=percent,
        today=round(today_total, 2),
        week=round(sum(
            incentive for job, incentive in zip(completed, earned)
            if isinstance(job.get("createdAt"), datetime)
            and job["createdAt"] >= datetime.utcnow() - timedelta(days=7)
        ), 2),
        total=round(sum(earned), 2),
        totalJobs=len(completed),
        assignedJobs=len(rows),
        jobs=[
            {
                "requestId": str(job.get("_id", "")),
                "issue": job.get("issue", ""),
                "amount": _job_amount(job),
                "incentive": incentive,
                "createdAt": _iso(job.get("createdAt")),
            }
            for job, incentive in list(zip(completed, earned))[:50]
        ],
        basis=(
            f"{percent:g}% of the recorded job amount, configured as "
            "ROADRESQ_ASSISTANT_INCENTIVE_PERCENT. Not a payroll figure."
        ),
    )


# ══════════════════════════════════════════════════════════════════════════
# §48 — feedback / complaints
# ══════════════════════════════════════════════════════════════════════════
FEEDBACK_STATES = {"open", "in_review", "resolved", "closed"}


def _serialize_feedback(doc: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "id": str(doc.get("_id", "")),
        "userId": doc.get("userId", ""),
        "role": doc.get("role", ""),
        "category": doc.get("category", ""),
        "subject": doc.get("subject", ""),
        "message": doc.get("message", ""),
        "requestId": doc.get("requestId", ""),
        "status": doc.get("status", "open"),
        "createdAt": _iso(doc.get("createdAt")),
        "updatedAt": _iso(doc.get("updatedAt")),
        "updates": doc.get("updates", []),
    }


@bp.post("/feedback")
def create_feedback():
    data = _body()
    message = str(data.get("message", "")).strip()
    if len(message) < 5:
        return _err("Please describe the issue (at least 5 characters).", 400,
                    "VALIDATION")

    record = {
        "userId": str(data.get("userId", "")),
        "role": str(data.get("role", "")),
        "category": str(data.get("category", "general")),
        "subject": str(data.get("subject", "")).strip()[:120],
        "message": message[:2000],
        "requestId": str(data.get("requestId", "")),
        "status": "open",
        "createdAt": datetime.utcnow(),
        "updatedAt": datetime.utcnow(),
        "updates": [
            {
                "status": "open",
                "at": datetime.utcnow().isoformat() + "Z",
                "note": "Report received",
            }
        ],
    }
    inserted = _coll("feedback").insert_one(record)
    record["_id"] = inserted.inserted_id
    return _ok("Feedback submitted", 201, feedback=_serialize_feedback(record))


@bp.get("/feedback")
def list_feedback():
    query: Dict[str, Any] = {}
    if request.args.get("userId"):
        query["userId"] = request.args["userId"]
    rows = (
        _coll("feedback")
        .find(query)
        .sort("createdAt", -1)
        .limit(100)
    )
    return _ok(feedback=[_serialize_feedback(r) for r in rows])


@bp.put("/feedback/<feedback_id>")
def update_feedback(feedback_id: str):
    oid = _oid(feedback_id)
    if oid is None:
        return _err("Invalid feedback id", 400, "VALIDATION")

    data = _body()
    status = str(data.get("status", "")).strip().lower()
    if status not in FEEDBACK_STATES:
        return _err(
            "status must be one of: " + ", ".join(sorted(FEEDBACK_STATES)),
            400,
            "VALIDATION",
        )

    note = str(data.get("note", "")).strip()[:500]
    updates = {
        "$set": {"status": status, "updatedAt": datetime.utcnow()},
        "$push": {
            "updates": {
                "status": status,
                "at": datetime.utcnow().isoformat() + "Z",
                "note": note,
            }
        },
    }
    _coll("feedback").update_one({"_id": oid}, updates)
    doc = _coll("feedback").find_one({"_id": oid})
    if doc is None:
        return _err("Feedback not found", 404, "NOT_FOUND")
    return _ok("Feedback updated", feedback=_serialize_feedback(doc))


# ══════════════════════════════════════════════════════════════════════════
# §51 — admin console login + revenue
# ══════════════════════════════════════════════════════════════════════════
@bp.post("/admin/login")
def admin_login():
    data = _body()
    username = str(data.get("username", "")).strip()
    password = str(data.get("password", ""))

    if not Config.admin_login(username, password):
        return _err("Invalid admin credentials", 401, "INVALID_CREDENTIALS")

    return _ok(
        "Signed in",
        role="admin",
        username=username,
        devMode=not bool(Config.ADMIN_PASSWORD),
        note=(
            "Development admin password in use (ROADRESQ_ADMIN_PASSWORD unset)."
            if not Config.ADMIN_PASSWORD
            else ""
        ),
    )


@bp.get("/admin/revenue")
def admin_revenue():
    """Revenue metrics computed from recorded payments and completed jobs."""
    requests_coll = _coll("rescue_requests")
    payments_coll = _coll("payments")

    paid_requests = list(
        requests_coll.find({"paymentStatus": {"$in": ["paid", "Paid", "success"]}})
    )
    gross = round(sum(_job_amount(r) for r in paid_requests), 2)

    payment_total = 0.0
    try:
        for payment in payments_coll.find({}):
            amount = payment.get("amount")
            if payment.get("status") in {"captured", "paid", "success"}:
                payment_total += float(amount or 0)
    except Exception:
        payment_total = 0.0

    commission_percent = 10.0
    completed = sum(1 for r in paid_requests if _is_completed(r))

    return _ok(
        currency=Config.PRICING_CURRENCY,
        gross=round(max(gross, payment_total), 2),
        commissionPercent=commission_percent,
        commission=round(max(gross, payment_total) * commission_percent / 100.0, 2),
        paidJobs=len(paid_requests),
        completedJobs=completed,
        averageTicket=round(gross / len(paid_requests), 2) if paid_requests else 0.0,
        basis=(
            "Sum of `amount` on requests marked paymentStatus=paid, checked "
            "against captured entries in `payments`. Commission uses the "
            f"{commission_percent:g}% platform rate."
        ),
    )


# ══════════════════════════════════════════════════════════════════════════
# §29 / §33 / §37 — crew profiles (skills, experience, documents, mechanic)
# ══════════════════════════════════════════════════════════════════════════
PROFILE_TEXT_FIELDS = ("name", "phone", "email", "photoUrl", "experienceYears",
                       "vehicleType", "bio", "address")


@bp.get("/mechanic/<mechanic_id>/profile")
def mechanic_profile(mechanic_id: str):
    doc = _coll("mechanics").find_one({"_id": _oid(mechanic_id)}) \
        if _oid(mechanic_id) else None
    if doc is None:
        doc = _coll("mechanics").find_one({"mechanicId": mechanic_id})
    if doc is None:
        return _err("Mechanic not found", 404, "NOT_FOUND")

    rating_row = list(_coll("ratings").aggregate([
        {"$match": {"mechanicId": mechanic_id}},
        {"$group": {"_id": None, "avg": {"$avg": "$rating"}, "count": {"$sum": 1}}},
    ]))
    jobs = _coll("rescue_requests").count_documents(
        {"mechanicId": _id_match(mechanic_id)}
    )
    completed = _coll("rescue_requests").count_documents(
        {
            "mechanicId": _id_match(mechanic_id),
            "status": {"$in": [
                sm.SERVICE_COMPLETED, sm.PAYMENT_PENDING,
                sm.PAYMENT_COMPLETED, sm.RATED, sm.CLOSED,
            ]},
        }
    )

    return _ok(
        mechanic={
            "id": str(doc.get("_id", "")),
            "name": doc.get("name", ""),
            "phone": doc.get("phone", ""),
            "email": doc.get("email", ""),
            "photoUrl": doc.get("photoUrl", ""),
            "skills": doc.get("skills") or doc.get("services") or [],
            "experienceYears": doc.get("experienceYears", ""),
            "vehicleType": doc.get("vehicleType", ""),
            "bio": doc.get("bio", ""),
            "verified": bool(doc.get("verified")),
            "documents": doc.get("documents") or [],
            "jobCount": jobs,
            "completedJobs": completed,
            "rating": round(float(rating_row[0]["avg"]), 2) if rating_row else 0.0,
            "ratingCount": int(rating_row[0]["count"]) if rating_row else 0,
        }
    )


@bp.put("/mechanic/<mechanic_id>/profile")
def update_mechanic_profile_v3(mechanic_id: str):
    """Update the mechanic's own profile fields.

    Verification and rating are deliberately NOT writable here — only the admin
    console can verify, and the rating aggregate is computed from stored
    ratings. Anything else would let a client award itself trust.
    """
    oid = _oid(mechanic_id)
    if oid is None:
        return _err("Invalid mechanic id", 400, "VALIDATION")

    data = _body()
    updates: Dict[str, Any] = {}
    for field in PROFILE_TEXT_FIELDS:
        if field in data:
            updates[field] = str(data.get(field) or "").strip()[:400]

    if "skills" in data:
        raw = data.get("skills")
        if isinstance(raw, list):
            updates["skills"] = [str(s).strip()[:60] for s in raw if str(s).strip()]
        elif isinstance(raw, str):
            updates["skills"] = [
                part.strip()[:60] for part in raw.split(",") if part.strip()
            ]

    if "documents" in data and isinstance(data.get("documents"), list):
        updates["documents"] = data["documents"][:12]

    if not updates:
        return _err("Nothing to update", 400, "VALIDATION")

    updates["updatedAt"] = datetime.utcnow()
    result = _coll("mechanics").update_one({"_id": oid}, {"$set": updates})
    if result.matched_count == 0:
        return _err("Mechanic not found", 404, "NOT_FOUND")

    return _ok("Profile saved", updated=len(updates) - 1)


@bp.put("/user/<user_id>/profile")
def update_user_profile(user_id: str):
    """§7 — name, vehicle and photo for a customer account."""
    oid = _oid(user_id)
    if oid is None:
        return _err("Invalid user id", 400, "VALIDATION")

    data = _body()
    updates: Dict[str, Any] = {}
    for field in ("name", "phone", "email", "vehicle", "photoUrl"):
        if field in data:
            updates[field] = str(data.get(field) or "").strip()[:200]

    if not updates:
        return _err("Nothing to update", 400, "VALIDATION")

    updates["updatedAt"] = datetime.utcnow()
    result = _coll("users").update_one({"_id": oid}, {"$set": updates})
    if result.matched_count == 0:
        return _err("User not found", 404, "NOT_FOUND")

    doc = _coll("users").find_one({"_id": oid}) or {}
    return _ok(
        "Profile saved",
        user={
            "id": user_id,
            "name": doc.get("name", ""),
            "phone": doc.get("phone", ""),
            "email": doc.get("email", ""),
            "vehicle": doc.get("vehicle", ""),
            "photoUrl": doc.get("photoUrl", ""),
        },
    )


@bp.get("/assistant/<assistant_id>/profile")
def assistant_profile(assistant_id: str):
    """Assistant profile plus the mechanic they are currently working with."""
    oid = _oid(assistant_id)
    doc = _coll("assistants").find_one({"_id": oid}) if oid else None
    if doc is None:
        doc = _coll("assistants").find_one({"assistantId": assistant_id})
    if doc is None:
        return _err("Assistant not found", 404, "NOT_FOUND")

    # Most recent job this assistant was assigned to carries the mechanic.
    latest = _coll("rescue_requests").find_one(
        {"assistantId": _id_match(assistant_id)},
        sort=[("createdAt", -1)],
    )
    mechanic_name = ""
    mechanic_id = ""
    current_job = ""
    if latest:
        mechanic_id = str(latest.get("mechanicId", "") or "")
        mechanic_name = latest.get("mechanicName", "") or ""
        current_job = str(latest.get("_id", ""))
        if not mechanic_name and mechanic_id:
            mech = _coll("mechanics").find_one({"_id": _oid(mechanic_id)}) \
                if _oid(mechanic_id) else None
            if mech:
                mechanic_name = mech.get("name", "")

    return _ok(
        assistant={
            "id": str(doc.get("_id", "")),
            "name": doc.get("name", ""),
            "phone": doc.get("phone", ""),
            "email": doc.get("email", ""),
            "photoUrl": doc.get("photoUrl", ""),
            "online": bool(doc.get("online")),
            "assignedMechanicId": mechanic_id,
            "assignedMechanicName": mechanic_name,
            "currentJobId": current_job,
        }
    )


# ══════════════════════════════════════════════════════════════════════════
# §52 — escalation watchdog (server-side, 5-minute window)
# ══════════════════════════════════════════════════════════════════════════
_watchdog_started = False
_watchdog_lock = threading.Lock()


def _escalate_once(socketio_available: bool = True) -> int:
    """Escalate stale unaccepted requests. Returns how many were escalated."""
    now = datetime.utcnow()
    cutoff = now - timedelta(seconds=Config.ESCALATION_SECONDS)
    escalated = 0

    open_states = [sm.CREATED, sm.SEARCHING, "Pending", "pending", "Searching"]
    stale = _coll("rescue_requests").find(
        {
            "status": {"$in": open_states},
            "createdAt": {"$lte": cutoff},
            "mechanicId": {"$in": ["", None]},
            "$or": [
                {"escalated": {"$exists": False}},
                {"escalated": False},
            ],
        }
    ).limit(25)

    for doc in stale:
        count = int(doc.get("escalationCount") or 0) + 1
        _coll("rescue_requests").update_one(
            {"_id": doc["_id"]},
            {
                "$set": {
                    "escalated": True,
                    "escalationCount": count,
                    "escalatedAt": now,
                    "escalationReason": (
                        f"No mechanic accepted within "
                        f"{Config.ESCALATION_SECONDS // 60} minutes"
                    ),
                    "updatedAt": now,
                }
            },
        )
        payload = {
            "requestId": str(doc["_id"]),
            "escalationCount": count,
            "reason": "no_accept_in_window",
            "windowSeconds": Config.ESCALATION_SECONDS,
            "issue": doc.get("issue", ""),
            "location": doc.get("location", {}),
        }
        realtime.emit_event("escalate_request", payload)
        realtime.emit_event("request_escalated", payload)
        escalated += 1
        log.info("Escalated request %s (%s)", doc["_id"], payload["reason"])

    # Second pass: an assignment that was never accepted is released so the
    # dispatcher can offer it to someone else.
    released = 0
    stale_assignments = _coll("rescue_requests").find(
        {
            "status": {"$in": [sm.MECHANIC_ASSIGNED, "Assigned"]},
            "updatedAt": {"$lte": cutoff},
        }
    ).limit(25)

    for doc in stale_assignments:
        _coll("rescue_requests").update_one(
            {"_id": doc["_id"]},
            {
                "$set": {
                    "previousMechanicId": str(doc.get("mechanicId", "")),
                    "mechanicId": "",
                    "mechanicName": "",
                    "status": sm.storage_label(sm.SEARCHING) or sm.SEARCHING,
                    "escalated": True,
                    "escalationCount": int(doc.get("escalationCount") or 0) + 1,
                    "escalatedAt": now,
                    "escalationReason": "assignment_not_accepted",
                    "updatedAt": now,
                }
            },
        )
        payload = {
            "requestId": str(doc["_id"]),
            "reason": "assignment_not_accepted",
            "windowSeconds": Config.ESCALATION_SECONDS,
        }
        realtime.emit_event("escalate_request", payload)
        realtime.emit_event("request_assigned", payload)
        released += 1
        log.info("Released stale assignment on %s", doc["_id"])

    return escalated + released


def start_escalation_watchdog() -> None:
    """Start the background sweep once per process."""
    global _watchdog_started
    with _watchdog_lock:
        if _watchdog_started:
            return
        _watchdog_started = True

    def _loop() -> None:
        while True:
            try:
                _escalate_once()
            except Exception as exc:  # a broken sweep must not kill the thread
                log.warning("Escalation sweep failed: %s", exc)
            time.sleep(max(5, Config.ESCALATION_SCAN_SECONDS))

    thread = threading.Thread(
        target=_loop, name="roadresq-escalation", daemon=True
    )
    thread.start()
    log.info(
        "Escalation watchdog started (window=%ss, scan=%ss)",
        Config.ESCALATION_SECONDS,
        Config.ESCALATION_SCAN_SECONDS,
    )


# ══════════════════════════════════════════════════════════════════════════
# Registration
# ══════════════════════════════════════════════════════════════════════════
def init_app(app, socketio) -> None:
    """Register the blueprint and the chat socket handler."""
    app.register_blueprint(bp)
    try:
        socketio.on_event("chat_message", handle_chat_message)
    except Exception as exc:  # pragma: no cover
        log.warning("Could not register chat_message handler: %s", exc)
    _ensure_upload_dir()
    log.info("modules_v3 registered: uploads, chat, tokens, attendance, "
             "earnings, feedback, admin, escalation")
