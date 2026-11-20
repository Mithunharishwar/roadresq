"""Check how mechanicId / assistantId / garageId are actually stored.

The mechanic-requests endpoint filters with the STRING id from the URL. If the
field is stored as an ObjectId, that filter matches nothing and every mechanic
sees an empty list. Temporary diagnostic.
"""

import sys
from collections import Counter

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

from bson import ObjectId
from pymongo import MongoClient

db = MongoClient("mongodb://localhost:27017/")["roadresq_db"]
req = db["rescue_requests"]

print("=== stored bson type of the linkage fields ===")
for field in ("mechanicId", "assistantId", "garageId", "regionId", "hubId"):
    types = Counter(
        type(d[field]).__name__
        for d in req.find({field: {"$exists": True, "$nin": [None, ""]}})
    )
    print(f"  {field}: {dict(types) if types else 'no non-empty values'}")

print()
print("=== same field, string filter vs ObjectId filter ===")
target = "69cb6ccb9c2936353441d921"
print(f"  query {{mechanicId: '{target}'}}        -> {req.count_documents({'mechanicId': target})} docs")
print(
    f"  query {{mechanicId: ObjectId('{target}')}} -> "
    f"{req.count_documents({'mechanicId': ObjectId(target)})} docs"
)

print()
print("=== sample _id / mechanicId pairs ===")
for d in req.find({"mechanicId": {"$exists": True, "$nin": [None, ""]}}).limit(5):
    print(
        f"  _id={d['_id']} ({type(d['_id']).__name__})  "
        f"mechanicId={d['mechanicId']} ({type(d['mechanicId']).__name__})"
    )
