# ROADRESQ — IMPLEMENTATION ROADMAP

**Created:** 2026-10-05
**Baseline:** `ROADRESQ_CURRENT_STATE.md` (audit complete, `flutter analyze` = 0 errors)
**Rule:** incremental and additive. The existing working frontend/backend contract is never broken. Every phase ends with a test + a report in the format of §55.

Legend: `[ ]` not started · `[~]` in progress · `[x]` done

---

## PHASE 1 — STABILISE THE CORE

*Goal: make the existing skeleton safe, valid, and correctly configured. No new product features.*

### 1.1 Configuration & secrets (spec §4, §39)
- [ ] `backend/config.py` — single source of truth; reads `MONGO_URI`, `DB_NAME`, `SECRET_KEY`, `RAZORPAY_KEY_ID/SECRET`, `ALLOCATION_*` weights, `DEV_MODE` from environment. No literals in route code.
- [ ] `backend/.env.example` — documents every variable.
- [ ] Remove the `SECRET_KEY` literal from `roadresq_backend.py`.
- [ ] Dart: `lib/core/config/app_config.dart` — **one** resolver for the API/socket host (`--dart-define=ROADRESQ_HOST`, `ROADRESQ_EMULATOR`, platform default). `api_service.dart` and `socket_service.dart` both consume it so they can never diverge.

### 1.2 Authentication hardening (spec §7, §8, §39)
- [ ] `backend/auth.py` — password hashing (PBKDF2/`werkzeug`), `issue_token` / `verify_token`, `@require_role`, `@require_owner`.
- [ ] Strip `password` from **all** serializers (`serialize_mechanic`, `serialize_user`) and from `/api/admin/tokens`.
- [ ] Login responses return a signed token; mutating rescue endpoints require it.
- [ ] Ownership guards: a user may only mutate their own request; a mechanic may only act on a request assigned to them.
- [ ] Label the demo OTP explicitly as `dev_otp` and gate it behind `DEV_MODE` (spec §42).

### 1.3 Domain correctness
- [ ] `backend/status_machine.py` — explicit states + legal transitions (§14) + failure states; `PUT /status` validates and returns 409 on illegal transition.
- [ ] Duplicate-request guard: reject an identical open request from the same phone within a configurable window (§40).
- [ ] Fix `GET /api/mechanic/<id>/requests` to filter by that mechanic only.
- [ ] Consistent JSON error envelope everywhere: `{"success": false, "message": ..., "code": ...}` (§38).
- [ ] `backend/db.py` — create all MongoDB indexes (§36): mechanic location, region/hub, online status, request status, `createdAt`, unique email/phone.

**Exit criteria:** password leak gone, all mutations guarded, illegal transitions rejected, duplicates rejected, indexes created, app still compiles.

---

## PHASE 2 — THE CORE RESEARCH FEATURE (highest value)

*Goal: implement §15–19 — the contribution the journal paper rests on.*

### 2.1 Regional network as data (spec §16)
- [ ] `regions` collection: name, city, centroid, boundary (bbox or GeoJSON polygon), search radius, escalation radius.
- [ ] `hubs` collection: `regionId`, name, location, services offered.
- [ ] `backend/geo.py` — haversine distance, bbox/polygon containment, `resolve_region(lat,lng)`.
- [ ] Mechanic document gains: `regionId`, `hubId`, `services[]`, `vehicleTypes[]`, `verified`, `available`, `currentRequestId`, `workload`, `rating`, `ratingCount`, `completedRescues`, `locationUpdatedAt`.

### 2.2 Eligibility filtering (spec §17)
- [ ] `backend/allocation.py::filter_eligible()` — keep a mechanic only if
      `verified AND online AND available AND service_compatible AND location_available AND region_compatible`.
- [ ] City-wide → region → escalation-radius region expansion when the set is empty.
- [ ] Never silently assign an ineligible mechanic; record the rejection reason per candidate.

### 2.3 Explainable ranking (spec §18)
- [ ] `backend/allocation.py::rank_candidates()` — transparent score:
      `proximity + service_match + availability + verification + workload + rating`, weights **configurable** via env, **no fabricated scientific validation**.
- [ ] Every decision emits per-candidate evidence:
      `distanceMeters, online, available, serviceCompatible, verified, workload, sameRegion, score, rank`.
- [ ] Distance component uses a documented decay (e.g. `1 - d/radius`, clamped) and ETA from a configured average speed.

### 2.4 Allocation logging (spec §19)
- [ ] `allocation_logs` collection: `requestId`, `regionId`, `hubId`, `candidateCount`, `eligibleCount`, `candidates[]` (with rejection reason), `selectedMechanicId`, `assignmentTimeMs`, `acceptanceTimeMs`, `status`, `failureReason`, `createdAt`.
- [ ] Persist one record per allocation attempt, including **failures** (`NO_MECHANIC_AVAILABLE`).

### 2.5 API (spec §37)
- [ ] `POST /api/allocation/find` — run filter→rank→assign, return the chosen mechanic **plus the full explainability payload**.
- [ ] `GET /api/allocation/<request_id>` — return the allocation log for that request.
- [ ] `POST /api/mechanic/<id>/accept` and `/decline` — record acceptance latency; decline re-triggers allocation excluding the decliner.
- [ ] `POST /api/mechanic/<id>/arrive` and `/complete`.

### 2.6 Tests (spec §48)
- [ ] `backend/tests/test_allocation.py` — unit tests for eligibility filters, ranking determinism, region resolution, empty-set escalation, and the §45 scenarios A–I at the engine level.

**Exit criteria:** §45 scenarios A–I are reproducible at the engine level with logged, explainable output.

---

## PHASE 3 — REAL-TIME

- [ ] `PUT /api/mechanic/<id>/location` must also emit `mechanic_location_updated` + `mechanic_location_global_updated` (parity with the request-scoped endpoint).
- [ ] Emit status events on **every** transition driven by the status machine (assigned → accepted → en-route → arrived → started → completed).
- [ ] Socket rooms per `requestId` so a user only receives their own rescue's events.
- [ ] Enable `simple-websocket` / native WebSocket on the server and allow the client to prefer `websocket` with `polling` fallback.
- [ ] Throttle GPS publishing (sensible intervals, configurable) — do not spam high-frequency updates (§20).
- [ ] Flutter: consume real-time updates on the Track tab without manual refresh; draw mechanic marker + polyline + ETA (§21–23).

---

## PHASE 4 — TRANSACTION

- [ ] `backend/pricing.py` — configurable model: base + distance/travel + additional + taxes; return an itemised breakdown (§30). No claims of market accuracy.
- [ ] `payments` collection: `paymentId`, `orderId`, `requestId`, `amount`, `status`, `method`, `signatureVerified`, `createdAt`.
- [ ] `POST /api/payments/create` → Razorpay order (test/sandbox) ; `POST /api/payments/verify` → **server-side** signature verification; only then mark request `PAYMENT_COMPLETED`.
- [ ] `ratings` collection (§31) + `POST /api/ratings` + `GET /api/mechanic/<id>/ratings`; mechanic aggregate computed **only** from stored ratings.
- [ ] Flutter: wire `payment_gateway_service.dart` (currently dead) or the live `payment_screen.dart` to the new endpoints; remove any fake "Payment Successful" path.

**Exit criteria:** a completed rescue can be billed, paid in Razorpay test mode, verified server-side, receipted, and rated.

---

## PHASE 5 — SAFETY & VOICE

- [ ] SOS (§26): confirm → capture GPS → show emergency contacts → create an emergency event. `DEV_MODE` must prevent messaging real contacts.
- [ ] Emergency contacts on the user profile.
- [ ] RoadResQ Buddy voice guidance via `flutter_tts` (§24) — non-blocking; must never gate the rescue flow. Currently `voice_service.dart` is dead code — wire or delete.
- [ ] Support centre content: breakdown safety, FAQs, cancellation policy, payment help (§35).
- [ ] Voice-first emergency (§25): explicit action only — no always-listening; do not claim continuous activation.

---

## PHASE 6 — ADVANCED (only if honestly implementable)

- [ ] `FaultDetectionService` interface behind a stable contract (§27). Ship the rule-based classifier explicitly labelled **AI prototype / rule-based fallback**, and **delete the `Random()` "confidence"** in `diagnose_screen.dart`.
- [ ] Optional image attachment on a rescue request, stored locally during development and associated with the request (§28). No claim of image analysis unless a model is actually integrated.
- [ ] Intelligent workload allocation / demand prediction — only with measurable, honest evaluation.

---

## PHASE 7 — RESEARCH

- [ ] Experiment scenarios A–L (§45) as scripted, repeatable runs against the live engine.
- [ ] Metrics from real data only: GPS acquisition, request processing, assignment, acceptance, assigned distance, ETA, completion, assignment success rate, no-mechanic cases, network failures (§44 §8).
- [ ] `GET /api/admin/export/allocation` → anonymised CSV with the §46 fields.
- [ ] `GET /api/admin/dashboard` — every metric aggregated from the database (§34); **no hardcoded numbers**.
- [ ] Make the admin dashboard **reachable** from the app (currently orphaned) — protected route, not on the role grid (§6).
- [ ] Journal evidence: screenshots, API transcripts, exported CSV. Anything not measured is labelled **To be evaluated** / **Prototype observation**.

---

## PHASE 8 — REPOSITORY HYGIENE (continuous)

- [ ] Delete or quarantine the ~110 dead files, or move them to `lib/_archive/` so the live app is legible.
- [ ] Delete the 0-byte root `crew_dispatch_service.dart` and the doc-only `backend/assistant_api_patch.py`.
- [ ] Rewrite `README.md` to describe the **actual** Flask + MongoDB architecture (it currently documents Firebase).
- [ ] Add `backend/requirements.txt` and a `run_backend.ps1` / `run_app.ps1` for reproducible startup.
- [ ] Add database documentation + API documentation (§54).

---

## CROSS-CUTTING RULES

1. Never break an existing endpoint signature already consumed by the Flutter app (spec §37).
2. Never claim a feature is done while it is a placeholder (spec §51).
3. Every phase ends with: `python -m py_compile`, the backend tests, `flutter analyze`, and a §55 progress report.
4. Measurements come from logs. If a number was not measured it is labelled as not measured.

---

## IMMEDIATE NEXT ACTION

Per §56 STEP 4 — identify the highest-priority missing functionality — the answer is:

> **The regional mechanic allocation engine (Phase 2), preceded by the Phase 1 security fixes it depends on.**

Phase 1 is a prerequisite: an allocation engine that writes assignments which any unauthenticated client can overwrite is not testable evidence. Both are therefore delivered as the first implementation increment.
