# RoadResQ — Production Readiness Report

Date: 2026-10-06
Scope: full stack (Flutter client, Flask backend, Firestore, Cloud Functions)

## VERDICT

**NOT production ready.** The backend and data layer are in good shape — 49/49
end-to-end tests pass. The **client authentication layer is not fit to ship**:
three of five roles can be entered without any real credential check, and
hardcoded secrets are compiled into the binary.

Roughly: the engine works, the front door is unlocked.

---

## 1. VERIFICATION LEGEND

Findings are marked by how they were confirmed:

- **[V]** — I verified this myself in this session with a direct tool result
  (grep/read/command output). File:line references are trace-confirmed.
- **[D]** — Reported by a delegated read-only audit, **not** independently
  re-verified by me. Treat as a lead to confirm, not as established fact.

Do not act on a [D] item without confirming it first.

---

## 2. AUTHENTICATION — THE BLOCKING PROBLEM

### 2.1 User (customer) phone login is fake — [V]

`lib/pages/user_login_page.dart`

```dart
:42   generatedOtp = '123456';
:45   SnackBar(content: Text('Demo OTP sent: $generatedOtp'))
:57   if (otp != generatedOtp) { ... 'Invalid OTP' ... }
```

The OTP is generated **on the device** and compared on the device. There is no
network call at all. Anyone can log in as any phone number by typing `123456`.

Confirmed by reading lines 32–63.

**This is trivially fixable** — the backend endpoints already exist and are
covered by passing tests (`POST /api/user/login-otp`, `POST /api/user/verify-otp`). [V]

### 2.2 Garage login performs no authentication — [V]

`lib/pages/garage_login_page.dart:28-50`

```dart
final id = garageIdController.text.trim();
if (id.isEmpty) { _showSnack('Enter your garage ID'); return; }
// ... immediately writes prefs and pushes GarageDashboard
```

No password, no OTP, no backend call, no verification. **Any non-empty string**
grants the garage dashboard, which controls token verification and release.

**This cannot be fixed client-side alone.** I checked the backend route list: [V]

```
=== any GARAGE auth endpoints? ===
>>> NONE - no /api/garage/* routes exist <<<
```

There is **no server-side garage authentication of any kind**. Fixing this
requires building a garage identity + credential store first — it is net-new
backend work, not a bug fix.

### 2.3 Assistant OTP is never actually validated — [V]

`lib/pages/assistant_login_page.dart:70-94`

```dart
Future<void> verifyOtp() async {
  final otp = otpController.text.trim();
  ...
  // Use the same login OTP endpoint - OTP is validated on server
  final response = await _service.loginOtp(phone: phone);
```

The comment claims the OTP is validated on the server, but **`otp` is read and
then never sent**. The call re-triggers the send-OTP endpoint. Any OTP value is
accepted for any phone that exists.

Note: the backend has **no** assistant OTP endpoint — only `/api/assistant/register`
and `/api/assistant/login`. [V] So this needs a decision: reuse
`/api/mechanic/verify-otp`, or add assistant OTP routes.

### 2.4 Hardcoded secrets in the client — [V]

| Secret | Locations |
|---|---|
| Razorpay key `rzp_test_SbTmM0x0VYHxcN` | `lib/services/payment_service.dart:30`, `lib/screens/payment_screen.dart:35`, `lib/core/constants/app_constants.dart:51` |
| Google Maps key `AIzaSyC9-oYH5WgjrauuGzK_XOBqQLDPPIx7WpY` | `lib/screens/request_location_screen.dart:59`, `lib/screens/user_tracking_screen.dart:49` |
| Fixed OTP `'123456'` | `lib/pages/user_login_page.dart:42`, `lib/features/auth/otp_screen.dart:25` |

The Maps key already has a `// TODO: Replace with your actual Google Maps API key`
comment. An unrestricted key is billable abuse waiting to happen; restrict it to
your package name + SHA-1 in Cloud Console.

### 2.5 Additional auth findings — [D] (not re-verified by me)

- No admin login exists anywhere, and `AdminDashboardPage` is never instantiated;
  `/admin/*` APIs exist with no UI path and no auth gate.
- Demo bypasses still compiled in: "Skip Login — Demo Mode", demo
  user/mechanic credentials, a demo phone pre-filled in the assistant login.
- Five separate `AuthService`-style classes exist while the live screens call
  REST directly — logic drift risk.
- `SessionService.restore()` exists but is never called, so no role has
  auto-login; every launch requires a fresh login.

**Confirm these before acting.** They are plausible and consistent with what I did
verify, but I did not read those files myself.

---

## 3. BACKEND (Flask + MongoDB) — HEALTHY

```
RoadResQ E2E module test
TOTAL 49   PASS 49   FAIL 0
```

Covers: infra, user, mechanic, assistant, rescue-request lifecycle, admin, token
module, and a live Socket.IO connect + broadcast round-trip. Re-run after all
changes today: still 49/49.

Test: `backend/tests/e2e_module_test.py` → report at `E2E_TEST_REPORT.md`.

### Defects found and fixed today — [V]

| Defect | Impact | Fix |
|---|---|---|
| `serialize_request` passed `hubId`/`regionId` through as raw Mongo `ObjectId` | 3 endpoints returned **HTTP 500 with an empty body**; the mechanic screen showed a meaningless "JSON error" | `_id_or_none()` in `serializers.py` |
| Emoji `print()` in `/api/mechanic/instant` | cp1252 `UnicodeEncodeError` → HTTP 500. **Instant Access login was dead** | stdout forced to UTF-8; print replaced with `log.info` |
| Emoji `print()` in the Socket.IO `connect` handler | Raised **before** `emit('connected')` → **no client could ever connect** | UTF-8 stdout; `log.info` on the critical path |
| `_error()` reported "Invalid JSON response" for any non-JSON body | Masked every server-side 500 | Now reports `HTTP <code>` + real message |
| Missing `_MongoJSONProvider` | One missed field anywhere = whole endpoint 500 | Global BSON-safe JSON encoder |

---

## 4. DATA LAYER (Firestore) — DEPLOYED

Rules and **32 indexes** are live in project `roadresq-e4b7b`.

### Missing composite indexes found and deployed today — [V]

Each of these would have thrown `FAILED_PRECONDITION` at runtime — the same
silent failure class that broke the garage dashboard:

| Query | Index | Files |
|---|---|---|
| jobs where `userId`, orderBy `createdAt` | `jobs(userId, createdAt)` | `lib/services/job_history_service.dart:45`, `:81` |
| jobs where `status`, orderBy `createdAt` | `jobs(status, createdAt)` | `lib/services/admin_service.dart:245`, `:278` |
| commissions where `crewId`, orderBy `processedAt` | `commissions(crewId, processedAt)` | `lib/services/crew_job_service.dart:291`, `:327` |
| jobs where `garageId`, orderBy `createdAt` | `jobs(garageId, createdAt)` | `lib/features/garage/garage_dashboard.dart:31` |

### Dashboard query bugs fixed — [V]

All three role dashboards queried a `jobs` field that no code writes, and hid the
real error behind "Check internet connection":

| Dashboard | Was querying | Now |
|---|---|---|
| Garage | `assignedGarageId` — written by **no** code path | `garageId` |
| Assistant | `assignedAssistantId` — a **`requests`** field, not `jobs` | `crewId` |
| Mechanic | `status` only, **no identity filter** → unprovable under rules | `+ crewId` |

All three also now `debugPrint` the true exception instead of a generic message.

**Known limitation:** the garage jobs list will legitimately be **empty** until a
job carries `garageId`, which is written only at handover by
`lib/services/garage_service.dart:89`. If a garage should see work assigned for
repair, something must write `garageId` earlier. Data-model decision, not a bug.

---

## 5. CLOUD FUNCTIONS — CODE FIXED, DEPLOY BLOCKED ON BILLING

### Deploy blocker — [V]

```
Error: Billing account for project '47837867447' is not open.
       Billing must be enabled for activation of service(s)
       'artifactregistry.googleapis.com' to proceed.
```

Requires attaching a billing account (Blaze). Only you can do this.

**14 functions the app calls** (dispatch, payments, SOS, invoicing, token verify,
offline queue, emergency SMS) are therefore all non-functional in this
environment. Note the **Firestore** work deploys fine — only Functions need billing.

### Code defects found and fixed today — [V]

1. **The module could not load at all.** `functions/index.js` read
   `functions.config().razorpay.key_id` at module scope. `functions.config()`
   returns `{}` when unset, so `.razorpay` is `undefined` and `.key_id` threw —
   taking **all 27 functions** down, not just payments:

   ```
   LOAD FAILED: Cannot read properties of undefined (reading 'key_id')
       at Object.<anonymous> (functions/index.js:39:38)
   ```

   The intended `|| fallback` never applied — the throw happens first.
   **This would have failed the deploy even with billing enabled.** Now read
   defensively (env var → legacy config → fallback).

2. **Two functions were silently unregistered.** `require("./tokenEngine")` does
   *not* register `generateToken`: `exports.x = ...` inside a sub-module sets that
   module's exports, while Firebase only deploys handlers on the **entry point's**
   `module.exports`. A load test caught `generateToken` still missing, and
   `checkZoneSecurity` missing the same way. Fixed with
   `Object.assign(exports, require(...))` for both.

   ```
   Before: module crashed            → 0 exports
   After : 28 exports registered, all 14 Dart-called callables present
   ```

### Still open — [D]

- `functions/index.js:947` logs a live SOS OTP + phone number; `:953` returns the
  OTP in the response ("Dev-only: return the OTP").
- Emergency SMS is queued but never sent (`:685-689`, "requires Twilio integration").
  **Safety-critical** for an emergency-response app.
- Escalation only `console.log`s instead of notifying (`:872-874`).

---

## 6. DEPENDENCIES & SECURITY

### npm advisories — [V]

```
packages with advisories: 36   {critical: 1, high: 11, moderate: 24}
```

The critical is `protobufjs` (prototype pollution / code injection), transitive via
`google-gax` ← `@google-cloud/firestore` ← `firebase-admin`.

Installed: `firebase-admin@11.11.1`, `firebase-functions@4.9.0`, `razorpay@2.9.8`, `uuid@9.0.1`. [V]

**I did not upgrade these, deliberately.** The fix is `firebase-admin@14`, a
semver-major bump that forces a coordinated migration: `firebase-admin` 11→14,
`firebase-functions` 4→6 (v6 drops `functions.config()`, used in this file), and
API changes across payment-handling code. Crucially, **I cannot deploy or test the
result** while billing is blocked — an unverifiable major upgrade of payment code
is a worse risk than this advisory.

My assessment of exploitability: **low.** `protobufjs`'s vulnerable paths involve
attacker-controlled protobuf *schemas*, and this app only parses protobuf from
Google's own Firestore/gRPC APIs. No end user supplies a schema.

**Do the upgrade as part of the billing-enabled deploy**, where it can be tested.

### Firestore rules warning — [V]

```
[W] 26:14 - Unused function: isValidLocation.
```

Pre-existing, harmless.

---

## 7. WHAT I DID NOT CHANGE, AND WHY

| Item | Why not |
|---|---|
| `firebase-admin`/`firebase-functions` major upgrade | Cannot deploy or test it (billing); touches payment code |
| Auth redesign (user/garage/assistant login) | Needs product decisions: whose credential store, which mechanism. Garage has **no** backend auth to call |
| Wiring `garageId` at assignment time | Data-model decision |
| Removing demo bypasses / dead login screens | Needs confirmation they are unused on every branch you ship |
| `firestore_service.dart:156,217` | Dynamic `orderBy` — index needs caller-by-caller review, not guessing |
| `npm audit fix` | Would swap versions under payment/commission code |

---

## 8. PATH TO PRODUCTION (priority order)

1. **Fix user phone login** — replace the client-side `123456` check with
   `POST /api/user/login-otp` + `POST /api/user/verify-otp`. Endpoints exist and
   are test-covered. Highest impact, lowest effort.
2. **Fix assistant OTP** — actually send the entered OTP to a verify endpoint.
   Requires reusing `/api/mechanic/verify-otp` or adding assistant routes.
3. **Build garage authentication** — net-new backend work; the client has nothing
   to authenticate against today.
4. **Enable billing (Blaze)** → `firebase deploy --only functions`. Unblocks 14
   features at once.
5. **Rotate + externalise secrets** — remove Razorpay/Maps keys from source;
   restrict the Maps key by package + SHA-1; move Razorpay to
   `firebase functions:secrets:set`.
6. **Strip dev bypasses** — Demo Mode, demo credentials, returned OTPs, OTP logging.
7. **Implement emergency SMS** — currently queued, never sent. Safety-critical.
8. **Firebase SHA-1 registration** — add debug fingerprint
   `BD:FC:FC:5E:27:BC:19:91:07:4C:EB:61:DE:E7:5D:FC:6E:E3:35:A9` for
   `com.example.roadresq` in project `roadresq-e4b7b`, so Firebase Phone Auth works.
9. **Decide a migration window** for the `firebase-admin` upgrade.
10. **Add version control** — this project has no git; today's edits have no
    rollback beyond `roadresq_lib_backup_pre-cleanup.zip`.
