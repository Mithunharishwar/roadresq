"""
Seed development data for RoadResQ.

Creates two regions, their hubs, and a spread of mechanics that exercise every
branch of the allocation engine (verified/unverified, online/offline, available
/busy, service-compatible/incompatible, in-region/out-of-region, fresh/stale
location).

RUNNING THIS IS EXPLICITLY A DEVELOPMENT ACTION.
  * Every seeded document carries `isDemoAccount: True` or `isDemoRegion: True`.
  * Demo mechanics are verified ONLY so that the allocation engine has
    eligible candidates to select. Real accounts created through
    /api/auth/register start unverified.
  * Nothing here is presented as real user, mechanic, or operational data.

Usage:
    python seed_demo_data.py            # add the demo dataset
    python seed_demo_data.py --reset    # delete the demo dataset first
"""

from __future__ import annotations

import argparse
import sys
from datetime import datetime, timedelta

import db
from auth import hash_password
from config import Config

# ── Geography ───────────────────────────────────────────────────────────────
# Two bbox regions with a deliberate gap between them, so a request raised
# outside both exercises the "no region resolved" path, and a request in one
# region exercises the cross-region rejection path.
REGIONS = [
    {
        "name": "Chennai Central",
        "city": "Chennai",
        "latMin": 12.85,
        "latMax": 13.30,
        "lngMin": 80.05,
        "lngMax": 80.45,
        "center": {"lat": 13.0827, "lng": 80.2707},
        "radiusKm": 25.0,
        "isDemoRegion": True,
    },
    {
        "name": "Coimbatore North",
        "city": "Coimbatore",
        "latMin": 10.90,
        "latMax": 11.15,
        "lngMin": 76.85,
        "lngMax": 77.10,
        "center": {"lat": 11.0168, "lng": 76.9558},
        "radiusKm": 20.0,
        "isDemoRegion": True,
    },
]

# Request origin used by the scenario scripts.
CHENNAI_USER = {"lat": 13.0827, "lng": 80.2707}

# ── Mechanics ───────────────────────────────────────────────────────────────
# Each entry documents which engine branch it is meant to exercise.
MECHANICS = [
    # --- Eligible candidates in Chennai Central ---------------------------
    {
        "name": "Demo Mechanic A - near, all-rounder",
        "phone": "9000000001",
        "region": "Chennai Central",
        "location": {"lat": 13.0900, "lng": 80.2750},  # ~0.9 km away
        "services": ["*"],
        "vehicleTypes": ["*"],
        "verified": True,
        "online": True,
        "available": True,
        "workload": 0,
        "rating": 4.6,
        "ratingCount": 12,
        "_exercises": "SCENARIO A/G - closest eligible mechanic",
    },
    {
        "name": "Demo Mechanic B - mid, tyre + battery",
        "phone": "9000000002",
        "region": "Chennai Central",
        "location": {"lat": 13.1100, "lng": 80.2900},  # ~3.7 km away
        "services": ["Flat Tyre", "Battery Problem"],
        "vehicleTypes": ["Car", "SUV"],
        "verified": True,
        "online": True,
        "available": True,
        "workload": 1,
        "rating": 4.2,
        "ratingCount": 8,
        "_exercises": "SCENARIO E/G - service-compatible but not universal",
    },
    {
        "name": "Demo Mechanic C - far, towing only",
        "phone": "9000000003",
        "region": "Chennai Central",
        "location": {"lat": 13.2000, "lng": 80.3800},  # ~16 km away
        "services": ["Towing"],
        "vehicleTypes": ["Truck", "Van"],
        "verified": True,
        "online": True,
        "available": True,
        "workload": 0,
        "rating": 3.9,
        "ratingCount": 3,
        "_exercises": "SCENARIO E/G/H - out of the default 10 km radius",
    },
    # --- Ineligible for specific reasons (§17) ---------------------------
    {
        "name": "Demo Mechanic D - UNVERIFIED (closest of all)",
        "phone": "9000000004",
        "region": "Chennai Central",
        "location": {"lat": 13.0829, "lng": 80.2709},  # ~30 m away
        "services": ["*"],
        "vehicleTypes": ["*"],
        "verified": False,
        "verificationStatus": "pending",
        "online": True,
        "available": True,
        "workload": 0,
        "rating": 0.0,
        "ratingCount": 0,
        "_exercises": "SCENARIO D - nearest mechanic is ineligible (unverified)",
    },
    {
        "name": "Demo Mechanic E - OFFLINE (very close)",
        "phone": "9000000005",
        "region": "Chennai Central",
        "location": {"lat": 13.0831, "lng": 80.2711},
        "services": ["*"],
        "vehicleTypes": ["*"],
        "verified": True,
        "online": False,
        "available": False,
        "workload": 0,
        "rating": 4.8,
        "ratingCount": 20,
        "_exercises": "SCENARIO D - nearest mechanic is offline",
    },
    {
        "name": "Demo Mechanic F - BUSY on another job",
        "phone": "9000000006",
        "region": "Chennai Central",
        "location": {"lat": 13.0850, "lng": 80.2720},
        "services": ["*"],
        "vehicleTypes": ["*"],
        "verified": True,
        "online": True,
        "available": False,
        "workload": 1,
        "currentRequestId": "demo-in-progress-job",
        "rating": 4.1,
        "ratingCount": 6,
        "_exercises": "SCENARIO D - nearest mechanic is unavailable",
    },
    {
        "name": "Demo Mechanic G - service-specific (Flat Tyre / Car only)",
        "phone": "9000000007",
        "region": "Chennai Central",
        "location": {"lat": 13.0840, "lng": 80.2715},
        "services": ["Flat Tyre"],
        "vehicleTypes": ["Car"],
        "verified": True,
        "online": True,
        "available": True,
        "workload": 0,
        "rating": 4.4,
        "ratingCount": 10,
        "_exercises": (
            "SCENARIO E - legitimate match for a Flat Tyre/Car request (and the "
            "closest one, so it wins); raise an Engine Trouble request instead "
            "to see it rejected with SERVICE_MISMATCH"
        ),
    },
    {
        "name": "Demo Mechanic H - STALE LOCATION",
        "phone": "9000000008",
        "region": "Chennai Central",
        "location": {"lat": 13.0835, "lng": 80.2712},
        "locationAgeHours": 5,  # deliberately older than ALLOC_LOCATION_STALE_SECONDS
        "services": ["*"],
        "vehicleTypes": ["*"],
        "verified": True,
        "online": True,
        "available": True,
        "workload": 0,
        "rating": 4.0,
        "ratingCount": 4,
        "_exercises": "SCENARIO K - location has gone stale",
    },
    # --- Another region (§16) --------------------------------------------
    {
        "name": "Demo Mechanic I - Coimbatore (different region)",
        "phone": "9000000009",
        "region": "Coimbatore North",
        "location": {"lat": 11.0168, "lng": 76.9558},
        "services": ["*"],
        "vehicleTypes": ["*"],
        "verified": True,
        "online": True,
        "available": True,
        "workload": 0,
        "rating": 4.7,
        "ratingCount": 15,
        "_exercises": "SCENARIO F - eligible but in a different region",
    },
    # --- No usable location ----------------------------------------------
    {
        "name": "Demo Mechanic J - NO LOCATION PUBLISHED",
        "phone": "9000000010",
        "region": "Chennai Central",
        "location": {},
        "services": ["*"],
        "vehicleTypes": ["*"],
        "verified": True,
        "online": True,
        "available": True,
        "workload": 0,
        "rating": 4.3,
        "ratingCount": 7,
        "_exercises": "SCENARIO K - eligible profile but no coordinates",
    },
]

DEMO_USER = {
    "name": "Demo User",
    "phone": "9111111111",
    "email": "demo.user@roadresq.local",
    "password": "demo1234",
    "isDemoAccount": True,
}


def _reset() -> None:
    """Delete only documents flagged as demo data."""
    removed = {
        "mechanics": db.mechanics().delete_many({"isDemoAccount": True}).deleted_count,
        "regions": db.regions().delete_many({"isDemoRegion": True}).deleted_count,
        "hubs": db.hubs().delete_many({"isDemoHub": True}).deleted_count,
        "users": db.users().delete_many({"isDemoAccount": True}).deleted_count,
    }
    for name, count in removed.items():
        print(f"  removed {count:>3} demo document(s) from {name}")


def seed(reset: bool = False) -> None:
    if reset:
        print("Resetting demo data...")
        _reset()

    print(f"Seeding into database '{Config.DB_NAME}' ...")

    # ── Regions ─────────────────────────────────────────────────────────
    region_ids = {}
    for region in REGIONS:
        existing = db.regions().find_one({"name": region["name"], "isDemoRegion": True})
        if existing:
            region_ids[region["name"]] = existing["_id"]
            print(f"  region '{region['name']}' already present")
            continue
        doc = dict(region)
        doc["createdAt"] = datetime.utcnow()
        doc["updatedAt"] = datetime.utcnow()
        inserted = db.regions().insert_one(doc)
        region_ids[region["name"]] = inserted.inserted_id
        print(f"  + region '{region['name']}'")

    # ── Hubs (one per region) ───────────────────────────────────────────
    hub_ids = {}
    for region in REGIONS:
        hub_name = f"{region['name']} Hub"
        existing = db.hubs().find_one({"name": hub_name, "isDemoHub": True})
        if existing:
            hub_ids[region["name"]] = existing["_id"]
            continue
        hub = {
            "name": hub_name,
            "regionId": str(region_ids[region["name"]]),
            "location": region["center"],
            "services": Config.SERVICE_CATEGORIES,
            "isDemoHub": True,
            "createdAt": datetime.utcnow(),
        }
        inserted = db.hubs().insert_one(hub)
        hub_ids[region["name"]] = inserted.inserted_id
        print(f"  + hub '{hub_name}'")

    # ── Mechanics ───────────────────────────────────────────────────────
    created = 0
    for entry in MECHANICS:
        existing = db.mechanics().find_one({"phone": entry["phone"]})
        if existing:
            print(f"  mechanic {entry['phone']} already present - skipped")
            continue

        age_hours = entry.pop("locationAgeHours", 0)
        exercised = entry.pop("_exercises", "")
        region_name = entry.pop("region")

        location = entry.get("location") or {}
        location_updated = (
            datetime.utcnow() - timedelta(hours=age_hours) if age_hours else datetime.utcnow()
        )

        doc = {
            "name": entry["name"],
            "email": f"{entry['phone']}@demo.roadresq.local",
            "phone": entry["phone"],
            # Demo accounts share one password so the flow can be exercised
            # quickly. It is still stored as a hash, never in plaintext.
            "password": hash_password("demo1234"),
            "role": "mechanic",
            "online": entry.get("online", False),
            "available": entry.get("available", True),
            "location": location,
            "locationUpdatedAt": location_updated,
            "verified": entry.get("verified", False),
            "verificationStatus": entry.get(
                "verificationStatus",
                "verified" if entry.get("verified") else "pending",
            ),
            "services": entry.get("services", []),
            "vehicleTypes": entry.get("vehicleTypes", []),
            "rating": entry.get("rating", 0.0),
            "ratingCount": entry.get("ratingCount", 0),
            "completedRescues": 0,
            "workload": entry.get("workload", 0),
            "currentRequestId": entry.get("currentRequestId", ""),
            "regionId": str(region_ids.get(region_name, "")),
            "regionName": region_name,
            "hubId": str(hub_ids.get(region_name, "")),
            "hubName": f"{region_name} Hub",
            "isDemoAccount": True,
            "demoPurpose": exercised,
            "createdAt": datetime.utcnow(),
            "updatedAt": datetime.utcnow(),
        }
        db.mechanics().insert_one(doc)
        created += 1
        print(f"  + mechanic {entry['phone']}  ({exercised})")

    # ── Demo user ───────────────────────────────────────────────────────
    if not db.users().find_one({"phone": DEMO_USER["phone"]}):
        user_doc = {
            "name": DEMO_USER["name"],
            "email": DEMO_USER["email"],
            "phone": DEMO_USER["phone"],
            "password": hash_password(DEMO_USER["password"]),
            "role": "user",
            "vehicles": [{"type": "Car", "details": "Demo hatchback"}],
            "emergencyContacts": [],
            "isDemoAccount": True,
            "createdAt": datetime.utcnow(),
            "updatedAt": datetime.utcnow(),
        }
        db.users().insert_one(user_doc)
        print(f"  + demo user {DEMO_USER['phone']} (password: {DEMO_USER['password']})")
    else:
        print(f"  demo user {DEMO_USER['phone']} already present")

    # ── Summary ─────────────────────────────────────────────────────────
    print()
    print("Seed complete.")
    print(f"  regions  : {db.regions().count_documents({'isDemoRegion': True})}")
    print(f"  hubs     : {db.hubs().count_documents({'isDemoHub': True})}")
    print(f"  mechanics: {db.mechanics().count_documents({'isDemoAccount': True})}"
          f"  ({created} newly created)")
    print()
    print("NOTE: seeded mechanics are flagged `isDemoAccount: true`. They are")
    print("      marked verified only so the allocation engine has eligible")
    print("      candidates. Do not present them as real service providers.")
    print()
    print("Suggested allocation probe (request origin in Chennai Central):")
    print(
        '  curl -X POST http://localhost:5050/api/allocation/find '
        '-H "Content-Type: application/json" '
        f'-d "{{\\"lat\\": {CHENNAI_USER['lat']}, '
        f'\\"lng\\": {CHENNAI_USER['lng']}, '
        '\\"issue\\": \\"Flat Tyre\\", \\"vehicle\\": \\"Car\\", '
        '\\"dryRun\\": true}}"'
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Seed RoadResQ development data")
    parser.add_argument(
        "--reset",
        action="store_true",
        help="delete existing demo documents before seeding",
    )
    args = parser.parse_args()

    if not db.ping():
        print(
            f"ERROR: MongoDB is not reachable at {Config.MONGO_URI}.\n"
            "Start the MongoDB service and try again.",
            file=sys.stderr,
        )
        return 1

    seed(reset=args.reset)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
