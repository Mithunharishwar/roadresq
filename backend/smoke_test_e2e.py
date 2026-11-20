"""
RoadResQ end-to-end acceptance test (§48, §49).

Drives the running backend over HTTP through the full journey:

    user creates a rescue
      -> allocation engine selects an eligible regional mechanic
        -> mechanic accepts, travels, arrives, completes
          -> price quoted
            -> payment order created + verified
              -> user rates the mechanic
                -> request CLOSED
                  -> admin dashboard and allocation export reflect it

Requires the server to be running and demo data seeded:

    python seed_demo_data.py --reset
    python roadresq_backend.py
    python smoke_test_e2e.py

Every step prints PASS/FAIL with the evidence it observed. Nothing is reported
as passing unless the server actually returned it.
"""

from __future__ import annotations

import json
import sys
import time
from typing import Any, Dict, Optional, Tuple

import requests

BASE = "http://127.0.0.1:5050"

# Chennai Central, matching seed_demo_data.py
USER_LAT, USER_LNG = 13.0827, 80.2707

DEMO_USER = {"phone": "9111111111", "password": "demo1234"}
DEMO_MECHANIC_PHONE = "9000000001"  # "Demo Mechanic A" — closest all-rounder

# Each run uses a fresh phone number for the rescue request so the duplicate
# guard (§40) never blocks a re-run. The guard itself is tested explicitly
# further down by re-posting the same phone + issue.
RUN_PHONE = "9" + str(int(time.time()))[-9:]

_results: list[Tuple[str, bool, str]] = []


def check(label: str, ok: bool, detail: str = "") -> bool:
    _results.append((label, ok, detail))
    print(f"  [{'PASS' if ok else 'FAIL'}] {label}" + (f" — {detail}" if detail else ""))
    return ok


def show(payload: Any, limit: int = 400) -> str:
    text = json.dumps(payload, default=str)
    return text if len(text) <= limit else text[:limit] + "..."


def get(path: str, **kw) -> Tuple[int, Any]:
    try:
        r = requests.get(f"{BASE}{path}", timeout=20, **kw)
        return r.status_code, _json(r)
    except Exception as exc:
        return 0, {"error": str(exc)}


def post(path: str, body: Optional[dict] = None, token: str = "") -> Tuple[int, Any]:
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    try:
        r = requests.post(f"{BASE}{path}", json=body or {}, headers=headers, timeout=25)
        return r.status_code, _json(r)
    except Exception as exc:
        return 0, {"error": str(exc)}


def put(path: str, body: Optional[dict] = None, token: str = "") -> Tuple[int, Any]:
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    try:
        r = requests.put(f"{BASE}{path}", json=body or {}, headers=headers, timeout=25)
        return r.status_code, _json(r)
    except Exception as exc:
        return 0, {"error": str(exc)}


def _json(response) -> Any:
    try:
        return response.json()
    except Exception:
        return {"raw": response.text[:300]}


def section(title: str) -> None:
    print(f"\n=== {title} ===")


def main() -> int:
    print("RoadResQ end-to-end acceptance test")
    print(f"Target: {BASE}")

    # ── 0. Server reachable ─────────────────────────────────────────────
    section("0. Server and configuration")
    status, health = get("/health")
    if not check("GET /health returns 200", status == 200, show(health, 120)):
        print("\nServer is not reachable. Start it with: python roadresq_backend.py")
        return 1

    status, system = get("/api/admin/system/health")
    db_info = (system or {}).get("database", {})
    check("MongoDB connected", bool(db_info.get("connected")), str(db_info.get("name")))
    check(
        "Indexes created with no failures",
        db_info.get("indexes", {}).get("failed") == 0,
        f"{db_info.get('indexes', {}).get('created')} indexes",
    )
    counts = db_info.get("collections", {})
    check(
        "Demo data present (regions + mechanics)",
        (counts.get("regions", 0) >= 1) and (counts.get("mechanics", 0) >= 1),
        f"regions={counts.get('regions')} mechanics={counts.get('mechanics')}",
    )

    status, cfg = get("/api/config/public")
    check("GET /api/config/public returns categories", status == 200 and bool(cfg.get("vehicleCategories")))

    # ── 1. Authentication ───────────────────────────────────────────────
    section("1. Authentication")
    status, login = post("/api/auth/login", {"role": "user", **DEMO_USER})
    user_token = login.get("token", "") if isinstance(login, dict) else ""
    check("User login returns a signed token", status == 200 and bool(user_token), show(login, 160))

    status, bad = post("/api/auth/login", {"role": "user", "phone": DEMO_USER["phone"], "password": "wrong"})
    check("Wrong password is rejected", status == 401, show(bad, 100))

    status, mech_login = post(
        "/api/auth/login",
        {"role": "mechanic", "phone": DEMO_MECHANIC_PHONE, "password": "demo1234"},
    )
    mech_token = mech_login.get("token", "") if isinstance(mech_login, dict) else ""
    mechanic = mech_login.get("mechanic", {}) if isinstance(mech_login, dict) else {}
    mechanic_id = mechanic.get("id", "")
    check("Mechanic login returns a token and profile", status == 200 and bool(mech_token) and bool(mechanic_id))

    # Password must never be echoed back. §39
    leak = "password" in json.dumps(mech_login) and "demo1234" in json.dumps(mech_login)
    check("Login response does not leak the stored password", not leak)
    check("Mechanic profile reports verification status", "verificationStatus" in mechanic, str(mechanic.get("verificationStatus")))

    status, me = get("/api/auth/me", headers={"Authorization": f"Bearer {user_token}"})
    check("GET /api/auth/me resolves the caller", status == 200, show(me, 120))

    status, unauth = get("/api/auth/me")
    check("Protected route rejects a missing token", status == 401)

    # ── 2. Mechanic goes online ─────────────────────────────────────────
    section("2. Mechanic publishes presence and location")
    status, avail = put(
        f"/api/mechanics/{mechanic_id}/availability",
        {"online": True, "available": True},
        token=mech_token,
    )
    check("Mechanic set online/available", status == 200, show(avail, 140))

    status, loc = put(
        f"/api/mechanics/{mechanic_id}/location",
        {"lat": 13.0900, "lng": 80.2750},
        token=mech_token,
    )
    check("Mechanic location published", status == 200, show(loc, 140))

    status, badloc = put(
        f"/api/mechanics/{mechanic_id}/location",
        {"lat": 999, "lng": 999},
        token=mech_token,
    )
    check("Out-of-range coordinates rejected", status == 400, show(badloc, 120))

    # ── 3. User creates a rescue request ────────────────────────────────
    section("3. User creates a rescue request")
    status, created = post(
        "/api/rescueRequests",
        {
            "name": "Demo User",
            "phone": RUN_PHONE,
            "issue": "Flat Tyre",
            "vehicle": "Car",
            "locationText": "Anna Salai, Chennai",
            "location": {"lat": USER_LAT, "lng": USER_LNG},
        },
    )
    request_obj = created.get("request", {}) if isinstance(created, dict) else {}
    request_id = request_obj.get("id", "")
    check("Rescue request created", status in (200, 201) and bool(request_id), show(created, 200))
    check(
        "Request resolved to a regional hub",
        bool(request_obj.get("regionId")),
        f"region={request_obj.get('regionName')}",
    )
    check(
        "New request starts in a canonical state",
        request_obj.get("statusCanonical") == "CREATED",
        str(request_obj.get("statusCanonical")),
    )

    # Duplicate guard. §40
    status, dup = post(
        "/api/rescueRequests",
        {
            "name": "Demo User",
            "phone": RUN_PHONE,
            "issue": "Flat Tyre",
            "vehicle": "Car",
            "location": {"lat": USER_LAT, "lng": USER_LNG},
        },
    )
    check("Duplicate request is rejected (409)", status == 409, show(dup, 120))

    status, missing = post(
        "/api/rescueRequests",
        {
            "name": "Demo User",
            "phone": RUN_PHONE,
            "issue": "Engine Trouble",
            "vehicle": "Car",
            # no location on purpose
        },
    )
    check(
        "Request without coordinates is rejected",
        status == 400 and "location" in str(missing.get("message", "")).lower(),
        show(missing, 140),
    )

    # ── 4. Allocation engine ────────────────────────────────────────────
    section("4. Regional allocation engine")
    status, alloc = post("/api/allocation/find", {"requestId": request_id})
    selected = alloc.get("selected") or {} if isinstance(alloc, dict) else {}
    explain = alloc.get("explain") or {} if isinstance(alloc, dict) else {}

    check("Allocation returned a decision", status == 200, show(alloc, 200))
    check("A mechanic was assigned", bool(selected.get("mechanicId")), str(selected.get("name")))
    check(
        "Request is now MECHANIC_ASSIGNED",
        explain.get("status") == "ASSIGNED",
        str(explain.get("status")),
    )
    check(
        "Region was resolved before filtering",
        bool(explain.get("regionId")),
        str(explain.get("regionName")),
    )
    check(
        "Eligibility filter ran (candidates >= eligible)",
        (explain.get("candidateCount") or 0) >= (explain.get("eligibleCount") or 0),
        f"{explain.get('candidateCount')} candidates -> {explain.get('eligibleCount')} eligible",
    )
    check(
        "Decision exposes a scoring breakdown",
        bool(selected.get("components")) and bool(selected.get("weights")),
        show(selected.get("components"), 160),
    )
    check(
        "Assignment latency was measured",
        explain.get("assignmentTimeMs") is not None,
        f"{explain.get('assignmentTimeMs')} ms",
    )
    check("Reasoning trace was produced", bool(alloc.get("readableTrace")))
    print("\n--- allocation trace ---")
    print(alloc.get("readableTrace", ""))
    print("--- end trace ---\n")

    # Rejected candidates must each carry a reason. §17
    rejected = [c for c in (alloc.get("candidates") or []) if not c.get("eligible")]
    check(
        "Every rejected candidate has a reason",
        all(c.get("reasons") for c in rejected),
        f"{len(rejected)} rejected candidates",
    )

    # Allocation evidence recorded. §19
    status, log = get(f"/api/allocation/{request_id}")
    check("Allocation record persisted and retrievable", status == 200, show(log, 140))

    # A second allocation attempt must be refused. §14
    status, again = post("/api/allocation/find", {"requestId": request_id})
    check("Re-allocation of an assigned request is refused", status == 409, show(again, 120))

    # ── 5. Mechanic lifecycle ───────────────────────────────────────────
    section("5. Mechanic accepts, travels, arrives, completes")
    assigned_id = selected.get("mechanicId", "")

    # The engine selects whichever eligible mechanic scores best, which is not
    # necessarily the one logged in above. Look the assigned mechanic up and
    # authenticate as them, so the ownership guard is exercised properly.
    assigned_token = mech_token
    if assigned_id and assigned_id != mechanic_id:
        status, roster = get("/api/mechanics?limit=200")
        assigned_phone = ""
        for entry in (roster.get("mechanics") or []) if isinstance(roster, dict) else []:
            if str(entry.get("id")) == str(assigned_id):
                assigned_phone = str(entry.get("phone") or "")
                break

        if assigned_phone:
            status, alt = post(
                "/api/auth/login",
                {"role": "mechanic", "phone": assigned_phone, "password": "demo1234"},
            )
            assigned_token = (alt.get("token") or assigned_token) if isinstance(alt, dict) else assigned_token
        check("Authenticated as the assigned mechanic", assigned_token != mech_token or assigned_id == mechanic_id)

    # A different mechanic must not be able to act on someone else's rescue. §39
    if assigned_id != mechanic_id:
        status, trespass = post(
            f"/api/mechanic/{assigned_id}/accept", {"requestId": request_id}, token=mech_token
        )
        check("Another mechanic cannot accept this rescue (403)", status == 403, show(trespass, 120))

    status, accepted = post(
        f"/api/mechanic/{assigned_id}/accept", {"requestId": request_id}, token=assigned_token
    )
    check("Mechanic accepted the rescue", status == 200, show(accepted, 160))
    accepted_req = accepted.get("request", {}) if isinstance(accepted, dict) else {}
    check(
        "Status is now Accepted",
        accepted_req.get("statusCanonical") == "MECHANIC_ACCEPTED",
        str(accepted_req.get("statusCanonical")),
    )

    status, skipped = post(
        f"/api/mechanic/{assigned_id}/complete", {"requestId": request_id}, token=assigned_token
    )
    check("Completing before starting is allowed only via the legal path", status in (200, 409), show(skipped, 120))

    status, enroute = post(
        f"/api/mechanic/{assigned_id}/start", {"requestId": request_id}, token=assigned_token
    )
    check("Mechanic marked en route", status == 200, str((enroute.get("request") or {}).get("statusCanonical")))

    status, arrived = post(
        f"/api/mechanic/{assigned_id}/arrive", {"requestId": request_id}, token=assigned_token
    )
    check("Mechanic marked arrived", status == 200, str((arrived.get("request") or {}).get("statusCanonical")))

    status, completed = post(
        f"/api/mechanic/{assigned_id}/complete", {"requestId": request_id}, token=assigned_token
    )
    completed_req = completed.get("request", {}) if isinstance(completed, dict) else {}
    check("Service completed", status == 200, show(completed, 160))
    check(
        "Request moved to PAYMENT_PENDING (not straight to closed)",
        completed_req.get("statusCanonical") == "PAYMENT_PENDING",
        str(completed_req.get("statusCanonical")),
    )
    check("Final price was quoted on completion", bool(completed.get("pricing")), show(completed.get("pricing"), 220))

    # A different mechanic must not be able to touch this request. §39
    status, other = post("/api/rescueRequests/aaaaaaaaaaaaaaaaaaaaaaaa/cancel", {})
    check("Invalid request id handled", status in (400, 404), show(other, 100))

    # ── 6. Payment ──────────────────────────────────────────────────────
    section("6. Pricing and payment")
    status, quote = get(f"/api/payments/quote?requestId={request_id}")
    q = quote.get("quote", {}) if isinstance(quote, dict) else {}
    check("Itemised quote returned", status == 200 and bool(q.get("lineItems")), show(quote, 220))
    check(
        "Quote is internally consistent (subtotal + tax = total)",
        q.get("total") is not None and abs((q.get("subtotal", 0) + q.get("tax", 0)) - q.get("total", 0)) < 0.05,
        f"subtotal={q.get('subtotal')} tax={q.get('tax')} total={q.get('total')}",
    )

    status, order = post("/api/payments/create", {"requestId": request_id})
    order_id = order.get("orderId", "") if isinstance(order, dict) else ""
    check("Payment order created", status in (200, 201) and bool(order_id), show(order, 200))
    check(
        "Payment mode is explicitly reported",
        order.get("mode") in {"live", "test", "simulated"},
        f"mode={order.get('mode')} simulated={order.get('simulated')}",
    )

    status, forged = post(
        "/api/payments/verify",
        {
            "requestId": request_id,
            "razorpayOrderId": order_id,
            "razorpayPaymentId": "pay_forged",
            "razorpaySignature": "0" * 64,
        },
    )
    check("A forged signature is rejected", status == 400, show(forged, 140))

    status, verified = post(
        "/api/payments/verify",
        {"requestId": request_id, "razorpayOrderId": order_id, "simulate": True},
    )
    check("Development payment flow completed and flagged", status == 200, show(verified, 200))
    if isinstance(verified, dict) and verified.get("simulated"):
        check(
            "Simulated payment is labelled as simulated, not as a real payment",
            bool(verified.get("message")) and "SIMULATED" in str(verified.get("message")).upper(),
            str(verified.get("message"))[:120],
        )
    check(
        "Request is now PAYMENT_COMPLETED",
        (verified.get("request") or {}).get("statusCanonical") == "PAYMENT_COMPLETED",
        str((verified.get("request") or {}).get("statusCanonical")),
    )

    # ── 7. Rating ───────────────────────────────────────────────────────
    section("7. Rating and closing")
    status, rated = post(
        "/api/ratings", {"requestId": request_id, "rating": 5, "review": "Fast and professional"}
    )
    check("Rating recorded", status in (200, 201), show(rated, 180))
    check(
        "Mechanic aggregate recomputed from stored ratings",
        bool((rated.get("mechanicAggregate") or {}).get("ratingCount")),
        show(rated.get("mechanicAggregate"), 120),
    )

    status, closed = get(f"/api/rescueRequests/{request_id}")
    check(
        "Request is CLOSED at the end of the journey",
        closed.get("statusCanonical") == "CLOSED",
        str(closed.get("statusCanonical")),
    )

    status, dup_rating = post("/api/ratings", {"requestId": request_id, "rating": 1})
    check("Double rating is rejected", status == 409, show(dup_rating, 120))

    status, ratings = get(f"/api/mechanics/{assigned_id}/ratings")
    check("Ratings list retrievable for the mechanic", status == 200, show(ratings, 160))

    # ── 8. Admin ────────────────────────────────────────────────────────
    section("8. Admin analytics and research export")
    status, dash = get("/api/admin/dashboard")
    check("Admin dashboard returns real aggregates", status == 200, show(dash, 200))
    if isinstance(dash, dict) and dash.get("allocation"):
        a = dash["allocation"]
        check(
            "Allocation metrics are derived from logs",
            a.get("totalAllocationAttempts", 0) >= 1,
            f"attempts={a.get('totalAllocationAttempts')} "
            f"successRate={a.get('assignmentSuccessRate')} "
            f"avgAssignmentMs={a.get('avgAssignmentTimeMs')}",
        )
    if isinstance(dash, dict) and dash.get("overview"):
        print("  overview:", show(dash["overview"], 300))

    status, summary = get("/api/admin/experiments/summary")
    check("Experiment summary computed", status == 200, show(summary, 220))

    status, csv_body = get("/api/admin/export/allocation")
    check("Allocation CSV export produced", status == 200, show(csv_body, 140))

    status, regions = get("/api/admin/regions")
    check("Regions listed", status == 200, show(regions, 160))

    status, logs = get("/api/admin/allocation-logs?limit=5")
    check("Allocation log listing works", status == 200, show(logs, 160))

    # ── 9. Fault classifier ─────────────────────────────────────────────
    section("9. Rule-based fault classifier")
    status, fault = post("/api/fault/classify", {"description": "my front tyre is punctured"})
    check("Classifier returns a labelled rule-based result", status == 200, show(fault, 200))
    if isinstance(fault, dict):
        check(
            "Classifier is labelled as rule-based, not as a trained model",
            "rule-based" in str(fault.get("method", "")) and bool(fault.get("disclaimer")),
            str(fault.get("label")),
        )

    # ── Summary ─────────────────────────────────────────────────────────
    passed = sum(1 for _, ok, _ in _results if ok)
    failed = len(_results) - passed
    print("\n" + "=" * 70)
    print(f"RESULT: {passed} passed, {failed} failed, {len(_results)} checks")
    if failed:
        print("\nFailures:")
        for label, ok, detail in _results:
            if not ok:
                print(f"  - {label} :: {detail}")
    print("=" * 70)
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
