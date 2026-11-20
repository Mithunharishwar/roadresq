"""
End-to-end acceptance test for the whole rescue lifecycle.

Runs the real HTTP API against a live backend and asserts what the four roles
must be able to do, in order:

    customer creates -> mechanic accepts/drives -> assistant joins
    -> garage receives -> payment -> rating -> closed

Run it with the backend up:

    backend\.venv\Scripts\python.exe backend\workflow_e2e.py

Exit code 0 means every step passed. It creates real records in the configured
database, so point it at a development instance.
"""

import json, urllib.request, urllib.error, time, sys

import os
BASE = os.getenv("ROADRESQ_BASE", "http://127.0.0.1:5050")
FAIL, STEPS = [], [0]

def call(m, p, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(BASE+p, data=data, method=m, headers={"Content-Type":"application/json"})
    try:
        with urllib.request.urlopen(req, timeout=12) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")

def check(name, cond, detail=""):
    STEPS[0] += 1
    print(f"[{STEPS[0]:02d}] {'PASS' if cond else 'FAIL'}  {name}" + ("" if cond else f"   <- {detail}"))
    if not cond: FAIL.append(name)

def doc(body):
    return body.get("request") or body.get("job") or body

stamp = str(int(time.time()))[-6:]
print("=== E2E: customer -> mechanic -> assistant -> garage -> payment -> rating ===")

st, body = call("POST", "/api/rescueRequests", {
    "name": f"E2E {stamp}", "phone": "9"+stamp+"001", "issue": "Battery Problem",
    "vehicle": "Car", "location": {"lat": 13.01, "lng": 80.21}, "locationText": "Guindy"})
rid = doc(body).get("_id")
check("customer creates request", st in (200, 201) and bool(rid), f"{st}")

st, mechs = call("GET", "/api/mechanics")
mechanic = next(m for m in mechs["mechanics"] if m.get("phone"))
mid = mechanic["_id"]

st, body = call("PUT", f"/api/rescueRequests/{rid}/assign", {"mechanicId": mid})
check("assigned to mechanic", st == 200 and doc(body).get("statusCanonical") == "MECHANIC_ASSIGNED",
      doc(body).get("statusCanonical"))

chain = [("accepted","MECHANIC_ACCEPTED"), ("on_the_way","MECHANIC_EN_ROUTE"),
         ("reached","ARRIVED"), ("in_progress","SERVICE_STARTED"), ("completed","SERVICE_COMPLETED")]
for token, canon in chain:
    st, body = call("PUT", f"/api/rescueRequests/{rid}/status", {"status": token, "mechanicId": mid})
    got = doc(body).get("statusCanonical")
    check(f"mechanic -> {canon}", st == 200 and got == canon, f"{st} {got}")

st, body = call("PUT", f"/api/rescueRequests/{rid}/status", {"status": "on_the_way"})
check("illegal regression refused (409)", st == 409, st)

st, asst = call("POST", "/api/assistant/instant", {"name": f"Rider {stamp}", "phone": "8"+stamp+"002"})
aid = (asst.get("assistant") or {}).get("_id")
st, body = call("PUT", f"/api/rescueRequests/{rid}/assign-assistant", {"assistantId": aid})
check("assistant joins the job", st == 200, f"{st} {body}")

st, gar = call("POST", "/api/garage/register", {"garageId": f"G{stamp}", "name": f"Garage {stamp}",
                                                "phone": "7"+stamp+"003", "password": "garage1234"})
check("garage registered", st in (200, 201), f"{st} {gar}")

st, body = call("PUT", f"/api/rescueRequests/{rid}/garage", {"garageId": f"G{stamp}"})
check("vehicle handed to garage", st == 200, f"{st} {body}")

st, body = call("PUT", f"/api/rescueRequests/{rid}/payment", {
    "amount": 640, "paymentStatus": "success", "paymentId": f"pay_{stamp}", "paymentMethod": "cash"})
check("payment recorded", st == 200, f"{st} {body}")

st, req = call("GET", f"/api/rescueRequests/{rid}")
check("all four identities on one record",
      str(req.get("mechanicId")) == str(mid) and str(req.get("assistantId")) == str(aid)
      and str(req.get("garageId")) == f"G{stamp}",
      (req.get("mechanicId"), req.get("assistantId"), req.get("garageId")))
check("paid amount stored", float(req.get("amount") or 0) == 640.0, req.get("amount"))
check("state is payment completed", req.get("statusCanonical") in ("PAYMENT_COMPLETED","RATED","CLOSED"),
      req.get("statusCanonical"))

st, body = call("POST", "/api/ratings", {"requestId": rid, "rating": 5, "review": "Fast and clear"})
check("customer rates the mechanic", st in (200, 201), f"{st} {body}")

st, req = call("GET", f"/api/rescueRequests/{rid}")
check("rating closes the loop", req.get("statusCanonical") in ("RATED","CLOSED"), req.get("statusCanonical"))

st, mj = call("GET", f"/api/mechanic/{mid}/requests")
mlist = mj.get("requests") if isinstance(mj, dict) else mj
check("mechanic sees the job", any(str(r.get("_id")) == str(rid) for r in (mlist or [])))
st, aj = call("GET", f"/api/assistant/{aid}/jobs")
check("assistant sees the job", any(str(j.get("_id")) == str(rid) for j in (aj or [])))
st, gj = call("GET", f"/api/garage/G{stamp}/jobs")
glist = gj.get("jobs") if isinstance(gj, dict) else gj
check("garage sees the job", any(str(j.get("_id")) == str(rid) for j in (glist or [])))

print()
print(f"RESULT: {STEPS[0]-len(FAIL)} passed, {len(FAIL)} failed")
if FAIL:
    print("failed:", FAIL); sys.exit(1)
