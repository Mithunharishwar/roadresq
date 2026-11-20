"""Chapter 1 - Introduction."""

BLOCKS = [
    ("chapter", "1", "INTRODUCTION"),

    ("h2", "1.1", "MOTIVATION"),
    ("p", "A vehicle that stops working is not only an inconvenience. On a shoulder of a highway, at night, or on an "
          "unlit arterial road, a stranded driver is exposed to moving traffic while trying to decide who to call. The "
          "decision itself is difficult: the owner usually does not know what has failed, cannot judge which nearby "
          "workshop handles that class of fault, and has no reliable way of knowing when help will arrive or what it "
          "will cost. The information needed to make the decision exists in fragments, spread across workshop "
          "telephone numbers, informal referrals and the owner's own recollection."),
    ("p", "Chennai illustrates the problem well. The metropolitan core contains a dense supply of workshops, so the "
          "difficulty there is not the absence of help but the absence of a way to choose among it. The semi-urban "
          "corridors along the arterial roads and the rural blocks beyond them contain far fewer workshops, and the "
          "workshops that exist are frequently unequipped for the particular fault. A rider whose scooter has lost "
          "electrical power needs a workshop with a battery and an electrician, not the nearest workshop, and in a thin "
          "supply area the nearest workshop is often the wrong one. This mismatch, rather than raw distance, is what "
          "produces the long and unpredictable recovery times that owners report."),
    ("p", "Two commercial forms currently address the need. The first is a subscription roadside-assistance product: the "
          "owner pays an annual fee, telephones a call centre, and an operator arranges a dispatch from a pre-vetted "
          "network. The second is a directory application: the owner searches for workshops, telephones several of "
          "them in sequence, and negotiates the price. The subscription form is convenient but prices an intermittent "
          "need as a continuous one and concentrates its network in the metropolitan zone. The directory form is cheap "
          "to operate but leaves the coordination burden on a person who is, at that moment, least able to carry it."),
    ("p", "Neither form records what happened after the arrangement was made. A call centre knows that an operator made "
          "a call; it does not necessarily know whether the dispatched resource carried the right equipment, whether it "
          "arrived, or whether the repair held. A directory knows that a search was performed. Without that outcome "
          "record, neither form can improve its selection over time, and neither can price a job against the fault that "
          "actually occurred rather than against a verbal description of it."),
    ("p", "These observations motivated the design of RoadResQ: a platform in which the assignment of a rescue crew is "
          "treated as a decision that is computed, recorded, explained and revised, rather than as a telephone call "
          "that is placed."),

    ("h2", "1.2", "OBJECTIVE"),
    ("p", "The objective of this project is to design, implement and evaluate a roadside rescue platform that reduces "
          "the time to resolution for a stranded owner by dispatching a crew that is both reachable and capable, and "
          "that renders every dispatch decision auditable. The specific technical objectives are:"),
    ("num", [
        "To implement an explicit request lifecycle in which every state and every legal transition is defined in one "
        "server-side table, so that a request cannot be advanced into a state that the lifecycle does not permit and "
        "so that the duration of each phase is measurable.",
        "To build a region-aware candidate retrieval step over an in-memory geospatial index of live crew positions, "
        "with an explicit staleness bound and a bounded radius-relaxation path for thin supply areas.",
        "To define an eligibility filter that removes crews which are offline, unverified, outside their declared "
        "service radius, incompatible with the reported fault or the vehicle class, or already at capacity, before any "
        "ranking is attempted.",
        "To design a transparent weighted allocation score over six normalised terms, with the weights exposed as "
        "configuration and with every decision accompanied by the factor contributions that produced it.",
        "To record each offer, its rank position and its outcome, and to estimate the acceptance and reputation terms "
        "of the score from that record using a shrunk estimator that remains usable for a crew with no history.",
        "To classify a free-text fault description into a service class, resolve a fixed tariff before the offer is "
        "made, and trigger a bounded disambiguation dialogue when the classification confidence is low.",
        "To support three request triggers, namely an explicit control, a hands-free voice keyword and a "
        "sensor-detected impact, with the sensor path subject to an in-application confirmation before any crew is "
        "contacted.",
        "To implement settlement as an append-only ledger keyed by the request identifier, with a pending state that "
        "decouples the physical completion of the job from the availability of the payment gateway.",
        "To evaluate the platform on a paired simulated corpus against a subscription baseline, a directory baseline "
        "and a proximity-only dispatch policy, and to report the results as differences rather than as absolute "
        "predictions.",
    ]),

    ("h2", "1.3", "PROBLEM DESCRIPTION"),
    ("p", "The problem addressed by this project has four distinct parts, and a system that solves only one of them "
          "does not solve the problem."),
    ("p", "The first part is the initiation problem. An owner who has just been involved in an incident, or who is "
          "standing beside a vehicle that will not start, may be unable to type a description, may not know the name "
          "of the road, and may be in a position where holding a telephone is itself hazardous. A platform that "
          "requires a typed form to begin has already excluded part of the population it is meant to serve."),
    ("p", "The second part is the selection problem. Given a position and a fault, the platform must choose among the "
          "crews that could attend. Choosing the nearest crew is the obvious rule and it is the wrong one in thin "
          "supply, because the nearest crew may be unverified, may not carry the equipment for that fault, may already "
          "be occupied, or may decline a job outside its own service radius. A selection rule that ignores these "
          "conditions produces a sequence of offers that are declined, and the owner experiences the sequence as "
          "delay."),
    ("p", "The third part is the commitment problem. The platform must fix the price of the job before the crew is "
          "dispatched, because an owner who is quoted after the repair has no bargaining position, and a crew that "
          "arrives without an agreed price has an incentive to inflate the charge. Fixing the price requires that the "
          "fault be classified into a service class, which in turn requires that an ambiguous description be resolved "
          "rather than guessed."),
    ("p", "The fourth part is the observability problem. The platform must record what happened, because the acceptance "
          "and reputation terms that improve the selection rule are estimated from that record, and because a dispute "
          "between an owner and a crew can only be resolved against evidence. A platform that does not record outcomes "
          "cannot improve, and cannot defend a decision it has made."),
    ("p", "Formally, the selection problem is stated as follows. Let R be a region, let M be the set of crews whose "
          "last reported position lies within a search radius of the request position, and let E(R) be the subset of M "
          "that satisfies the availability, capability, radius and freshness predicates for the request. If E(R) is "
          "empty the platform relaxes the radius within a bounded number of rounds and marks the request as degraded. "
          "Otherwise the platform computes a score for each crew in E(R), orders the set by that score, and offers the "
          "job to the highest-ranked crew, promoting the next crew in order on a decline or an expiry. The problem is "
          "therefore not a shortest-path problem; it is a ranking problem over a filtered and comparatively small "
          "candidate set, and the quality of the ranking depends on information that the platform must accumulate."),

    ("h2", "1.4", "EXISTING SYSTEM"),
    ("p", "Existing systems fall into three groups, and each group is described below in terms of the mechanism it uses "
          "rather than the product it is sold as."),
    ("p", "The first group is the operator-mediated subscription service. The owner telephones a number, an operator "
          "records the vehicle, the position and a verbal description of the fault, and the operator contacts a "
          "workshop from a pre-vetted network. The strength of this form is verification: the workshops in the network "
          "have been checked, and the owner does not have to assess them. Its weakness is that the assignment is made "
          "by a person against a verbal description, so the decision adds a triage delay to every job, and the person "
          "making it has no structured record of which crew carries which capability."),
    ("p", "The second group is the directory application. The owner searches a list of workshops by locality, reads "
          "ratings, and telephones the ones that appear suitable. The strength of this form is coverage at low "
          "operating cost: a workshop can be listed without the platform employing anyone. Its weakness is that the "
          "platform observes the search and not the service. It cannot compute a reputation from completed jobs, "
          "cannot enforce a tariff, and cannot measure a response time, because it never learns that a job happened."),
    ("p", "The third group is proximity-based automated dispatch, which is the mechanism used by the ride-hailing "
          "applications that owners increasingly expect roadside assistance to resemble. The platform obtains the "
          "position of both parties, computes a distance, and assigns the nearest available provider. This form has "
          "low decision latency and is well understood. Its weakness in the roadside context is that it treats a "
          "rescue as a transport problem. A ride-hailing trip succeeds if a vehicle of the right size arrives; a "
          "rescue succeeds only if a crew with the right capability arrives, and the nearest available crew is "
          "frequently the wrong crew."),
    ("h4", "Limitations of the Existing Systems"),
    ("bul2", [
        ("Capability is not modelled.", " No existing form represents which crew can perform which class of repair, so "
         "a battery failure and an engine failure are dispatched identically."),
        ("Availability is inferred rather than published.", " A workshop that is listed is assumed to be reachable, even "
         "when it is closed, fully occupied or outside its own travel radius."),
        ("Position freshness is unbounded.", " A directory holds no live position, and a proximity rule that consumes a "
         "stale position ranks a crew by where it was rather than by where it is."),
        ("The price is resolved after the service.", " Where a tariff exists it is quoted verbally, so the owner "
         "commits to a job whose cost is not fixed."),
        ("Outcomes are not recorded.", " Without a record of offers, declines, arrivals and ratings, neither the "
         "selection rule nor the tariff can be revised from evidence."),
        ("Initiation requires typed input.", " No existing form supports a hands-free or sensor-triggered request, so "
         "the population that can begin a request is narrower than the population that needs one."),
    ]),

    ("h2", "1.5", "PROPOSED SYSTEM"),
    ("p", "RoadResQ addresses these limitations with six functional components. The detailed architecture is presented "
          "in Chapter 3 and the method for each stage is given in Chapter 4; the components are summarised here so "
          "that the remainder of the report can refer to them by name."),

    ("h3", "1.5.1", "Multi-Channel Trigger and Context Capture"),
    ("p", "A request may be initiated by an explicit SOS control, by a hands-free voice keyword evaluated on the device, "
          "or by an impact event detected from the accelerometer and gyroscope streams. The three paths converge on a "
          "single context-capture step that records the position fix with its accuracy radius, the vehicle identity "
          "and class, the fault description and any attached photograph. The voice path uses a locally evaluated "
          "keyword detector so that audio does not leave the device until the keyword has matched, and the impact path "
          "opens a confirmation prompt rather than dispatching, because a false dispatch is far more expensive than a "
          "false prompt."),

    ("h3", "1.5.2", "Explicit Lifecycle State Machine"),
    ("p", "Every request advances through a lifecycle whose states and legal transitions are held in one server-side "
          "table. The states run from creation, through search, assignment, acceptance, travel, arrival, service, "
          "settlement and rating, to closure, with a separate set of failure states for cancellation, unavailability, "
          "decline, payment failure and network failure. The request orchestrator is the only writer of the status "
          "field, and a transition is admitted only if the table contains an entry for the current state, the "
          "requested next state and the role of the caller. Illegal transitions are therefore unrepresentable rather "
          "than merely unlikely, and every transition carries a server-side timestamp so that phase durations do not "
          "depend on client clocks."),

    ("h3", "1.5.3", "Region-Aware, Capability-Constrained Allocation"),
    ("p", "On confirmation, the platform resolves the request to an administrative region, issues a radius query "
          "against an in-memory index of live crew positions, and applies the eligibility predicates. A crew enters "
          "the eligible set only if it is verified, online, available, compatible with the reported fault and the "
          "vehicle class, its position is fresher than the staleness bound, and the request lies inside the crew's own "
          "declared service radius. If the eligible set is empty, the radius is relaxed by a fixed factor for a bounded "
          "number of rounds and the request is flagged as degraded rather than failed."),

    ("h3", "1.5.4", "Transparent Six-Term Ranking Score"),
    ("p", "The eligible crews are ranked by a weighted sum of six normalised terms: proximity, service compatibility, "
          "availability, verification state, workload and rating. Proximity is normalised against the search radius so "
          "that it expresses relative position rather than an absolute distance. The weights are configuration "
          "parameters with published defaults, and the allocation engine returns the contribution of each term "
          "alongside the total score, so that a dispatch can be explained from the factors that produced it. The "
          "engine is implemented as a pure module that touches no database and no web framework, which allows each "
          "decision to be tested and each experiment to be repeated."),

    ("h3", "1.5.5", "Fault Classification and Fixed Tariff"),
    ("p", "The free-text fault description is represented as a weighted term vector and classified into one of six "
          "service classes. Where a photograph is supplied, its embedding is appended to the feature vector so that "
          "text and image contribute to the same posterior. The dispatched class is chosen by minimising expected cost "
          "against a cost matrix derived from the tariff table rather than by taking the maximum posterior, which "
          "biases ambiguous cases away from towing and towards the lighter classes. A confidence floor triggers a "
          "bounded disambiguation dialogue, and the tariff for the resolved class and vehicle class is written to the "
          "request record before any offer is made, so that the price is fixed for the duration of the job."),

    ("h3", "1.5.6", "Settlement, Rating and Recalibration"),
    ("p", "On completion the platform captures the authorised amount, computes the payout obligation, and appends a "
          "ledger entry keyed by the request identifier under a uniqueness constraint, so that a repeated completion "
          "event cannot produce a duplicate obligation. The invoice is generated from the same stored values as the "
          "ledger entry, so the two cannot disagree. A gateway failure produces a pending settlement state rather than "
          "an incomplete job. The rating recorded at closure, together with the offer log, is aggregated on a "
          "recalibration interval to revise the acceptance and reputation terms, the effective-speed model used for "
          "arrival estimation, and, conditionally, the allocation weights."),

    ("h2", "1.6", "SUMMARY"),
    ("p", "This chapter set out the practical problem of roadside breakdown assistance, described why the existing "
          "subscription, directory and proximity-based forms each fail in a different part of that problem, and stated "
          "the objectives of the project. It then introduced the six components of RoadResQ: a multi-channel trigger, "
          "an explicit lifecycle state machine, a region-aware and capability-constrained allocation step, a "
          "transparent six-term ranking score, fault classification with a fixed tariff, and settlement with a "
          "recalibration loop. The chapters that follow review the relevant literature, present the system design, "
          "describe the algorithms and their implementation, report the testing performed, and evaluate the platform "
          "against three baselines."),
]
