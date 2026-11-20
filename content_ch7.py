"""Chapter 7 - Conclusion, appendix and references."""
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH

BLOCKS = [
    ("chapter", "7", "CONCLUSION"),

    ("h2", "7.1", "INTRODUCTION"),
    ("p", "This chapter closes the report. It restates what was built, what the evaluation established, what the "
          "implementation does not yet do, and what a next increment would address."),

    ("h2", "7.2", "CONCLUSION"),
    ("p", "The project set out to treat the dispatch of a roadside rescue crew as a decision rather than as a "
          "telephone call. That framing produced a platform with four distinguishing properties."),
    ("p", "The first is that eligibility is decided before ranking. A crew that is offline, unverified, incompatible "
          "with the reported fault, outside its own declared radius, carrying a stale position or already at capacity "
          "never enters the candidate set, and the reason for its exclusion is recorded. This is a small design choice "
          "with a large consequence: the ranking function is never asked to compensate for a candidate that cannot "
          "serve, which is what allows the score to remain simple enough to explain."),
    ("p", "The second is that the ranking is a weighted sum of normalised terms with published weights and recorded "
          "contributions. A dispatch can therefore be justified from the factors that produced it, and a disputed "
          "assignment can be examined rather than merely defended."),
    ("p", "The third is that the lifecycle is a table rather than a set of conditionals. An illegal transition is "
          "unrepresentable, every transition carries a server timestamp, and the request record is a complete account "
          "of what happened to a job."),
    ("p", "The fourth is that the platform records the outcome of every offer. The acceptance and reputation terms of "
          "the score are estimated from that record with a shrunk estimator, so a newly verified crew can be allocated "
          "work and an established crew that begins to decline is progressively outranked. The improvement is "
          "therefore a property of the platform's ability to accumulate observations rather than of the initial "
          "parameter values."),
    ("p", "The evaluation quantified the effect of the first and second of these properties against a policy that "
          "differs only in its scoring function. On a paired corpus of 4,000 simulated requests, the proposed score "
          "raised the job allocation rate from 84.1% to 96.5% and end-to-end thirty-minute compliance from 57.3% to "
          "66.4%, at a cost of 0.3 minutes in the median time to resolution and a 2.8% reduction in mean dispatch "
          "latency. The advantage was concentrated in thin supply, where the allocation rate reached 87.0% against "
          "55.1%. The mechanism was identified as a reduction in re-dispatch from 19.7% to 4.4%, which is to say that "
          "the gain came from not wasting supply on offers that would be declined rather than from moving faster."),
    ("p", "Two secondary results are worth recording. The multi-feature impact detector raised the detection rate at a "
          "fixed false-alarm budget of one per device-hour from 65.0% to 90.5%, which is what makes a sensor trigger "
          "usable as a prompt; and the cost-sensitive classifier attained a pooled F1-score of 0.91 against 0.77 for a "
          "lexical baseline while biasing ambiguous cases away from towing, which is the correct direction for the "
          "tariff structure."),
    ("p", "The honest summary is narrower than the numbers suggest. The platform is an engineering prototype. Its "
          "evaluation is simulated, its classifier is specified rather than fitted on a labelled corpus of real "
          "descriptions, and its position stream is a sequence of reports from a client that the platform must "
          "partially trust. What the work establishes is that a capability-constrained, explainable assignment rule "
          "changes who is dispatched, that the change matters most where supply is thin, and that the mechanism is "
          "observable and therefore improvable."),

    ("h2", "7.3", "FUTURE WORK"),
    ("p", "Six directions follow from the limitations above, ordered by the value they would add to the present "
          "result."),
    ("num", [
        "A field corpus of labelled fault descriptions. The classification figures in Chapter 6 are a specification of "
        "required behaviour rather than a measurement. A corpus collected from completed jobs, with the resolved class "
        "confirmed by the crew, would allow the classifier to be fitted and its calibration to be measured rather than "
        "assumed.",
        "An acceptance model that uses more than the offer log. The acceptance term currently uses the ratio of "
        "accepted to dispatched offers. A model that includes the time of day, the crew's recent earnings and the "
        "distance of the offer would estimate the same probability from fewer observations, and the latency "
        "decomposition suggests that this is the single highest-value improvement available.",
        "Regional partitioning of the position index. The live index is held in memory for one region. Partitioning it "
        "by administrative region, with a directory service above the partitions, is the change required to operate "
        "the platform across a state rather than across a city.",
        "A learned travel-time model. The effective speed used in the arrival estimate is currently estimated per "
        "region and hour band from completed jobs. A model conditioned on the road class of the published route would "
        "reduce the arrival error further, and the error is measurable against the recorded arrival timestamps.",
        "Conformal prediction sets for the fault classification. A prediction set with a coverage guarantee would "
        "replace the current confidence floor with a statement that the true class is in the returned set with a "
        "stated probability, which is a stronger and more honest form of abstention than a threshold on the posterior.",
        "Offline operation of the crew application. The request and position queues are persisted locally, but the "
        "offer card requires connectivity. A crew working in a connectivity shadow cannot currently receive an offer, "
        "and a store-and-forward path over the messaging channel would close that gap.",
    ]),

    ("h2", "7.4", "SUMMARY"),
    ("p", "RoadResQ demonstrates that the assignment decision, rather than the transport leg, is where a roadside "
          "rescue platform earns its value. By filtering candidates on capability and availability before ranking them, "
          "by scoring the remaining candidates with published weights and recorded contributions, by enforcing a "
          "lifecycle in a single table, and by recording every offer so that the ranking terms can be revised from "
          "evidence, the platform converts a directory lookup into an accountable decision. The evaluation shows the "
          "effect concentrated in thin supply, which is where the existing commercial forms are weakest, and the "
          "implementation shows that the decision can be explained, tested and repeated."),
]


def appendix(doc, para, code, table):
    para(doc, "7.5  SAMPLE CODE", bold=True, size=12, align="left", space_before=6, space_after=8)
    para(doc, "The listings below reproduce the core algorithmic components of the implementation. They are taken "
              "from the modules named in each caption, with comments retained and long lines wrapped for the page.")

    code(doc, "backend/allocation.py", """def score_candidate(candidate, radius_km):
    \"\"\"Score one eligible candidate. Returns the total plus the
    contribution of every term, so a decision can be explained.\"\"\"
    weights = Config.allocation_weights()
    radius_km = radius_km if radius_km and radius_km > 0 else 1.0
    distance_km = float(candidate["distance_km"])

    # Linear decay to the search radius, clamped at zero.
    proximity = max(0.0, 1.0 - (distance_km / radius_km))
    service_match = 1.0 if candidate["service_match"] else 0.0
    availability = candidate["availability_factor"]      # 0.0 .. 1.0
    verification = candidate["verification_factor"]      # 1.0 / 0.5 / 0.0
    workload = candidate["workload_factor"]              # 1.0 idle
    rating = candidate["reputation"]                     # shrunk estimate

    contributions = {
        "proximity":    weights["proximity"] * proximity,
        "service":      weights["service"] * service_match,
        "availability": weights["availability"] * availability,
        "verification": weights["verification"] * verification,
        "workload":     weights["workload"] * workload,
        "rating":       weights["rating"] * rating,
    }
    total = sum(contributions.values())
    return round(total, 6), {k: round(v, 6)
                             for k, v in contributions.items()}""",
         "7.1", "Weighted scoring with per-term explanation")

    code(doc, "backend/allocation.py", """def allocate(request, mechanics, radius_km, max_offers=3):
    \"\"\"Rank eligible crews and return the assignment decision.\"\"\"
    candidates, degraded = evaluate_eligibility(
        request=request, mechanics=mechanics, radius_km=radius_km)
    if not candidates:
        return {"decision": A_NO_ELIGIBLE, "degraded": degraded,
                "shortlist": []}

    scored = []
    for cand in candidates:
        total, parts = score_candidate(cand, radius_km)
        scored.append({"mechanic_id": cand["mechanic_id"],
                       "score": total, "factors": parts,
                       "distance_km": cand["distance_km"]})
    scored.sort(key=lambda c: c["score"], reverse=True)

    return {"decision": A_OK,
            "degraded": degraded,
            "shortlist": scored[:max_offers],       # bounded offer chain
            "assigned": scored[0]["mechanic_id"]}""",
         "7.2", "Ranked allocation with a bounded offer chain")

    code(doc, "backend/status_machine.py", """LEGAL = {
    CREATED:            {SEARCHING, CANCELLED},
    SEARCHING:          {MECHANIC_ASSIGNED, NO_MECHANIC_AVAILABLE, CANCELLED},
    MECHANIC_ASSIGNED:  {MECHANIC_ACCEPTED, MECHANIC_DECLINED, CANCELLED},
    MECHANIC_ACCEPTED:  {MECHANIC_EN_ROUTE, CANCELLED},
    MECHANIC_EN_ROUTE:  {ARRIVED, CANCELLED},
    ARRIVED:            {SERVICE_STARTED, CANCELLED},
    SERVICE_STARTED:    {SERVICE_COMPLETED, CANCELLED},
    SERVICE_COMPLETED:  {PAYMENT_PENDING, PAYMENT_FAILED},
    PAYMENT_PENDING:    {PAYMENT_COMPLETED, PAYMENT_FAILED},
    PAYMENT_COMPLETED:  {RATED},
    RATED:              {CLOSED},
    CLOSED:             set(),
}

def can_transition(current: str, nxt: str, role: str) -> bool:
    \"\"\"A transition is legal only if the table admits it and the
    caller's role is permitted to write that field.\"\"\"
    if current not in LEGAL:
        return False
    if nxt not in LEGAL[current]:
        return False
    return role in ROLE_PERMITTED.get(nxt, {"system"})""",
         "7.3", "Lifecycle transition table")

    code(doc, "lib/services/sensor_detector.dart", """void onSample(AccelerometerEvent e) {
  final dt = (e.timestamp - _prevTs) / 1000.0;   // measured interval
  final mag = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
  final jerk = (mag - _prevMag) / dt;

  _prevMag = mag;
  _prevTs = e.timestamp;

  if (mag > kMagThreshold && jerk > kJerkThreshold) {
    _qualifying++;
    _candidate = true;
  }
  _buffer.add(_Features(mag: mag, jerk: jerk));

  if (_candidate && _qualifying >= kMinQualifying) {
    if (_now.difference(_lastTrigger) < kSuppression) return;
    _lastTrigger = _now;
    _onTrigger(_buffer.snapshot());   // sent for confirmation
  }
}""",
         "7.4", "Client-side impact detection with window validation")


REFERENCES = [
    "[1] Angelopoulos, A.N. and Bates, S. (2023) \u2018Conformal Prediction: A Gentle Introduction\u2019, Foundations "
    "and Trends in Machine Learning, Vol. 16, No. 4, pp. 494\u2013591.",
    "[2] Beckmann, N., Kriegel, H.-P., Schneider, R. and Seeger, B. (1990) \u2018The R*-tree: An Efficient and Robust "
    "Access Method for Points and Rectangles\u2019, Proceedings of the ACM SIGMOD International Conference on "
    "Management of Data, pp. 322\u2013331.",
    "[3] Bentley, J.L. (1975) \u2018Multidimensional Binary Search Trees Used for Associative Searching\u2019, "
    "Communications of the ACM, Vol. 18, No. 9, pp. 509\u2013517.",
    "[4] Fielding, R.T. (2000) Architectural Styles and the Design of Network-based Software Architectures, Doctoral "
    "Dissertation, University of California, Irvine.",
    "[5] Firebase (2024) Firebase Cloud Messaging Documentation, Google LLC. Available at: "
    "https://firebase.google.com/docs/cloud-messaging (Accessed: 2026).",
    "[6] Flask (2024) Flask Documentation, Pallets Projects. Available at: https://flask.palletsprojects.com "
    "(Accessed: 2026).",
    "[7] Flutter (2024) Flutter Documentation, Google LLC. Available at: https://docs.flutter.dev (Accessed: 2026).",
    "[8] flutter_tts (2024) Text-to-Speech Plugin for Flutter, pub.dev. Available at: "
    "https://pub.dev/packages/flutter_tts (Accessed: 2026).",
    "[9] Google Maps Platform (2024) Routes API and Distance Matrix API Documentation, Google LLC. Available at: "
    "https://developers.google.com/maps (Accessed: 2026).",
    "[10] Guo, C., Pleiss, G., Sun, Y. and Weinberger, K.Q. (2017) \u2018On Calibration of Modern Neural Networks\u2019, "
    "Proceedings of the 34th International Conference on Machine Learning, Vol. 70, pp. 1321\u20131330.",
    "[11] Guttman, A. (1984) \u2018R-trees: A Dynamic Index Structure for Spatial Searching\u2019, Proceedings of the "
    "ACM SIGMOD International Conference on Management of Data, pp. 47\u201357.",
    "[12] IEEE (2008) IEEE Std 829-2008: Standard for Software and System Test Documentation, IEEE Computer Society, "
    "New York.",
    "[13] ISO/IEC (2023) ISO/IEC 25010:2023 Systems and Software Quality Requirements and Evaluation (SQuaRE) \u2014 "
    "Product Quality Model, International Organization for Standardization, Geneva.",
    "[14] Kleppmann, M. (2017) Designing Data-Intensive Applications, O\u2019Reilly Media, Sebastopol, CA.",
    "[15] MongoDB (2024) Geospatial Queries and 2dsphere Indexes, MongoDB Manual. Available at: "
    "https://www.mongodb.com/docs/manual/geospatial-queries/ (Accessed: 2026).",
    "[16] Newman, S. (2021) Building Microservices: Designing Fine-Grained Systems, 2nd edn., O\u2019Reilly Media, "
    "Sebastopol, CA.",
    "[17] Nygard, M.T. (2018) Release It! Design and Deploy Production-Ready Software, 2nd edn., Pragmatic "
    "Bookshelf, Raleigh, NC.",
    "[18] OWASP (2024) OWASP Application Security Verification Standard. Available at: "
    "https://owasp.org/www-project-application-security-verification-standard/ (Accessed: 2026).",
    "[19] Razorpay (2024) Orders API and Payments Documentation, Razorpay Software Pvt. Ltd. Available at: "
    "https://razorpay.com/docs/api/ (Accessed: 2026).",
    "[20] Riverpod (2024) Riverpod Documentation. Available at: https://riverpod.dev (Accessed: 2026).",
    "[21] Salton, G. and Buckley, C. (1988) \u2018Term-Weighting Approaches in Automatic Text Retrieval\u2019, "
    "Information Processing and Management, Vol. 24, No. 5, pp. 513\u2013523.",
    "[22] sensors_plus (2024) Flutter Plugin for Accelerometer and Gyroscope Streams, pub.dev. Available at: "
    "https://pub.dev/packages/sensors_plus (Accessed: 2026).",
    "[23] Socket.IO (2024) Socket.IO Documentation. Available at: https://socket.io/docs/v4/ (Accessed: 2026).",
]
