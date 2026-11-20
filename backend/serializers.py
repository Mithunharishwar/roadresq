"""
Single source of truth for API document shapes.

The previous backend serialized the same collections in several places with
slightly different results, and two of those variants leaked the stored
password. Every route — legacy and new — now serializes through this module.

Compatibility rule (§37): every key the existing Flutter client already reads
is preserved exactly. New keys are added alongside; nothing is renamed.

Spec references: §13 (rescue request data model, no duplicated data),
§14 (status surfaced to the UI), §36 (collections), §39 (never emit secrets).
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Dict, Optional

import status_machine as sm
from auth import sanitize_document

# Keys the Flutter client already consumes must never disappear.
_LEGACY_REQUEST_DEFAULTS: Dict[str, Any] = {
    "name": "",
    "phone": "",
    "issue": "",
    "vehicle": "",
    "locationText": "",
    "status": "Pending",
    "mechanicId": "",
    "mechanicName": "",
    "assistantId": "",
    "assistantName": "",
    "assistantStatus": "pending",
    "amount": 0,
    "paymentStatus": "pending",
    "paymentId": "",
    "paymentMethod": "",
    "distanceKm": 0,
}


def _iso(value: Any) -> Optional[str]:
    """Render a datetime (or passthrough value) as an ISO-8601 string.

    Timestamps are stored as naive UTC (`datetime.utcnow()`), so they are
    serialized with a `Z`. Without it the client parsed "2026-11-17T04:18" as
    *local* time and the app displayed every time 5h30m early for IST users.
    """
    if value is None:
        return None
    if isinstance(value, datetime):
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc).isoformat().replace("+00:00", "Z")
        return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
    if isinstance(value, (int, float)):
        try:
            return (
                datetime.fromtimestamp(float(value), timezone.utc)
                .isoformat()
                .replace("+00:00", "Z")
            )
        except (OverflowError, OSError, ValueError):
            return str(value)
    return str(value)


def _id_str(value: Any) -> str:
    return str(value) if value else ""


def _id_or_none(value: Any) -> Optional[str]:
    """ObjectId-safe rendering that preserves None instead of collapsing to ''.

    `regionId` and `hubId` are stored as Mongo ObjectIds on some request
    documents. Passing them through raw made `jsonify` raise
    "Object of type ObjectId is not JSON serializable", which turned the whole
    endpoint into an empty-bodied HTTP 500 (the Flutter client could then only
    report "Invalid JSON response").
    """
    return None if value is None else str(value)


def serialize_request(doc: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    """Serialize a rescue request.

    Preserves every legacy key and adds the canonical lifecycle, pricing and
    allocation fields the new UI and the research logs rely on.
    """
    if not doc:
        return {}

    location = doc.get("location") or {}
    if not isinstance(location, dict):
        location = {}

    legacy_status = doc.get("status", "Pending")
    canonical = sm.normalize(legacy_status) or sm.CREATED

    payload: Dict[str, Any] = dict(_LEGACY_REQUEST_DEFAULTS)

    payload.update(
        {
            "name": doc.get("name", ""),
            "phone": doc.get("phone", ""),
            "issue": doc.get("issue", ""),
            "vehicle": doc.get("vehicle", ""),
            "locationText": doc.get("locationText", ""),
            "location": location,
            # Preserve legacy top-level lat/lng, but never invent (0, 0).
            "lat": location.get("lat", doc.get("lat")),
            "lng": location.get("lng", doc.get("lng")),
            "status": legacy_status,
            "mechanicId": _id_str(doc.get("mechanicId")),
            "mechanicName": doc.get("mechanicName", ""),
            "mechanicLocation": doc.get("mechanicLocation") or {},
            "assistantId": _id_str(doc.get("assistantId")),
            "assistantName": doc.get("assistantName", ""),
            "assistantLocation": doc.get("assistantLocation") or {},
            "assistantStatus": doc.get("assistantStatus", "pending"),
            # Garage handover. The garage's own job list filters on this field,
            # so the client needs to see it to tell "mine" from "unclaimed".
            "garageId": doc.get("garageId", "") or "",
            "garageLinkedAt": _iso(doc.get("garageLinkedAt")),
            "amount": doc.get("amount", 0),
            "paymentStatus": doc.get("paymentStatus", "pending"),
            "paymentId": doc.get("paymentId", ""),
            "paymentMethod": doc.get("paymentMethod", ""),
            "paidAt": _iso(doc.get("paidAt")),
            "createdAt": _iso(doc.get("createdAt")),
            "updatedAt": _iso(doc.get("updatedAt") or doc.get("createdAt")),
            "distanceKm": doc.get("distanceKm", 0),
            "hub": doc.get("hub"),
        }
    )

    # ── New, additive fields ───────────────────────────────────────────
    payload.update(
        {
            "_id": _id_str(doc.get("_id")),
            "id": _id_str(doc.get("_id")),
            # Canonical lifecycle state — the UI shows this. §14
            "statusCanonical": canonical,
            "statusLabel": sm.CANONICAL_TO_LEGACY.get(canonical, legacy_status),
            "progressPercent": sm.progress_percent(canonical),
            # Region / hub
            "regionId": _id_or_none(doc.get("regionId")),
            "hubId": _id_or_none(doc.get("hubId")),
            "regionName": doc.get("regionName"),
            # Assignment evidence
            "allocationLogId": _id_str(doc.get("allocationLogId")),
            "assignedMechanicId": _id_str(doc.get("mechanicId")),
            "etaMinutes": doc.get("etaMinutes"),
            "assignedDistanceKm": doc.get("assignedDistanceKm"),
            # Service detail
            "vehicleDetails": doc.get("vehicleDetails", ""),
            "issueDescription": doc.get("issueDescription", ""),
            "imageUrl": doc.get("imageUrl", ""),
            # Timestamps
            "acceptedAt": _iso(doc.get("acceptedAt")),
            "enRouteAt": _iso(doc.get("enRouteAt")),
            "arrivedAt": _iso(doc.get("arrivedAt")),
            "serviceStartedAt": _iso(doc.get("serviceStartedAt")),
            "serviceCompletedAt": _iso(doc.get("serviceCompletedAt")),
            "cancelledAt": _iso(doc.get("cancelledAt")),
            "updatedAt": _iso(doc.get("updatedAt")),
            # Lifecycle measurements used by the research export. §44
            "assignmentTimeMs": doc.get("assignmentTimeMs"),
            "acceptanceTimeMs": doc.get("acceptanceTimeMs"),
            "completionTimeMinutes": doc.get("completionTimeMinutes"),
            # Payment / rating
            "pricing": doc.get("pricing"),
            "orderId": doc.get("orderId", ""),
            "signatureVerified": doc.get("signatureVerified", False),
            "paymentSimulated": doc.get("paymentSimulated", False),
            "rating": doc.get("rating"),
            "review": doc.get("review", ""),
            "ratedAt": _iso(doc.get("ratedAt")),
            # Cancellation
            "cancellationReason": doc.get("cancellationReason", ""),
            "cancelledBy": doc.get("cancelledBy", ""),
            "failureReason": doc.get("failureReason", ""),
            "isDuplicateOf": _id_str(doc.get("isDuplicateOf")),
        }
    )

    return payload


def serialize_mechanic(
    doc: Optional[Dict[str, Any]], include_sensitive: bool = False
) -> Dict[str, Any]:
    """Serialize a mechanic.

    The stored password is NEVER included unless `include_sensitive` is
    explicitly passed by an internal caller. This closes the credential-leak
    defect in the previous `serialize_mechanic`. §39
    """
    if not doc:
        return {}

    payload = {
        "_id": _id_str(doc.get("_id")),
        "id": _id_str(doc.get("_id")),
        "name": doc.get("name", ""),
        "email": doc.get("email", ""),
        "phone": doc.get("phone", ""),
        "role": doc.get("role", "mechanic"),
        "online": bool(doc.get("online", False)),
        "available": bool(doc.get("available", True)),
        "isOnline": bool(doc.get("online", False)),
        "location": doc.get("location") or {},
        "locationUpdatedAt": _iso(doc.get("locationUpdatedAt")),
        # Verification — explicit, never inferred from the row existing. §8
        "verified": bool(doc.get("verified", False)),
        "verificationStatus": doc.get("verificationStatus", "unverified"),
        # Regional network. §16
        "regionId": doc.get("regionId"),
        "regionName": doc.get("regionName"),
        "hubId": doc.get("hubId"),
        "hubName": doc.get("hubName"),
        # Capabilities. §12, §32
        "services": doc.get("services") or doc.get("skills") or [],
        "vehicleTypes": doc.get("vehicleTypes") or [],
        # Standing
        "rating": float(doc.get("rating") or 0.0),
        "ratingCount": int(doc.get("ratingCount") or 0),
        "completedRescues": int(doc.get("completedRescues") or 0),
        "workload": int(doc.get("workload") or 0),
        "currentRequestId": _id_str(doc.get("currentRequestId")),
        "isBanned": bool(doc.get("isBanned", False)),
        "active": bool(doc.get("active", True)),
        "createdAt": _iso(doc.get("createdAt")),
        "updatedAt": _iso(doc.get("updatedAt")),
    }

    if include_sensitive:
        payload["passwordHashPresent"] = bool(doc.get("password"))

    return payload


def serialize_user(doc: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    """Serialize a user. The stored password is never emitted. §39"""
    if not doc:
        return {}

    return {
        "_id": _id_str(doc.get("_id")),
        "id": _id_str(doc.get("_id")),
        "name": doc.get("name", ""),
        "email": doc.get("email", ""),
        "phone": doc.get("phone", ""),
        "role": doc.get("role", "user"),
        "vehicles": doc.get("vehicles", []),
        "emergencyContacts": doc.get("emergencyContacts", []),
        "regionId": doc.get("regionId"),
        "isBanned": bool(doc.get("isBanned", False)),
        "createdAt": _iso(doc.get("createdAt")),
        "updatedAt": _iso(doc.get("updatedAt")),
    }


def serialize_hub(doc: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    if not doc:
        return {}
    return {
        "_id": _id_str(doc.get("_id")),
        "id": _id_str(doc.get("_id")),
        "name": doc.get("name", ""),
        "regionId": _id_str(doc.get("regionId")),
        "location": doc.get("location") or {},
        "services": doc.get("services") or [],
        "createdAt": _iso(doc.get("createdAt")),
    }


def serialize_region(doc: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    """Serialize a region. Index/bbox helper fields are kept for GeoJSON use."""
    if not doc:
        return {}

    payload = sanitize_document(dict(doc))
    payload["_id"] = _id_str(doc.get("_id"))
    payload["id"] = _id_str(doc.get("_id"))
    payload["createdAt"] = _iso(doc.get("createdAt"))
    payload["updatedAt"] = _iso(doc.get("updatedAt"))

    # Drop the index-only `center` pair from the client payload to avoid
    # confusing it with the region centroid.
    payload.pop("center", None)
    return payload


def serialize_allocation_log(doc: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    """Serialize an allocation record (§19/§46 evidence)."""
    if not doc:
        return {}

    payload = sanitize_document(dict(doc))
    payload["_id"] = _id_str(doc.get("_id"))
    payload["id"] = _id_str(doc.get("_id"))
    payload["createdAt"] = _iso(doc.get("createdAt"))
    payload["acceptedAt"] = _iso(doc.get("acceptedAt"))
    return payload


def serialize_payment(doc: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    if not doc:
        return {}
    payload = sanitize_document(dict(doc))
    payload["_id"] = _id_str(doc.get("_id"))
    payload["id"] = _id_str(doc.get("_id"))
    for key in ("createdAt", "paidAt", "updatedAt"):
        if key in payload:
            payload[key] = _iso(doc.get(key))
    return payload


def serialize_rating(doc: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    if not doc:
        return {}
    payload = sanitize_document(dict(doc))
    payload["_id"] = _id_str(doc.get("_id"))
    payload["id"] = _id_str(doc.get("_id"))
    payload["createdAt"] = _iso(doc.get("createdAt"))
    return payload


def serialize_token(doc: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    """Serialize a legacy digital vehicle token (password never included)."""
    if not doc:
        return {}
    payload = sanitize_document(dict(doc))
    payload["_id"] = _id_str(doc.get("_id"))
    payload["id"] = _id_str(doc.get("_id"))
    for key in ("createdAt", "updatedAt", "releasedAt"):
        if key in payload:
            payload[key] = _iso(doc.get(key))
    return payload


def serialize_garage(doc: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    """Garage identity. Never includes the password hash."""
    if not doc:
        return {}
    return {
        "id": _id_str(doc.get("_id")),
        "garageId": doc.get("garageId", ""),
        "name": doc.get("name", ""),
        "phone": doc.get("phone", ""),
        "email": doc.get("email", ""),
        "verified": bool(doc.get("verified", False)),
        "createdAt": _iso(doc.get("createdAt")),
    }


def error(message: str, status: int = 400, code: str = "") -> Dict[str, Any]:
    """Canonical error envelope. §38"""
    body = {"success": False, "message": message}
    if code:
        body["code"] = code
    return body


def ok(message: str = "", **extra) -> Dict[str, Any]:
    body = {"success": True}
    if message:
        body["message"] = message
    body.update(extra)
    return body
