"""
RoadResQ regional mechanic allocation engine.

This is the central research component (spec §15–§19). It is deliberately a
*pure* module: it takes lists and dicts, returns lists and dicts, and touches
no database and no Flask object. That makes every decision independently
testable and every experiment in §45 reproducible.

Pipeline implemented here:

    GPS point
      → resolve region
        → build candidate pool (same region / priority hubs)
          → ELIGIBILITY FILTER   (verified, online, available,
                                  service-compatible, location fresh,
                                  region-compatible)
            → RANK (transparent, configurable weights)
              → ASSIGNMENT DECISION + full explainability record
                → allocation log record (for §19 / §46 evidence)

Honesty constraints baked into the design:
  * Distances are great-circle distances, not road distances. They are
    reported as such and never described as "shortest route".
  * The weights are configuration. They are NOT claimed to be scientifically
    optimal, and nothing here reports an accuracy or improvement percentage.
  * An ineligible mechanic is never silently assigned.
  * Every rejection carries a machine-readable reason.
"""

from __future__ import annotations

import time
from typing import Any, Dict, Iterable, List, Optional, Tuple

from config import Config
from geo import (
    coerce_coordinate,
    distance_meters,
    estimate_eta_minutes,
    haversine_km,
    resolve_region,
)

# ── Rejection reasons (stable identifiers, safe to aggregate in experiments) ─
R_NOT_VERIFIED = "NOT_VERIFIED"
R_OFFLINE = "OFFLINE"
R_UNAVAILABLE = "UNAVAILABLE"
R_AT_CAPACITY = "AT_CAPACITY"
R_SERVICE_MISMATCH = "SERVICE_MISMATCH"
R_VEHICLE_MISMATCH = "VEHICLE_MISMATCH"
R_LOCATION_MISSING = "LOCATION_MISSING"
R_LOCATION_STALE = "LOCATION_STALE"
R_REGION_MISMATCH = "REGION_MISMATCH"
R_OUT_OF_RADIUS = "OUT_OF_RADIUS"
R_BANNED = "BANNED"

# ── Outcome statuses for an allocation attempt ─────────────────────────────
A_OK = "ASSIGNED"
A_NO_REGION = "NO_REGION_RESOLVED"
A_NO_ELIGIBLE = "NO_MECHANIC_AVAILABLE"


# ─────────────────────────────────────────────────────────────────────────────
# Field coercion helpers — mechanic documents arrive in mixed shapes because
# the project has both legacy demo rows and new region-aware rows.
# ─────────────────────────────────────────────────────────────────────────────
def _as_bool(value: Any, default: bool = False) -> bool:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value != 0
    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "yes", "on", "verified"}
    return default


def _as_list(value: Any) -> List[str]:
    if value is None:
        return []
    if isinstance(value, str):
        return [part.strip() for part in value.split(",") if part.strip()]
    if isinstance(value, (list, tuple, set)):
        return [str(v).strip() for v in value if str(v).strip()]
    return []


def _norm(value: Any) -> str:
    return str(value or "").strip().lower().replace("_", " ").replace("-", " ")


def mechanic_location(mechanic: Dict[str, Any]) -> Optional[Tuple[float, float]]:
    """Extract a valid (lat, lng) from a mechanic document, or None."""
    loc = mechanic.get("location") or mechanic.get("currentLocation") or {}
    if isinstance(loc, dict):
        return coerce_coordinate(loc.get("lat"), loc.get("lng"))
    return None


def _naive_utc_to_epoch(stamp) -> Optional[float]:
    """Convert a datetime to a POSIX timestamp, treating naive values as UTC.

    PyMongo returns naive `datetime` objects that are UTC. Calling
    `.timestamp()` on a naive datetime interprets it as *local* time, so on a
    UTC+05:30 host a just-published location appeared to be 5.5 hours old and
    every mechanic failed the staleness rule. Naive values are therefore
    converted with `calendar.timegm`, which reads them as UTC.
    """
    import calendar
    from datetime import datetime

    if isinstance(stamp, datetime):
        if stamp.tzinfo is None:
            return float(calendar.timegm(stamp.utctimetuple()))
        return stamp.timestamp()

    if isinstance(stamp, str):
        try:
            parsed = datetime.fromisoformat(stamp.replace("Z", "+00:00"))
        except ValueError:
            return None
        if parsed.tzinfo is None:
            return float(calendar.timegm(parsed.utctimetuple()))
        return parsed.timestamp()

    return None


def location_age_seconds(
    mechanic: Dict[str, Any], now: Optional[float] = None
) -> Optional[float]:
    """Seconds since the mechanic last published a location, or None if unknown."""
    now = now if now is not None else time.time()
    stamp = (
        mechanic.get("locationUpdatedAt")
        or mechanic.get("location_updated_at")
        or mechanic.get("updatedAt")
    )
    if stamp is None:
        # Legacy rows carry no timestamp; treat as unknown rather than stale so
        # existing demo data stays usable. The staleness rule then only applies
        # to mechanics that do publish timestamps.
        return None

    if isinstance(stamp, (int, float)) and not isinstance(stamp, bool):
        return max(0.0, now - float(stamp))

    epoch = _naive_utc_to_epoch(stamp)
    if epoch is None:
        return None
    return max(0.0, now - epoch)


def is_verified(mechanic: Dict[str, Any]) -> bool:
    """Verification is explicit — a test row is not a verified professional."""
    status = _norm(mechanic.get("verificationStatus") or mechanic.get("verification"))
    if status in {"verified", "approved", "active"}:
        return True
    if status in {"pending", "in progress", "rejected", "suspended", "unverified"}:
        return False
    return _as_bool(mechanic.get("verified"), default=False)


def is_online(mechanic: Dict[str, Any]) -> bool:
    return _as_bool(mechanic.get("online"), default=False)


def is_available(mechanic: Dict[str, Any]) -> bool:
    """Available = flagged available, not holding an active job, under capacity."""
    if mechanic.get("currentRequestId"):
        return False
    max_jobs = mechanic.get("maxConcurrentJobs")
    try:
        max_jobs = int(max_jobs) if max_jobs is not None else 1
    except (TypeError, ValueError):
        max_jobs = 1
    try:
        workload = int(mechanic.get("workload") or 0)
    except (TypeError, ValueError):
        workload = 0
    if workload >= max(1, max_jobs):
        return False
    # `available` defaults to True: a mechanic that is online and unoccupied is
    # available unless explicitly flagged otherwise.
    return _as_bool(mechanic.get("available"), default=True)


def services_of(mechanic: Dict[str, Any]) -> List[str]:
    return _as_list(mechanic.get("services") or mechanic.get("skills"))


def vehicle_types_of(mechanic: Dict[str, Any]) -> List[str]:
    return _as_list(mechanic.get("vehicleTypes") or mechanic.get("vehicle_types"))


def _service_supported(mechanic: Dict[str, Any], issue: str) -> bool:
    """True when the mechanic declares the requested service.

    `*` is accepted as an explicit wildcard so seeded demo mechanics can serve
    everything; an empty service list is NOT a wildcard — an unknown capability
    must not be treated as a capable one.
    """
    offered = [_norm(s) for s in services_of(mechanic)]
    if not offered:
        return False
    if "*" in offered or "all" in offered:
        return True
    target = _norm(issue)
    if not target:
        return False
    return any(target == s or target in s or s in target for s in offered)


def _vehicle_supported(mechanic: Dict[str, Any], vehicle: str) -> bool:
    supported = [_norm(v) for v in vehicle_types_of(mechanic)]
    if not supported:
        # No restriction declared — do not reject on vehicle alone.
        return True
    if "*" in supported or "all" in supported:
        return True
    target = _norm(vehicle)
    if not target:
        return True
    return any(target == v or target in v or v in target for v in supported)


# ─────────────────────────────────────────────────────────────────────────────
# ELIGIBILITY FILTER  (§17)
# ─────────────────────────────────────────────────────────────────────────────
def evaluate_eligibility(
    mechanic: Dict[str, Any],
    request_doc: Dict[str, Any],
    *,
    region_id: Optional[str],
    request_lat: float,
    request_lng: float,
    radius_km: float,
    now: Optional[float] = None,
    enforce_region: bool = True,
) -> Dict[str, Any]:
    """Evaluate one candidate and explain the verdict.

    Returns a candidate record carrying:
      eligible, reasons (why not), distanceMeters, distanceKm, etaMinutes,
      sameRegion, score factors, and the raw flags actually used.
    """
    now = now if now is not None else time.time()

    record: Dict[str, Any] = {
        "mechanicId": str(mechanic.get("_id", mechanic.get("id", ""))),
        "name": mechanic.get("name", ""),
        "phone": mechanic.get("phone", ""),
        "regionId": mechanic.get("regionId"),
        "hubId": mechanic.get("hubId"),
        "eligible": False,
        "reasons": [],
        "distanceMeters": None,
        "distanceKm": None,
        "etaMinutes": None,
        "sameRegion": False,
        "verified": is_verified(mechanic),
        "online": is_online(mechanic),
        "available": is_available(mechanic),
        "serviceCompatible": False,
        "vehicleCompatible": False,
        "locationAvailable": False,
        "locationAgeless": None,
        "workload": int(mechanic.get("workload") or 0),
        "rating": float(mechanic.get("rating") or 0.0),
        "ratingCount": int(mechanic.get("ratingCount") or 0),
    }

    reasons: List[str] = []

    # 1. Banned / suspended first — nothing else matters.
    if _as_bool(mechanic.get("isBanned"), default=False):
        reasons.append(R_BANNED)

    # 2. Verified
    if not record["verified"]:
        reasons.append(R_NOT_VERIFIED)

    # 3. Online
    if not record["online"]:
        reasons.append(R_OFFLINE)

    # 4. Available / not at capacity
    if not record["available"]:
        if mechanic.get("currentRequestId"):
            reasons.append(R_UNAVAILABLE)
        else:
            reasons.append(R_AT_CAPACITY)

    # 5. Service compatibility
    record["serviceCompatible"] = _service_supported(
        mechanic, request_doc.get("issue", "")
    )
    if not record["serviceCompatible"]:
        reasons.append(R_SERVICE_MISMATCH)

    # 6. Vehicle compatibility
    record["vehicleCompatible"] = _vehicle_supported(
        mechanic, request_doc.get("vehicle", "")
    )
    if not record["vehicleCompatible"]:
        reasons.append(R_VEHICLE_MISMATCH)

    # 7. Location available and fresh
    coords = mechanic_location(mechanic)
    if coords is None:
        reasons.append(R_LOCATION_MISSING)
    else:
        record["locationAvailable"] = True
        age = location_age_seconds(mechanic, now=now)
        record["locationAgeless"] = age
        if age is not None and age > Config.LOCATION_STALENESS_SECONDS:
            reasons.append(R_LOCATION_STALE)

    # 8. Region compatibility
    mech_region = mechanic.get("regionId")
    if enforce_region and region_id:
        record["sameRegion"] = str(mech_region or "") == str(region_id)
        if not record["sameRegion"]:
            reasons.append(R_REGION_MISMATCH)
    else:
        # No region taxonomy configured (or escalation mode) — treat every
        # candidate as region-compatible and record that honestly.
        record["sameRegion"] = True if not region_id else record["sameRegion"]

    # 9. Distance / radius. Only computable when a location exists.
    if coords is not None:
        d_m = distance_meters(request_lat, request_lng, coords[0], coords[1])
        record["distanceMeters"] = round(d_m, 1)
        record["distanceKm"] = round(d_m / 1000.0, 3)
        record["etaMinutes"] = estimate_eta_minutes(
            d_m / 1000.0, Config.ASSUMED_AVG_SPEED_KMH
        )
        if radius_km and (d_m / 1000.0) > radius_km:
            reasons.append(R_OUT_OF_RADIUS)

    record["reasons"] = reasons
    record["eligible"] = len(reasons) == 0
    return record


# ─────────────────────────────────────────────────────────────────────────────
# RANKING  (§18)
# ─────────────────────────────────────────────────────────────────────────────
def score_candidate(
    candidate: Dict[str, Any], radius_km: float
) -> Dict[str, Any]:
    """Compute the transparent composite score for one eligible candidate.

    score = w_proximity * proximity
          + w_service   * service_match
          + w_availability * availability
          + w_verification * verification
          + w_workload * workload_factor
          + w_rating   * rating_factor

    Every component is returned so a decision can be explained line by line.
    """
    weights = Config.allocation_weights()
    radius_km = radius_km if radius_km and radius_km > 0 else 1.0

    distance_km = candidate.get("distanceKm")
    if distance_km is None:
        proximity = 0.0
    else:
        # Linear decay to the search radius, clamped at zero. Straight-line.
        proximity = max(0.0, 1.0 - (float(distance_km) / radius_km))

    service_match = 1.0 if candidate.get("serviceCompatible") else 0.0
    availability = 1.0 if candidate.get("available") else 0.0
    verification = 1.0 if candidate.get("verified") else 0.0

    # Fewer concurrent jobs is better; cap the penalty at 3 jobs.
    workload = int(candidate.get("workload") or 0)
    workload_factor = max(0.0, 1.0 - (min(workload, 3) / 3.0))

    # Unrated mechanics get a neutral 0.5 so they are neither punished nor
    # promoted. Ratings are normalised on a 5-point scale.
    rating_count = int(candidate.get("ratingCount") or 0)
    rating_value = float(candidate.get("rating") or 0.0)
    if rating_count <= 0 or rating_value <= 0:
        rating_factor = 0.5
    else:
        rating_factor = max(0.0, min(1.0, rating_value / 5.0))

    components = {
        "proximity": round(proximity, 4),
        "serviceMatch": service_match,
        "availability": availability,
        "verification": verification,
        "workloadFactor": round(workload_factor, 4),
        "ratingFactor": round(rating_factor, 4),
    }

    total = (
        weights["proximity"] * proximity
        + weights["service"] * service_match
        + weights["availability"] * availability
        + weights["verification"] * verification
        + weights["workload"] * workload_factor
        + weights["rating"] * rating_factor
    )

    return {
        "score": round(total, 6),
        "components": components,
        "weights": weights,
    }


def rank_candidates(
    eligible: Iterable[Dict[str, Any]], radius_km: float
) -> List[Dict[str, Any]]:
    """Return eligible candidates ordered best-first, each with its score.

    Ties are broken deterministically by distance, then by mechanic id, so a
    repeated experiment on the same data yields identical rankings.
    """
    scored: List[Dict[str, Any]] = []
    for candidate in eligible:
        result = score_candidate(candidate, radius_km)
        enriched = dict(candidate)
        enriched.update(result)
        scored.append(enriched)

    scored.sort(
        key=lambda c: (
            -float(c.get("score") or 0.0),
            float(c.get("distanceMeters") if c.get("distanceMeters") is not None else 1e18),
            str(c.get("mechanicId") or ""),
        )
    )

    for index, candidate in enumerate(scored, start=1):
        candidate["rank"] = index

    return scored


# ─────────────────────────────────────────────────────────────────────────────
# FULL DECISION
# ─────────────────────────────────────────────────────────────────────────────
def allocate(
    mechanics: Iterable[Dict[str, Any]],
    request_doc: Dict[str, Any],
    regions: Optional[Iterable[Dict[str, Any]]] = None,
    *,
    request_lat: Optional[float] = None,
    request_lng: Optional[float] = None,
    radius_km: Optional[float] = None,
    escalation_radius_km: Optional[float] = None,
    exclude_mechanic_ids: Optional[Iterable[str]] = None,
    now: Optional[float] = None,
    started_at: Optional[float] = None,
) -> Dict[str, Any]:
    """Run the full allocation pipeline and return an explainable decision.

    Args:
        mechanics: every candidate mechanic document (unfiltered).
        request_doc: the rescue request being allocated.
        regions: region documents used to resolve the request's region.
        request_lat/lng: GPS point; falls back to `request_doc["location"]`.
        radius_km: in-region search radius.
        escalation_radius_km: radius used when the region yields nobody (§17).
        exclude_mechanic_ids: mechanics to skip (e.g. they already declined).
        now: injectable clock for deterministic tests.
        started_at: when the allocation attempt began, for latency logging.

    Returns a dict containing `status`, `selected`, `candidates` (every
    evaluated mechanic with its verdict), `explain`, and a ready-to-store
    `allocationLog` record matching §19 / §46.
    """
    now = now if now is not None else time.time()
    started_at = started_at if started_at is not None else now
    radius_km = float(radius_km or Config.DEFAULT_SEARCH_RADIUS_KM)
    escalation_radius_km = float(
        escalation_radius_km or Config.ESCALATION_RADIUS_KM
    )

    # ── Resolve the request's GPS point ─────────────────────────────────
    if request_lat is None or request_lng is None:
        loc = request_doc.get("location") or {}
        coords = coerce_coordinate(
            loc.get("lat") if isinstance(loc, dict) else None,
            loc.get("lng") if isinstance(loc, dict) else None,
        )
        if coords is None:
            return {
                "status": "INVALID_LOCATION",
                "selected": None,
                "candidates": [],
                "explain": {
                    "reason": "request has no valid GPS coordinates",
                    "message": "A valid latitude/longitude is required to allocate.",
                },
                "allocationLog": None,
            }
        request_lat, request_lng = coords

    # ── Resolve region (§16) ────────────────────────────────────────────
    region_list = list(regions or [])
    region = resolve_region(region_list, request_lat, request_lng)
    region_id = str(region.get("_id") or region.get("id")) if region else None
    hub_id = region.get("hubId") if region else None

    excluded = {str(x) for x in (exclude_mechanic_ids or [])}

    def _evaluate(pool: Iterable[Dict[str, Any]], enforce_region: bool, radius: float):
        out = []
        for mechanic in pool:
            mid = str(mechanic.get("_id", mechanic.get("id", "")))
            if mid in excluded:
                continue
            out.append(
                evaluate_eligibility(
                    mechanic,
                    request_doc,
                    region_id=region_id,
                    request_lat=request_lat,
                    request_lng=request_lng,
                    radius_km=radius,
                    now=now,
                    enforce_region=enforce_region,
                )
            )
        return out

    all_mechanics = list(mechanics)

    # ── Stage 1: region-scoped, in-radius ───────────────────────────────
    stage1 = _evaluate(all_mechanics, enforce_region=True, radius=radius_km)
    eligible1 = [c for c in stage1 if c["eligible"]]
    ranked = rank_candidates(eligible1, radius_km)
    escalation_used = False
    candidates_evaluated = stage1

    # ── Stage 2: escalation when the region yields nobody (§17) ─────────
    if not ranked:
        escalation_used = True
        stage2 = _evaluate(
            all_mechanics, enforce_region=False, radius=escalation_radius_km
        )
        eligible2 = [c for c in stage2 if c["eligible"]]
        ranked = rank_candidates(eligible2, escalation_radius_km)
        candidates_evaluated = stage2

    # Latency is measured against the engine's own clock (`now`) rather than
    # reading the wall clock again, so a decision is reproducible when a fixed
    # clock is injected. Clamped at zero so a caller-supplied clock that runs
    # ahead cannot produce a negative duration.
    assignment_ms = max(0, int(round((now - started_at) * 1000)))

    # ── Outcome ─────────────────────────────────────────────────────────
    if ranked:
        selected = ranked[0]
        status = A_OK
        failure_reason = None
    else:
        selected = None
        status = A_NO_ELIGIBLE
        # Lead with the most common rejection reason so the UI and the
        # experiment log can explain *why* nobody could take the job.
        tally: Dict[str, int] = {}
        for candidate in candidates_evaluated:
            for reason in candidate["reasons"]:
                tally[reason] = tally.get(reason, 0) + 1
        failure_reason = (
            max(tally.items(), key=lambda kv: kv[1])[0] if tally else "NO_CANDIDATES"
        )

    request_id = str(
        request_doc.get("_id") or request_doc.get("id") or request_doc.get("requestId") or ""
    )

    explain = {
        "requestId": request_id,
        "vehicleType": request_doc.get("vehicle", ""),
        "issueType": request_doc.get("issue", ""),
        "requestLocation": {"lat": request_lat, "lng": request_lng},
        "regionId": region_id,
        "regionName": (region or {}).get("name"),
        "hubId": hub_id,
        "radiusKm": radius_km,
        "escalationRadiusKm": escalation_radius_km,
        "escalationUsed": escalation_used,
        "regionResolved": region is not None,
        "candidateCount": len(candidates_evaluated),
        "eligibleCount": len(ranked),
        "excludedMechanicIds": sorted(excluded),
        "weights": Config.allocation_weights(),
        "distanceKind": "great-circle (straight line, not road distance)",
        "assumedSpeedKmh": Config.ASSUMED_AVG_SPEED_KMH,
        "selectedMechanicId": selected["mechanicId"] if selected else None,
        "selectedMechanicName": selected["name"] if selected else None,
        "selectedDistanceKm": selected["distanceKm"] if selected else None,
        "selectedEtaMinutes": selected["etaMinutes"] if selected else None,
        "assignmentTimeMs": assignment_ms,
        "failureReason": failure_reason,
        "status": status,
        "evaluatedAt": now,
    }

    allocation_log = {
        "requestId": request_id,
        "regionId": region_id,
        "regionName": (region or {}).get("name"),
        "hubId": hub_id,
        "vehicleType": request_doc.get("vehicle", ""),
        "issueType": request_doc.get("issue", ""),
        "requestLocation": {"lat": request_lat, "lng": request_lng},
        "radiusKm": radius_km,
        "escalationUsed": escalation_used,
        "candidateCount": len(candidates_evaluated),
        "eligibleCount": len(ranked),
        "excludedMechanicIds": sorted(excluded),
        # Full per-candidate evidence — the point of §18/§19.
        "candidates": candidates_evaluated,
        "rankedMechanics": [
            {
                "rank": c["rank"],
                "mechanicId": c["mechanicId"],
                "name": c.get("name", ""),
                "score": c.get("score"),
                "components": c.get("components"),
                "distanceMeters": c.get("distanceMeters"),
                "distanceKm": c.get("distanceKm"),
                "etaMinutes": c.get("etaMinutes"),
                "sameRegion": c.get("sameRegion"),
                "workload": c.get("workload"),
            }
            for c in ranked
        ],
        "selectedMechanicId": selected["mechanicId"] if selected else None,
        "selectedMechanicName": selected["name"] if selected else None,
        "selectedDistanceKm": selected["distanceKm"] if selected else None,
        "selectedEtaMinutes": selected["etaMinutes"] if selected else None,
        "assignmentTimeMs": assignment_ms,
        "acceptanceTimeMs": None,
        "status": status,
        "failureReason": failure_reason,
        "weights": Config.allocation_weights(),
        "assumedSpeedKmh": Config.ASSUMED_AVG_SPEED_KMH,
        "createdAt": now,
    }

    return {
        "status": status,
        "selected": selected,
        "candidates": candidates_evaluated,
        "ranked": ranked,
        "explain": explain,
        "allocationLog": allocation_log,
    }


def human_readable_decision(decision: Dict[str, Any]) -> str:
    """Render the decision as an operator-readable trace.

    Mirrors the §18 example so an allocation can be pasted straight into a
    report or the journal appendix.
    """
    explain = decision.get("explain") or {}
    lines: List[str] = []

    lines.append(f"Request {explain.get('requestId', '-')}")
    lines.append(
        f"  region            : {explain.get('regionName') or 'not resolved'}"
        f" ({explain.get('regionId') or '-'})"
    )
    lines.append(
        f"  search radius     : {explain.get('radiusKm')} km"
        + (
            f"  (escalated to {explain.get('escalationRadiusKm')} km)"
            if explain.get("escalationUsed")
            else ""
        )
    )
    lines.append(
        "  candidates / eligible : "
        f"{explain.get('candidateCount')} / {explain.get('eligibleCount')}"
    )
    lines.append("")

    ranked = decision.get("ranked") or []
    if not ranked:
        lines.append(
            f"  NO MECHANIC ASSIGNED — dominant reason: "
            f"{explain.get('failureReason')}"
        )
        for candidate in decision.get("candidates") or []:
            lines.append(
                f"    - {candidate.get('mechanicId')}: "
                f"{', '.join(candidate.get('reasons') or [])}"
            )
        return "\n".join(lines)

    for candidate in ranked:
        lines.append(f"  Candidate (rank {candidate['rank']}): {candidate.get('name')}")
        distance = candidate.get("distanceKm")
        lines.append(
            "    Distance          = "
            + (f"{distance} km" if distance is not None else "unavailable")
        )
        lines.append(f"    Online            = {candidate.get('online')}")
        lines.append(f"    Available         = {candidate.get('available')}")
        lines.append(f"    Service compatible= {candidate.get('serviceCompatible')}")
        lines.append(f"    Verified          = {candidate.get('verified')}")
        lines.append(f"    Current workload  = {candidate.get('workload')}")
        lines.append(
            f"    Region            = {'same hub' if candidate.get('sameRegion') else 'different'}"
        )
        lines.append(f"    ETA (estimated)   = {candidate.get('etaMinutes')} min")
        lines.append(f"    Score             = {candidate.get('score')}")
        lines.append(
            "    Score breakdown   = "
            + ", ".join(
                f"{k}={v}"
                for k, v in (candidate.get("components") or {}).items()
            )
        )
        lines.append("")

    selected = decision.get("selected") or {}
    lines.append(f"  Final ranking     = {selected.get('rank')}")
    return "\n".join(lines)
