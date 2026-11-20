"""
Rescue request lifecycle — explicit states and legal transitions.

The old backend accepted any string posted to `PUT /status`, so a request could
jump backwards or into states that never existed. This module is the single
authority on which transitions are legal.

Spec reference: §14 (rescue request status machine).

    CREATED → SEARCHING → MECHANIC_ASSIGNED → MECHANIC_ACCEPTED →
    MECHANIC_EN_ROUTE → ARRIVED → SERVICE_STARTED → SERVICE_COMPLETED →
    PAYMENT_PENDING → PAYMENT_COMPLETED → RATED → CLOSED

Failure states: CANCELLED, NO_MECHANIC_AVAILABLE, MECHANIC_DECLINED,
PAYMENT_FAILED, NETWORK_FAILURE.
"""

from __future__ import annotations

from typing import Dict, List, Optional, Set

# ── Canonical states ────────────────────────────────────────────────────────
CREATED = "CREATED"
SEARCHING = "SEARCHING"
MECHANIC_ASSIGNED = "MECHANIC_ASSIGNED"
MECHANIC_ACCEPTED = "MECHANIC_ACCEPTED"
MECHANIC_EN_ROUTE = "MECHANIC_EN_ROUTE"
ARRIVED = "ARRIVED"
SERVICE_STARTED = "SERVICE_STARTED"
SERVICE_COMPLETED = "SERVICE_COMPLETED"
PAYMENT_PENDING = "PAYMENT_PENDING"
PAYMENT_COMPLETED = "PAYMENT_COMPLETED"
RATED = "RATED"
CLOSED = "CLOSED"

# ── Failure / terminal-by-exception states ──────────────────────────────────
CANCELLED = "CANCELLED"
NO_MECHANIC_AVAILABLE = "NO_MECHANIC_AVAILABLE"
MECHANIC_DECLINED = "MECHANIC_DECLINED"
PAYMENT_FAILED = "PAYMENT_FAILED"
NETWORK_FAILURE = "NETWORK_FAILURE"

HAPPY_PATH: List[str] = [
    CREATED,
    SEARCHING,
    MECHANIC_ASSIGNED,
    MECHANIC_ACCEPTED,
    MECHANIC_EN_ROUTE,
    ARRIVED,
    SERVICE_STARTED,
    SERVICE_COMPLETED,
    PAYMENT_PENDING,
    PAYMENT_COMPLETED,
    RATED,
    CLOSED,
]

FAILURE_STATES: Set[str] = {
    CANCELLED,
    NO_MECHANIC_AVAILABLE,
    MECHANIC_DECLINED,
    PAYMENT_FAILED,
    NETWORK_FAILURE,
}

ALL_STATES: Set[str] = set(HAPPY_PATH) | FAILURE_STATES

# Terminal states: nothing may follow.
TERMINAL_STATES: Set[str] = {CLOSED, CANCELLED}

# ── Legal transitions ───────────────────────────────────────────────────────
TRANSITIONS: Dict[str, Set[str]] = {
    CREATED: {SEARCHING, CANCELLED},
    SEARCHING: {
        MECHANIC_ASSIGNED,
        NO_MECHANIC_AVAILABLE,
        CANCELLED,
        NETWORK_FAILURE,
    },
    MECHANIC_ASSIGNED: {
        MECHANIC_ACCEPTED,
        MECHANIC_DECLINED,
        NO_MECHANIC_AVAILABLE,  # decline with no other candidate
        CANCELLED,
    },
    MECHANIC_ACCEPTED: {MECHANIC_EN_ROUTE, CANCELLED, NETWORK_FAILURE},
    MECHANIC_EN_ROUTE: {ARRIVED, CANCELLED, NETWORK_FAILURE},
    ARRIVED: {SERVICE_STARTED, CANCELLED},
    SERVICE_STARTED: {SERVICE_COMPLETED, NETWORK_FAILURE},
    SERVICE_COMPLETED: {PAYMENT_PENDING},
    PAYMENT_PENDING: {PAYMENT_COMPLETED, PAYMENT_FAILED, CANCELLED},
    # A failed payment may be retried.
    PAYMENT_FAILED: {PAYMENT_PENDING, CANCELLED},
    PAYMENT_COMPLETED: {RATED, CLOSED},
    RATED: {CLOSED},
    CLOSED: set(),
    CANCELLED: set(),
    # A request that found nobody may be retried by the user.
    NO_MECHANIC_AVAILABLE: {SEARCHING, CANCELLED},
    MECHANIC_DECLINED: {SEARCHING, CANCELLED},
    NETWORK_FAILURE: {SEARCHING, CANCELLED},
}

# ── Legacy label compatibility ──────────────────────────────────────────────
# The Flutter client and the existing MongoDB documents use title-case labels
# ("Pending", "Assigned", "On The Way", ...). Mapping them onto canonical
# states keeps the existing frontend contract working while the backend gains
# a real state machine. §37 — do not break existing integration.
LEGACY_TO_CANONICAL: Dict[str, str] = {
    "pending": CREATED,
    "created": CREATED,
    "searching": SEARCHING,
    "assigned": MECHANIC_ASSIGNED,
    "accepted": MECHANIC_ACCEPTED,
    "on the way": MECHANIC_EN_ROUTE,
    "on_the_way": MECHANIC_EN_ROUTE,
    "enroute": MECHANIC_EN_ROUTE,
    "en_route": MECHANIC_EN_ROUTE,
    "reached": ARRIVED,
    "arrived": ARRIVED,
    "started": SERVICE_STARTED,
    "service_started": SERVICE_STARTED,
    "in progress": SERVICE_STARTED,
    "in_progress": SERVICE_STARTED,
    "completed": SERVICE_COMPLETED,
    "service_completed": SERVICE_COMPLETED,
    "payment pending": PAYMENT_PENDING,
    "payment_pending": PAYMENT_PENDING,
    "paid": PAYMENT_COMPLETED,
    "payment completed": PAYMENT_COMPLETED,
    "payment_completed": PAYMENT_COMPLETED,
    "payment failed": PAYMENT_FAILED,
    "payment_failed": PAYMENT_FAILED,
    "rated": RATED,
    "closed": CLOSED,
    "cancelled": CANCELLED,
    "canceled": CANCELLED,
    "no mechanic available": NO_MECHANIC_AVAILABLE,
    "no_mechanic_available": NO_MECHANIC_AVAILABLE,
    "mechanic declined": MECHANIC_DECLINED,
    "mechanic_declined": MECHANIC_DECLINED,
    "network failure": NETWORK_FAILURE,
    "network_failure": NETWORK_FAILURE,
}

# Canonical state → the title-case label the Flutter UI already renders.
CANONICAL_TO_LEGACY: Dict[str, str] = {
    CREATED: "Pending",
    SEARCHING: "Searching",
    MECHANIC_ASSIGNED: "Assigned",
    MECHANIC_ACCEPTED: "Accepted",
    MECHANIC_EN_ROUTE: "On The Way",
    ARRIVED: "Reached",
    SERVICE_STARTED: "In Progress",
    SERVICE_COMPLETED: "Completed",
    PAYMENT_PENDING: "Payment Pending",
    PAYMENT_COMPLETED: "Paid",
    RATED: "Rated",
    CLOSED: "Closed",
    CANCELLED: "Cancelled",
    NO_MECHANIC_AVAILABLE: "No Mechanic Available",
    MECHANIC_DECLINED: "Mechanic Declined",
    PAYMENT_FAILED: "Payment Failed",
    NETWORK_FAILURE: "Network Failure",
}


def normalize(status: Optional[str]) -> Optional[str]:
    """Map any accepted spelling onto a canonical state.

    Returns None when the value is unknown — callers must reject it rather than
    storing an unrecognised status.
    """
    if not status or not isinstance(status, str):
        return None

    raw = status.strip()
    if not raw:
        return None

    # Already canonical (case-insensitive, spaces/underscores equivalent).
    key = raw.lower().replace("-", " ").replace("_", " ").strip()
    key_underscore = key.replace(" ", "_")

    for candidate in ALL_STATES:
        if raw == candidate:
            return candidate
        if candidate.lower().replace("_", " ") == key:
            return candidate
        if candidate.lower() == key_underscore:
            return candidate

    return LEGACY_TO_CANONICAL.get(key) or LEGACY_TO_CANONICAL.get(key_underscore)


def can_transition(current: Optional[str], target: Optional[str]) -> bool:
    """True when `current → target` is a legal transition."""
    cur = normalize(current) or CREATED
    tgt = normalize(target)
    if tgt is None:
        return False
    return tgt in TRANSITIONS.get(cur, set())


def validate_transition(current: Optional[str], target: Optional[str]) -> dict:
    """Validate a transition and explain the outcome.

    Returns:
        {
          "ok": bool,
          "from": canonical current state,
          "to": canonical target state (None when unrecognised),
          "allowed": sorted list of legal next states,
          "reason": human-readable explanation when ok is False,
          "raw_to": the original value received,
        }
    """
    cur = normalize(current) or CREATED
    tgt = normalize(target)
    allowed = sorted(TRANSITIONS.get(cur, set()))

    if target is None or (isinstance(target, str) and not target.strip()):
        return {
            "ok": False,
            "from": cur,
            "to": None,
            "allowed": allowed,
            "reason": "status is required",
            "raw_to": target,
        }

    if tgt is None:
        return {
            "ok": False,
            "from": cur,
            "to": None,
            "allowed": allowed,
            "reason": (
                f"unknown status '{target}'. Valid states: "
                + ", ".join(sorted(ALL_STATES))
            ),
            "raw_to": target,
        }

    if cur == tgt:
        # Idempotent re-assertion is harmless (e.g. a retried request).
        return {
            "ok": True,
            "from": cur,
            "to": tgt,
            "allowed": allowed,
            "reason": "no change",
            "idempotent": True,
            "raw_to": target,
        }

    if tgt in TRANSITIONS.get(cur, set()):
        return {
            "ok": True,
            "from": cur,
            "to": tgt,
            "allowed": allowed,
            "reason": "legal transition",
            "raw_to": target,
        }

    return {
        "ok": False,
        "from": cur,
        "to": tgt,
        "allowed": allowed,
        "reason": (
            f"illegal transition {cur} → {tgt}. From {cur} the legal next "
            f"state(s) are: {', '.join(allowed) if allowed else 'none (terminal)'}"
        ),
        "raw_to": target,
    }


def storage_label(canonical_or_legacy: Optional[str]) -> str:
    """Return the label to persist in the `status` field.

    The live Flutter UI compares the raw `status` string against title-case
    labels ("Assigned", "On The Way", "Reached", ...) via its own
    `normalizeStatus()` helper. Persisting canonical codes would break that
    contract (§37), so documents keep the legacy label while `normalize()`
    continues to map it onto the explicit state machine.
    """
    canonical = normalize(canonical_or_legacy)
    if canonical is None:
        return str(canonical_or_legacy or "")
    return CANONICAL_TO_LEGACY.get(canonical, canonical)


def is_terminal(status: Optional[str]) -> bool:
    """True when no further transitions are possible."""
    return (normalize(status) or CREATED) in TERMINAL_STATES


def progress_percent(status: Optional[str]) -> int:
    """Position of a state along the happy path, as a percentage (UI helper)."""
    cur = normalize(status)
    if cur is None:
        return 0
    if cur in FAILURE_STATES:
        return 100
    try:
        idx = HAPPY_PATH.index(cur)
    except ValueError:
        return 0
    return int(round(idx / (len(HAPPY_PATH) - 1) * 100))
