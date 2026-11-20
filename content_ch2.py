"""Chapter 2 - Related Work."""

BLOCKS = [
    ("chapter", "2", "RELATED WORK"),

    ("h2", "2.1", "INTRODUCTION"),
    ("p", "The problem of dispatching a rescue crew to a stranded vehicle sits at the intersection of four research "
          "traditions: spatio-temporal data structures for proximity retrieval, assignment and matching under "
          "uncertainty, short-text classification for fault description, and mobile sensing for incident detection. "
          "It also depends on a body of practice in platform engineering, because a dispatch decision is only useful "
          "if the platform that makes it is reliable enough to be trusted at the moment it is needed."),
    ("p", "This chapter reviews the literature and the technical documentation relevant to those four areas. The "
          "review is organised by mechanism rather than by chronology, because the mechanisms are what the design "
          "reuses. It closes by stating five gaps that the surveyed work leaves open, which are the gaps that "
          "RoadResQ is designed to address."),

    ("h2", "2.2", "RELATED WORKS"),

    ("h3", "2.2.1", "Geospatial Retrieval and Spatial Indexing"),
    ("p", "The retrieval step of any dispatch system answers a circular range query: which providers lie within a "
          "radius of the request. The naive answer scans every provider, which costs time linear in the size of the "
          "provider set and becomes unacceptable when the query is issued once per request. Bentley [3] introduced the "
          "multidimensional binary search tree, which partitions the space along alternating axes and supports "
          "associative search in time logarithmic in the number of stored points on average. Guttman [11] generalised "
          "the idea to the R-tree, in which objects are grouped into minimum bounding rectangles and the tree index is "
          "maintained over those rectangles rather than over individual coordinates. Beckmann et al. [2] refined the "
          "structure into the R*-tree, which reduces overlap between sibling rectangles by a forced reinsertion "
          "strategy and therefore improves range-query performance for the skewed distributions that occur in real "
          "urban data."),
    ("p", "The practical lesson from this line of work is not that a particular tree should be implemented, because "
          "production document stores already provide one. It is that the index must be maintained incrementally and "
          "that its entries must be invalidated explicitly. A provider's position is a transient quantity; an index "
          "that retains a stale entry answers a query about where a provider used to be. MongoDB exposes a two-"
          "dimensional sphere index that supports proximity queries and distance computation directly in the query "
          "language [15], and the reference implementation used in this project relies on that facility for durable "
          "queries while maintaining a smaller in-memory index for the live positions that the allocation path "
          "consumes. The staleness bound is therefore a first-class parameter of the retrieval step rather than an "
          "implementation detail."),

    ("h3", "2.2.2", "Assignment, Matching and Scoring"),
    ("p", "Once a candidate set exists, the platform must choose one member of it. The simplest rule is nearest-first, "
          "which is optimal for a pure transport objective and is the rule that ride-hailing platforms apply to "
          "passenger pickup. The roadside case differs because the service is not transport but repair, and a crew "
          "that arrives quickly without the required capability has not delivered the service. The matching "
          "literature addresses this by treating assignment as a constrained optimisation over a bipartite graph, "
          "usually with a cost that combines distance with a compatibility term. In the online setting that applies "
          "here, requests arrive continuously and the assignment must be made without knowledge of future requests, "
          "so a greedy rule over a scored candidate set is the practical alternative to a global optimum that cannot "
          "be computed."),
    ("p", "A recurring difficulty in scored assignment is the treatment of providers with little history. A term that "
          "estimates a probability from a small number of observations is unstable, and a naive estimate will either "
          "exclude a new provider permanently or promote it on the strength of a single favourable observation. The "
          "standard remedy is shrinkage towards a prior, in which the observed mean is blended with a prior mean in "
          "proportion to the number of observations. The prior strength is then the parameter that governs how quickly "
          "observed behaviour displaces the prior, and it is set so that the prior remains dominant until enough "
          "observations exist for the shrinkage to be negligible. RoadResQ applies this estimator to both the "
          "acceptance rate and the reputation of a crew, which is what allows a newly verified crew to be allocated "
          "work rather than being permanently outranked by an established one."),

    ("h3", "2.2.3", "Short-Text Classification for Fault Triage"),
    ("p", "The fault description supplied by an owner is short, informal and frequently ambiguous: \u201cnot starting\u201d "
          "may describe a discharged battery, a failed starter motor or an empty fuel tank. Salton and Buckley [21] "
          "established that weighting term frequencies by inverse document frequency improves discrimination in "
          "automatic text retrieval, because it suppresses the terms that occur in almost every document and "
          "emphasises the terms that distinguish among classes. The same weighting is effective for short-text "
          "classification into a small fixed taxonomy, and a linear model over the weighted representation is both "
          "accurate enough for a six-class problem and cheap enough to evaluate inside a request handler."),
    ("p", "Two design decisions distinguish the classification step of this project from a plain maximum-posterior "
          "rule. The first is that the decision is taken by minimising expected cost rather than by maximising the "
          "posterior, because the tariff structure supplies a cost for each confusion and the cost of an unnecessary "
          "tow is much larger than the cost of a delayed classification. The second is that a confidence floor "
          "triggers a disambiguation dialogue rather than a guess, which converts an uncertain classification into a "
          "short interaction instead of an incorrect dispatch. Calibration of the posterior is a prerequisite for the "
          "confidence floor to mean anything, and Guo et al. [10] showed that modern neural classifiers are "
          "systematically overconfident, which is the reason the floor in this project is applied to a calibrated "
          "posterior rather than to a raw softmax output. Conformal prediction [1] offers a distribution-free "
          "alternative in which a prediction set rather than a point estimate is returned with a coverage guarantee; "
          "the approach is attractive where a classifier must abstain, and it is noted here as a direction that the "
          "current implementation does not yet take."),

    ("h3", "2.2.4", "Incident Detection from Mobile Sensors"),
    ("p", "A sensor-triggered request depends on distinguishing a genuine impact from the ordinary accelerations of "
          "riding. The published approaches apply a threshold to the resultant acceleration magnitude, optionally "
          "combined with a threshold on the first derivative of the magnitude, and then validate the candidate over a "
          "window so that isolated spikes do not fire a trigger. The mobile platform exposes accelerometer and "
          "gyroscope streams with a requested sampling interval through the sensor plugin [22], and the interval is a "
          "hint rather than a guarantee, so a threshold expressed in units per second must be computed against the "
          "achieved interval rather than the requested one."),
    ("p", "The literature is consistent on one point that has a direct design consequence: a magnitude threshold "
          "alone responds to potholes, kerb strikes and dropped handsets, so a detector tuned to catch every impact "
          "will fire many times per hour of ordinary riding. Because a false dispatch costs a crew's time and an "
          "owner's confidence, while a false prompt costs a single tap, the appropriate architecture is a sensitive "
          "detector followed by a confirmation interaction, not a conservative detector followed by automatic "
          "dispatch. RoadResQ adopts that architecture and reports the detector's operating characteristic as a "
          "detection rate against false alarms per device-hour, which is the form in which the operating cost is "
          "actually incurred."),

    ("h3", "2.2.5", "Platform Engineering, Interfaces and Reliability"),
    ("p", "A dispatch decision is only as useful as the platform that delivers it. Fielding [4] formalised the "
          "representational state transfer style, in which resources are manipulated through a uniform interface and "
          "servers hold no client session state between requests; the style is the reason the service tier of this "
          "project can be replaced or replicated during a deployment without disturbing a job already in progress. "
          "Kleppmann [14] sets out the distinction between the durability guarantees of a transactional store and the "
          "eventual consistency of an analytical one, which justifies the separation of the request record from the "
          "event stream in the present design: an analytics outage must not be able to block a rescue. Newman [16] and "
          "Nygard [17] describe the operational patterns that make such a separation survivable, in particular "
          "idempotency of mutating operations, bounded retry with a fallback, and the treatment of a dependency "
          "outage as a degraded mode rather than as a failure."),
    ("p", "The framework and provider documentation surveyed here is cited because the implementation depends on "
          "specific behaviour that the documentation defines. Flask [6] supplies the request handling and the "
          "blueprint mechanism through which the additive API surface of this project is mounted beside the legacy "
          "handlers; Flask-SocketIO and Socket.IO [23] supply the bidirectional channel over which position updates "
          "and arrival estimates are pushed, with HTTP long-polling as the fallback transport when a native WebSocket "
          "cannot be negotiated. Flutter [7] compiles a single Dart codebase to Android and iOS artefacts, which is "
          "what allows the same request interface to be offered on both platforms. Riverpod [20] provides the state "
          "management through which the client subscribes to a request record and rebuilds the tracking view when the "
          "record changes. The mapping provider [9] supplies geocoding, route computation and encoded polyline "
          "geometry, and the polyline is decoded for rendering so that the route presented to the owner is the route "
          "the crew is following. Spoken guidance during tracking is produced through the text-to-speech plugin [8], "
          "and the payment provider [19] supplies server-side order creation and signature verification, so that the "
          "client never handles a card or account credential. Push delivery of lifecycle events uses the messaging "
          "service [5]."),
    ("p", "Security practice follows the verification standard published by OWASP [18], in particular the requirements "
          "for authenticated access to every mutating endpoint, for authorisation by role at a single enforcement "
          "point, and for the validation of payload schema before a handler is invoked. Quality and test documentation "
          "follow ISO/IEC 25010 [13] and IEEE 829 [12], which together supply the vocabulary used in Chapter 5 for "
          "distinguishing functional suitability from reliability, usability and security, and for recording test "
          "cases in a form that another engineer can execute."),

    ("h2", "2.3", "OBSERVATION FROM RELATED WORKS"),
    ("p", "The survey supports five observations, each of which corresponds to a gap that the present work addresses."),
    ("bul2", [
        ("Gap 1: Capability is absent from the assignment objective.",
         " Spatial indexing is well understood and proximity retrieval is a solved problem, but the dispatch rules "
         "described in the literature and used in practice optimise distance alone. The roadside service is a repair "
         "rather than a transport, so a rule that ignores which crew can perform which repair optimises the wrong "
         "quantity."),
        ("Gap 2: Availability and freshness are assumed rather than verified.",
         " A proximity rule consumes whatever position it is given. Where no staleness bound is applied, the rule "
         "ranks a crew by an obsolete position, and where availability is inferred from a listing rather than "
         "published by the crew, the rule offers jobs to crews that cannot accept them."),
        ("Gap 3: Acceptance behaviour is not modelled, so declines are absorbed as delay.",
         " A decline is not a failure of the platform; it is information about the crew. Systems that do not record "
         "offers and their outcomes must re-offer blindly, and the owner experiences the resulting sequence as an "
         "unexplained wait. The shrinkage estimators described in Section 2.2.2 exist precisely to convert that "
         "record into a ranking term, and no surveyed roadside system does so."),
        ("Gap 4: The price is resolved after the service rather than before it.",
         " Classification of a short fault description into a tariffed service class is a tractable problem, and the "
         "inverse-document-frequency representation of Salton and Buckley [21] is sufficient for it. In practice the "
         "classification is either not performed or not made binding, so the owner commits to a job of unknown cost."),
        ("Gap 5: Initiation assumes a user who can type, and detection assumes a user who can be trusted.",
         " Voice and sensor triggers are studied separately from dispatch, and sensor triggers are usually presented "
         "as autonomous. Neither treatment matches the roadside case, in which the owner may be unable to type and the "
         "sensor may be wrong, so the correct composition is a multi-channel trigger followed by a confirmation."),
    ]),

    ("h2", "2.4", "SUMMARY"),
    ("p", "This chapter reviewed spatial indexing and range retrieval, scored assignment with shrinkage estimators, "
          "short-text classification with cost-sensitive decisions, mobile impact detection, and the platform "
          "engineering practices on which a dispatch service depends. The review shows that each individual mechanism "
          "is mature, and that the gap lies in their composition: no surveyed system combines a capability-constrained "
          "eligibility filter, an explainable weighted ranking, a fixed pre-dispatch tariff and a recorded offer log "
          "in one lifecycle. The design presented in the next chapter is organised around exactly that composition."),
]
