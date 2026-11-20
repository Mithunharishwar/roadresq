"""Verify GET /api/garage/<garageId>/jobs returns real linked rows.

Inserts one tagged rescue_requests document carrying `garageId`, calls the
endpoint, asserts the row comes back, then removes the document. The tag makes
the record unambiguously ours so it can never be confused with real data.

Run with the backend up:
    .venv/Scripts/python.exe backend/_verify_garage_jobs.py
"""

import json
import sys
import urllib.request

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

from pymongo import MongoClient

RUN_TAG = "VERIFY-GARAGE-JOBS"
GARAGE_ID = "GARAGE-VERIFY-1791308645"
BASE = "http://127.0.0.1:5050"

db = MongoClient("mongodb://localhost:27017/")["roadresq_db"]
requests = db["rescue_requests"]

failures = []
checks = 0


def check(label, ok, detail=""):
    global checks
    checks += 1
    print(f"  [{'V' if ok else 'X'}] {label}{(' — ' + detail) if detail else ''}")
    if not ok:
        failures.append(label)


def get(url):
    with urllib.request.urlopen(url, timeout=15) as r:
        return r.status, json.loads(r.read().decode("utf-8"))


inserted_id = None
try:
    # ── baseline: nothing is linked for this garage ──
    status, body = get(f"{BASE}/api/garage/{GARAGE_ID}/jobs")
    check("endpoint returns 200", status == 200, f"HTTP {status}")
    check("returns a JSON array", isinstance(body, list), type(body).__name__)
    baseline = len(body)
    print(f"      baseline rows: {baseline}")

    # ── insert a linked request, tagged ──
    inserted_id = requests.insert_one(
        {
            "name": RUN_TAG,
            "phone": "0000000000",
            "issue": "Battery Problem",
            "vehicle": "Car",
            "locationText": f"{RUN_TAG} location",
            "location": {"lat": 12.9, "lng": 80.2},
            "status": "Assigned",
            "garageId": GARAGE_ID,
            "verifyTag": RUN_TAG,
        }
    ).inserted_id
    print(f"      inserted {inserted_id}")

    status, body = get(f"{BASE}/api/garage/{GARAGE_ID}/jobs")
    check("linked row is returned", len(body) == baseline + 1,
          f"{baseline} -> {len(body)}")

    # Identify the row by a field serialize_request actually emits — it builds an
    # explicit payload, so ad-hoc fields like `verifyTag` do not survive it.
    mine = [d for d in body if d.get("name") == RUN_TAG]
    check("the returned row is the one we inserted", len(mine) == 1,
          f"matched {len(mine)}")

    if mine:
        row = mine[0]
        check("row carries a usable id", bool(row.get("id")),
              repr(row.get("id")))
        check("row carries the issue text", row.get("issue") == "Battery Problem")
        check("row carries the location text",
              row.get("locationText") == f"{RUN_TAG} location")
        check("row carries a status", bool(row.get("status")),
              repr(row.get("status")))

    # ── a different garage must not see it ──
    status, other = get(f"{BASE}/api/garage/SOME-OTHER-GARAGE/jobs")
    check("another garage does not see the row",
          not any(d.get("verifyTag") == RUN_TAG for d in other))

finally:
    if inserted_id is not None:
        requests.delete_one({"_id": inserted_id})
        left = requests.count_documents({"verifyTag": RUN_TAG})
        print(f"      cleaned up (remaining tagged docs: {left})")

print()
total = checks
passed = checks - len(failures)
print(f"TOTAL {total}  PASS {passed}  FAIL {len(failures)}")
for f in failures:
    print(f"  FAILED: {f}")
sys.exit(1 if failures else 0)
