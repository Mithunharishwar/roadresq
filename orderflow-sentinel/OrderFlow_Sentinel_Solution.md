# OrderFlow Sentinel
### Self-Healing AI for Order & API Failure Resolution

**Hackathon solution submission — Use Case 1**

| Field | Detail |
|---|---|
| Solution name | OrderFlow Sentinel ("Sentinel") |
| Industry anchor | Telecom broadband / device order fulfilment · Retail omnichannel order management |
| Generalises to | Insurance policy issuance, banking account opening, logistics booking, utility connection |
| Failure modes in scope | API Response Errors · Order Delays · Order Rejections |
| Stage target | Stage II POC (Stage I artefacts included; Stage III path defined) |
| Core claim | Sentinel does not just *alert* on a broken order — it produces an evidence-backed diagnosis and, where provably safe, a **completed resolution** with an audit trail. |

---

## 1. Executive summary

A modern order is not a record; it is a **journey across 6–10 systems joined by APIs**. E-commerce/CRM → OMS → inventory → payment → provisioning/activation → logistics → notification. Every hop is a chance for the order to stall, be rejected, or die silently.

Existing monitoring answers *"is the API up?"*. It does not answer the question operations actually asks at 9 a.m.: **"which orders are about to miss their promise, why, and what do I do right now?"**

OrderFlow Sentinel is an AI layer that:

1. **Reconstructs** a single causal timeline per order from API telemetry, order-status events and SLA timers, correlated on `order_id` + `trace_id`.
2. **Detects** the three failure modes in real time — including *predicted* delays before the SLA breach.
3. **Diagnoses** the failing hop and the probable root cause, attaching the specific evidence (log lines, response codes, timing deltas, prior incidents).
4. **Resolves** — retry with back-off, reroute to a fallback gateway, refresh a token, throttle, normalise-and-resubmit, or escalate with a pre-filled diagnosis — gated by a policy layer that only permits actions that are **reversible, idempotent and low-risk**.
5. **Learns** which resolutions actually worked, and uses that outcome ledger to re-rank future action selection.

The differentiator is the **last mile**: diagnosis is table stakes in 2026; *safe autonomous completion of the transaction* is not.

---

## 2. Problem framing

### 2.1 The structural failure
Orders fail at **seams**, not inside systems. Each system is individually healthy — CPU flat, 200 OK on its own health check — while the *contract between two systems* is broken: a schema field renamed, a callback never fired, a 429 absorbed silently, a validation rule tightened on the carrier side.

This produces three characteristic pathologies:

| Pathology | What it looks like | Why monitoring misses it |
|---|---|---|
| **Silent stall** | Order sits in `PENDING_PROVISIONING` for 40 min | No error is logged anywhere — the event simply never arrives |
| **Absorbed rejection** | Order flips to `REJECTED` with a generic reason code | A 200 response carried a business-level failure in the body |
| **Error storm, individual triage** | 400 orders fail identically within 3 minutes | Alerting is per-threshold, not per-pattern; operators open 400 tickets |

### 2.2 The operational cost
Operations teams triage by hand: open the OMS, read the order, find the correlation ID, hunt the log across 5 tools, guess the hop, retry manually, escalate. This is the "swivel-chair tax". It is slow (minutes to hours per order), inconsistent (depends who is on shift), and **undocumented** — the fix is never fed back into the system.

### 2.3 Why now
Three things became true simultaneously: (a) LLMs can read heterogeneous logs and produce a defensible causal narrative; (b) event-driven order platforms expose enough telemetry to reconstruct a true per-order timeline; (c) business tolerance for "we'll check it manually" has collapsed under same-day-delivery and same-day-activation promises.

---

## 3. Solution overview — four loops

Sentinel is organised as four closed loops, each independently demoable:

```
   ┌──────────────────────────────────────────────────────────────┐
   │  LOOP 1 — DETECT                                             │
   │  telemetry → per-order timeline → 3-class failure label      │
   └───────────────────────────┬──────────────────────────────────┘
                               ▼
   ┌──────────────────────────────────────────────────────────────┐
   │  LOOP 2 — DIAGNOSE                                           │
   │  error clustering → failing hop → root cause + evidence      │
   └───────────────────────────┬──────────────────────────────────┘
                               ▼
   ┌──────────────────────────────────────────────────────────────┐
   │  LOOP 3 — DECIDE & ACT                                       │
   │  policy gate → auto-resolve (low risk) | recommend (high)    │
   └───────────────────────────┬──────────────────────────────────┘
                               ▼
   ┌──────────────────────────────────────────────────────────────┐
   │  LOOP 4 — LEARN                                              │
   │  outcome ledger → action success rates → re-ranked actions   │
   └───────────────────────────┬──────────────────────────────────┘
                               └──── feeds back into Loop 3
```

### 3.1 What "self-healing" means here (precise definition)
A resolution is **self-healing** only if all five conditions hold:

1. It is **idempotent** — replaying it cannot double-provision or double-charge.
2. It is **reversible or compensated** — if it fails halfway, a saga compensation restores the pre-action state.
3. It is **bounded** — retry budgets, attempt caps and expiry are explicit.
4. It is **explained** — every action carries the diagnosis that justified it.
5. It is **audited** — immutable log of who/what acted, on what evidence, with what result.

Anything that fails these conditions is **recommended to a human**, never executed. This is the design commitment that makes the system deployable in telecom and retail, where an autonomous double-activation or double-refund is a regulatory event.

---

## 4. Scope boundaries (explicit)

**In scope**
- Detection, diagnosis and resolution of the three failure modes on an order/API journey.
- Human-in-the-loop approval workflow with ranked recommendations.
- Feedback capture and action re-ranking.
- Synthetic data generation with ground-truth labels for evaluation.

**Out of scope (stated to protect credibility)**
- Replacing the OMS/provisioning systems. Sentinel is a **sidecar**, not a system of record.
- Root-causing infrastructure faults (that is APM's job). Sentinel consumes APM signals as inputs.
- Any use of real customer, payment or PII data.
- Multi-tenant SaaS hardening, SSO, RBAC beyond a demo-grade operator session.

---

## 5. Architecture

### 5.1 Components

| # | Component | Responsibility | Key design decision |
|---|---|---|---|
| 1 | **Collectors** | OTel-compatible ingestion of API logs, gateway access logs, OMS status events, carrier callbacks | Sidecar + log shipper; no code change required in the source systems |
| 2 | **Correlator** | Joins events into one timeline per `order_id`; resolves `trace_id`, `request_id`, `idempotency_key` fallbacks | Events are the source of truth (event sourcing); state is derived, never authoritative |
| 3 | **Journey Model** | Declarative per-order-type state machine: expected hops, allowed transitions, per-hop SLA | YAML-defined; new order types onboarded without code |
| 4 | **SLAtimer / Watermark** | Computes `expected_at` per hop from learned baselines; emits time-to-breach | Separates "late" from "broken" — the delay detector's foundation |
| 5 | **Failure Detector** | 3-class classifier + rule guardrails | Hybrid: rules for hard signals, ML for ambiguity |
| 6 | **Clustering Service** | Embeds error payloads, clusters into incidents (blast radius) | One incident, N orders — fixes the "400 tickets" pathology |
| 7 | **Root-Cause Agent** | Walks the call chain, ranks candidate hops, produces diagnosis + evidence | LLM writes the narrative; the *graph traversal* decides the culprit |
| 8 | **Resolution Engine** | Action library + selection + execution with saga compensation | Actions are typed, versioned, idempotent |
| 9 | **Policy Gate** | Autonomy decision: auto / recommend / block | Externalised policy (OPA-style), auditable and testable |
| 10 | **Operator Console** | Incident queue, order timeline, diagnosis card, approve/reject, audit trail | Ranked by revenue-at-risk × SLA urgency |
| 11 | **Outcome Ledger** | Records action → result → verified-fixed | The training set for Loop 4 |

### 5.2 Data contracts (the three event types)

```jsonc
// 1. api_call — one row per outbound/inbound hop
{ "order_id": "...", "trace_id": "...", "hop": "payment.authorize",
  "svc": "payment-gw", "status": 504, "latency_ms": 30000,
  "req_schema_v": "3.2", "resp_body": "...", "ts": "..." }

// 2. order_event — business state transition
{ "order_id": "...", "from": "PAYMENT_PENDING", "to": "PAYMENT_FAILED",
  "reason_code": "GW_TIMEOUT", "actor": "system", "ts": "..." }

// 3. sla_timer — derived, per hop
{ "order_id": "...", "hop": "provisioning", "expected_at": "...",
  "p95_baseline_s": 42, "time_to_breach_s": 610 }
```

### 5.3 Storage
- **Hot path**: Redpanda/Kafka topic per event type → stream processor (Flink or a Python consumer for POC).
- **Timeline store**: Postgres + TimescaleDB (hypertable on `order_id`, `ts`) — supports the "show me this order's last 2 hours" query at demo speed.
- **Vector store**: pgvector for error-signature embeddings (keeps the stack single-database).
- **Object store**: raw payloads for evidence, content-addressed.

### 5.4 Deployment
Docker Compose for the demo (7 services + console). Production target: Kubernetes, one namespace per environment, OTel collector as DaemonSet.

---

## 6. Failure taxonomy and detection design

### 6.1 Taxonomy (the backbone of the whole system)

| Class | Sub-type | Primary signals | Detector |
|---|---|---|---|
| **API_ERROR** | `TRANSIENT_5XX` | 500/502/503/504, latency ≫ p95 | Rule + latency z-score |
| | `TIMEOUT` | request duration ≥ client timeout, no response | Rule |
| | `AUTH` | 401/403, `token_expired`, clock-skew | Rule |
| | `RATE_LIMIT` | 429, `Retry-After`, quota headers | Rule |
| | `CONTRACT` | JSON-schema mismatch, missing field, type change, unknown enum | Schema differ (not a status code at all) |
| | `MALFORMED` | truncated body, partial response, 200-with-error-payload | Payload validator |
| **DELAY** | `QUEUE_BACKLOG` | broker depth ↑, consumer lag ↑, no hop entry | Lag monitor + baseline |
| | `STALLED_CALLBACK` | order in awaiting-state past expected, no inbound event | Watermark expiry |
| | `MISSING_EVENT` | state machine needs event X, timeline has no X | Journey-model satisfiability check |
| | `DOWNSTREAM_SLOW` | hop latency above learned baseline but under timeout | Sequential anomaly model |
| | `PREDICTED_BREACH` | trajectory of current hop exceeds remaining budget | Survival model (§9) |
| **REJECTION** | `VALIDATION` | field-level errors, address/postcode failure, format | Rule + classifier |
| | `BUSINESS_RULE` | credit limit, eligibility, region restriction, duplicate order | Rule (rule id from source system) |
| | `INVENTORY` | out-of-stock, allocation conflict, reservation expiry | Rule |
| | `PAYMENT` | decline codes, 3DS failure, fraud hold | Code map + classifier |
| | `DUPLICATE` | idempotency collision, same order twice | Fingerprint match |

**Why a taxonomy and not just a classifier?** Because the resolution action is a function of the *sub-type*, not the class. `TRANSIENT_5XX` → retry; `CONTRACT` → never retry (retrying a schema mismatch burns budget and hides the bug) → escalate with the schema diff. A flat 3-class model would blur exactly the distinction the resolution engine depends on.

### 6.2 Detection logic

**Layer 1 — deterministic rules (high precision, zero latency).** Explicit signals: status code class, journey-model violation, watermark expiry. These need no ML and must never be wrong.

**Layer 2 — statistical baselines (per hop, per hour-of-day, per carrier/partner).** Latency and inter-event gaps modelled as robust distributions (median + MAD, or a rolling P95 with seasonality). An order is "delayed" when its hop age exceeds `baseline_p95 × k`, where `k` is tuned per hop from labelled synthetic data. This is what catches *silent* stalls where nothing errored.

**Layer 3 — supervised classifier (fills the ambiguity).** Gradient-boosted trees over engineered features (hop, status, latency z, retry count, payload size delta, schema version, partner, hour, order value band, prior failures on same order). Trained on the fault-injected synthetic corpus where ground truth is known. Handles the grey zone: is a 12 s response on a 15 s timeout a warning or normal?

**Layer 4 — contract drift detector.** Periodically diffs observed response schemas against the registered contract per hop. Catches the highest-severity, lowest-visibility failure in the taxonomy: a partner silently renames `postal_code` → `zip`. Nothing throws; the order quietly fails validation two hops later.

**Output contract per order (what every downstream component consumes):**

```json
{ "order_id": "...", "failure_class": "DELAY", "sub_type": "STALLED_CALLBACK",
  "failing_hop": "provisioning.activate", "confidence": 0.91,
  "detected_at": "...", "ttb_seconds": 610, "evidence_refs": ["ev_8821","ev_8822"] }
```

### 6.3 Blast-radius clustering (a headline capability)
Every failure is fingerprinted: `hash(hop, sub_type, error_code, normalised_message_embedding_cluster)`.

Orders sharing a fingerprint within a rolling window are grouped into **one incident**. The console shows "Incident INC-4471 · 312 orders · provisioning-gw · TRANSIENT_5XX". One operator decision then applies to 312 orders — which is the difference between firefighting and operations. Clustering also converts 312 individual data points into one training signal, making the feedback loop learn ~300× faster in exactly the situations that matter.

---

## 7. Root-cause agent

### 7.1 Design principle
**The LLM writes the explanation; it does not choose the culprit.** Causal attribution is done by deterministic graph traversal over the reconstructed call chain; the LLM's job is to read the evidence bundle and produce a human-legible narrative plus a resolution argument. This keeps the system auditable and prevents the classic failure mode of an LLM confidently blaming the wrong service.

### 7.2 Pipeline

```
timeline → build hop DAG (parent/child from trace spans, else from journey order)
        → score each node:  error_rate↑  latency_delta↑  retry_count↑
                            ↓
        → candidate culprits (top-k by score)
                            ↓
        → test counterfactuals from evidence:
             "did downstream hops fail only after this hop?"
             "did this hop fail for orders that never reached it?"
             "does the error signature match a known incident?"
                            ↓
        → ranked hypothesis with per-hypothesis evidence refs + confidence
                            ↓
        → LLM narrative (grounded, must cite evidence_ids, temperature 0)
```

### 7.3 Guardrails on the narrative layer
- **Evidence binding**: the model may only reference `evidence_id`s supplied in its context; any claim without a citation is rejected by a post-validator and the response is regenerated once, then falls back to a template.
- **Structured output**: JSON schema validation, not free text, then rendered.
- **No actions from the LLM**: the model proposes an action *category* from a closed enum; the Resolution Engine maps category → concrete, tested action. The LLM cannot invent an API call.
- **Narrative is advisory**: operators see the deterministic score and the evidence, so they can disagree with the story.

### 7.4 Diagnosis card (what the operator sees)
```
INC-4471 · 312 orders · provisioning-gw               [AUTO-RESOLVING]
Probable cause:  upstream gateway 504s after 30s (confidence 0.91)
Failing hop:     provisioning.activate  →  carrier-gw-alpha
First seen:      14:02:11    Blast radius: 312 orders / 4 partners
SLA at risk:     118 orders breach install slot in < 45 min

Evidence
  ev_8821  14:02:11  POST /activate  504  30002ms   (x312, all identical)
  ev_8819  14:01:58  carrier-gw-alpha p99 latency 28s → 30s (timeout cliff)
  ev_8802  13:58:40  same signature on 9 orders — cluster opened
  ev_8790  13:41:02  last success on gateway alpha (delta suggests quota)

Why not a retry-loop: 3 prior retries on same gateway failed; back-off exhausted.
Recommended:           reroute to carrier-gw-beta (last success 13:44, capacity OK)
Risk:                  LOW — idempotent activation, beta slot available, reversible
Expected recovery:     ~4 min for 118 at-risk orders
```

That card is the product. Everything else exists to fill it in.

---

## 8. Resolution engine

### 8.1 Action library (typed, versioned, idempotent)

| Action | Applies to | Mechanics | Safety |
|---|---|---|---|
| `RETRY_BACKOFF` | TRANSIENT_5XX, TIMEOUT | Exponential back-off (2s→4s→8s, jitter), max 3, respects `Retry-After` | Idempotency key required; no blind retry on non-idempotent POST |
| `REROUTE_GATEWAY` | persistent 5XX on one partner | Switch to fallback partner from a ranked pool; health-checked | Only if fallback healthy and capability-equivalent |
| `REFRESH_TOKEN` | AUTH | OAuth refresh, retry once, rotate on repeated failure | Scoped credential, no PII in logs |
| `THROTTLE_ADAPTIVE` | RATE_LIMIT | Token bucket reshape, queue-and-drain rather than drop | Never drops an order; delays only |
| `ENRICH_RESUBMIT` | fixable VALIDATION | Address normalisation/geocoding, phone/format repair, then resubmit | Only fields with deterministic transforms; never invent data |
| `RECONCILE_STATE` | MISSING_EVENT, STALLED_CALLBACK | Pull authoritative status from source system, back-fill timeline | Read-only then state-sync, no business action |
| `REPLAY_EVENT` | lost/duplicate event | Re-publish from outbox with same event key | Exactly-once via key dedupe |
| `RESERVE_ALTERNATE` | INVENTORY | Substitute SKU / alternate warehouse | Requires customer-visible rule consent |
| `ESCALATE` | BUSINESS_RULE, PAYMENT decline, hard rejects | Ranked recommendation + pre-filled diagnosis to human queue | Default for anything uncertain |

### 8.2 Decision matrix (the resolution policy)

| Failure sub-type | Auto? | Action | Why |
|---|---|---|---|
| `TRANSIENT_5XX` (1st/2nd attempt) | **Auto** | `RETRY_BACKOFF` | Provably harmless, fully idempotent |
| `TIMEOUT` (no side effect proven) | **Auto** | `RETRY_BACKOFF` | Requires side-effect check before retry |
| `AUTH` | **Auto** | `REFRESH_TOKEN` → retry once | Containable, no order mutation |
| `RATE_LIMIT` | **Auto** | `THROTTLE_ADAPTIVE` | Delays, never drops |
| `TRANSIENT_5XX` (exhausted) | **Auto** | `REROUTE_GATEWAY` | Reversible, capability-checked |
| `CONTRACT` | **Escalate** | `ESCALATE` + schema diff | Retrying hides a partner bug; contract change needs owner decision |
| `MALFORMED` | **Escalate** | `ESCALATE` + payload snapshot | Could indicate data corruption |
| `VALIDATION` (deterministic fix) | **Auto** | `ENRICH_RESUBMIT` | Address/postcode normalisation is reversible and testable |
| `VALIDATION` (unfixable) | **Escalate** | `ESCALATE` | Needs customer contact |
| `BUSINESS_RULE` | **Escalate** | `ESCALATE` | Policy decision, not a technical one |
| `INVENTORY` | **Recommend** | `RESERVE_ALTERNATE` | Customer-visible substitution needs consent |
| `PAYMENT` decline | **Escalate** | `ESCALATE` | Financial/regulatory boundary — never auto |
| `DUPLICATE` | **Auto** | Dedupe + `REPLAY_EVENT` | Prevents double fulfilment |
| `PREDICTED_BREACH` | **Recommend** | Pre-emptive alert / priority bump | No safe unilateral action |
| Any class, order value above threshold | **Escalate** | — | Value-weighted risk gate |

### 8.3 Autonomy gate (how "safe" is computed)

```
risk_score = w1·irreversibility + w2·financial_exposure + w3·(1 - model_confidence)
           + w4·(1 - historical_success_rate(action, sub_type))
           + w5·regulatory_flag

risk_score < 0.30  → AUTO          (execute, log, notify)
0.30 – 0.60        → AUTO_SHADOW   (dry-run, verify preconditions, then execute)
> 0.60             → RECOMMEND     (human approves)
```

The weights are **business-configurable**, not learned. A telecom can set regulatory_flag to dominate for anything touching activation; a retailer can weight financial exposure. This is the layer auditors ask about, so it must be legible and versioned, not a neural net.

### 8.4 Execution safety patterns

- **Idempotency keys** derived from `(order_id, hop, intent_hash)` — a replayed action is a no-op at the downstream system.
- **Saga compensation**: every action declares an inverse (`REROUTE_GATEWAY` inverse = cancel-on-new-partner-if-orphaned). If a step fails, the saga unwinds to the last known-good state.
- **Pre-flight verification**: before executing, re-verify preconditions (order still in expected state, no concurrent action, budget remaining).
- **Attempt ledger**: per order per hop, hard caps. Sentinel will not be the reason a system gets hammered.
- **Kill switch**: global, per-partner, and per-action-class. One toggle returns the system to recommend-only mode.
- **Shadow mode**: every auto-action first runs in dry-run for the first N incidents per action class, and the operator's actual choice is compared to Sentinel's. Promotion to live autonomy requires a measured success rate above a configured bar.

---

## 9. Delay prediction (the pre-emptive half)

Detection says "this is late". Prediction says "this will be late in 38 minutes" — which is the only version operations can act on.

**Model**: gradient-boosted survival analysis (or a Weibull AFT / Cox PH baseline for interpretability). Inputs: current hop, elapsed time, hop's learned baseline distribution (hour-of-day, partner, order type), queue depth, downstream health, retry count, historical completion curve for that hop.

**Output**: `P(breach | state)` for each remaining SLA milestone, plus the **time-to-breach** estimate — the single number the console sorts by.

**Why survival models rather than a classifier**: the target is inherently censored (orders still in flight have not yet breached). A binary classifier would have to discard in-flight orders — precisely the population we care about.

**Alert policy**: emit at T-minus-45 min (or X% of remaining budget), ranked by revenue-at-risk, deduplicated into the parent incident so 300 orders do not produce 300 pages.

---

## 10. Feedback loop

**Outcome ledger** — one row per action attempt:

```json
{ "incident_id": "...", "order_id": "...", "action": "REROUTE_GATEWAY",
  "sub_type": "TRANSIENT_5XX", "executed_at": "...", "mode": "AUTO",
  "result": "RESOLVED", "verified_by": "order_event:ACTIVATED",
  "time_to_resolve_s": 231, "operator_override": null }
```

**Verification of "did it work"** is not "did the API return 200" — it is **"did the order advance to the next journey state"**. That distinction is why most automation projects report success while customers still churn.

**Learning mechanisms (in increasing sophistication, all shippable):**
1. **Success-rate table** per `(sub_type, action, partner)` — feeds the risk score's `historical_success_rate` term. Ships in week one, immediately useful.
2. **Contextual bandit** (Thompson sampling) over action choices per sub-type — explores alternatives (e.g. retry vs reroute at attempt 2) while bounding regret.
3. **Operator-override mining**: when a human rejects Sentinel's recommendation, that pair is labelled and surfaced as a prompt for a **new rule candidate**. The system's policy improves from disagreement, which is the cheapest possible supervision.
4. **Drift watch**: if auto-resolution success rate drops below threshold for an action class, that class is automatically demoted to `RECOMMEND`. Self-healing includes healing itself.

---

## 11. Data strategy (no real customer or payment data)

### 11.1 Synthetic order-flow generator (primary asset)

A simulated 6-service pipeline (CRM → OMS → inventory → payment → provisioning → notification), each hop an HTTP service with its own latency distribution, failure injection, retry semantics and partner variants.

**Fault injection matrix** — every taxonomy sub-type has a seeded injector with controllable rate:

| Injected fault | How it manifests in telemetry | Ground-truth label |
|---|---|---|
| `gw_timeout` | 30 s hang, 504 at gateway | API_ERROR/TIMEOUT |
| `schema_rename` | 200 OK, field `postal_code` → `zip`, validation fails 2 hops later | API_ERROR/CONTRACT |
| `token_expiry` | 401 burst across orders, correlated in time | API_ERROR/AUTH |
| `rate_limit` | 429 with Retry-After, bursty | API_ERROR/RATE_LIMIT |
| `callback_drop` | no inbound event, order ages past watermark | DELAY/STALLED_CALLBACK |
| `queue_backlog` | consumer lag ↑, hop latency distribution shifts | DELAY/QUEUE_BACKLOG |
| `address_invalid` | validation reject, deterministic fix possible | REJECTION/VALIDATION |
| `credit_hold` | business-rule reject, requires human | REJECTION/BUSINESS_RULE |
| `dup_submit` | same idempotency key twice | REJECTION/DUPLICATE |
| `stock_conflict` | allocation failure at reservation | REJECTION/INVENTORY |

**Why synthetic is a feature, not a compromise**: it gives **labelled ground truth at scale** (10k–100k orders, minutes of simulation), controlled class balance, and the ability to demo a rare-but-critical fault on demand. Real datasets cannot do any of that — and using real order data in a hackathon is a compliance problem, not an asset.

**Realism controls** (what makes the demo credible rather than a toy): hourly traffic seasonality, long-tail latency (lognormal + occasional stall), partner-specific behaviour drift, correlated failures (one bad deploy → many hops degrade), partial recovery, and background noise orders that *look* suspicious but are normal (these are the false positives that prove the detector isn't just thresholding).

### 11.2 Secondary / validation datasets (for credibility)
- **TrainTicket** microservice traces — realistic multi-service call chains with injected anomalies.
- **LogHub** collections (HDFS, BGL, Linux) — for error-clustering and log-parsing technique validation.
- **Public HTTP/API access-log corpora** for the contract-drift detector.

These prove the detector generalises beyond the simulator; the simulator provides the labels.

### 11.3 Privacy posture
No PII, no PAN, no real addresses. Synthetic customer IDs are opaque UUIDs; addresses are generated from public postcode/grid data or faker libraries. Payloads are structurally realistic, semantically fake. This is stated explicitly in the submission — judges in telecom/retail score data governance.

---

## 12. AI/ML technique map

| Task | Technique | Why this one | Fallback if time-constrained |
|---|---|---|---|
| Failure classification | LightGBM on engineered features | Fast, explainable (SHAP), handles tabular imbalance well | Rules only |
| Error clustering | Sentence embeddings (`all-MiniLM-L6-v2`) + HDBSCAN | Catches semantically identical errors with different text; no fixed cluster count needed | Normalised-message hashing |
| Latency baselines | Robust rolling stats (median/MAD) per hop × hour | Survives outliers; no training needed | Static P95 |
| Delay/anomaly | GBDT survival (or Weibull AFT) | Handles censored in-flight orders — the actual target population | Quantile regression |
| Contract drift | JSON-schema diffing + type inference | Deterministic, zero false-negative on structural change | Manual contract registry |
| Root cause | Graph traversal + counterfactual scoring, LLM for narrative only | Auditable attribution; LLM cannot hallucinate the culprit | Template narrative |
| Action selection | Success-rate table → contextual bandit | Starts deterministic, improves with data | Static policy matrix |
| Log parsing | Drain-style template mining | Cheap, well-understood, feeds clustering | Regex library |

**Deliberate restraint**: only two components are "AI" in the expensive sense (embeddings, LLM narrative). The rest is classical ML and rules chosen because they are debuggable at 3 a.m. A hackathon solution that is 90% LLM is a demo; one that is 90% engineering with targeted AI is a product.

---

## 13. Technology stack

| Layer | Choice | Rationale |
|---|---|---|
| Ingestion | OpenTelemetry Collector, Redpanda (Kafka API) | OTel = standard, no lock-in; Redpanda = single binary, fast demo spin-up |
| Stream processing | Python consumer (POC) → Flink (Stage III) | Correct tool at each stage |
| Timeline store | Postgres + TimescaleDB | One database for state, time-series and vectors (pgvector) |
| Feature/ML | scikit-learn, LightGBM, sentence-transformers | Mature, CPU-only, no GPU dependency for demo |
| Agent orchestration | LangGraph (state machine, not free-roaming agent) | Deterministic control flow with LLM nodes |
| Policy | OPA/Rego or a Python policy table with signed config | Externalised, testable, auditable |
| Backend | FastAPI + WebSocket | Real-time console updates |
| Console | Next.js + Tailwind + Recharts | Fast to build, credible look |
| Deployment | Docker Compose → Kubernetes | Demo portability |

**Demo machine requirement**: 8 GB RAM, no GPU. This matters — judges distrust solutions that need infrastructure nobody has.

---

## 14. Evaluation plan and success metrics

### 14.1 Detection quality (measured against ground truth in the simulator)

| Metric | Target (POC) | Why it matters |
|---|---|---|
| Per-class precision | ≥ 0.90 | False alarms destroy operator trust faster than missed detections |
| Per-class recall | ≥ 0.85 | Missing a class means a silent revenue leak |
| Sub-type accuracy | ≥ 0.80 | Sub-type drives the action; class-level accuracy alone is misleading |
| MTTD (p50 / p95) | < 60 s / < 3 min | Must beat human discovery, not just exist |
| False-positive rate on noise orders | < 5% | The simulator contains deliberately ambiguous normal orders |

### 14.2 Resolution quality

| Metric | Target | Definition |
|---|---|---|
| Auto-resolution rate | ≥ 40% of failures | Share resolved without human touch |
| Auto-resolution precision | ≥ 95% | Share of auto-actions that actually fixed it and caused no harm |
| Harm events | **0** | Double-activation, double-charge, wrong-address delivery — hard gate |
| MTTR (auto-handled) | < 5 min | vs. baseline manual ~45 min |
| MTTR (escalated) | −50% vs. baseline | Pre-filled diagnosis saves triage time |
| Recommendation acceptance rate | ≥ 70% | Measures whether the diagnosis is actually right |

### 14.3 Baseline comparisons (run all three, show the table)

1. **Threshold alerting** (status-code rules + fixed SLA timer) — the status quo.
2. **APM-style anomaly detection** (latency/error-rate per service) — the sophisticated status quo.
3. **OrderFlow Sentinel** — order-centric, semantics-aware, action-taking.

The interesting result is not "Sentinel wins"; it is **where** the baselines fail (silent stalls, contract drift, blast-radius collapse) and by how much.

---

## 15. Stage mapping (JATAYU)

### Stage I — Foundations
**Deliverables**: failure taxonomy (all 3 classes, 16 sub-types); order-journey model as a declarative state machine for 2 verticals (telecom broadband, retail omnichannel); synthetic data generator with the fault-injection matrix; labelled corpus (≥ 50k orders).
**Gate**: taxonomy covers every scenario in the use-case brief; generator reproduces all 3 modes on demand with configurable rates.

### Stage II — POC (submission target)
**Deliverables**: correlator + timeline; 3-class + sub-type detector; root-cause agent with evidence binding; resolution engine with 5 auto actions (`RETRY_BACKOFF`, `REROUTE_GATEWAY`, `REFRESH_TOKEN`, `THROTTLE_ADAPTIVE`, `ENRICH_RESUBMIT`) + escalation; operator console; evaluation report vs. 2 baselines.
**Gate**: ≥ 40% auto-resolution at ≥ 95% action precision, 0 harm events, live demo of both telecom and retail scenarios on the same codebase.

### Stage III — Production shape
**Deliverables**: full action library; delay prediction with survival model; blast-radius incident management; feedback loop with bandit-based action selection; audit trail and immutable evidence store; shadow-mode rollout tooling; multi-tenant config; SLO/alerting integration (PagerDuty/Slack).
**Gate**: 30-day shadow-mode run with measured action precision, operator override rate trending down, and a documented promotion decision per action class.

---

## 16. Demo narrative (3 minutes, two verticals, one engine)

**0:00 — Set the stage.** Split screen: the order journey with 6 hops, and an ops console showing 1,240 live orders. "Every one of these is an API call waiting to fail."

**0:40 — Telecom: silent stall → self-heal.**
Inject `gw_timeout` at `provisioning.activate`. Within seconds: 312 orders turn amber, one incident card appears (not 312 tickets), because the signatures cluster. Diagnosis card shows the 504s, the latency cliff, and "3 retries exhausted — rerouting to carrier-gw-beta." Sentinel reroutes. 118 install-slot-at-risk orders recover **before** the slot is missed. Point at the timer: 6 minutes to breach when it was detected; human discovery historically took 20+.

**1:40 — Retail: fixable reject → resubmit.**
Inject `address_invalid`. Order flips `REJECTED`. Sentinel classifies VALIDATION/fixable, normalises the postcode (deterministic transform, shown on screen), resubmits, order proceeds to fulfilment. Then inject `credit_hold` on another order — same pipeline, but this time it **refuses** to act, and produces a pre-filled diagnosis for the operator. The contrast is the pitch: autonomy where safe, evidence where not.

**2:30 — The loop closes.**
Show the outcome ledger: "reroute succeeded 41/42 times on this partner, median 4 min." Show the override case: operator disagreed once, and the policy table now has a candidate rule. "The system got better while we were demoing."

**2:55 — Generalise.** Same engine, different journey YAML: insurance policy issuance, account opening, logistics booking. "We didn't build a telecom fix. We built the shape of the fix."

---

## 17. Differentiation

| | APM / observability (Datadog, Dynatrace, Splunk) | Order-management exception queues | **OrderFlow Sentinel** |
|---|---|---|---|
| Unit of analysis | Service, host, endpoint | Ticket, order row | **Order journey, end-to-end** |
| Detects silent stalls | Weak (no error to alert on) | Only via ageing reports | **Yes — watermark + journey satisfiability** |
| Understands business rules | No | Partially | **Yes — sub-type drives action** |
| Acts | No (alerts) | Manual retry buttons | **Yes — policy-gated, idempotent, saga-compensated** |
| Cross-order learning | No | No | **Yes — blast-radius clustering + outcome ledger** |
| Auditability of autonomy | n/a | n/a | **Central: risk score, evidence binding, kill switch** |

**One-line positioning**: *APM tells you the system is unhealthy. Sentinel tells you which orders will miss their promise, why, and fixes the ones it is allowed to fix.*

---

## 18. Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Auto-action causes harm (double-activation) | Low | Severe | Idempotency keys + saga compensation + value/regulatory gate + hard kill switch; financial and activation actions never auto in POC |
| LLM hallucinates a root cause | Medium | High | LLM never chooses the culprit; narrative evidence-bound and schema-validated; deterministic score shown alongside |
| Synthetic data too clean → inflated metrics | High | Medium | Adversarial noise orders, correlated failures, partner drift, long-tail latency; report metrics on a held-out noise-heavy split |
| Single-partner demo overfits | Medium | Medium | Two verticals, three partner variants, journey-model swap proven live |
| Operator distrust → automation disabled | Medium | High | Shadow mode first; recommendations ranked with evidence; override always available and mined for policy improvement |
| Scope explosion in 48 h | High | High | Stage II gate fixed at 5 auto actions and 2 verticals; Stage III explicitly deferred |
| Correlation gaps (missing trace_id) | Medium | Medium | Fallback cascade: trace_id → request_id → idempotency_key → time-window + order_id heuristic |

---

## 19. Business impact model (illustrative — plug your own volumes)

Assumptions clearly labelled so judges can substitute their own numbers:

- 20,000 orders/day, 3% hit a failure = **600 affected orders/day**
- Manual triage+fix: **20 min** per order (swivel-chair across 5 tools)
- 40% auto-resolvable at Stage II → **240 orders/day × 20 min = 80 operator-hours/day recovered**
- Of the remaining 360, pre-filled diagnosis cuts triage by half → **60 more hours/day**
- SLA-breach reduction: at-risk orders caught at T-45 instead of post-breach → assume 30% of would-be breaches prevented
- Revenue protection: 600 × 30% breach-prevented × order value × churn-avoidance factor

**The honest framing**: the headline number is not the labour saving — it is that **failures stop being discovered by customers**. Everything else is arithmetic.

---

## 20. Execution plan

**Phase A — Foundations (Day 1–2)**
Journey model YAML for 2 verticals · generator + fault injectors · taxonomy constants · timeline store schema.

**Phase B — Detection (Day 3–4)**
Correlator · rules layer · baselines · GBDT classifier trained on labelled corpus · contract-drift detector · evaluation harness with the 3 baselines.

**Phase C — Diagnosis & resolution (Day 5–6)**
Clustering service · root-cause graph traversal · LLM narrative with evidence binding · action library (5 actions) · policy gate · saga + idempotency · outcome ledger.

**Phase D — Console & narrative (Day 6–7)**
Incident queue, order timeline, diagnosis card, approve/reject, audit view · demo script rehearsal twice · metrics table frozen.

**Team shape (4 people)**: (1) data/simulation + ML detector, (2) backend/pipeline + policy engine, (3) agent + resolution engine, (4) frontend console + narrative/pitch. Two people overlap on integration from Day 4.

---

## 21. Submission checklist

- [ ] Problem statement quantified with the team's own assumptions (not borrowed stats)
- [ ] Architecture diagram + data contracts
- [ ] Failure taxonomy with sub-types and the action each maps to
- [ ] Live demo: telecom 504 auto-reroute · retail address auto-resubmit · retail credit-hold refusal
- [ ] Metrics table vs. 2 baselines (detection P/R, MTTD, MTTR, auto-resolution precision, harm events = 0)
- [ ] Safety story: idempotency, saga, policy gate, kill switch, audit trail
- [ ] Data governance statement (synthetic, no PII/PAN)
- [ ] Generalisation slide: same engine, 3 other industries via journey YAML
- [ ] Stage II/III boundary stated explicitly (what is real vs. roadmap)
- [ ] Repo with `docker compose up` one-command demo

---

## Appendix A — Why this solution wins on typical judging axes

| Judging axis | Where this solution scores |
|---|---|
| **Innovation** | Order-centric self-healing (not service-centric alerting); blast-radius clustering; risky-autonomy gate with saga compensation; override mining as supervision |
| **Technical depth** | Hybrid detector (rules + robust stats + GBDT + schema diffing); survival model for censored in-flight orders; counterfactual root-cause attribution; idempotent action execution |
| **Feasibility** | CPU-only, single-database stack; 5 actions not 50; sidecar deployment (no OMS rewrite); 7-day build plan with gates |
| **Impact** | Quantified MTTD/MTTR and revenue protection; addresses a cost every telecom and retailer already carries |
| **Responsibility** | No PII, explicit autonomy boundaries, kill switch, audit trail, human override as first-class |
| **Presentation** | One diagnosis card as the hero artefact; two verticals, one engine; 3-minute script with a deliberate refusal moment |

## Appendix B — The one-sentence version

*OrderFlow Sentinel turns order failures from something customers discover into something the system detects, explains, and — when it is provably safe — fixes itself.*
