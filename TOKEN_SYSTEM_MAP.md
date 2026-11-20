# RoadResQ Token System — Implementation Map

Answer to: *"Is a token generating system implemented?"* — **Yes, but it is implemented four
times over three storage backends, and only two of the four are verifiable.**

This map names the authoritative path, shows exactly which implementations are
incompatible (and why), and lists what should be retired.

---

## 1. The three distinct "token" concepts

| # | Concept | Purpose | Authoritative location |
|---|---------|---------|------------------------|
| 1 | **Vehicle handover token** | 6-char code + QR for garage drop-off/pickup | Cloud Functions (Firestore) |
| 2 | **Auth token** | Session auth after login | `backend/auth.py` |
| 3 | **SOS OTP** | Emergency one-time code | `functions/index.js` |

Only concept 1 is fragmented. Concepts 2 and 3 are clean, single-source and should be left alone.

---

## 2. Concept 1 — the four vehicle-token implementations

### Authoritative pair

* **Generation:** `functions/tokenEngine.js` → callable `generateToken`
* **Verification:** `functions/index.js:688` → callable `verifyToken`

`verifyToken` is what the app actually calls, so **whatever `verifyToken` can read defines
what a valid token is.** It queries Firestore:

```js
db.collection("tokens").where("tokenCode", "==", tokenCode)
```

and inside a transaction it:

* rejects if `consumedAt` is already set (one-time use / anti-replay)
* rejects if `expiresAt` has passed
* marks `consumedAt`, `status: "consumed"`, `consumedBy`

So a valid token **must** be a document in **Firestore `tokens`** carrying a **`tokenCode`**,
and expiry only works if **`expiresAt`** is present.

### Compatibility matrix

| Implementation | Store | Identity | writes `tokenCode`? | writes `expiresAt`? | Verifiable by `verifyToken`? |
|---|---|---|---|---|---|
| `functions/tokenEngine.js` | Firestore `tokens` | 6-char code | ✅ | ✅ *(added 2026-10-06)* | ✅ **authoritative** |
| `lib/providers/token_provider.dart` | Firestore `tokens` | 6-char code | ✅ | ✅ (30 min) | ✅ compatible |
| `lib/services/token_service.dart` | **Realtime DB** `tokens/{uuid}` | UUID v4 | ❌ | ❌ | ❌ **can never verify** |
| `backend/roadresq_backend.py:1208` | **MongoDB** `tokens` | Mongo `_id` | ❌ | ❌ | ❌ **can never verify** |

### Why the bottom two can never verify

`lib/services/token_service.dart` writes to the **Realtime Database** under
`tokens/{tokenId}` where `tokenId` is a `uuid.v4()` — there is no `tokenCode` field at all,
and it is not Firestore. `verifyToken` queries a *different database* by a *field that does
not exist*. The same is true of the MongoDB route, which stores only
`vehicleId/userId/jobId/hubId/status`.

**Both are wired into live screens**, so this is a real defect, not just dead code:

* `lib/screens/rescue_request_screen.dart:146` → `TokenService.generateToken()` (Realtime DB)
* `lib/screens/admin_dashboard_page.dart:257` → `ApiService.createToken()` (MongoDB)

A token minted from either screen **cannot be scanned and verified at the garage.**

### Who calls what

**Generation**

| Caller | Path | State |
|---|---|---|
| `lib/services/crew_job_service.dart:209` | `httpsCallable('generateToken')` | was broken (function unregistered) — **fixed 2026-10-06** |
| `lib/features/crew/token_generator.dart:60` | `tokenProvider.generateToken()` → Firestore direct | works, bypasses Cloud Function |
| `lib/features/crew/assistant_dashboard.dart:42` | `tokenProvider.generateToken()` → Firestore direct | works, bypasses Cloud Function |
| `lib/screens/rescue_request_screen.dart:146` | `TokenService.generateToken()` → Realtime DB | **broken path** |
| `lib/screens/admin_dashboard_page.dart:257` | `ApiService.createToken()` → MongoDB | **broken path** |

**Verification**

| Caller | Path | State |
|---|---|---|
| `lib/features/garage/garage_scanner.dart:61` | `tokenProvider.validateTokenCode()` → `verifyToken` CF | ✅ correct |
| `lib/providers/token_provider.dart:217` | `httpsCallable('verifyToken')` | ✅ correct |
| `lib/services/garage_service.dart:47` | `httpsCallable('verifyToken')` | ✅ correct |

The verification side is consistent — every verifier funnels through the one Cloud Function.
The fragmentation is entirely on the **generation** side.

---

## 3. Recommended target architecture

```
generateToken (Cloud Function)  ──┐
                                  ├──►  Firestore "tokens"  ◄── verifyToken (Cloud Function)
tokenProvider.generateToken()   ──┘        (tokenCode, expiresAt)         ▲
                                                                          │
                                                        garage_scanner / garage_service
```

**Keep:** `functions/tokenEngine.js` as the single generation entry point; `verifyToken` as the
single verifier; `token_provider.dart` only as a *client for* the Cloud Function, not as a
second writer.

**Retire:**

1. `lib/services/token_service.dart` — Realtime DB + UUID. Migrate
   `rescue_request_screen.dart` onto the Cloud Function.
2. The MongoDB token routes (`backend/roadresq_backend.py:1198–1255`) — no `tokenCode`, so
   unverifiable. Keep only if an admin *reporting* need exists, and then treat the records as
   metadata rather than tokens.
3. The direct-Firestore write inside `tokenProvider.generateToken()` — route it through the
   Cloud Function so auth + uniqueness + expiry are enforced server-side in one place.

---

## 4. Changes applied 2026-10-06

| # | File | Change | Why |
|---|------|--------|-----|
| 1 | `functions/index.js` | `Object.assign(exports, require("./tokenEngine"))` — and the same for `zoneSecurityEngine` | Sub-module exports never reach the entry point, so `generateToken` **and** `checkZoneSecurity` were unregistered; the client call at `crew_job_service.dart:209` would fail NOT_FOUND. A bare `require()` fixes nothing — that was the first attempt, and a load test caught that `generateToken` was still missing from the exports. |
| 2 | `functions/tokenEngine.js` | `Math.random()` → `crypto.randomInt()` | The code authorises a physical vehicle handover; it must not be predictable from previously issued tokens |
| 3 | `functions/tokenEngine.js` | Now writes `expiresAt` (+30 min), `consumedAt: null`, `issuedFor` | `verifyToken` **skips** its expiry check when `expiresAt` is absent — without this, wiring the function would have produced tokens that never expire |
| 4 | `lib/providers/token_provider.dart:67` | `Random()` → `Random.secure()` | Same CSPRNG requirement on the client-side generator |

Verified: `node --check` passes on both JS files; `flutter analyze` clean on the Dart change;
generator produces 6-char codes, no `I/O/0/1` confusables, 32-char alphabet
(keyspace 1,073,741,824); expiry simulation valid at 0 min and EXPIRED at +31 min.

---

## 5. Open items

1. **Deployment is NOT done.** `generateToken` only becomes callable after
   `firebase deploy --only functions` against project `roadresq-e4b7b`. This was deliberately
   left to you — it pushes to a live Firebase project.
2. **Decide the fate of the two broken generator paths** (Realtime DB, MongoDB). Until they are
   migrated or removed, QR tokens originating from Rescue Request and the Admin Dashboard
   cannot be verified.
3. **`verifyToken` assumes `expiresAt` exists.** A safer form than
   `if (expiresAt && now > expiresAt)` would be to *reject* a token that has no `expiresAt`,
   so a future generator cannot silently produce non-expiring tokens again.
4. **Two DB handles in one file:** `backend/roadresq_backend.py` reads tokens via
   `rq_db.tokens()` but writes via `db["tokens"]`.
5. **Schema drift:** `token_service.dart` uses lifecycle `created → in_transit → at_hub →
   released`; everyone else uses `generated → handed_to_garage → repair_started →
   ready_for_pickup → closed` (+ `consumed`).
6. **QR is never produced on the client:** `token_provider.dart` writes `'qrUrl': ''` with the
   note *"QR would be generated client-side via qr_flutter"*. The Cloud Function is the only
   path that returns a real `qrData` URL.
