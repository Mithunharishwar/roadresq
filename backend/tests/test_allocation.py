"""
Tests for the RoadResQ allocation engine and the modules it depends on.

These tests are pure: no MongoDB and no HTTP. Each experiment scenario from the
master prompt (§45) is reproduced against the engine with fixed data, so the
results are reproducible and can be reported honestly.

Run:  python -m pytest tests -v
"""

from __future__ import annotations

import time

import pytest

import allocation
import auth
import geo
import pricing
import status_machine as sm

# ─────────────────────────────────────────────────────────────────────────────
# Fixtures / helpers
# ─────────────────────────────────────────────────────────────────────────────
NOW = 1_800_000_000.0  # fixed clock so results never depend on wall time

CHENNAI = {"lat": 13.0827, "lng": 80.2707}
COIMBATORE = {"lat": 11.0168, "lng": 76.9558}

CHENNAI_REGION = {
    "_id": "region-chennai",
    "name": "Chennai Central",
    "latMin": 12.85,
    "latMax": 13.30,
    "lngMin": 80.05,
    "lngMax": 80.45,
    "radiusKm": 25.0,
}

COIMBATORE_REGION = {
    "_id": "region-coimbatore",
    "name": "Coimbatore North",
    "latMin": 10.90,
    "latMax": 11.15,
    "lngMin": 76.85,
    "lngMax": 77.10,
    "radiusKm": 20.0,
}


def mechanic(
    mechanic_id,
    *,
    lat=13.09,
    lng=80.275,
    region="region-chennai",
    verified=True,
    online=True,
    available=True,
    services=("*",),
    vehicle_types=("*",),
    workload=0,
    rating=4.5,
    rating_count=10,
    location_age_seconds=0,
    location=None,
    current_request="",
):
    """Build a mechanic document in the shape the engine consumes."""
    if location is None and lat is not None and lng is not None:
        location = {"lat": lat, "lng": lng}

    doc = {
        "_id": mechanic_id,
        "name": f"Mechanic {mechanic_id}",
        "phone": "9000000000",
        "regionId": region,
        "hubId": f"hub-{region}",
        "verified": verified,
        "verificationStatus": "verified" if verified else "pending",
        "online": online,
        "available": available,
        "services": list(services),
        "vehicleTypes": list(vehicle_types),
        "workload": workload,
        "rating": rating,
        "ratingCount": rating_count,
        "currentRequestId": current_request,
    }
    if location:
        doc["location"] = location
        if location_age_seconds is not None:
            doc["locationUpdatedAt"] = NOW - location_age_seconds
    else:
        doc["location"] = {}
    return doc


def request_doc(issue="Flat Tyre", vehicle="Car", lat=CHENNAI["lat"], lng=CHENNAI["lng"], rid="req-1"):
    return {
        "_id": rid,
        "issue": issue,
        "vehicle": vehicle,
        "location": {"lat": lat, "lng": lng},
        "status": sm.SEARCHING,
    }


def run(mechanics, req=None, regions=(CHENNAI_REGION,)):
    return allocation.allocate(
        mechanics,
        req or request_doc(),
        list(regions),
        now=NOW,
        started_at=NOW,
    )


# ─────────────────────────────────────────────────────────────────────────────
# GEO
# ─────────────────────────────────────────────────────────────────────────────
class TestGeo:
    @pytest.mark.parametrize(
        "lat,lng,expected",
        [
            (13.0, 80.0, True),
            (-90, -180, True),
            (90, 180, True),
            (91, 80, False),
            (-91, 80, False),
            (13, 181, False),
            (None, 80, False),
            ("abc", 80, False),
            (float("nan"), 80, False),
            (float("inf"), 80, False),
        ],
    )
    def test_coordinate_validation(self, lat, lng, expected):
        assert geo.is_valid_coordinate(lat, lng) is expected

    def test_haversine_matches_known_short_distance(self):
        # 0.01 degrees of latitude is ~1.111 km anywhere on the globe.
        d = geo.haversine_km(13.0000, 80.0000, 13.0100, 80.0000)
        assert d == pytest.approx(1.111, abs=0.01)

    def test_haversine_is_zero_for_identical_points(self):
        assert geo.haversine_km(13.0827, 80.2707, 13.0827, 80.2707) == pytest.approx(0.0)

    def test_haversine_chennai_to_coimbatore_is_plausible(self):
        # Great-circle distance between the two cities is ~425 km.
        d = geo.haversine_km(
            CHENNAI["lat"], CHENNAI["lng"], COIMBATORE["lat"], COIMBATORE["lng"]
        )
        assert 400 < d < 450

    def test_bbox_contains_accepts_both_key_styles(self):
        assert geo.bbox_contains({"latMin": 12.8, "latMax": 13.3, "lngMin": 80.0, "lngMax": 80.5}, 13.0, 80.2)
        assert geo.bbox_contains({"minLat": 12.8, "maxLat": 13.3, "minLng": 80.0, "maxLng": 80.5}, 13.0, 80.2)
        assert not geo.bbox_contains({"latMin": 12.8, "latMax": 13.3, "lngMin": 80.0, "lngMax": 80.5}, 14.0, 80.2)

    def test_polygon_containment_with_hole(self):
        polygon = {
            "type": "Polygon",
            "coordinates": [
                [[80.0, 12.8], [80.5, 12.8], [80.5, 13.3], [80.0, 13.3], [80.0, 12.8]],
                [[80.2, 13.0], [80.3, 13.0], [80.3, 13.1], [80.2, 13.1], [80.2, 13.0]],
            ],
        }
        assert geo.polygon_contains(polygon, 12.9, 80.1)
        # Inside the hole -> outside the polygon.
        assert not geo.polygon_contains(polygon, 13.05, 80.25)

    def test_resolve_region_picks_the_smallest_match(self):
        small = dict(CHENNAI_REGION, _id="small", radiusKm=2.0,
                     latMin=13.0, latMax=13.15, lngMin=80.2, lngMax=80.35)
        regions = [CHENNAI_REGION, small]
        assert geo.resolve_region(regions, 13.08, 80.27)["_id"] == "small"

    def test_resolve_region_returns_none_when_outside_everything(self):
        assert geo.resolve_region([CHENNAI_REGION], 0.0, 0.0) is None

    def test_eta_uses_configured_speed(self):
        # 30 km at an assumed 30 km/h is 60 minutes.
        assert geo.estimate_eta_minutes(30.0, 30.0) == pytest.approx(60.0)


# ─────────────────────────────────────────────────────────────────────────────
# STATUS MACHINE (§14)
# ─────────────────────────────────────────────────────────────────────────────
class TestStatusMachine:
    def test_happy_path_is_fully_walkable(self):
        for current, nxt in zip(sm.HAPPY_PATH, sm.HAPPY_PATH[1:]):
            assert sm.can_transition(current, nxt), f"{current} -> {nxt} should be legal"

    def test_illegal_backwards_transition_is_rejected(self):
        verdict = sm.validate_transition(sm.SERVICE_COMPLETED, sm.SEARCHING)
        assert verdict["ok"] is False
        assert verdict["allowed"] == ["PAYMENT_PENDING"]

    def test_unknown_status_is_rejected(self):
        verdict = sm.validate_transition(sm.CREATED, "SOMETHING_ELSE")
        assert verdict["ok"] is False
        assert "unknown status" in verdict["reason"]

    def test_legacy_labels_normalize(self):
        assert sm.normalize("Pending") == sm.CREATED
        assert sm.normalize("Assigned") == sm.MECHANIC_ASSIGNED
        assert sm.normalize("On The Way") == sm.MECHANIC_EN_ROUTE
        assert sm.normalize("Reached") == sm.ARRIVED
        assert sm.normalize("Completed") == sm.SERVICE_COMPLETED
        assert sm.normalize("on_the_way") == sm.MECHANIC_EN_ROUTE

    def test_storage_label_round_trips_for_the_ui(self):
        for canonical, label in sm.CANONICAL_TO_LEGACY.items():
            assert sm.storage_label(canonical) == label
            assert sm.normalize(label) == canonical

    def test_terminal_states_accept_nothing(self):
        for terminal in (sm.CLOSED, sm.CANCELLED):
            assert sm.TRANSITIONS[terminal] == set()
            assert sm.is_terminal(terminal)

    def test_payment_failure_can_retry(self):
        assert sm.can_transition(sm.PAYMENT_FAILED, sm.PAYMENT_PENDING)

    def test_progress_percent_monotonic_along_happy_path(self):
        values = [sm.progress_percent(s) for s in sm.HAPPY_PATH]
        assert values == sorted(values)
        assert values[0] == 0 and values[-1] == 100


# ─────────────────────────────────────────────────────────────────────────────
# AUTH (§39)
# ─────────────────────────────────────────────────────────────────────────────
class TestAuth:
    def test_password_is_hashed_not_plaintext(self):
        stored = auth.hash_password("secret123")
        assert "secret123" not in stored
        assert auth.is_hashed(stored)

    def test_correct_password_verifies_and_wrong_one_does_not(self):
        stored = auth.hash_password("secret123")
        assert auth.verify_password(stored, "secret123") is True
        assert auth.verify_password(stored, "secret124") is False

    def test_two_hashes_of_the_same_password_differ(self):
        assert auth.hash_password("same") != auth.hash_password("same")

    def test_legacy_plaintext_still_verifies_and_is_flagged_for_rehash(self):
        assert auth.verify_password("plaintext", "plaintext") is True
        assert auth.verify_password("plaintext", "wrong") is False
        assert auth.needs_rehash("plaintext") is True

    def test_sanitize_document_removes_credentials(self):
        cleaned = auth.sanitize_document(
            {"name": "A", "password": "x", "passwordHash": "y", "password_hash": "z"}
        )
        assert "password" not in cleaned
        assert "passwordHash" not in cleaned
        assert "password_hash" not in cleaned
        assert cleaned["name"] == "A"

    def test_token_round_trip(self):
        issued = auth.issue_token("abc123", "mechanic")
        payload = auth.decode_token(issued["token"])
        assert payload is not None
        assert payload["sub"] == "abc123"
        assert payload["role"] == "mechanic"

    def test_tampered_token_is_rejected(self):
        token = auth.issue_token("abc123", "user")["token"]
        payload_b64, signature = token.split(".")
        forged_payload = auth._b64url_encode(b'{"sub":"hacker","role":"admin","exp":9999999999}')
        assert auth.decode_token(f"{forged_payload}.{signature}") is None

    def test_garbage_token_is_rejected(self):
        assert auth.decode_token("not-a-token") is None
        assert auth.decode_token("") is None
        assert auth.decode_token("a.b.c") is None

    def test_expired_token_is_rejected(self, monkeypatch):
        monkeypatch.setattr(auth.Config, "TOKEN_TTL_SECONDS", -10)
        token = auth.issue_token("abc123", "user")["token"]
        assert auth.decode_token(token) is None


# ─────────────────────────────────────────────────────────────────────────────
# PRICING (§30)
# ─────────────────────────────────────────────────────────────────────────────
class TestPricing:
    def test_quote_is_itemised_and_internally_consistent(self):
        q = pricing.quote("Flat Tyre", 5.0)
        labels = [item["label"] for item in q["lineItems"]]
        assert "Base service charge" in labels
        assert "Distance / travel charge" in labels
        assert "Service charge" in labels
        assert q["total"] == pytest.approx(q["subtotal"] + q["tax"], abs=0.01)

    def test_unknown_service_has_no_surcharge(self):
        q = pricing.quote("Something Not In The Rate Card", 1.0)
        assert q["lineItems"][2]["amount"] == 0.0

    def test_distance_increases_the_total(self):
        near = pricing.quote("Towing", 1.0)
        far = pricing.quote("Towing", 20.0)
        assert far["total"] > near["total"]

    def test_missing_distance_is_treated_as_zero_not_guessed(self):
        q = pricing.quote("Towing", None)
        assert q["lineItems"][1]["amount"] == 0.0

    def test_minor_units_match_major_units(self):
        q = pricing.quote("Flat Tyre", 3.0)
        assert q["totalMinorUnits"] == int(round(q["total"] * 100))


# ─────────────────────────────────────────────────────────────────────────────
# ELIGIBILITY FILTER (§17)
# ─────────────────────────────────────────────────────────────────────────────
class TestEligibility:
    def _evaluate(self, m, req=None, enforce_region=True, radius_km=10.0):
        return allocation.evaluate_eligibility(
            m,
            req or request_doc(),
            region_id="region-chennai",
            request_lat=CHENNAI["lat"],
            request_lng=CHENNAI["lng"],
            radius_km=radius_km,
            now=NOW,
            enforce_region=enforce_region,
        )

    def test_a_fully_qualified_mechanic_is_eligible(self):
        record = self._evaluate(mechanic("m1"))
        assert record["eligible"] is True
        assert record["reasons"] == []

    def test_unverified_is_rejected(self):
        record = self._evaluate(mechanic("m1", verified=False))
        assert record["eligible"] is False
        assert allocation.R_NOT_VERIFIED in record["reasons"]

    def test_offline_is_rejected(self):
        record = self._evaluate(mechanic("m1", online=False))
        assert allocation.R_OFFLINE in record["reasons"]

    def test_busy_mechanic_is_rejected(self):
        record = self._evaluate(mechanic("m1", available=False, current_request="other"))
        assert allocation.R_UNAVAILABLE in record["reasons"]

    def test_at_capacity_is_distinguished_from_unavailable(self):
        record = self._evaluate(mechanic("m1", available=False, workload=1))
        assert allocation.R_AT_CAPACITY in record["reasons"]

    def test_incompatible_service_is_rejected(self):
        m = mechanic("m1", services=("Flat Tyre",))
        record = self._evaluate(m, request_doc(issue="Engine Trouble"))
        assert allocation.R_SERVICE_MISMATCH in record["reasons"]

    def test_wildcard_service_matches_anything(self):
        m = mechanic("m1", services=("*",))
        assert self._evaluate(m, request_doc(issue="Engine Trouble"))["eligible"] is True

    def test_empty_service_list_is_not_a_wildcard(self):
        m = mechanic("m1", services=())
        record = self._evaluate(m, request_doc(issue="Flat Tyre"))
        assert allocation.R_SERVICE_MISMATCH in record["reasons"]

    def test_incompatible_vehicle_type_is_rejected(self):
        m = mechanic("m1", vehicle_types=("Bike",))
        record = self._evaluate(m, request_doc(vehicle="Truck"))
        assert allocation.R_VEHICLE_MISMATCH in record["reasons"]

    def test_no_location_is_rejected(self):
        record = self._evaluate(mechanic("m1", location={}))
        assert allocation.R_LOCATION_MISSING in record["reasons"]

    def test_stale_location_is_rejected(self):
        m = mechanic("m1", location_age_seconds=10_000)
        record = self._evaluate(m)
        assert allocation.R_LOCATION_STALE in record["reasons"]

    def test_fresh_location_is_accepted(self):
        m = mechanic("m1", location_age_seconds=60)
        assert self._evaluate(m)["eligible"] is True

    def test_naive_utc_datetime_from_mongo_is_treated_as_fresh(self):
        """PyMongo returns naive UTC datetimes.

        The staleness check must read them as UTC. Reading a naive datetime as
        local time made a just-published location look hours old on a UTC+05:30
        host, which silently emptied the candidate pool.
        """
        from datetime import datetime

        m = mechanic("m1")
        # Naive UTC, 30 seconds before the engine's clock.
        m["locationUpdatedAt"] = datetime.utcfromtimestamp(NOW - 30)
        age = allocation.location_age_seconds(m, now=NOW)
        assert age is not None and age < 120, f"expected ~30s, got {age}"
        assert self._evaluate(m)["eligible"] is True

    def test_naive_utc_datetime_beyond_the_window_is_stale(self):
        from datetime import datetime

        m = mechanic("m1")
        m["locationUpdatedAt"] = datetime.utcfromtimestamp(NOW - 3 * 3600)
        assert allocation.R_LOCATION_STALE in self._evaluate(m)["reasons"]

    def test_iso_string_location_timestamp_is_parsed(self):
        from datetime import datetime

        m = mechanic("m1")
        m["locationUpdatedAt"] = datetime.utcfromtimestamp(NOW - 10).isoformat()
        assert self._evaluate(m)["eligible"] is True

    def test_different_region_is_rejected_when_region_is_enforced(self):
        m = mechanic("m1", region="region-coimbatore")
        record = self._evaluate(m, enforce_region=True)
        assert allocation.R_REGION_MISMATCH in record["reasons"]
        assert record["sameRegion"] is False

    def test_different_region_is_allowed_when_enforcement_is_off(self):
        m = mechanic("m1", region="region-coimbatore")
        assert self._evaluate(m, enforce_region=False)["eligible"] is True

    def test_out_of_radius_is_rejected(self):
        m = mechanic("m1", lat=13.30, lng=80.45)  # ~28 km from the request
        record = self._evaluate(m, radius_km=10.0)
        assert allocation.R_OUT_OF_RADIUS in record["reasons"]

    def test_banned_mechanic_is_rejected(self):
        m = mechanic("m1")
        m["isBanned"] = True
        assert allocation.R_BANNED in self._evaluate(m)["reasons"]

    def test_distance_and_eta_are_recorded(self):
        record = self._evaluate(mechanic("m1"))
        assert record["distanceKm"] is not None
        assert record["etaMinutes"] is not None
        assert record["distanceMeters"] == pytest.approx(record["distanceKm"] * 1000, rel=1e-3)


# ─────────────────────────────────────────────────────────────────────────────
# RANKING (§18)
# ─────────────────────────────────────────────────────────────────────────────
class TestRanking:
    def test_closer_mechanic_ranks_first_when_all_else_is_equal(self):
        near = mechanic("near", lat=13.0850, lng=80.2720)
        far = mechanic("far", lat=13.1500, lng=80.3200)
        decision = run([far, near])
        assert decision["selected"]["mechanicId"] == "near"
        assert decision["selected"]["rank"] == 1

    def test_ranking_is_deterministic_across_input_order(self):
        a = mechanic("a", lat=13.0850, lng=80.2720)
        b = mechanic("b", lat=13.0900, lng=80.2800)
        first = [c["mechanicId"] for c in run([a, b])["ranked"]]
        second = [c["mechanicId"] for c in run([b, a])["ranked"]]
        assert first == second

    def test_lower_workload_wins_a_close_race(self):
        busy = mechanic("busy", lat=13.0850, lng=80.2720, workload=2)
        free = mechanic("free", lat=13.0851, lng=80.2721, workload=0)
        assert run([busy, free])["selected"]["mechanicId"] == "free"

    def test_every_score_is_explained_by_its_components(self):
        decision = run([mechanic("m1")])
        top = decision["ranked"][0]
        assert set(top["components"]) == {
            "proximity", "serviceMatch", "availability",
            "verification", "workloadFactor", "ratingFactor",
        }
        assert top["weights"] == allocation.Config.allocation_weights()

    def test_unrated_mechanic_gets_the_neutral_rating_factor(self):
        unrated = mechanic("u", rating=0, rating_count=0)
        record = allocation.score_candidate(
            {
                "distanceKm": 1.0, "serviceCompatible": True, "available": True,
                "verified": True, "workload": 0, "rating": 0, "ratingCount": 0,
            },
            10.0,
        )
        assert record["components"]["ratingFactor"] == 0.5

    def test_proximity_decays_to_zero_at_the_radius(self):
        record = allocation.score_candidate(
            {
                "distanceKm": 10.0, "serviceCompatible": True, "available": True,
                "verified": True, "workload": 0, "rating": 5, "ratingCount": 1,
            },
            10.0,
        )
        assert record["components"]["proximity"] == 0.0


# ─────────────────────────────────────────────────────────────────────────────
# SCENARIOS (§45) — the experiment set the journal will use
# ─────────────────────────────────────────────────────────────────────────────
class TestScenarios:
    def test_scenario_A_single_eligible_mechanic(self):
        decision = run([mechanic("only")])
        assert decision["status"] == allocation.A_OK
        assert decision["explain"]["eligibleCount"] == 1
        assert decision["selected"]["mechanicId"] == "only"

    def test_scenario_B_three_available_mechanics(self):
        pool = [mechanic(f"m{i}", lat=13.0850 + i * 0.01, lng=80.2750 + i * 0.01) for i in range(3)]
        decision = run(pool)
        assert decision["explain"]["eligibleCount"] == 3
        assert [c["rank"] for c in decision["ranked"]] == [1, 2, 3]

    def test_scenario_C_five_available_mechanics(self):
        pool = [mechanic(f"m{i}", lat=13.0850 + i * 0.008, lng=80.2750, vehicle_types=("*",)) for i in range(5)]
        decision = run(pool)
        assert decision["explain"]["eligibleCount"] == 5

    def test_scenario_D_nearest_mechanic_unavailable_falls_to_the_next(self):
        unavailable = mechanic("nearest", lat=13.0830, lng=80.2710, available=False, current_request="busy")
        fallback = mechanic("second", lat=13.1000, lng=80.2800)
        decision = run([unavailable, fallback])
        assert decision["selected"]["mechanicId"] == "second"
        rejected = [c for c in decision["candidates"] if c["mechanicId"] == "nearest"][0]
        assert rejected["eligible"] is False

    def test_scenario_E_nearest_does_not_support_the_service(self):
        wrong_service = mechanic("tyre-only", lat=13.0830, lng=80.2710, services=("Flat Tyre",))
        right_service = mechanic("engine", lat=13.1200, lng=80.2900, services=("Engine Trouble",))
        decision = run([wrong_service, right_service], req=request_doc(issue="Engine Trouble"))
        assert decision["selected"]["mechanicId"] == "engine"
        assert allocation.R_SERVICE_MISMATCH in [
            r for c in decision["candidates"] if c["mechanicId"] == "tyre-only" for r in c["reasons"]
        ]

    def test_scenario_F_nearest_is_in_another_region(self):
        other_region = mechanic("other", lat=13.0828, lng=80.2708, region="region-coimbatore")
        same_region = mechanic("same", lat=13.1200, lng=80.3000)
        decision = run([other_region, same_region])
        # The nearer mechanic is in another region and must not be selected.
        assert decision["selected"]["mechanicId"] == "same"
        assert allocation.R_REGION_MISMATCH in [
            r for c in decision["candidates"] if c["mechanicId"] == "other" for r in c["reasons"]
        ]

    def test_scenario_F_escalation_uses_the_wider_radius_when_the_region_is_empty(self):
        # ~15 km from the request: outside the 10 km in-region radius but inside
        # the 25 km escalation radius, so only the escalation pass can find it.
        far_but_eligible = mechanic("far", lat=13.2000, lng=80.3400)
        decision = run([far_but_eligible])
        assert decision["explain"]["escalationUsed"] is True
        assert decision["status"] == allocation.A_OK
        assert decision["selected"]["mechanicId"] == "far"

    def test_scenario_G_multiple_eligible_mechanics_picks_the_best_score(self):
        # All three must be inside the default 10 km radius AND under capacity,
        # otherwise the eligibility filter removes them before ranking runs.
        pool = [
            mechanic("a", lat=13.0850, lng=80.2720, workload=0, rating=4.9, rating_count=30),
            mechanic("b", lat=13.1100, lng=80.2900, workload=0, rating=4.0, rating_count=5),
            mechanic("c", lat=13.1300, lng=80.3050, workload=0, rating=3.0, rating_count=2),
        ]
        decision = run(pool)
        assert decision["selected"]["mechanicId"] == "a"
        assert decision["explain"]["eligibleCount"] == 3

    def test_scenario_H_excluded_mechanic_is_skipped(self):
        decliner = mechanic("decliner", lat=13.0830, lng=80.2710)
        other = mechanic("other", lat=13.1000, lng=80.2800)
        decision = allocation.allocate(
            [decliner, other], request_doc(), [CHENNAI_REGION],
            exclude_mechanic_ids=["decliner"], now=NOW, started_at=NOW,
        )
        assert decision["selected"]["mechanicId"] == "other"
        assert decision["explain"]["excludedMechanicIds"] == ["decliner"]

    def test_scenario_I_no_mechanic_available_reports_a_reason(self):
        pool = [
            mechanic("m1", online=False),
            mechanic("m2", verified=False),
            mechanic("m3", available=False, current_request="busy"),
        ]
        decision = run(pool)
        assert decision["status"] == allocation.A_NO_ELIGIBLE
        assert decision["selected"] is None
        assert decision["explain"]["failureReason"] in {
            allocation.R_OFFLINE,
            allocation.R_NOT_VERIFIED,
            allocation.R_UNAVAILABLE,
            allocation.R_AT_CAPACITY,
        }

    def test_scenario_I_with_an_empty_pool(self):
        decision = run([])
        assert decision["status"] == allocation.A_NO_ELIGIBLE
        assert decision["explain"]["failureReason"] == "NO_CANDIDATES"

    def test_scenario_K_poor_gps_out_of_range_is_refused_not_guessed(self):
        decision = allocation.allocate(
            [mechanic("m1")],
            request_doc(lat=999.0, lng=999.0),
            [CHENNAI_REGION],
            now=NOW, started_at=NOW,
        )
        assert decision["status"] == "INVALID_LOCATION"
        assert decision["selected"] is None

    def test_scenario_K_missing_gps_is_refused(self):
        req = request_doc()
        req["location"] = {}
        decision = allocation.allocate([mechanic("m1")], req, [CHENNAI_REGION], now=NOW, started_at=NOW)
        assert decision["status"] == "INVALID_LOCATION"

    def test_stale_locations_leave_nobody_eligible(self):
        decision = run([mechanic("m1", location_age_seconds=99_999)])
        assert decision["status"] == allocation.A_NO_ELIGIBLE
        assert decision["explain"]["failureReason"] == allocation.R_LOCATION_STALE


# ─────────────────────────────────────────────────────────────────────────────
# ALLOCATION LOG EVIDENCE (§19, §46)
# ─────────────────────────────────────────────────────────────────────────────
class TestAllocationLog:
    def test_log_contains_the_required_evidence_fields(self):
        decision = run([mechanic("m1"), mechanic("m2", online=False)])
        log = decision["allocationLog"]

        for field in (
            "requestId", "regionId", "hubId", "vehicleType", "issueType",
            "candidateCount", "eligibleCount", "candidates", "rankedMechanics",
            "selectedMechanicId", "selectedDistanceKm", "selectedEtaMinutes",
            "assignmentTimeMs", "acceptanceTimeMs", "status", "failureReason",
            "weights", "createdAt",
        ):
            assert field in log, f"allocation log missing '{field}'"

    def test_log_records_a_rejection_reason_for_every_rejected_candidate(self):
        decision = run([mechanic("ok"), mechanic("offline", online=False)])
        rejected = [c for c in decision["allocationLog"]["candidates"] if not c["eligible"]]
        assert rejected
        for candidate in rejected:
            assert candidate["reasons"], "a rejected candidate must carry a reason"

    def test_log_records_candidate_count_and_eligible_count(self):
        decision = run([mechanic("ok"), mechanic("offline", online=False)])
        assert decision["allocationLog"]["candidateCount"] == 2
        assert decision["allocationLog"]["eligibleCount"] == 1

    def test_assignment_latency_is_measured(self):
        decision = run([mechanic("m1")])
        assert isinstance(decision["allocationLog"]["assignmentTimeMs"], int)
        assert decision["allocationLog"]["assignmentTimeMs"] >= 0

    def test_failure_is_logged_with_its_reason(self):
        decision = run([mechanic("offline", online=False)])
        assert decision["allocationLog"]["status"] == allocation.A_NO_ELIGIBLE
        assert decision["allocationLog"]["failureReason"] == allocation.R_OFFLINE
        assert decision["allocationLog"]["selectedMechanicId"] is None

    def test_readable_trace_mentions_the_selected_mechanic(self):
        decision = run([mechanic("m1")])
        trace = allocation.human_readable_decision(decision)
        assert "Final ranking" in trace
        assert "Score" in trace

    def test_readable_trace_explains_a_failure(self):
        decision = run([mechanic("offline", online=False)])
        trace = allocation.human_readable_decision(decision)
        assert "NO MECHANIC ASSIGNED" in trace
        assert allocation.R_OFFLINE in trace


# ─────────────────────────────────────────────────────────────────────────────
# DETERMINISM
# ─────────────────────────────────────────────────────────────────────────────
class TestReproducibility:
    def test_identical_inputs_produce_identical_decisions(self):
        pool = [
            mechanic("a", lat=13.0850, lng=80.2720),
            mechanic("b", lat=13.0900, lng=80.2800, workload=1),
        ]
        first = run(pool)
        second = run(pool)
        assert [c["mechanicId"] for c in first["ranked"]] == [c["mechanicId"] for c in second["ranked"]]
        assert [c["score"] for c in first["ranked"]] == [c["score"] for c in second["ranked"]]
        assert first["explain"]["eligibleCount"] == second["explain"]["eligibleCount"]

    def test_decision_does_not_depend_on_input_ordering(self):
        pool = [mechanic(f"m{i}", lat=13.0850 + i * 0.005, lng=80.2750) for i in range(4)]
        forward = [c["mechanicId"] for c in run(pool)["ranked"]]
        backward = [c["mechanicId"] for c in run(list(reversed(pool)))["ranked"]]
        assert forward == backward
