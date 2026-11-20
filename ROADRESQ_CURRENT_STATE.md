# ROADRESQ — CURRENT IMPLEMENTATION AUDIT

**Audit date:** 2026-10-05
**Repository:** `roadresq/` (Flutter client + Flask/MongoDB backend + legacy Firebase artefacts)
**Method:** Full static inspection of `lib/**` (159 Dart files), `backend/*.py`, `functions/index.js`; `flutter analyze` run on the real tree; import/reference graph rebuilt to separate live code from dead code. No file was modified to produce this audit.

---

## 1. VERIFIED TOOLCHAIN STATE

| Component | Observed | Notes |
|---|---|---|
| Flutter | 3.41.4 stable (2026-03-03) | Works |
| Dart SDK | 3.11.1 | Works |
| Python (default `python`) | 3.12.2 | **Flask stack NOT installed** |
| `py -3.14` | 3.14 | present |
| MongoDB service (`MongoDB`) | **Running** | Windows service confirmed live |
| `flutter analyze` | **0 errors**, 31 issues (all `warning`/`info`) | Project compiles |

**Conclusion:** the Flutter app compiles cleanly. There are **no compile-blocking errors**. The real defects are *behavioural*, *security*, *architectural* and *missing-feature* defects, not syntax errors.

---

## 2. ACTUAL ARCHITECTURE (as-built, not as-documented)

```
main.dart
 └─ SplashScreen                     lib/screens/splash_screen.dart
     └─ RoleSelectionScreen          lib/screens/role_selection_screen.dart
         ├─ UserLoginPage            lib/pages/user_login_page.dart
         │   └─ UserMainScreen       lib/screens/user_main_screen.dart  (5 tabs)
         ├─ MechanicLoginPage        lib/pages/mechanic_login_page.dart
         │   └─ MechanicMainScreen   lib/screens/mechanic_main_screen.dart (4 tabs)
         ├─ GarageLoginPage          lib/pages/garage_login_page.dart
         │   └─ GarageDashboard      lib/features/garage/garage_dashboard.dart
         └─ AssistantLoginPage       lib/pages/assistant_login_page.dart
             └─ AssistantMainScreen  lib/screens/assistant_main_screen.dart
```

**The live stack is Flutter → Flask → MongoDB.** `main.dart` uses `MaterialApp(home: SplashScreen())`, **not** `GoRouter`.

`lib/core/router/app_router.dart` (GoRouter) is **never referenced by `main.dart`** — the entire `go_router` subgraph is dead.

### Discrepancy: README describes a different product
`README.md` documents a **Firebase** backend (Firestore, Cloud Functions, FCM, `dispatchTwoManCrew`, 2-Man Crew, Digital Token, Zone Security). The **running** backend is Flask + MongoDB. The README is materially out of date with the code and must be corrected before it is used as evidence for review.

The "2-Man Crew / Digital Token / Zone Security" patents are implemented only against Firebase (mostly in `functions/index.js` and dead Dart services), **not** in the live Flask backend.

---

## 3. LIVE API SURFACE — Flask backend

`backend/roadresq_backend.py` — 1436 lines, single file, `port 5050`, `debug=True`, `0.0.0.0`.

| Group | Endpoints | Status |
|---|---|---|
| Basic | `GET /`, `/health`, `/db-test` | Working |
| User auth | `POST /api/user/signup`, `/login`, `/login-otp`, `/verify-otp` | Working (insecure — see §6) |
| Mechanic auth | `POST /api/mechanic/register`, `/login`, `/login-otp`, `/verify-otp`, `/instant` | Working (insecure) |
| Mechanic state | `PUT /api/mechanic/<id>/online`, `/location`; `GET /api/mechanic/<id>/requests` | Working |
| Assistant | `POST /api/assistant/register`, `/login`; `GET /api/assistant/<id>/jobs`; `PUT /api/assistant/<id>/online`, `/location` | Working |
| Rescue | `GET/POST /api/rescueRequests`; `GET /api/rescueRequests/available`; `GET /api/rescueRequests/<id>` | Working |
| Rescue write | `PUT /api/rescueRequests/<id>/assign`, `/status`, `/payment`, `/mechanic-location`, `/assign-assistant`, `/assistant-location` | Working (no guards) |
| Admin | `GET /api/admin/{requests,mechanics,hubs,users,tokens,zones}`, `PUT /api/admin/assign-mechanic`, `POST /api/admin/tokens`, `PUT /api/admin/tokens/<id>/status|release`, `POST/DELETE /api/admin/zones`, `DELETE /api/admin/users/<id>`, `DELETE /api/admin/tokens/<id>` | Working |
| Socket.IO | `connect`, `disconnect`, `mechanic_online`, `mechanic_location_update`, `accept_request`, `complete_request`, `assign_assistant`, `assistant_location_update`, `assistant_status_update`, `new_request_created`, `new_request`, `status_updated`, `request_assigned`, `payment_updated`, `update_location`, `crew_online`, `assistant_online`, `escalate_request`, `backup_crew_notification` | Working |

**Transport note:** `async_mode="threading"` means **HTTP long-polling only**. `socket_service.dart` correctly requests `transports: ['polling']`.

### MongoDB collections actually used
`rescue_requests`, `mechanics`, `users`, `hubs`, `tokens`, `zones` — all under database `roadresq_db`.

**No indexes are created anywhere.** There are no regions/allocation/payment/rating/notification/support collections.

---

## 4. LIVE FLUTTER LAYER

**Wired services** (imported by live screens): `api_service`, `socket_service`, `assistant_service`, `activity_service`, `live_tracking_service`, `notification_service`, `token_service`, `crew_dispatch_service` (lib/), `zone_security_service`, `offline_queue_service`, `payment_split_service`, `firestore_service` (Firebase).

**Tab structure**

| User (`user_main_screen.dart`) | Mechanic (`mechanic_main_screen.dart`) |
|---|---|
| 0 Home → `screens/user_home_screen.dart` | 0 Home → `mechanic_home_screen.dart` |
| 1 Track → `request_status_screen.dart` (only if `last_request_id` set) | 1 History → `mechanic_history_screen.dart` |
| 2 History → `my_requests_screen.dart` | 2 Passbook → `mechanic_passbook_screen.dart` |
| 3 Support → `support_center_screen.dart` | 3 Profile → `profile_screen.dart` |
| 4 Profile → `profile_screen.dart` | |

There is **no Admin entry point** in the running app. `admin_dashboard_page.dart` exists but is **orphaned** — it is not reachable from `main.dart`. Admin is effectively API-only today.

---

## 5. CLASSIFICATION OF THE CURRENT STATE

### ✅ COMPLETED (works, verified in code)
- Splash → role selection → 4 role logins → 3 dashboards + garage, all navigable.
- Flask + MongoDB CRUD for rescue requests; request create/list/get/assign/status/location.
- Socket.IO server + client with reconnect, timeout guard, exponential backoff, offline callback, and a dev host selector (`useEmulator()` / `useLanHost()` / `setSocketHost()`).
- `ApiService` REST client covering all live Flask endpoints.
- Socket event surface fully wired on both sides (server handlers added for the frontend-emitted events).
- Material 3 theming with a working light/dark `ThemeController`.
- Real-time mechanic/assistant location fan-out to user screens.
- `flutter analyze`: 0 errors.

### 🟡 PARTIALLY COMPLETED
- **Authentication** — email/password works end-to-end; phone+OTP exists but is a *local demo* on the user side. No session token, no role guard, no ownership check.
- **Payment** — a `PUT /payment` status write exists and a Razorpay UI exists in `payment_screen.dart`, but there is **no order creation, no server-side signature verification, no payments collection**.
- **Tracking** — location updates flow, but `PUT /mechanic/<id>/location` does **not** emit a socket event while `PUT /rescueRequests/<id>/mechanic-location` does (inconsistent real-time).
- **Garage flow** — `garage_login_page.dart` never calls a backend; it writes to `SharedPreferences` only.
- **Assistant flow** — `assistant_signup_page.dart` returns to login instead of entering the dashboard.
- **Mechanic signup** — routes to `MechanicHomeScreen(mechanicId: 'new_mechanic_demo', ...)`, a **hardcoded demo id**.

### 🔴 BROKEN / DEFECTIVE
1. **Password disclosure (security bug).** `serialize_mechanic()` (line 95) and `serialize_user()` (line 110) return `"password": doc.get("password","")` in API responses. `/api/admin/mechanics`, `/api/mechanic/login`, `/api/mechanic/register`, `/api/admin/users` (user path strips it, login does not) all leak stored credentials.
2. **Passwords stored in plaintext.** No hashing anywhere in the backend.
3. **No authorisation.** Any client can `PUT /api/rescueRequests/<id>/assign` or `/status` or `/payment` for **any** request. No identity is established or checked. Violates the ownership requirements (§39).
4. **No status-machine validation.** `PUT /status` writes whatever string is posted — arbitrary/invalid states are accepted, and there is no transition guard (§14, §38).
5. **Duplicate rescue requests allowed.** Nothing prevents repeated submissions (§40).
6. **`GET /api/mechanic/<id>/requests` is wrong.** It returns *all* requests in `Assigned/Accepted/...` states, not that mechanic's requests — every mechanic sees every assigned job.
7. **`/api/admin/tokens` returns the password field** and mutates `d["_id"]` before re-reading it into `"id"`, so `id` never equals the original `_id`.
8. **Two unused allocation functions.** `_findBestCrew` (`dispatch_provider.dart:246`) and `_createJob` (`dispatch_provider.dart:309`) are never called — **the dispatch/allocation path is dead code**.
9. **`users`/`mechanics` collections diverge from spec** — no `role`, verification, region, hub, service capability, or availability fields exist on the live documents.

### 🟠 PLACEHOLDER / DEMO
- Hardcoded demo OTP `"1234"` returned by `/user/login-otp`, `/user/verify-otp`, `/mechanic/login-otp`, `/mechanic/verify-otp` (lines 243, 256, 369, 382).
- `/api/mechanic/instant` grants access with an **empty password** and no verification.
- `user_login_page.dart` OTP is **entirely client-side** (`generatedOtp = '123456'`) — it never calls the backend.
- `otp_screen.dart` accepts **any** 6-digit OTP (`if (otp.length < 4) throw`).
- `core_session_service.dart` hardcodes OTP `999999` and signs in anonymously.
- `login_screen.dart` has `loginAsDemoUser()` / `loginAsDemoMechanic()` with fake ids `demo_user_001` / `demo_mechanic_001`.
- `diagnose_screen.dart` fabricates an "AI diagnosis": `Random().nextInt(...)` + `confidence = 0.82 + Random().nextDouble()*0.17`. **This is a random number generator presented as AI.**
- `recent_activity_screen.dart` renders a hardcoded placeholder activity list.
- 9 "novel" modules fabricate sample data (`_sampleJobs()`, `_sampleZones()`, `sampleEstimate()`, `_defaultTrend()`, `sampleReport()`).
- ETA is computed from hardcoded assumed speeds (`request_status_screen.dart:316` `km/30*60`, `:378` `km/50*60`).

### ⛔ NOT IMPLEMENTED (spec-critical gaps)
Per the master prompt, **entirely absent** from the live Flask backend:

| Spec § | Feature | State |
|---|---|---|
| §14 | Rescue request **status machine** | Absent |
| §15–19 | **Regional mechanic allocation engine** (eligibility filter, explainable ranking, allocation logging) | **Absent — the central research contribution** |
| §16 | Regions/hubs as data + region resolution from GPS | Only a bare `hubs` collection with no logic |
| §29–30 | Razorpay **order + server-side verification**, configurable pricing | Absent |
| §31 | Ratings & reviews collection + aggregation | Absent |
| §34 | Admin dashboard **metrics** (computed from real data) | Absent |
| §36 | MongoDB **indexes** | Absent |
| §38 | Consistent JSON error envelope + validation | Partial |
| §42 | Explicit dev/demo mode separation | Absent |
| §45–46 | Experiment scenarios + **CSV research export** | Absent |
| §24–26 | Voice guidance (TTS), SOS flow | Service files exist but are **dead code** |
| §27–28 | AI fault detection / image upload | Absent (random stub only) |

### 🔵 RESEARCH-CRITICAL
The single most important missing component is the **GPS-based regional mechanic allocation pipeline** (§15, §53). Today, "allocation" is a manual `PUT /assign` with a `mechanicId` posted by the client, plus an orphaned `_findBestCrew` that nothing calls. There is:
- no eligibility filtering,
- no service-compatibility check,
- no region/hub gating,
- no workload/availability model,
- no explainable ranking output,
- no `allocation_logs` record,
- no measured assignment latency.

Therefore **no experiment in §45 can currently be run and no journal metric in §46 can currently be produced.** This is the blocker for the research deliverables.

---

## 6. SECRETS / HARDCODED VALUES INVENTORY

**Hardcoded credentials**
| File:line | Value |
|---|---|
| `backend/roadresq_backend.py:10` | `SECRET_KEY = 'roadresq-secret-key'` |
| `backend/roadresq_backend.py:26` | `mongodb://localhost:27017/` (no auth) |
| `lib/firebase_options.dart:44,55,64,74,84` | 5 Firebase `apiKey` literals |
| `lib/screens/request_location_screen.dart:59` | Google Maps key `AIzaSyC9-...` |
| `lib/screens/user_tracking_screen.dart:49` | Google Maps key `AIzaSyC9-...` |
| `lib/core/constants/app_constants.dart:51`, `lib/services/payment_service.dart:30`, `lib/screens/payment_screen.dart:35` | Razorpay key `rzp_test_SbTmM0x0VYHxcN` |
| `functions/index.js:31,32,1896,1921` | Razorpay `key_secret` fallback `"test_secret"` |

**Hardcoded dev hosts (must be centralised — §4)**
| File:line | Value |
|---|---|
| `lib/services/api_service.dart:8` | `http://192.168.31.206:5050/api` |
| `lib/services/socket_service.dart:26` | `http://192.168.31.206:5050` |
| `lib/services/socket_service.dart:32` | `http://10.0.2.2:5050` |
| `lib/crew_dispatch_service.dart:10` | `http://10.0.2.2:5050/api` |
| `lib/core/services/backend_auth_service.dart:28` | `http://192.168.31.206:5050/api` |
| `lib/core/constants/api_endpoints.dart:8` | `https://us-central1-roadresq-e4b7b.cloudfunctions.net` |

`main.dart` already supports `--dart-define=ROADRESQ_HOST=` / `ROADRESQ_EMULATOR`, but **only the socket host honours it**; `ApiService.defaultBaseUrl` remains a separate hardcoded constant. They can silently diverge.

---

## 7. DEAD CODE

**~110 of 159 Dart files under `lib/` are unreachable from `main.dart`.** Verified by following every `import` and every navigation target from the entry point.

Highlights:
- Entire `lib/providers/**` tree (8 core + 9 novel) — **zero** providers are used. Riverpod is a dependency but the live app uses `setState` + direct service calls.
- Entire `lib/screens/novel/**` (10 files) and their models/services/providers.
- Entire `lib/features/**` except `garage/garage_dashboard.dart`.
- `lib/core/router/app_router.dart`, `core/services/*`, `core/utils/{validators,error_handler,geohash}.dart`.
- `lib/screens/admin_dashboard_page.dart` — **the admin UI exists but is unreachable.**
- `lib/services/{payment_service, payment_gateway_service, admin_service, crew_job_service, garage_service, rating_service, chat_service, voice_service, storage_service, core_session_service, user_sos_service, job_history_service, realtime_service, sensor_service, push_notification_service, location_service, sos_security_service, assistant_service_stub}.dart`.
- Root-level `crew_dispatch_service.dart` — **0-byte empty file**, duplicate of `lib/crew_dispatch_service.dart`.
- `backend/assistant_api_patch.py` — doc-only stub, not part of the running backend.

**Duplicate implementations (live vs dead):**
| Concept | Live | Dead |
|---|---|---|
| Role selection | `screens/role_selection_screen.dart` | `features/auth/role_selection.dart`, `features/auth/role_selection_screen.dart` |
| Login | `pages/*_login_page.dart` | `screens/login_screen.dart`, `features/auth/login_screen.dart` |
| User home | `screens/user_home_screen.dart` | `features/user_home_screen.dart`, `features/user/user_home_screen.dart` |
| Auth service | `services/api_service.dart` | `services/auth_service.dart`, `core/services/auth_service.dart`, `features/auth_service.dart` |
| Crew dispatch | `services/crew_dispatch_service.dart` | root `crew_dispatch_service.dart` (empty) |
| Assistant | `services/assistant_service.dart` | `services/assistant_service_stub.dart` |

---

## 8. TOP-RANKED DEFECTS (fix order per §50/§56)

| # | Defect | Severity | Phase |
|---|---|---|---|
| 1 | Passwords returned in API responses + stored in plaintext | Critical | 1 |
| 2 | No authorisation / ownership checks on rescue mutations | Critical | 1 |
| 3 | No status-machine validation | High | 1 |
| 4 | Duplicate request creation possible | High | 1 |
| 5 | `GET /mechanic/<id>/requests` returns all requests | High | 1 |
| 6 | Hardcoded dev host split across two constants that can diverge | High | 1 |
| 7 | No indexes | Medium | 1 |
| 8 | `/api/mechanic/<id>/location` emits no socket event | Medium | 3 |
| 9 | **Regional allocation engine + logging absent** | **Critical (research)** | 2 |
| 10 | Regions/hubs have no logic | High | 2 |
| 11 | Payments have no order/verification | High | 4 |
| 12 | Ratings absent | Medium | 4 |
| 13 | Admin metrics absent; admin UI unreachable | Medium | 4/7 |
| 14 | No experiment export | High (research) | 7 |
| 15 | ~110 dead files obscure the real app | Medium | continuous |

---

## 9. WHAT MUST NOT BE DONE (per §51 — recorded as constraints)

- Do not migrate off Flutter/Flask/MongoDB.
- Do not fabricate results, ratings, GPS, or "payment successful".
- Do not claim AI where the code is `Random()`.
- Do not present the demo OTP as production authentication.
- Do not claim the allocation is optimised beyond what the code measures.
- Do not break the existing frontend/backend contract.

---

## 10. SUMMARY

RoadResQ has a **working end-to-end skeleton**: role selection, four login surfaces, three dashboards, a Flask/MongoDB backend, Socket.IO real-time plumbing, and a compiling Flutter app with zero analyzer errors.

It is **not yet a roadside-assistance platform with an allocation engine**. The research contribution of the master prompt — regional, availability-aware, service-compatible mechanic allocation with explainable ranking and logged evidence — **does not exist in the running system**. Authentication is insecure and unguarded, payments are unverified, ratings and admin metrics are absent, and roughly 70% of the repository is unreachable code.

The next phase must therefore be: **secure and validate the core → build the allocation engine → wire real-time → transaction → admin/analytics → experiment logging.** See `ROADRESQ_IMPLEMENTATION_ROADMAP.md`.
