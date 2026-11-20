# RoadResQ — Patent execution playbook, start to finish

India route. Every link below was live on 3 Nov 2026. Work top to bottom; do not skip Stage 1 or Stage 6.

**The one rule that overrides everything:** the paper, the repo, the demo video and the competition entry stay private until you hold an application number. India has absolute novelty — your own disclosure is prior art against you.

---

## Stage 0 — Build the disclosure pack (1 day)

Create a folder `01_invention_disclosure/` and put these in it. This same pack goes to the IP cell *and* to the patent agent; you assemble it once.

| File | What it must contain | Status |
|---|---|---|
| `disclosure-form.md` | Filled copy of [invention-disclosure-roadresq.md](invention-disclosure-roadresq.md) | Template provided |
| `architecture.pdf` | Three-tier architecture diagram, module structure, data flow | From your manuscript |
| `algorithms.pdf` | The eight algorithms with pseudocode and complexity | From your manuscript |
| `screenshots.pdf` | App screens: request, classification, offer chain, job close, ledger | Take now, before any public post |
| `novelty-statement.md` | 1 page: what is new, what problem it solves, why it is not obvious | Write this yourself |
| `prior-art-log.md` | Your search record | [prior-art-log.md](prior-art-log.md) |
| `dates.md` | Dated log: who conceived what, when, first working build, first demo | Start today, backfill from git history |

The dated log matters later. If inventorship is ever questioned — by the college, a co-author, or an examiner — this is your evidence.

---

## Stage 1 — The IP cell enquiry (today, 2 emails)

### 1a. Find the right door

Your college is SRM Easwari Engineering College (Valliammai Society), Bharathi Salai, Ramapuram, Chennai 600 089. Published contacts, verified on the college site:

- Principal: [principal@eec.srmrmp.edu.in](mailto:principal@eec.srmrmp.edu.in)
- Helpdesk: [helpdesk@eec.srmrmp.edu.in](mailto:helpdesk@eec.srmrmp.edu.in)
- Office: 044 4392 3041 · Mobile +91 89396 28204 · Toll free 1800 103 2535
- [Contact page](https://srmeaswari.ac.in/contact-us/)

There is no publicly listed "IPR cell" address, so send to the Principal **and** your Head of Department (Information Technology), and ask them to route it to the IPR cell / Research & Development cell. Mark it **"Request for institutional IP policy — student invention, time-bound"**.

### 1b. What to ask (all five, in writing)

1. A copy of the institution's **IP policy** covering student inventions, and the clause that governs ownership.
2. Whether the college will be **applicant, co-applicant, or will issue an NOC** for students to file in their own names.
3. Whether the college will **bear the official fees and agent costs**, and whether any scheme (institutional IP fund, SIPP, AICTE/TN innovation grant) is available.
4. Whether filing **must go through a college-empanelled agent**, or whether you may appoint your own registered agent.
5. If the college is applicant: the **revenue-share / licence terms** for the students, in writing.

Ask for the reply **by email**, and give a date. A verbal "yes, go ahead" is worth nothing at the filing counter — the applicant named on Form 1 is who owns the patent.

### 1c. Email template — copy, edit, send

```
Subject: Request for institutional IP policy — student invention (patent filing, time-bound)

Respected Sir/Madam,

We are Mithun Harishwar P R and Lokeshwaran K, final-year B.Tech Information
Technology students, working under the guidance of Dr K. Sudha, on a project
titled "RoadResQ: A Voice-First, Capability-Constrained On-Demand Vehicle
Breakdown Assistance Platform with Weighted Geospatial Partner Allocation and
Sensor-Triggered Incident Escalation".

The work includes a mechanism we believe may be patentable in India: sensor-
triggered incident escalation with in-app confirmation, capability-constrained
partner allocation over a maintained spatial index, and a tamper-evident payout
ledger. A manuscript is in preparation and has not been published or submitted.

We intend to file a provisional patent application at the Indian Patent Office,
and we need the institution's position before we do, because the applicant named
on the application is the owner of the rights.

We request, in writing:
1. A copy of the institution's IP policy as it applies to student inventions.
2. Whether the college will be applicant, co-applicant, or will issue an NOC for
   us to file in our own names.
3. Whether the institution will support the official fees and agent costs, and
   any scheme available for this.
4. Whether we must use a college-empanelled patent agent or may appoint our own.
5. If the college is applicant, the revenue-share or licence terms for us.

We would be grateful for a reply by <DATE, e.g. 10 November 2026>, as publication
of the manuscript must wait until the application number is issued.

Attached: one-page invention disclosure and the draft abstract.

Regards,
Mithun Harishwar P R (<phone>, <roll no>)
Lokeshwaran K (<phone>, <roll no>)
Department of Information Technology
```

### 1d. Meanwhile — do not wait

The IP cell reply governs *ownership*, not *timing*. If the college is silent for more than about ten days, escalate once in writing, and proceed on the assumption that you file as applicants with a college NOC (ask for it explicitly in the escalation). Losing the priority date costs more than an ownership argument.

### 1e. Also settle inventorship now

Get all three of you to sign a one-page **inventor agreement**: who contributed what technically, and that any filing names only actual contributors. Dr K. Sudha is an inventor only if she contributed to the technical solution; supervision alone is not inventorship, though college policy may still make the institution an applicant. If she did contribute — the simulation design and evaluation methodology may qualify — name her.

---

## Stage 2 — Prior-art search (half a day, then hand to the agent)

A preliminary pass is already done and saved: see [prior-art-log.md](prior-art-log.md). Read the "what this means for your claims" section before you talk to any agent — it changes what you should ask them to draft.

### 2a. Search the four sources

| Source | URL | How to use it |
|---|---|---|
| IP India public search | https://iprsearch.ipindia.gov.in/PublicSearch | The only reliable route to Indian filings. Use "Application Number" / "Applicant Name" / "Abstract" search; keyword search is weak |
| Google Patents | https://patents.google.com/ | Paste the query strings from the log; use the CPC filters `G06Q10`, `G06Q50`, `G08G1`, `G07C5` |
| Espacenet | https://worldwide.espacenet.com/ | Classification search + `G06Q`/`G08G` combinations; good for EP/JP/CN families |
| Indian Patent Journal | https://search.ipindia.gov.in/IPOJournal/Journal/Patent | Weekly published applications — search recent issues for "roadside", "breakdown", "dispatch" |

### 2b. Run these exact strings (they are the ones already used)

```
"roadside assistance" dispatch provider ranking
"roadside assistance" impact detection automatic escalation
dispatch "spatial index" service provider allocation
"vehicle breakdown" voice request assistance platform
roadside assistance "service capability" partner matching job assignment
```

Add these two, which target your differentiators specifically:

```
roadside assistance provider "reputation score" ranking availability
"crash detection" "in-app confirmation" emergency service dispatch
```

### 2c. Record every hit in one table

Columns: publication number · title · applicant · priority date · status (active/expired) · CPC · one line on what it discloses · one line on how your mechanism differs. Fill it even for the near-misses — an examiner will find them, and your agent needs to know before drafting, not after.

### 2d. Where to stop

Ten hours of searching, not ten weeks. The goal is to know which of your three mechanisms is already crowded, so the agent drafts around it. If a hit reads exactly like your core claim, tell the agent before they quote — it changes the strategy, not necessarily the filing.

---

## Stage 3 — Pick a registered agent (2–3 days)

### 3a. Verify the agent is actually registered

Register: https://iprsearch.ipindia.gov.in/AgentRegister — search by name, number, or state. Anyone not on this register cannot file for you. Note the **agent number** and check the "defaulted in payment of fees" and "removed from register" lists on the same page.

### 3b. Shortlist three, in Chennai or working remotely

Prefer agents who list **software / computer-related inventions / Section 3(k)** as a practice area; a patents-only boutique beats a generalist IP firm for this filing. Ask each for their agent number and two granted CRI patents they drafted.

### 3c. RFQ email template

```
Subject: Fixed-fee quote — provisional patent application (software, India)

Dear <Agent>,

We are a three-member student team (two B.Tech IT students, one faculty guide)
filing a provisional application in India for a computer-implemented system in
roadside assistance dispatch. Agent number: <from register>.

Scope requested:
1. Prior-art review of the attached log and a short written opinion on
   Section 3(k) exposure.
2. Drafting of a provisional specification: field, background, problem,
   summary, a detailed description referencing our architecture and eight
   algorithms, at least one figure set, and a claim skeleton.
3. Filing assistance for Form 1, Form 2 (provisional), Form 3 and Form 5.

Please quote:
- A fixed fee for items 1–3, itemised, inclusive of GST.
- Whether the fee includes claim drafting, or claims are deferred to the
  complete specification.
- Turnaround time from receipt of the disclosure pack.
- Your experience with Section 3(k) / CRI Guideline 2025 cases (two examples).
- Whether you will conduct an independent prior-art search, and its cost.
- Official fees are separate; we understand Form 1 is Rs 1,600 for a natural
  person / startup / educational institution, and Rs 8,000 otherwise.

Applicant will be confirmed within a week (individuals or the institution).
Filing target: within three weeks.

Attachments: invention disclosure, architecture, algorithms, prior-art log.

Regards,
<name>, <phone>
```

### 3d. What to do with the quotes

Take the middle one unless the cheapest one has CRI experience the others lack. Watch for the two traps: a fee that excludes claim drafting (you will pay again at the complete specification), and an agent who wants to file a "broad" claim covering the whole platform — that is the fastest route to a Section 3(k) objection.

---

## Stage 4 — Get the provisional drafted (1–2 weeks)

Give the agent the Stage 0 pack plus this brief. Do not let them draft from the abstract alone; the abstract is the least useful document you have.

**Brief to the agent — the three claim families, in priority order:**

1. **Sensor-triggered escalation.** On-device impact detection from inertial sensor data, confirmation window, escalation path on expiry, handoff into the dispatch pipeline. Recite the sensor and the device; this is your strongest hardware-anchored claim.
2. **Capability-constrained allocation.** Radius query over a maintained multidimensional spatial index; composite ranking over network distance, capability fit, shrunk reputation and lagged acceptance; bounded offer chain with re-dispatch. State the technical effect as reduced dispatch latency and lower re-dispatch under thin supply, and cite your measured 19.7% → 4.4% and 87.0% vs 55.1% figures.
3. **Append-only payout ledger.** Digitally captured tariff at job closure written to a tamper-evident, hash-chained record. Dependent claim, not a lead claim.

**Tell the agent explicitly to avoid:** claiming the platform as a marketplace or business method; claiming the cost-minimising classifier as a formula in isolation; claiming pricing, commission or subscription rules; relying on the simulation as proof of technical effect rather than as supporting data.

**What comes back — check these five things before accepting the draft:**

- An independent claim that names at least one hardware or network element it acts on.
- A specification that states the technical problem (latency, misallocation under thin supply) in the first two paragraphs.
- Your eight algorithms described as implementation, not as maths.
- At least one figure set consistent with the manuscript.
- No claim so broad that the Allstate or GM Cruise families in the prior-art log would read on it.

---

## Stage 5 — File (one sitting, ~2 hours)

### 5a. Set up access

- Portal: https://ipronline.ipindia.gov.in/epatentfiling/goForLogin/doLogin
- Signing: a **Class II/III DSC without encryption**, or **e-Sign** using Aadhaar/PAN. Vendor list and e-Sign steps are on the [filing process page](https://ipindia.gov.in/page-content/filing-process-1). E-Sign is faster for students; a DSC costs money and takes a day or two.
- Payment: net banking. Keep the e-receipt PDF.

### 5b. The forms, in filing order

| Form | Purpose | Fee (natural person / startup / educational institution, e-filing) |
|---|---|---|
| [Form 1](https://ipindia.gov.in/storage/uploads/docs-operator/86c74a8b-b029-4b79-812a-d260b2f90368.pdf) | Application for grant of patent | ₹1,600 |
| [Form 2](https://ipindia.gov.in/storage/uploads/docs-operator/ee69dc48-77c4-4900-b222-154573143a4f.pdf) | Provisional specification | included |
| [Form 3](https://ipindia.gov.in/storage/uploads/docs-operator/4652ade0-c8b8-487b-95a4-6fea424590a0.pdf) | Statement and undertaking (Section 8) | Nil |
| [Form 5](https://ipindia.gov.in/storage/uploads/docs-operator/a28ee9a0-b85d-47d6-8d56-7e35dd2bf271.pdf) | Declaration as to inventorship | Nil |
| [Form 26](https://ipindia.gov.in/storage/uploads/docs-operator/a7c7f5c7-3be3-4a8c-ba57-07c06ee91184.pdf) | Power of attorney, if using an agent | Nil |

Extra charges beyond 30 sheets or 10 claims: ₹160 per extra sheet, ₹320 per extra claim (e-filing, lower slab). Keep the provisional under those limits — it is a placeholder, not the full case.

Official fee schedule: [First Schedule](https://ipindia.gov.in/storage/uploads/docs-operator/d7bed07b-5c56-404b-a0c8-152b4bd18f0f.pdf)

### 5c. Before you hit submit, confirm

- Applicant name, address and nationality are **exactly** as in the IP cell reply — individuals, or the institution, or both with a stated share.
- All inventors named on Form 5, in the same order as Form 1.
- The provisional describes the **full breadth** you may later claim — anything omitted cannot be added to the complete specification.
- You have the signed inventor agreement and, if applicable, the college NOC, scanned and stored.

### 5d. Immediately after

Save into `03_filed/`: the application number, the e-receipt, the filed PDFs with a timestamp, and the Form 1 acknowledgement. Then, and only then, the manuscript can go out.

---

## Stage 6 — After filing: the 12-month clock

| Deadline | What | Consequence of missing it |
|---|---|---|
| T+12 months | Complete specification (Form 2 complete) | Application lapses — **no extension exists** |
| T+18 months | Automatic publication | You can pull it earlier with Form 9 (₹2,500) |
| By T+48 months | Request for Examination, Form 18 (₹4,000) | Nothing is ever examined; application is treated as withdrawn |
| On FER | Reply within 6 months, extendable by 3 (Form 4) | Application deemed abandoned |
| Year 3 onward | Renewals | Patent ceases |

Put these five dates into a calendar today, with reminders at 30 days before each.

**Decision point at month 9–10:** the complete specification costs real money (agent drafting again, plus any extra claims). Decide then, using what has changed — a working pilot, a grant, an incubator offer, or nothing. Letting the provisional lapse costs you nothing further and is a legitimate outcome.

---

## What to keep, and where

```
roadresq/
  patent/
    01_invention_disclosure/   disclosure form, architecture, algorithms, novelty statement, dated log
    02_prior_art/              prior-art-log.md, saved search screenshots, agent's opinion
    03_filed/                  application number, e-receipt, filed PDFs, Form 1 ack
    04_correspondence/         IP cell emails, NOC, inventor agreement, agent quotes
    05_deadlines.md            the five dates above
```

Two habits that save student teams: every call with the IP cell or an agent gets a follow-up email summarising what was agreed ("as discussed, the college will…"), and nothing about the invention goes to a public channel — no LinkedIn post, no GitHub push, no competition portal — until `03_filed/` has an application number in it.
