"""
RoadResQ — end-to-end module test.

Exercises every HTTP module plus the Socket.IO realtime layer against a running
backend and reports a truthful pass/fail per step.

Run (backend must already be running, MongoDB up):
    .\\.venv\\Scripts\\python.exe backend\\tests\\e2e_module_test.py

Safety: every record this script creates is stamped with RUN_TAG. Destructive
calls (DELETE) target ONLY objects created by this run, never pre-existing data.
"""
from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request

# The Windows console defaults to cp1252, which cannot encode server-supplied
# text or box-drawing separators. Never let an encoding error kill the run.
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

BASE = os.environ.get("ROADRESQ_BASE", "http://127.0.0.1:5050")
DEV_OTP = os.environ.get("ROADRESQ_DEV_OTP", "1234")
STAMP = str(int(time.time()))
RUN_TAG = "E2E-" + STAMP  # marks every record this run creates

RESULTS: list[dict] = []


def call(method: str, path: str, body=None, timeout: int = 25):
    """Return (status_code_or_None, parsed_json_or_raw_text)."""
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read().decode("utf-8", "replace")
            try:
                return r.status, json.loads(raw)
            except Exception:
                return r.status, raw
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "replace")
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, raw
    except Exception as e:  # connection refused, timeout, ...
        return None, f"{type(e).__name__}: {e}"


def check(module: str, step: str, method: str, path: str, ok: bool,
          detail="", expected="2xx") -> bool:
    RESULTS.append({
        "module": module, "step": step, "method": method, "path": path,
        "expected": expected, "ok": bool(ok), "detail": str(detail)[:220],
    })
    print(f"  [{'PASS' if ok else 'FAIL'}] {step:<46} {method:<6} {path}")
    if not ok:
        print(f"         -> {str(detail)[:160]}")
    return bool(ok)


def head(title: str):
    print(f"\n-- {title} " + "-" * max(0, 60 - len(title)))


# ─────────────────────────────── 1. infrastructure
def t_infra():
    head("Infrastructure")
    for path, key in (("/health", "message"), ("/db-test", "mechanicCount"), ("/", None)):
        st, body = call("GET", path)
        ok = st == 200
        check("infra", f"GET {path}", "GET", path, ok, body, "200")
    st, body = call("GET", "/db-test")
    if st == 200 and isinstance(body, dict):
        check("infra", "Mongo reachable via /db-test", "GET", "/db-test",
              body.get("success") is True, body, "success=true")


# ─────────────────────────────── 2. user module
def t_user():
    head("User module")
    email = f"e2e.user.{STAMP}@example.com"
    phone = "9" + STAMP[-9:]
    pw = "E2ePass!123"

    st, b = call("POST", "/api/user/signup",
                 {"name": RUN_TAG, "email": email, "password": pw, "phone": phone})
    check("user", "signup", "POST", "/api/user/signup", st in (200, 201), b, "200/201")

    st, b = call("POST", "/api/user/login", {"email": email, "password": pw})
    check("user", "login (email+password)", "POST", "/api/user/login", st == 200, b, "200")

    st, b = call("POST", "/api/user/login", {"email": email, "password": "wrong"})
    check("user", "login rejects bad password", "POST", "/api/user/login", st == 401, b, "401")

    st, b = call("POST", "/api/user/login-otp", {"phone": phone})
    check("user", "login-otp (send)", "POST", "/api/user/login-otp", st == 200, b, "200")

    st, b = call("POST", "/api/user/verify-otp", {"phone": phone, "otp": DEV_OTP})
    check("user", "verify-otp (dev OTP)", "POST", "/api/user/verify-otp", st == 200, b, "200")

    st, b = call("POST", "/api/user/verify-otp", {"phone": phone, "otp": "0000"})
    check("user", "verify-otp rejects bad OTP", "POST", "/api/user/verify-otp", st == 401, b, "401")
    return {"email": email, "phone": phone, "password": pw}


# ─────────────────────────────── 3. mechanic module
def t_mechanic():
    head("Mechanic module")
    email = f"e2e.mech.{STAMP}@example.com"
    phone = "8" + STAMP[-9:]
    pw = "E2ePass!123"

    st, b = call("POST", "/api/mechanic/register",
                 {"name": RUN_TAG, "email": email, "password": pw, "phone": phone})
    mid = None
    if isinstance(b, dict) and isinstance(b.get("mechanic"), dict):
        mid = b["mechanic"].get("id") or b["mechanic"].get("_id")
    check("mechanic", "register", "POST", "/api/mechanic/register", st in (200, 201), b, "200/201")

    st, b = call("POST", "/api/mechanic/login", {"email": email, "password": pw})
    if not mid and isinstance(b, dict) and isinstance(b.get("mechanic"), dict):
        mid = b["mechanic"].get("id")
    check("mechanic", "login", "POST", "/api/mechanic/login", st == 200, b, "200")

    st, b = call("POST", "/api/mechanic/login-otp", {"phone": phone})
    check("mechanic", "login-otp (send)", "POST", "/api/mechanic/login-otp", st == 200, b, "200")

    st, b = call("POST", "/api/mechanic/verify-otp", {"phone": phone, "otp": DEV_OTP})
    check("mechanic", "verify-otp", "POST", "/api/mechanic/verify-otp", st == 200, b, "200")

    st, b = call("POST", "/api/mechanic/instant",
                 {"name": RUN_TAG + "-instant", "phone": "7" + STAMP[-9:]})
    check("mechanic", "instant access", "POST", "/api/mechanic/instant", st == 200, b, "200")

    if mid:
        st, b = call("PUT", f"/api/mechanic/{mid}/online", {"online": True})
        check("mechanic", "go online", "PUT", f"/api/mechanic/{mid}/online", st == 200, b, "200")
        st, b = call("PUT", f"/api/mechanic/{mid}/location", {"lat": 12.99, "lng": 80.09})
        check("mechanic", "push location", "PUT", f"/api/mechanic/{mid}/location", st == 200, b, "200")
        st, b = call("GET", f"/api/mechanic/{mid}/requests")
        check("mechanic", "load requests (THE reported bug)", "GET",
              f"/api/mechanic/{mid}/requests", st == 200 and isinstance(b, list), b, "200 list")
    else:
        check("mechanic", "id captured for sub-tests", "GET", "-", False, "no mechanic id returned")
    return {"id": mid, "email": email}


# ─────────────────────────────── 4. assistant module
def t_assistant():
    head("Assistant module")
    email = f"e2e.asst.{STAMP}@example.com"
    pw = "E2ePass!123"
    st, b = call("POST", "/api/assistant/register",
                 {"name": RUN_TAG, "email": email, "password": pw, "phone": "6" + STAMP[-9:]})
    check("assistant", "register", "POST", "/api/assistant/register", st in (200, 201), b, "200/201")

    st, b = call("POST", "/api/assistant/login", {"email": email, "password": pw})
    aid = None
    if isinstance(b, dict):
        for k in ("assistant", "mechanic", "user"):
            if isinstance(b.get(k), dict):
                aid = b[k].get("id") or b[k].get("_id")
                break
    check("assistant", "login", "POST", "/api/assistant/login", st == 200, b, "200")

    if aid:
        st, b = call("PUT", f"/api/assistant/{aid}/online", {"online": True})
        check("assistant", "go online", "PUT", f"/api/assistant/{aid}/online", st == 200, b, "200")
        st, b = call("GET", f"/api/assistant/{aid}/jobs")
        check("assistant", "fetch jobs", "GET", f"/api/assistant/{aid}/jobs",
              st == 200 and isinstance(b, list), b, "200 list")
    else:
        check("assistant", "id captured for sub-tests", "GET", "-", False, "no assistant id returned")
    return {"id": aid}


# ─────────────────────────────── 5. rescue request lifecycle
def t_rescue(mech, asst):
    head("Rescue request lifecycle")
    payload = {
        "name": RUN_TAG, "phone": "5550000" + STAMP[-4:], "issue": "E2E test flat tyre",
        "vehicle": "TN-00-E2E", "locationText": "E2E test location",
        "location": {"lat": 12.9951, "lng": 80.0992},
    }
    st, b = call("POST", "/api/rescueRequests", payload)
    rid = b.get("request", {}).get("id") if isinstance(b, dict) else None
    check("rescue", "create request", "POST", "/api/rescueRequests", st in (200, 201), b, "200/201")

    st, b = call("GET", "/api/rescueRequests")
    check("rescue", "list requests", "GET", "/api/rescueRequests",
          st == 200 and isinstance(b, list), f"len={len(b) if isinstance(b, list) else b}", "200 list")

    st, b = call("GET", "/api/rescueRequests/available")
    check("rescue", "list available (was 500)", "GET", "/api/rescueRequests/available",
          st == 200 and isinstance(b, list), f"len={len(b) if isinstance(b, list) else b}", "200 list")

    if not rid:
        check("rescue", "id captured for lifecycle", "GET", "-", False, "no id returned")
        return {}
    st, b = call("GET", f"/api/rescueRequests/{rid}")
    check("rescue", "get by id", "GET", f"/api/rescueRequests/{rid}", st == 200, b, "200")

    if mech.get("id"):
        st, b = call("PUT", f"/api/rescueRequests/{rid}/assign",
                     {"mechanicId": mech["id"], "mechanicName": RUN_TAG})
        check("rescue", "assign mechanic", "PUT", f"/api/rescueRequests/{rid}/assign", st == 200, b, "200")
        st, b = call("PUT", f"/api/rescueRequests/{rid}/mechanic-location", {"lat": 12.996, "lng": 80.100})
        check("rescue", "mechanic location update", "PUT",
              f"/api/rescueRequests/{rid}/mechanic-location", st == 200, b, "200")

    if asst.get("id"):
        st, b = call("PUT", f"/api/rescueRequests/{rid}/assign-assistant",
                     {"assistantId": asst["id"], "assistantName": RUN_TAG})
        check("rescue", "assign assistant", "PUT", f"/api/rescueRequests/{rid}/assign-assistant",
              st == 200, b, "200")
        st, b = call("PUT", f"/api/rescueRequests/{rid}/assistant-location",
                     {"assistantId": asst["id"], "lat": 12.996, "lng": 80.100})
        check("rescue", "assistant location update", "PUT",
              f"/api/rescueRequests/{rid}/assistant-location", st == 200, b, "200")

    # The state machine is authoritative. MECHANIC_ASSIGNED may NOT jump straight
    # to MECHANIC_EN_ROUTE, so the illegal move must be refused and the legal
    # two-step path (Accepted -> On The Way) must be accepted. §14
    st, b = call("PUT", f"/api/rescueRequests/{rid}/status", {"status": "on_the_way"})
    check("rescue", "state machine refuses illegal jump", "PUT",
          f"/api/rescueRequests/{rid}/status", st in (400, 409), b, "400/409 refused")

    st, b = call("PUT", f"/api/rescueRequests/{rid}/status", {"status": "Accepted"})
    check("rescue", "status -> Accepted (legal)", "PUT",
          f"/api/rescueRequests/{rid}/status", st == 200, b, "200")

    st, b = call("PUT", f"/api/rescueRequests/{rid}/status", {"status": "On The Way"})
    check("rescue", "status -> On The Way (legal)", "PUT",
          f"/api/rescueRequests/{rid}/status", st == 200, b, "200")

    st, b = call("PUT", f"/api/rescueRequests/{rid}/payment",
                 {"paymentStatus": "paid", "amount": 500, "paymentMethod": "cash"})
    check("rescue", "record payment", "PUT", f"/api/rescueRequests/{rid}/payment", st == 200, b, "200")
    return {"id": rid}


# ─────────────────────────────── 6. admin module
def t_admin(mech, rescue):
    head("Admin module")
    for path in ("/api/admin/requests", "/api/admin/hubs", "/api/admin/mechanics",
                 "/api/admin/users", "/api/admin/zones", "/api/admin/tokens"):
        st, b = call("GET", path)
        check("admin", f"list {path.split('/')[-1]}", "GET", path,
              st == 200 and isinstance(b, list), b, "200 list")

    if mech.get("id") and rescue.get("id"):
        st, b = call("PUT", "/api/admin/assign-mechanic",
                     {"requestId": rescue["id"], "mechanicId": mech["id"]})
        check("admin", "assign-mechanic", "PUT", "/api/admin/assign-mechanic", st == 200, b, "200")

    # zone create + delete (own record only)
    st, b = call("POST", "/api/admin/zones",
                 {"name": RUN_TAG, "latMin": 1, "latMax": 2, "lngMin": 3, "lngMax": 4})
    zid = b.get("zone", {}).get("id") if isinstance(b, dict) else None
    check("admin", "create zone", "POST", "/api/admin/zones", st in (200, 201), b, "200/201")
    if zid:
        st, b = call("DELETE", f"/api/admin/zones/{zid}")
        check("admin", "delete own zone", "DELETE", f"/api/admin/zones/{zid}", st == 200, b, "200")


# ─────────────────────────────── 7. token module
def t_token():
    head("Token module (backend Mongo path)")
    st, b = call("POST", "/api/admin/tokens",
                 {"vehicleId": "TN-00-E2E", "userId": RUN_TAG, "jobId": "", "hubId": ""})
    tid = b.get("token", {}).get("id") if isinstance(b, dict) else None
    check("token", "create token", "POST", "/api/admin/tokens", st in (200, 201), b, "200/201")

    if tid:
        st, b = call("PUT", f"/api/admin/tokens/{tid}/status", {"status": "in_transit"})
        check("token", "update status", "PUT", f"/api/admin/tokens/{tid}/status", st == 200, b, "200")
        st, b = call("PUT", f"/api/admin/tokens/{tid}/release", {"releasedBy": RUN_TAG})
        check("token", "release", "PUT", f"/api/admin/tokens/{tid}/release", st == 200, b, "200")
        st, b = call("DELETE", f"/api/admin/tokens/{tid}")
        check("token", "delete own token", "DELETE", f"/api/admin/tokens/{tid}", st == 200, b, "200")

    note = ("NOTE: this Mongo token carries no tokenCode, so it can never be "
            "verified by the verifyToken Cloud Function (see TOKEN_SYSTEM_MAP.md)")
    print(f"  [INFO] {note}")


# ─────────────────────────────── 8. socket.io realtime
def t_socket():
    head("Socket.IO realtime")
    try:
        import socketio
    except ImportError:
        check("socket", "python-socketio available", "WS", "/socket.io", False,
              "python-socketio not installed", "importable")
        return
    sio = socketio.Client(reconnection=False, request_timeout=10)
    events = []

    @sio.on("*")
    def _catch(event, *args):
        events.append(event)

    try:
        sio.connect(BASE, transports=["polling"], wait_timeout=12)
    except Exception as e:
        check("socket", "connect to /socket.io", "WS", "/socket.io", False,
              f"{type(e).__name__}: {e}", "connected")
        return

    check("socket", "connect to /socket.io", "WS", "/socket.io", True,
          f"sid={getattr(sio, 'sid', '?')}", "connected")

    # Trigger a real server-side broadcast: creating a request emits 'new_request'
    call("POST", "/api/rescueRequests", {
        "name": RUN_TAG + "-socket", "phone": "5550001" + STAMP[-4:],
        "issue": "E2E socket broadcast test", "vehicle": "TN-00-SOCK",
        "location": {"lat": 12.99, "lng": 80.09},
    })
    time.sleep(2.5)
    check("socket", "receive 'new_request' broadcast", "WS", "/socket.io",
          "new_request" in events, f"events seen={events[:6]}", "event received")
    try:
        sio.disconnect()
    except Exception:
        pass


# ─────────────────────────────── main
def main():
    print(f"RoadResQ E2E module test  |  base={BASE}  |  run={RUN_TAG}")
    print("=" * 78)
    t_infra()
    t_user()
    mech = t_mechanic()
    asst = t_assistant()
    rescue = t_rescue(mech, asst)
    t_admin(mech, rescue)
    t_token()
    t_socket()

    passed = sum(1 for r in RESULTS if r["ok"])
    failed = [r for r in RESULTS if not r["ok"]]
    print("\n" + "=" * 78)
    print(f"TOTAL {len(RESULTS)}   PASS {passed}   FAIL {len(failed)}")
    if failed:
        print("\nFAILURES:")
        for r in failed:
            print(f"  - [{r['module']}] {r['step']}  ({r['method']} {r['path']})")
            print(f"      expected {r['expected']} -> {r['detail']}")
    print(f"\nRecords created by this run are tagged {RUN_TAG} and can be cleaned up.")

    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "E2E_TEST_REPORT.md")
    with open(os.path.abspath(out), "w", encoding="utf-8") as fh:
        fh.write(f"# RoadResQ E2E Test Report\n\n")
        fh.write(f"- Base URL: `{BASE}`\n- Run tag: `{RUN_TAG}`\n")
        fh.write(f"- Result: **{passed}/{len(RESULTS)} passed**, {len(failed)} failed\n\n")
        fh.write("| Module | Step | Method | Path | Expected | Result | Detail |\n")
        fh.write("|---|---|---|---|---|---|---|\n")
        for r in RESULTS:
            det = r["detail"].replace("|", "\\|").replace("\n", " ")[:150]
            fh.write(f"| {r['module']} | {r['step']} | {r['method']} | `{r['path']}` | "
                     f"{r['expected']} | {'PASS' if r['ok'] else '**FAIL**'} | {det} |\n")
    print(f"Report written: {os.path.abspath(out)}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
