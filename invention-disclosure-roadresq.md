# Invention disclosure — RoadResQ

Fill this in before contacting the IP cell or an agent. It is the document both will ask for, and writing it forces you to separate what is genuinely new from what is standard engineering. Replace every `<...>`.

---

## 1. Title

A voice-first, capability-constrained on-demand vehicle breakdown assistance platform with weighted geospatial partner allocation and sensor-triggered incident escalation.

## 2. Inventors

| Name | Department / role | Contribution to the technical solution | Contact |
|---|---|---|---|
| Mithun Harishwar P R | IT, student | `<be specific: which algorithms, which modules>` | `<phone, email>` |
| Lokeshwaran K | IT, student | `<...>` | `<...>` |
| K. Sudha | IT, faculty | `<... or "supervision only, no technical contribution">` | `<...>` |

Inventorship means contribution to the technical solution. Supervision, funding, lab access and review of the manuscript are not contribution. Be accurate here — an incorrect inventorship declaration is a ground to revoke a granted patent.

## 3. Applicant and ownership

- Proposed applicant: `<the three individuals / the institution / joint with stated share>`
- Institution policy reference: `<clause and date, from the IP cell reply>`
- NOC required from institution: `<yes / no>`
- Funding used: `<self / college / grant — with reference>`

## 4. The problem, technically stated

Breakdowns on a carriageway shoulder create an exposure interval whose cost rises with time, while the assistance transaction itself is unstructured: `<complete this in three sentences — the fault is not characterised before dispatch, partner selection does not account for capability, and the price is agreed after the intervention>`.

Do not describe a business opportunity. Describe a technical deficiency in existing systems.

## 5. What exists today, and why it fails

| Existing approach | Technical limitation |
|---|---|
| Subscription entitlement | `<...>` |
| Directory of telephone numbers | `<...>` |
| Informal arrangement | `<...>` |
| Nearest-partner automated dispatch | `<...>` |

Cite the prior art you found in `prior-art-log.md` here, by publication number, and state in one line each how your mechanism differs.

## 6. The invention — the three mechanisms

### 6a. Sensor-triggered escalation
- Sensor(s) and sampling used: `<accelerometer / gyroscope, rate, threshold derivation>`
- How an impact event is distinguished from ordinary motion: `<...>`
- The confirmation window: `<duration, what the user sees, what happens on confirmation vs expiry>`
- What the escalation path does on expiry: `<...>`
- Why this reduces false dispatches compared with a bare threshold trigger: `<...>`

### 6b. Capability-constrained partner allocation
- How a symptom becomes a service class, and the confidence floor: `<class set, cost function in words, fallback behaviour>`
- Spatial index: `<structure, what is maintained, update cadence>`
- Composite score: `<each term, and why each is needed — network distance, capability fit, shrunk reputation, lagged acceptance>`
- Bounded offer chain: `<length, ordering, timeout, what triggers re-dispatch>`
- Measured effect: `<e.g. re-dispatch 19.7% -> 4.4%; rural allocation 87.0% vs 55.1% — state that these are simulated>`

### 6c. Payout ledger
- What is captured at job closure: `<tariff fields, who confirms>`
- Why the record is tamper-evident: `<hash chaining / append-only structure / signing>`
- What fails in current practice that this fixes: `<...>`

## 7. What is NOT claimed

List deliberately, so the agent does not draft it: the marketplace business model; commission, subscription or surge pricing rules; the cost-minimisation formula in isolation; the app's visual design; the simulation methodology itself.

## 8. Closest known prior art

| Publication | Applicant | What it discloses | How we differ |
|---|---|---|---|
| `<from prior-art-log.md>` | | | |

## 9. Disclosure history — the critical section

| Date | Event | Public? | Evidence |
|---|---|---|---|
| `<date>` | First conception / design note | No | `<file, commit hash>` |
| `<date>` | Working build | No | `<repo commit>` |
| `<date>` | Demo to `<whom>` | `<yes/no, NDA?>` | `<...>` |
| `<date>` | Manuscript drafted | No | `<file>` |
| | Manuscript submitted / published | **must be No, or after filing** | |

If anything was already public — a college expo, a competition portal, a public repo, a LinkedIn post — write it down here honestly. Discovering it later is far worse than disclosing it now.

## 10. Publication plan

- Target venue and submission deadline: `<...>`
- Filing must precede submission by: `<date>`
- Who is holding the manuscript until then: `<name>`

## 11. Attachments

- [ ] Architecture diagram
- [ ] Eight algorithms with pseudocode
- [ ] App screenshots
- [ ] Prior-art log
- [ ] Dated conception log
- [ ] Inventor agreement (signed)
- [ ] Institution IP policy / NOC

## 12. Signatures

Inventor 1: `<name>` — `<signature>` — `<date>`
Inventor 2: `<name>` — `<signature>` — `<date>`
Inventor 3: `<name>` — `<signature>` — `<date>`
