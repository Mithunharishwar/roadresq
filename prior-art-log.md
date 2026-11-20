# Prior-art log — RoadResQ

Preliminary scan, 3 November 2026. Source: Google Patents query API (worldwide corpus). This is a **screening pass**, not a freedom-to-operate or patentability opinion — a registered agent must do the definitive search.

## How the search was run

Five queries, each against the worldwide corpus and again filtered to India. Query strings are reproduced exactly so you can repeat or extend them.

```
Q1  "roadside assistance" dispatch provider ranking
Q2  "roadside assistance" impact detection automatic escalation
Q3  dispatch "spatial index" service provider allocation
Q4  "vehicle breakdown" voice request assistance platform
Q5  roadside assistance "service capability" partner matching job assignment
```

| Query | Worldwide hits | India-filtered hits |
|---|---|---|
| Q1 | 255 | 0 |
| Q2 | 1,983 | 0 |
| Q3 | 127 | 0 |
| Q4 | 1,715 | 0 |
| Q5 | 0 | 0 |

**Important caveat on the zeros.** The India filter returned nothing for every query, including one that returns 1,715 worldwide. That is not evidence that India has no filings in this space — it reflects that Google Patents carries only bibliographic data for most Indian applications, not searchable full text. **The Indian landscape is still unknown and must be searched on the IP India portal** (https://iprsearch.ipindia.gov.in/PublicSearch), by applicant name, application number and abstract, and in the weekly Journal. Do not tell an agent "India is clear" on the basis of this table.

Q5 returned zero results worldwide, which means the phrase combination is too narrow rather than that nothing exists. Re-run it as `roadside assistance capability matching assignment` without the quoted phrases.

---

## Cluster 1 — Roadside assistance dispatch and provider ranking (highest risk)

| Publication | Title | Applicant | Priority |
|---|---|---|---|
| US11132629B2 | Crowdsourced roadside assistance service provider assignment system | Allstate Insurance | 2014-07-30 |
| US9760846B1 | Roadside assistance service provider assignment system | Allstate Insurance | 2014-07-30 |
| US9940596B1 | Roadside assistance management | Allstate Insurance | 2014-03-13 |
| US9412130B2 | Assistance on the go | Allstate Insurance | 2009-08-19 |
| US9684924B2 | Assistance on the go | Allstate Insurance | 2009-08-19 |
| US10410148B1 | Roadside assistance | Allstate Insurance | 2009-08-19 |
| US10382900B1 | Roadside assistance | Allstate Insurance | 2009-08-19 |
| US10600127B1 | Assistance on the go | Allstate Insurance | 2009-08-19 |
| US20090313077A1 | Consumer initiated, service provider direct dispatching system | G. Y. Wheeler | 2008-06-17 |
| JP2022014293A | Road service dispatch system | Prestige International | 2020-07-06 |
| US20080014908A1 | System and method for coordinating customized mobility services | A. Vasant | 2006-07-17 |

**What this cluster discloses.** A dispatch platform that receives a roadside request, selects among providers, and ranks them. US9412130B2's claims recite prioritised ranking of roadside assistance providers on availability, telematics-derived diagnosis, and preset preferences; US11132629B2 recites provider *certification* as a claim element — that is capability matching in substance.

**Implication for you.** A claim to "rank roadside assistance partners by distance, capability and reputation" is very likely anticipated or obvious over this family. The broad framing will not survive examination.

**Where you can still stand:** the specific composite where capability operates as a **hard constraint** derived from a service-class taxonomy produced by the confidence-floored classifier, combined with a **shrunk reputation estimate** and a **lagged acceptance estimate**, executed under a **bounded offer chain with re-dispatch**. That combination is not what Allstate claims, and the shrunk-reputation plus lagged-acceptance pair is the least crowded part. Draft narrowly around it, and put the measured re-dispatch reduction in the specification as the technical effect.

---

## Cluster 2 — Impact detection and automatic escalation (high risk, broad art)

| Publication | Title | Applicant | Priority |
|---|---|---|---|
| US10043323B1 | Accident response using autonomous vehicle monitoring | State Farm | 2014-05-20 |
| US20250036123A1 | Autonomous vehicle operation feature monitoring | State Farm | 2014-05-20 |
| US20240059323A1 | Dynamic emergency detection and automated responses | GM Cruise | 2022-08-18 |
| US12345536B2 | Smart home sensor malfunction detection | State Farm | 2016-01-22 |
| US9342976B2 | Incident response system | Israelife Foundation | 2008-05-09 |
| US10943463B1 | Technologies for assistance and security services | A. G. Clark | 2018-02-19 |
| US20140309853A1 | Vehicle diagnostics and roadside assistance | Flextronics | 2013-04-15 |
| EP3411866B1 | Methods and devices for providing information about a vehicle | Volkswagen | 2016-02-03 |
| WO2018017075A1 | Crowd-sourced emergency response | Ford Global Technologies | 2016-07-20 |

**What this cluster discloses.** Sensor-triggered incident detection followed by automatic notification or response is heavily worked, particularly by insurers and autonomous-vehicle programmes. Crash detection → emergency call is old art.

**Implication for you.** Do not claim "detect impact from sensors and escalate" alone. Your defensible specificity is the **two-stage confirmation**: impact signature detected on-device, a bounded confirmation window opened in-application, and escalation only on expiry without user input — plus the handoff into a *service-class* dispatch path rather than a generic emergency call. Claim the handoff, not the detection.

---

## Cluster 3 — Voice and platform framing (low risk, low value)

Q4 surfaced mostly autonomous-vehicle and telematics material — KR102342623B1 (voice and connection platform), EP4229855B1 (event determination for mobility providers), ES3013498T3 (vehicle monitoring and maintenance). Nothing here reads on a voice-keyword request flow specifically.

**Implication.** "Voice-first" is a useful specification detail and a good product differentiator, but a weak claim element. Do not build an independent claim on speech input.

---

## Cluster 4 — Spatial index / geographic allocation (not yet characterised)

Q3 returned database and telecom material (Oracle stream-data indexing, Snowflake indexed geospatial search, HERE comparative routing) rather than dispatch art. The query was a keyword mismatch — "spatial index" pulls data-infrastructure patents.

**What to do instead.** Search by CPC rather than by words: `G06Q10/08` (logistics), `G06Q50/30` (transport), `G08G1/00` (traffic control), `G01C21/34` (route search). Then read the dispatch-specific hits. Spatial indexing on its own is well-known infrastructure and should be described as the implementation environment, never claimed as the invention.

---

## Summary: risk per claim family

| Claim family | Prior-art risk | Recommendation |
|---|---|---|
| Capability-constrained allocation with composite scoring | **High** — Allstate family is close | Narrow to hard capability constraint + shrunk reputation + lagged acceptance + bounded offer chain; never claim ranking in general |
| Sensor-triggered escalation | **High** for detection, **moderate** for the confirmation-window handoff | Claim the two-stage confirmation and the handoff into service-class dispatch |
| Append-only payout ledger with captured tariff | **Low** in this pass, unverified | Keep as dependent claim; search "tamper-evident ledger service payment" before relying on it |
| Voice-first request flow | Low, but weak | Specification detail only |

## Gaps you must close before the agent drafts

1. **Indian filings.** Search IP India by applicant (Allstate, Prestige, insurance incumbents, Indian roadside startups) and scan the last 12 months of the Patent Journal. None of this is covered above.
2. **Indian startup filings in this space.** Search by applicant name for the obvious commercial players, not by keyword — Indian full text is not keyword-searchable.
3. **Non-patent literature.** Your own field's papers on capability-aware task allocation and reputation shrinkage in two-sided markets. The agent needs these; examiners cite them.
4. **Expired art.** Several Allstate filings from 2009 will expire around 2029–2030. Expired art still destroys novelty — it does not become free to claim.

## Reproducing this scan

Open https://patents.google.com/ and paste a query string; add `&country=IN` to the URL for the India filter. For a structured pull, the same endpoint used here is:

```
https://patents.google.com/xhr/query?url=<url-encoded "q=<query>">
```

The script that produced the table above is `_prior_art_scan.py` in this folder — edit the `QUERIES` list and re-run to extend coverage.
