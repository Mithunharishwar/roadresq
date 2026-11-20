"""Find a mechanic that actually has jobs, so the History/Passbook tabs can be
verified against real rows on the device. Temporary helper."""

import sys
from collections import Counter

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

from bson import ObjectId
from pymongo import MongoClient

db = MongoClient("mongodb://localhost:27017/")["roadresq_db"]


def non_empty(field):
    return {field: {"$exists": True, "$nin": [None, ""]}}


counts = Counter(
    str(d.get("mechanicId"))
    for d in db["rescue_requests"].find(non_empty("mechanicId"))
)
print(f"mechanics with assigned requests: {len(counts)}")
for mid, n in counts.most_common(6):
    m = db["mechanics"].find_one({"_id": ObjectId(mid)}) if len(mid) == 24 else None
    print(
        f"  {mid}  requests={n}  "
        f"name={m.get('name') if m else '?'}  "
        f"email={m.get('email') if m else '?'}"
    )

print()
print("completed / closed requests that have a mechanic and an amount:")
found = 0
for d in db["rescue_requests"].find(
    {
        **non_empty("mechanicId"),
        "status": {"$in": ["Completed", "completed", "Closed", "closed"]},
    }
):
    found += 1
    print(
        f"  id={d.get('_id')} status={d.get('status')} "
        f"amount={d.get('amount')} mechanicId={d.get('mechanicId')} "
        f"issue={d.get('issue')}"
    )
print(f"  total: {found}")

print()
print("any request with a non-zero amount at all:")
for d in db["rescue_requests"].find({"amount": {"$nin": [None, 0, "0"]}}):
    print(
        f"  id={d.get('_id')} status={d.get('status')} amount={d.get('amount')} "
        f"mechanicId={d.get('mechanicId')}"
    )
