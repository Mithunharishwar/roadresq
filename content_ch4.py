"""Chapter 4 - Methodology."""

BLOCKS = [
    ("chapter", "4", "METHODOLOGY"),

    ("h2", "4.1", "INTRODUCTION"),
    ("p", "This chapter states the method behind each stage of the platform: how a request is represented, how the "
          "lifecycle is enforced, how the candidate set is retrieved and filtered, how the ranking score is composed, "
          "how the classification and detection stages decide, and how settlement and recalibration are performed. "
          "The formulation is given before the implementation because the parameters that appear in the equations are "
          "the parameters that the evaluation varies in Chapter 6."),

    ("h3", "4.1.1", "Request Representation and Trigger Capture"),
    ("p", "A request is represented as a single record whose identifier is the join key for every downstream artefact. "
          "The record carries the requesting identity, the vehicle and its class, the position at the time of the "
          "request with its accuracy radius, the fault description and any attached evidence, the resolved service "
          "class and posterior, the fixed tariff, the assigned crew, the assignment and arrival timestamps, the "
          "lifecycle status, the settlement reference and the rating. Holding the service class, the tariff and the "
          "assignment as fields of the same record allows a database-level constraint to enforce that no request "
          "carries a tariff inconsistent with its class, which converts a class of application bugs into an integrity "
          "violation."),
    ("p", "A trigger is recorded with its source, because the three paths carry different trust. An explicit control is "
          "a direct statement of intent. A voice keyword is evaluated locally over a short rolling window, so the "
          "audio never leaves the device until the keyword has matched, and the full recognition session is opened "
          "only afterwards; this bounds the background power cost and keeps the capture local. An impact event is an "
          "unverified claim and is never treated as a request until it has been confirmed, as described in "
          "Section 4.1.8."),
    ("fig", "fig_pipeline.png", "4.1",
     "End-to-end processing pipeline as nine stages, with the recalibration loop that returns settled outcomes to the "
     "allocation terms and the detection thresholds.", 6.2),

    ("h3", "4.1.2", "Lifecycle State Machine and Transition Table"),
    ("p", "The lifecycle is defined by a set of states and a transition table. A transition is admitted only if the "
          "table contains an entry for the current state, the requested next state and the role of the caller; "
          "otherwise the request is rejected with the current state and the set of states reachable from it, so that a "
          "client can recover without guessing. The states and the legal progression are shown in Figure 4.2."),
    ("fig", "fig_lifecycle.png", "4.2",
     "Request lifecycle. The forward path runs from creation to closure; failure states are reachable from the stages "
     "at which the corresponding failure can occur and are recorded with a reason code.", 6.2),
    ("p", "Concentrating the transition logic in one table rather than distributing it across handlers has three "
          "consequences. An illegal transition is unrepresentable rather than merely unlikely, which eliminates the "
          "partially applied transition as a failure mode. Every transition is written with a server-side timestamp, "
          "so the duration of each phase is measurable without reference to client clocks. And the table is the single "
          "definition of the lifecycle, so an audit of a request can be read as a walk through it."),
    ("p", "Two transitions deserve comment because they carry domain meaning. The arrival transition is validated "
          "against the crew's reported position, so a crew cannot record an arrival from a position inconsistent with "
          "the request location; an inconsistent attempt is recorded as an anomalous arrival and rejected. The "
          "completion transition is the only one that may write a settlement, and it is idempotent with respect to a "
          "client-supplied operation identifier, so a retry caused by a network interruption cannot produce a second "
          "charge."),

    ("h3", "4.1.3", "Region Resolution and Geospatial Retrieval"),
    ("p", "Distance between two points is computed with the haversine form of the great-circle distance, which is "
          "numerically stable for the short separations that occur within a city:"),
    ("eq", "d = 2R \u00b7 arcsin( \u221a[ sin\u00b2(\u0394\u03c6/2) + cos\u03c6\u2081 \u00b7 cos\u03c6\u2082 \u00b7 sin\u00b2(\u0394\u03bb/2) ] )",
     "(4.1)"),
    ("p", "where \u03c6 is latitude, \u03bb is longitude and R is the mean earth radius. Great-circle distance is used for "
          "the eligibility test and for the distance term of the score because it requires only the two endpoints and "
          "can therefore be evaluated inside the index traversal. Network distance, obtained from the routing provider, "
          "is used only for the arrival estimate and the route polyline, because the great-circle distance is "
          "systematically shorter than the drivable distance and would produce a systematically optimistic estimate."),
    ("p", "A request is first resolved to an administrative region. The region determines the candidate pool, because a "
          "crew assigned outside its own operating region cannot be held to the service terms of the request. A "
          "circular range query of radius R is then issued against the position index, with R defaulting to ten "
          "kilometres. If the filtered candidate set is empty, R is multiplied by a relaxation factor of 2.5 for at "
          "most two rounds, and a request served from a relaxed round is flagged as degraded so that its arrival error "
          "can be excluded from the accuracy aggregates."),

    ("h3", "4.1.4", "Eligibility Filtering"),
    ("p", "Eligibility is a conjunction of predicates evaluated before any ranking. A crew m is eligible for request r "
          "only if"),
    ("eq", "E(r) = { m \u2208 M : verified(m) \u2227 online(m) \u2227 available(m) \u2227 fit(m, k\u1d63) > 0 "
           "\u2227 fresh(m, t) \u2227 d(m, r) \u2264 \u03c1\u2098 }", "(4.2)"),
    ("p", "where k\u1d63 is the service class of the request, \u03c1\u2098 is the crew's own declared service radius and "
          "fresh(m, t) requires the reported position to be younger than the staleness bound. The distinction between "
          "the search radius and the crew's own radius matters: a crew with a narrow declared radius may lie inside "
          "the search radius while the request lies outside the crew's radius, and such a crew must be excluded "
          "because it would decline the job. Each exclusion is recorded with a reason code, which is what allows the "
          "administrator console to explain why a request found no crew."),

    ("h3", "4.1.5", "The Weighted Allocation Score"),
    ("p", "The eligible set is ranked by a weighted sum of six normalised terms. The proximity term converts distance "
          "into a decreasing score over the search radius:"),
    ("eq", "P\u0302(m, r) = max( 0, 1 \u2212 d(m, r) / R )", "(4.3)"),
    ("p", "The remaining terms are the service match, which is one when the crew's declared classes include the "
          "requested class and zero otherwise; the availability term, which reflects the crew's remaining capacity; "
          "the verification term, which distinguishes a verified capability from a merely declared one; the workload "
          "term, which penalises a crew already carrying work; and the rating term, which is the shrunk reputation "
          "estimate of Section 4.1.6. The total score is"),
    ("eq", "S(m, r) = w\u209a\u00b7P\u0302 + w\u209b\u00b7service + w\u2090\u00b7availability + "
           "w\u1d65\u00b7verification + w\u2097\u00b7workload + w\u1d63\u00b7rating", "(4.4)"),
    ("p", "with the weights held as configuration. The defaults used in the present implementation are listed in "
          "Table 4.1. They are deliberately simple and are not claimed to be optimal: proximity dominates because "
          "travel time is the largest single component of the time to resolution, service compatibility carries the "
          "second largest weight because a capable crew at a moderate distance is worth more than an incapable crew "
          "next door, and verification is weighted so that a capability mismatch cannot be traded against proximity."),
    ("tab", "4.1", "Default allocation weights and their rationale",
     ["Term", "Symbol", "Default", "Rationale"],
     [["Proximity", "w\u209a", "0.45", "Travel time is the largest component of the time to resolution"],
      ["Service compatibility", "w\u209b", "0.20", "A capable crew at moderate distance beats an incapable neighbour"],
      ["Availability", "w\u2090", "0.15", "Remaining capacity predicts whether the offer will be accepted"],
      ["Verification", "w\u1d65", "0.10", "A verified capability outranks a merely declared one"],
      ["Workload", "w\u2097", "0.05", "Penalises a crew already carrying work"],
      ["Rating", "w\u1d63", "0.05", "Shrunk reputation; small weight until observations accumulate"]],
     [1.55, 0.75, 0.85, 3.15]),
    ("p", "The score returns its factor contributions alongside the total, and the allocation log stores them. This is "
          "the mechanism by which a decision can be explained: an owner, a crew or an administrator can read which "
          "terms produced the ranking, and a disputed assignment can be examined rather than merely asserted."),
    ("fig", "fig_alloc.png", "4.3",
     "Allocation procedure: retrieval, eligibility filtering, scoring, ranked offer with a bounded fallback chain, and "
     "escalation when the chain is exhausted.", 5.0),

    ("h3", "4.1.6", "Reputation and Acceptance Estimation"),
    ("p", "Both the reputation term and the acceptance term estimate a probability from a small and growing number of "
          "observations, and both require shrinkage towards a prior in order to be usable for a crew with no history. "
          "The reputation estimate is"),
    ("eq", "Rep(m) = ( \u03a3\u1d62 s\u1d62 + \u03b1\u00b7s\u2080 ) / ( n\u2098 + \u03b1 )", "(4.5)"),
    ("p", "where s\u1d62 is the rating awarded on the i-th completed job of crew m, n\u2098 is the number of completed "
          "jobs, s\u2080 is the prior mean rating and \u03b1 is the prior strength expressed as an equivalent number of "
          "observations. The acceptance estimate is formed from the offer log in the same way,"),
    ("eq", "Acc(m) = ( a\u2098 + \u03b2\u00b7a\u2080 ) / ( o\u2098 + \u03b2 )", "(4.6)"),
    ("p", "where a\u2098 is the number of offers accepted by crew m, o\u2098 is the number of offers dispatched to it, "
          "a\u2080 is the prior acceptance rate and \u03b2 is the corresponding prior strength. In both estimators the "
          "prior strength governs how quickly observed behaviour displaces the prior, and it is set so that the prior "
          "remains dominant until enough observations exist for the shrinkage to be negligible. A newly verified crew "
          "therefore receives the prior reputation and the prior acceptance probability, which is what allows it to be "
          "allocated work instead of being permanently outranked."),
    ("p", "The capability-fit term takes three values rather than two, which is what makes the verification record "
          "operationally meaningful:"),
    ("eq", "fit(m, k) = 1 if k verified for m;  0.5 if k declared only;  0 otherwise", "(4.7)"),
    ("p", "An unverified crew remains eligible but is outranked by a verified one unless the distance and reputation "
          "terms dominate. This allows the platform to serve a thin network without misrepresenting the verification "
          "state: the crew is dispatched, and the owner is shown that the capability is declared rather than "
          "verified."),

    ("h3", "4.1.7", "Fault Classification and Tariff Resolution"),
    ("p", "The fault description is tokenised and represented as a sparse vector over the union of the corpus "
          "vocabulary and the service taxonomy. Term frequencies are weighted by inverse document frequency,"),
    ("eq", "w(t, r) = tf(t, r) \u00b7 log( N / df(t) )", "(4.8)"),
    ("p", "so that the tokens that discriminate between service classes carry more weight than the tokens that occur in "
          "almost every description. Where a photograph is supplied, a visual embedding is appended to the feature "
          "vector before classification, so that text and image contribute to the same posterior rather than being "
          "reconciled by a separate rule. The posterior over classes is"),
    ("eq", "P(k | x) = exp(z\u2096) / \u03a3\u2c7c\u2208C exp(z\u2c7c)", "(4.9)"),
    ("p", "The dispatched class is not the maximum-posterior class. Because a class-pair cost matrix is available from "
          "the tariff structure, the class that minimises expected cost is selected:"),
    ("eq", "k* = argmin\u2096\u2208C \u03a3\u2c7c\u2208C P(j | x) \u00b7 cost(k, j)", "(4.10)"),
    ("p", "The cost matrix is derived from the tariff table rather than estimated, and cost(k, j) is the difference "
          "between the tariff of class k and the true cost of class j plus a re-dispatch penalty. The effect is to bias "
          "ambiguous cases away from towing and towards the lighter classes, because an unnecessary tow is the more "
          "expensive error. This is a stated policy rather than a statistical property of the classifier, and it is "
          "recorded as such. The classification is dispatched only if the posterior mass on the selected class exceeds "
          "a confidence floor; below the floor a bounded disambiguation dialogue asks for the one additional "
          "observation that separates the leading classes, and the classification is repeated on the supplemented "
          "input."),

    ("h3", "4.1.8", "Sensor-Triggered Incident Detection"),
    ("p", "The detector operates on the accelerometer and gyroscope streams at the interval the platform can achieve, "
          "which is a hint rather than a guarantee on Android. Two features are computed incrementally as each sample "
          "arrives. The first is the resultant magnitude of proper acceleration,"),
    ("eq", "|a| = \u221a( a\u2093\u00b2 + a\u1d67\u00b2 + a\u1d69\u00b2 )", "(4.11)"),
    ("p", "and the second is the jerk, computed as the first difference of the magnitude normalised by the measured "
          "sampling interval rather than the requested one:"),
    ("eq", "j[n] = ( |a|[n] \u2212 |a|[n\u22121] ) / \u0394t\u2098\u2091\u2090\u209b", "(4.12)"),
    ("p", "A candidate is raised at the first sample at which both the magnitude and the jerk exceed their thresholds. "
          "The candidate is then validated over a window of W samples by requiring the count of qualifying samples to "
          "exceed a minimum, which suppresses isolated spikes and single-sample sensor faults. A validated candidate "
          "is checked against a local suppression interval and then transmitted to the incident service with the raw "
          "feature values that produced it, so that the thresholds can later be re-selected from observed data."),
    ("p", "The incident service applies three further checks: a per-device rate limit, a check that the device has not "
          "produced a trigger within the suppression interval, and a check that the device is in a state consistent "
          "with movement, which prevents a trigger produced while the device rests on a workshop bench from being "
          "propagated. A validated and accepted trigger does not dispatch. It presents a confirmation prompt with a "
          "bounded response window; an affirmative response converts the trigger into an ordinary request, a negative "
          "response discards it and records a false positive against the operating point, and no response within the "
          "window escalates to the emergency contact designated by the owner without dispatching a crew. The "
          "three-way outcome is deliberate: a contact escalation is cheap and reversible, whereas a crew dispatch is "
          "neither."),

    ("h3", "4.1.9", "Arrival Estimation, Settlement and Payout"),
    ("p", "The arrival estimate for an offer or a tracking update is"),
    ("eq", "T\u0302 = d_route / v_eff(t) + \u03c4_prep", "(4.13)"),
    ("p", "where d_route is the remaining network distance on the published route, v_eff is an effective speed and "
          "\u03c4_prep is a preparation allowance for loading equipment and departing. The effective speed is not a "
          "constant: it is estimated per region and per hour of day from the observed relation between the network "
          "distance of completed jobs and their measured travel duration, and it is recomputed on the recalibration "
          "interval. The estimate is therefore learned rather than nominal, and its accuracy is measurable against the "
          "recorded arrival timestamp, which is the mechanism by which it improves. An estimate is pushed to the owner "
          "only when it differs from the last published value by more than a change threshold."),
    ("p", "The tariff written at classification is immutable for the duration of the job. On completion the authorised "
          "amount is captured and the payout obligation is computed as"),
    ("eq", "Pay(m) = C \u00b7 (1 \u2212 c) \u2212 F", "(4.14)"),
    ("p", "where C is the captured amount, c is the commission rate and F is a fixed platform fee applied where the "
          "platform incurs a cost independent of the job value. The obligation is written to an append-only ledger "
          "keyed by the request identifier, and the ledger entry records the captured amount, the commission, the fee "
          "and the resulting payout, so that the arithmetic of the settlement is reproducible from the stored record "
          "alone."),

    ("h3", "4.1.10", "Algorithms"),
    ("p", "The procedures above are stated as four algorithms. Each is given with its purpose, its input, its "
          "processing and its complexity, in which N is the number of indexed crews, k is the size of the eligible "
          "set, C is the number of service classes and B is the number of offer rounds in the fallback chain."),

    ("h4", "Algorithm 4.1  Eligible Candidate Retrieval"),
    ("code", "allocation.py", """INPUT   request r (position, service class, vehicle class), radius R, index I
OUTPUT  eligible set E(r), degraded flag

1  region = resolve_region(r.position)
2  rounds = 0
3  REPEAT
4      candidates = I.radius_query(r.position, R)          # O(log N + k)
5      E = []
6      FOR each m IN candidates
7          reasons = []
8          IF NOT verified(m)            : reasons.append(NOT_VERIFIED)
9          IF NOT online(m)              : reasons.append(OFFLINE)
10         IF NOT available(m)           : reasons.append(UNAVAILABLE)
11         IF at_capacity(m)             : reasons.append(AT_CAPACITY)
12         IF NOT service_match(m, r)    : reasons.append(SERVICE_MISMATCH)
13         IF NOT vehicle_match(m, r)    : reasons.append(VEHICLE_MISMATCH)
14         IF location_age(m) > TTL      : reasons.append(LOCATION_STALE)
15         IF region(m) != region        : reasons.append(REGION_MISMATCH)
16         IF distance(m, r) > m.radius  : reasons.append(OUT_OF_RADIUS)
17         IF reasons is empty           : E.append(m)
18     IF E is empty AND rounds < 2
19         R = R * 2.5 ;  rounds = rounds + 1
20 UNTIL E is not empty OR rounds = 2
21 RETURN E, (rounds > 0)""", "4.1", "Eligibility filtering with bounded radius relaxation"),

    ("h4", "Algorithm 4.2  Weighted Allocation with Bounded Fallback"),
    ("code", "allocation.py", """INPUT   request r, eligible set E, weights w, offer window W, bound B
OUTPUT  assigned crew, or escalation record

1  IF E is empty : RETURN escalate(NO_MECHANIC_AVAILABLE)
2  scored = []
3  FOR each m IN E
4      p = max(0, 1 - distance(m, r) / R)
5      s = w.proximity*p + w.service*service_match(m, r)
6            + w.availability*availability(m) + w.verification*verify(m)
7            + w.workload*workload(m) + w.rating*reputation(m)
8      scored.append((s, m, factors_of(s)))
9  scored.sort_descending()                              # O(k log k)
10 FOR i = 0 TO min(B, len(scored)) - 1
11     crew = scored[i]
12     outcome = dispatch_offer(crew, r, W)              # server-side timer
13     IF outcome = ACCEPTED
14         write_assignment(r, crew)
15         RETURN crew, scored[0:i+1]
16     IF outcome = DECLINED
17         record_decline(crew, r) ;  update_acceptance(crew)
18     ELSE
19         record_expiry(crew, r)
20 RETURN escalate(OFFER_CHAIN_EXHAUSTED)""", "4.2", "Scoring, ranked offer and bounded fallback"),

    ("h4", "Algorithm 4.3  Cost-Sensitive Fault Classification"),
    ("code", "pricing.py", """INPUT   description text x, optional image, cost matrix K, floor c
OUTPUT  service class k*, tariff, or disambiguation request

1  v = tfidf_vector(x)
2  IF image present : v = concat(v, embed(image))        # same posterior
3  z = model_linear_scores(v)
4  P = softmax(z)                                        # Eq. 4.9
5  k* = argmin_k SUM_j P[j] * K[k][j]                    # Eq. 4.10
6  IF P[k*] < c
7      RETURN disambiguate(top_two(P), x)
8  tariff = tariff_table[k*][vehicle_class]
9  write(r, class = k*, posterior = P, tariff = tariff)   # immutable thereafter
10 RETURN k*, tariff""", "4.3", "Cost-sensitive classification and tariff fixation"),

    ("h4", "Algorithm 4.4  Client-Side Impact Detection"),
    ("code", "sensor_detector.dart", """INPUT   accelerometer and gyroscope stream, thresholds A, J, window W, count Q
OUTPUT  validated trigger, or nothing

1  buffer = ring_buffer(W) ;  qualifying = 0
2  ON SAMPLE s AT time t
3      dt = t - t_prev                                  # measured, not requested
4      mag = sqrt(s.x^2 + s.y^2 + s.z^2)                # Eq. 4.11
5      jerk = (mag - mag_prev) / dt                     # Eq. 4.12
6      IF mag > A AND jerk > J
7          candidate = true ;  qualifying = qualifying + 1
8      buffer.push(mag, jerk)
9      IF candidate AND qualifying >= Q
10         IF now - last_trigger < suppression
11             RETURN
12         last_trigger = now
13         send_to_incident_service(features = buffer.raw())
14     IF now - window_start > W
15         qualifying = 0 ;  candidate = false""", "4.4", "Multi-feature impact detection with window validation"),

    ("tab", "4.2", "Runtime parameters of the allocation, classification and detection stages",
     ["Parameter", "Meaning", "Value used"],
     [["R (default)", "Search radius around the resolved region", "10 km"],
      ["Relaxation factor", "Multiplier applied when the eligible set is empty", "2.5\u00d7, at most 2 rounds"],
      ["Position staleness bound", "Age beyond which a crew position is not trusted", "900 s"],
      ["Offer window", "Time a crew has to accept an offer", "server-side timer"],
      ["B (fallback bound)", "Maximum offers dispatched per request", "3"],
      ["Weights", "Proximity / service / availability / verification / workload / rating",
       "0.45 / 0.20 / 0.15 / 0.10 / 0.05 / 0.05"],
      ["Confidence floor", "Posterior below which disambiguation is triggered", "class-dependent"],
      ["Assumed speed", "Nominal speed used when the routing provider is unavailable", "30 km/h"],
      ["Staleness of ETA", "Change threshold before an estimate is pushed", "configured"]],
     [1.55, 3.0, 1.75]),

    ("h2", "4.2", "SUMMARY"),
    ("p", "This chapter has stated the method for each stage of the platform: the request record and its triggers, the "
          "transition table that governs the lifecycle, the retrieval and eligibility rules that construct the "
          "candidate set, the six-term score that ranks it, the shrunk estimators that supply the acceptance and "
          "reputation terms, the cost-sensitive classifier that fixes the tariff, the multi-feature detector that "
          "validates an impact, and the arrival and settlement arithmetic. The parameters introduced here are the "
          "parameters varied in the evaluation, and the algorithms stated here are the procedures tested in the next "
          "chapter."),
]
