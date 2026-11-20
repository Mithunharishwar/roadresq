# Patent Roadmap — RoadResQ (India)

Prepared 2 Nov 2026. Based on your workspace manuscript: *"RoadResQ: A Voice-First, Capability-Constrained On-Demand Vehicle Breakdown Assistance Platform with Weighted Geospatial Partner Allocation and Sensor-Triggered Incident Escalation"* — Mithun Harishwar P R, Lokeshwaran K, K. Sudha (Easwari Engineering College, Chennai).

Official fees and procedures cited from IP India (First Schedule fees; Filing Process page). Not legal advice — a registered Indian patent agent must draft and file.

---

## 1. Timeline (patent vs. paper)

| When | Action | Why it matters |
|---|---|---|
| Now | Prior-art search (free) | Decides whether filing is worth the money |
| **Before** paper submission | File provisional application | India has **absolute novelty** — your own conference/journal paper is prior art against you |
| T+12 months | Complete specification (no extension possible) | Locks the final claim scope |
| T+18 months | Automatic publication | Application becomes public |
| By T+48 months | Request for Examination (Form 18) | No examination happens without it |
| ~T+2–4 years | First Examination Report → reply → grant | Normal track; expedited track is faster |

---

## 2. The rule that decides everything: file first, publish second

- India follows absolute novelty. A paper, preprint, GitHub repo, LinkedIn post, college expo demo, or product page **published before your filing date** destroys novelty.
- Statutory exceptions (Sections 29–34: government-notified exhibitions, learned-society proceedings in limited circumstances, working for reasonable trial) are **narrow, condition-heavy, and applied strictly**. Do not plan around them.
- Consequence: your manuscript currently has `[TO BE PROVIDED]` emails and appears unpublished. **File the provisional first, then submit.** Same for the demo, the pitch deck, and any competition submission with public disclosure.
- If a submission deadline is imminent and filing is not possible: submit, and accept that patent protection in India is likely lost — but keep the option of filing in the US (12-month grace period under US law) if that market matters.

---

## 3. Is it patentable in India? (Section 3(k))

Section 3(k) excludes "a mathematical or business method or a computer programme *per se* or algorithms." Software is not banned — it must be claimed as a **technical solution to a technical problem**, with the inventive contribution in the implementation, not the maths.

The **CRI Guidelines 2025** (released 29 July 2025) codify this: the two-step test is (a) look at the substance of the claim beyond its wording, and (b) decide whether that substance is abstract or concretely implemented. Recognised technical effects include faster processing, improved memory/network use, real-time control, and systems-level improvement.

**Your strong candidates (technical, concrete):**

1. **Sensor-triggered incident escalation** — accelerometer/gyroscope impact signature detected on-device, false-positive suppression via in-app confirmation window, escalation to a dispatch path when confirmation is absent. This is a device-level control function with a hardware sensor input and a physical-world outcome. Strongest claim family.
2. **Capability-constrained partner allocation** — radius query over a maintained multidimensional spatial index, composite ranking over network distance + capability fit + shrunk reputation + lagged acceptance estimate, under a **bounded offer chain** with re-dispatch. Frame the technical effect as reduced dispatch latency and lower re-dispatch rate under thin supply (your simulated 19.7% → 4.4% re-dispatch and 87.0% vs 55.1% rural allocation are the technical-effect evidence).
3. **Append-only payout ledger with digitally captured tariff** — if implemented as hash-chained/tamper-evident records with the tariff captured at job closure. Weaker on its own; strong as a dependent claim.

**Weak or excluded — do not lead with these:**

- "A platform that connects stranded drivers to mechanics" → business method / marketplace model.
- Pricing, subscription, commission and payout *rules* divorced from technical implementation.
- The symptom classifier as a standalone cost-minimisation formula → mathematical method / algorithm per se. Claim it as a classification *stage within* the dispatch pipeline, with the confidence floor and fallback behaviour specified.
- UI layout alone → not a patent claim (see design registration, §7).

**Drafting discipline:** every independent claim should recite a hardware or network element it acts on (sensor, GPS, radio interface, server-side spatial index) and a measurable technical effect. Use the simulation results as evidence in the specification.

---

## 4. Claim skeleton to hand your agent

```
1. A computer-implemented method for dispatching roadside assistance, comprising:
   (a) detecting, at a mobile device, an impact event from inertial sensor data;
   (b) opening a confirmation window and, on expiry without user input,
       initiating an escalation path;
   (c) classifying at least one symptom into a service class from a set,
       subject to a confidence floor, and falling back to a structured
       interactive flow when the floor is not met;
   (d) retrieving a candidate set by a radius query over a spatial index
       maintained for partner entities;
   (e) ranking candidates by a composite score comprising network distance,
       capability fit, a shrunk reputation estimate and a lagged acceptance
       estimate;
   (f) issuing offers over a bounded, ordered offer chain and re-dispatching
       when the chain is exhausted;
   (g) closing the job with a digitally captured tariff written to an
       append-only ledger.

9. A system comprising a mobile device with an inertial sensor and a
   positioning receiver, and a server configured to perform (c)–(g).
14. A non-transitory computer-readable medium storing instructions for
   the method of claim 1.
```

Ask the agent for: 1 independent method claim, 1 system claim, 1 CRM claim, 10–14 dependent claims narrowing each stage, plus a specification that states the technical problem (dispatch latency and misallocation under thin supply) and the measured improvement.

---

## 5. Inventorship and ownership — settle this before filing

- **Inventors** are only those who contributed to the *technical* invention. If a guide or HoD only supervised or arranged funding, they are not an inventor — but institutional policy may still make the college an applicant.
- **College policy first.** Get Easwari Engineering College's IP policy in writing. Three outcomes are possible: (a) college owns, you are inventors; (b) joint ownership; (c) you own, college gets a licence. This determines who signs Form 1 and who pays.
- **Fee consequence:** an educational institution files in the same low-fee slab as a natural person/startup (₹1,600 for Form 1 e-filing). So college-as-applicant does not cost more — the question is purely who owns the rights.
- Put a **written assignment** in place among the three authors, and an **NDA** before showing the working system to garages, investors, or competition judges.

---

## 6. Filing steps, forms and official fees (individual / startup / educational institution, e-filing)

| Step | Form | Fee (₹) | Deadline / note |
|---|---|---|---|
| Provisional application | Form 1 + Form 2 (provisional) | 1,600 | Starts your priority date |
| Statement & undertaking | Form 3 | Nil | With filing; update on foreign filings |
| Inventorship declaration | Form 5 | Nil | With filing or within 6 months |
| Power of attorney (if agent) | Form 26 | Nil | Only if using an agent |
| Complete specification | Form 2 (complete) + Form 3 | Nil up to 30 sheets / 10 claims | **Within 12 months of provisional — no extension** |
| Extra sheets / claims | — | 160 per extra sheet; 320 per extra claim | Beyond 30 sheets / 10 claims |
| Early publication (optional) | Form 9 | 2,500 | Speeds up public disclosure |
| Request for Examination | Form 18 | 4,000 | **Within 48 months of priority**; no examination without it |
| Expedited examination (optional) | Form 18A | 8,000 | Only for eligible applicants (startups, etc.) |
| FER reply | — | Nil | 6 months, extendable by 3 (Form 4: 1,000/month) |
| Renewals | — | 800/yr (years 3–6), rising to 8,000/yr (years 17–20) | From the 3rd year |

For a non-eligible applicant (company, large entity), the same steps cost ₹8,000 / ₹20,000 / ₹60,000 respectively.

**Realistic all-in budget for a student team:** official fees ≈ ₹6,000–8,000; professional drafting and prosecution typically ₹25,000–60,000+ depending on agent and claim complexity — get two or three written quotes before committing. DPIIT-recognised startups get an 80% fee rebate and can use the SIPP scheme for facilitator support; a student team usually does not qualify unless a company is incorporated.

---

## 7. What a patent will *not* protect — cover these too

| IP | Covers | Cost/effort | Verdict for RoadResQ |
|---|---|---|---|
| Copyright | Your source code and UI expression (not the idea) | Low; registration is optional but useful evidence | Do it — cheap, and useful in a dispute |
| Trademark | "RoadResQ" name and logo, classes 9 / 38 / 42 | A few thousand per class | Do it before launch or a public demo |
| Design registration | The GUI's visual appearance (Locarno 14-04) | Moderate; must be filed before public disclosure | Optional — only if the UI is distinctive |
| Trade secret / NDA | Algorithms you choose not to publish | Free | Use for anything you decide not to claim |

---

## 8. Should you actually file? An honest reading

**For:** it is a genuine, specific, technically framed mechanism with quantified results, it strengthens the paper, it helps with incubator/funding and college credit, and the official cost at the student/educational slab is small.

**Against:** a patent is only as strong as its claims, and the commercial moat for a two-sided marketplace is usually network density, not exclusivity. The evaluation is simulated — an examiner will not treat simulation as proof, and a challenger can design around a claim that is too narrow.

**Recommendation:** file a provisional now, cheaply, to freeze the priority date before the paper goes out. Spend the following 12 months deciding whether the complete specification is worth the drafting cost — you can let the provisional lapse with no further spend.

---

## 9. Next 7 days

1. Ask the college IP cell for the IP policy in writing (who owns student work).
2. Run a prior-art search: IP India public search, Google Patents, Espacenet — queries: "roadside assistance dispatch capability ranking", "crash detection escalation dispatch", "spatial index service provider allocation". Save the hits.
3. Shortlist 2–3 registered patent agents (IP India's e-register of patent agents); ask for a fixed-fee provisional quote.
4. Have the agent draft the provisional from §4 above plus your manuscript's system architecture and algorithms.
5. File Form 1 + Form 2 (provisional) + Form 3 + Form 5. Get the application number.
6. **Only then** submit the paper, publish the repo, or demo publicly.
