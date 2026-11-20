"""Verify the backend endpoints the Flutter app's reachable screens call.

Covers the reads that replaced Firestore, using only EXISTING data (no writes,
so nothing in the database is modified):

  * GET /api/zones                        <- ZoneSecurityService (SOS submit)
  * GET /api/garage/<garageId>/jobs       <- GarageDashboard
  * GET /api/rescueRequests/<id>          <- RequestStatusScreen (4s poll)
  * GET /api/mechanic/<id>/requests       <- MechanicHomeScreen
  * GET /api/assistant/<id>/jobs          <- AssistantHomeScreen

Run with the backend up:
    .venv/Scripts/python.exe backend/verify_client_reads.py
"""

import json
import sys
import urllib.request

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

from bson import ObjectId
from pymongo import MongoClient

BASE = "http://127.0.0.1:5050"
db = MongoClient("mongodb://localhost:27017/")["roadresq_db"]

failures = []
checks = 0


def check(label, ok, detail=""):
    global checks
    checks += 1
    print(f"  [{'V' if ok else 'X'}] {label}{(' — ' + detail) if detail else ''}")
    if not ok:
        failures.append(label)


def get(path):
    with urllib.request.urlopen(BASE + path, timeout=20) as r:
        return r.status, json.loads(r.read().decode("utf-8"))


print("=== GET /api/zones (replaced the Firestore `zones` read) ===")
status, zones = get("/api/zones")
check("returns 200", status == 200, f"HTTP {status}")
check("returns a JSON array", isinstance(zones, list), type(zones).__name__)
print(f"      zones returned: {len(zones)}")

print()
print("=== GET /api/garage/<garageId>/jobs ===")
garage = db["garages"].find_one({})
if garage:
    gid = garage.get("garageId")
    status, jobs = get(f"/api/garage/{gid}/jobs")
    check("returns 200", status == 200, f"HTTP {status}")
    check("returns a JSON array", isinstance(jobs, list), type(jobs).__name__)
    print(f"      garageId={gid} jobs={len(jobs)}")
else:
    check("a garage exists to test with", False)

print()
print("=== GET /api/rescueRequests/<id> (RequestStatusScreen poll) ===")
doc = db["rescue_requests"].find_one({"mechanicId": {"$nin": [None, ""]}})
if doc:
    rid = str(doc["_id"])
    status, req = get(f"/api/rescueRequests/{rid}")
    check("returns 200", status == 200, f"HTTP {status}")
    check("is a JSON object", isinstance(req, dict), type(req).__name__)
    check("carries an id", bool(req.get("id")), repr(req.get("id")))
    check("carries a status", bool(req.get("status")), repr(req.get("status")))
    check("carries a statusCanonical", bool(req.get("statusCanonical")),
          repr(req.get("statusCanonical")))
else:
    check("a request with a mechanic exists to test with", False)

print()
print("=== GET /api/mechanic/<id>/requests (MechanicHomeScreen) ===")
if doc:
    mid = str(doc["mechanicId"])
    status, rows = get(f"/api/mechanic/{mid}/requests")
    check("returns 200", status == 200, f"HTTP {status}")
    check("returns a JSON array", isinstance(rows, list), type(rows).__name__)
    print(f"      mechanicId={mid} requests={len(rows)}")

print()
print("=== GET /api/assistant/<id>/jobs (AssistantHomeScreen) ===")
asst = db["mechanics"].find_one({"role": "assistant"})
if asst:
    aid = str(asst["_id"])
    status, rows = get(f"/api/assistant/{aid}/jobs")
    check("returns 200", status == 200, f"HTTP {status}")
    check("returns a JSON array", isinstance(rows, list), type(rows).__name__)
    print(f"      assistantId={aid} jobs={len(rows)}")
else:
    check("an assistant exists to test with", False)

print()
checks_total = checks
print(f"TOTAL {checks_total}  PASS {checks_total - len(failures)}  FAIL {len(failures)}")
for f in failures:
    print(f"  FAILED: {f}")
sys.exit(1 if failures else 0)
