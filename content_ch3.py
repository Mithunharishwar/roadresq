"""Chapter 3 - Proposed System Design."""

BLOCKS = [
    ("chapter", "3", "PROPOSED SYSTEM DESIGN"),

    ("h2", "3.1", "INTRODUCTION"),
    ("p", "The design of a rescue platform is constrained less by what the software can compute than by what it is "
          "allowed to decide. Three constraints govern the architecture presented in this chapter. First, a client "
          "must not be able to decide its own price, its own eligibility or its own assignee, because a modified "
          "client could then select a cheaper tariff or a preferred crew. Second, a rescue already in progress must "
          "survive the replacement of any server process, because a deployment that interrupts a job leaves an owner "
          "stranded for a second time. Third, a decision must be explainable after the fact, because the platform's "
          "claim to fairness rests on being able to show the factors that produced an assignment."),
    ("p", "These three constraints produce a three-tier architecture in which responsibility is separated by the kind "
          "of decision each tier is permitted to make, and in which the allocation engine is isolated as a pure "
          "function. This chapter presents the architecture, enumerates the seven modules, and records the software "
          "specifications and development tools used in the implementation."),

    ("h2", "3.2", "SYSTEM ARCHITECTURE"),
    ("p", "The platform is organised into a client tier, a stateless service tier and a data tier. Figure 3.1 shows "
          "the tiers, the components within each tier, and the external dependencies that the service tier consumes."),
    ("fig", "fig_arch.png", "3.1",
     "Three-tier architecture of RoadResQ: client applications issue requests to a stateless service tier, which reads "
     "and writes a partitioned data tier and consumes external mapping, payment and messaging providers.", 6.1),

    ("p", "The client tier contains three applications. The owner application renders the trigger interface, the "
          "confirmation view, the tracking map with the crew's position and the route polyline, the lifecycle status, "
          "the invoice and the rating interface. The crew application has a deliberately smaller surface: an "
          "availability control, an offer card, a navigation view and a status control. The administrator console is a "
          "web client used for verification, monitoring and dispute resolution, and it is the only client permitted to "
          "write a verification record or issue a refund."),
    ("p", "The service tier contains the stateless processes that implement the request lifecycle. The API gateway and "
          "identity service terminates transport security, authenticates the caller, enforces authorisation by role, "
          "applies rate limits and validates the payload schema before any downstream handler is invoked. Because "
          "every mutating operation on a request passes through it, the gateway is the single enforcement point for "
          "the rule that a client may not write a field it does not own. The request orchestrator holds the lifecycle "
          "state machine and is the only writer of the request status field. The allocation engine performs candidate "
          "retrieval, eligibility filtering, scoring and offer dispatch, and holds no state with respect to the "
          "request beyond the fields it writes. The fault triage and pricing service performs classification and "
          "tariff resolution and is separated from the allocation engine because its workload profile differs: "
          "classification is compute-bound and benefits from a warm model in memory, whereas allocation is input-output "
          "bound on the position index, and co-locating them would force one scaling policy on both."),
    ("p", "The notification service consumes lifecycle events and position updates and dispatches them to the owner "
          "through push, short message and voice channels. It is separated from the orchestrator so that a messaging "
          "provider outage delays notifications without delaying the lifecycle. The incident service validates "
          "sensor-triggered events, because a sensor trigger is an unverified claim from a client and must be handled "
          "with a different trust posture from an owner-initiated request. The payment service owns the order "
          "lifecycle, the platform ledger and the payout computation, and it is the only service permitted to write to "
          "the settlement ledger. The realtime layer maintains the position stream over a bidirectional channel and "
          "pushes refreshed arrival estimates. The telemetry and event log records every transition and every "
          "allocation decision."),
    ("p", "The data tier contains four stores with different consistency requirements. The transactional store holds "
          "the identity, vehicle, crew, request, offer and settlement records in a document schema indexed by request "
          "identifier. The geo index holds the current position of every available crew together with a staleness "
          "timestamp, and it is maintained in memory because an available crew's position is a transient quantity "
          "whose durability provides no benefit. The object store holds the photographic evidence attached to a "
          "request and the generated invoices, addressed by opaque identifiers and served through time-limited signed "
          "links. The analytical store holds the closed-request fact table and the derived aggregates from which the "
          "acceptance and reputation terms are recomputed."),
    ("p", "Two properties of the data flow follow from this arrangement and are worth stating explicitly. The position "
          "index is written by the tracking path from the crew's own stream and is read by the allocation path; it is "
          "never written by the allocation path, so an allocation decision cannot alter the evidence on which it was "
          "based. The event log is written by every service and read only by the analytics service; because it is not "
          "read on the critical path of any transition, an analytics outage cannot block a rescue."),

    ("h2", "3.3", "LIST OF MODULES"),
    ("p", "The platform is implemented as seven modules. Each module is described below in terms of its responsibility, "
          "its inputs and outputs, and the design decision that justifies its boundary."),

    ("h3", "Module 1", "User Module"),
    ("p", "The user module owns registration, authentication, vehicle records, request initiation and the owner's view "
          "of a job. It supports the three trigger paths described in Chapter 1 and captures the context of a request: "
          "the position fix with its accuracy radius, the vehicle identity and class, the fault description and any "
          "photograph. Registration is unified across owners and crews so that a single identity can hold both roles "
          "without duplicating the authentication path. Vehicle records are held as a collection associated with the "
          "identity, which implements a family account in which one owner manages several vehicles and one vehicle can "
          "be used by more than one member of a household. The module also presents the invoice and the rating "
          "interface at closure, and exposes the owner's request history."),

    ("h3", "Module 2", "Mechanic and Crew Module"),
    ("p", "The crew module publishes the state on which the allocation decision depends: whether the crew is online, "
          "whether it is available, its current position with a timestamp, its declared service radius, the service "
          "classes it can perform and the vehicle classes it can handle, and its current workload. It also renders the "
          "offer card, the navigation view and the status control through which the crew accepts, declines, arrives, "
          "starts and completes a job. The module is treated as a lower-trust client in one specific respect: the "
          "transitions it publishes advance the lifecycle, and each transition is validated server-side against the "
          "crew's reported position, so that a crew cannot record an arrival from a position that is inconsistent with "
          "the request location. Capacity is published rather than inferred, and a crew that reaches its concurrent job "
          "limit is excluded by the eligibility filter rather than by a post-hoc check."),

    ("h3", "Module 3", "Administrator Module"),
    ("p", "The administrator module owns verification, monitoring and dispute resolution. Verification is recorded per "
          "capability rather than per crew, so that a workshop can be verified for battery and tyre work while "
          "remaining unverified for engine diagnostics, which is the structure the capability-fit term requires. The "
          "module exposes a live view of open requests, a map of crew positions, the allocation log with the factor "
          "contributions of each decision, and the dispute queue. Every administrative action is written with the "
          "identity of the operator and the reason code, so that a revocation of verification can be reconstructed "
          "later. It is the only module permitted to issue a refund or to alter a verification record, and access is "
          "restricted by role so that a monitoring operator cannot perform a verification."),

    ("h3", "Module 4", "Service and Tariff Module"),
    ("p", "The service module holds the fault taxonomy and the tariff table. The taxonomy defines six service classes, "
          "namely battery, tyre and puncture, fuel, engine, towing and lockout, and each class is associated with the "
          "vehicle classes it applies to and a tariff band. The module resolves a free-text description into a class, "
          "computes the expected cost of each candidate class against a cost matrix derived from the tariff table, and "
          "writes the resolved class and the fixed tariff to the request record before any offer is made. It also "
          "supplies the capability vocabulary that the crew module uses to declare what it can perform, so that the "
          "classification and the eligibility filter share one definition of a service class rather than two."),

    ("h3", "Module 5", "Payment Module"),
    ("p", "The payment module creates the gateway order, captures the authorised amount on completion, computes the "
          "payout obligation, writes the ledger entry and generates the invoice. Three settlement states are "
          "distinguished and written to the request record: settled, refunded and pending. The pending state exists to "
          "decouple the physical completion of the job from the availability of the payment provider, so that a "
          "gateway outage degrades the settlement latency rather than the service itself. The ledger is append-only and "
          "keyed by the request identifier under a uniqueness constraint, so a repeated completion event cannot "
          "produce a duplicate obligation, and a correction is expressed as a compensating entry rather than as an "
          "update."),

    ("h3", "Module 6", "Notification Module"),
    ("p", "The notification module converts lifecycle events into messages on the channel appropriate to the "
          "recipient: a push notification for a status change, a short message for a crew that has not opened the "
          "application, and spoken guidance for the owner during tracking. It also pushes refreshed arrival estimates "
          "over the realtime channel, but only when an estimate changes by more than a configured threshold, which "
          "prevents a stream of near-identical values from being transmitted. Delivery failures are retried with a "
          "bounded backoff and then recorded, so that a message that was never delivered is distinguishable from a "
          "message that was delivered and ignored."),

    ("h3", "Module 7", "Analytics and Recalibration Module"),
    ("p", "The analytics module aggregates closed requests, offers and ratings into the quantities on which the "
          "platform improves. Partner aggregates report the acceptance rate, the completion rate, the median arrival "
          "error and the rating distribution, and it is these aggregates that supply the reputation and acceptance "
          "terms of the allocation score. Demand aggregates report the request rate by region, time of day and service "
          "class, which is the input to a recruitment decision. Reliability aggregates report the allocation failure "
          "rate, the degraded-mode rate and the dispute rate. The module operates on an aggregation interval rather "
          "than on individual jobs, because a single rating or a single arrival error is dominated by noise and a "
          "per-job update would make the allocation policy unstable."),

    ("h2", "3.4", "SOFTWARE SPECIFICATIONS"),
    ("p", "The implementation is organised so that each tier is realised by a technology whose properties match the "
          "requirement that tier imposes, rather than by a single framework applied uniformly."),
    ("bul2", [
        ("Operating system:", " Microsoft Windows 11 (development) and Ubuntu 22.04 LTS (containerised service tier)."),
        ("Client language and framework:", " Dart 3.4 with Flutter 3.22, compiled to native Android and iOS artefacts "
         "from a single codebase, with Riverpod 2.5 for state management and GoRouter 14 for navigation."),
        ("Client libraries:", " Google Maps Flutter 2.7 for the map surface, geolocator 10 for position fixes, "
         "flutter_polyline_points 2 for decoding route geometry, dio 5 and http 1 for interface calls, "
         "connectivity_plus 6 for reachability, sensors_plus for the accelerometer and gyroscope streams, and "
         "flutter_tts for spoken guidance."),
        ("Service language and framework:", " Python 3.11 with Flask 3.1 and Flask-Cors, served by a WebSocket-capable "
         "application server; Flask-SocketIO 5.6 and python-socketio 5.17 for the realtime channel."),
        ("Data access:", " PyMongo 4.18 against MongoDB 7.0, with a two-dimensional sphere index on crew positions and "
         "a compound index on the request identifier and status."),
        ("Payment integration:", " Razorpay 2.0 server-side order creation with signature verification, and an "
         "explicitly labelled simulation path when keys are absent so that the lifecycle can be tested without live "
         "credentials."),
        ("Notification services:", " Firebase Cloud Messaging for push delivery and a short-message gateway for the "
         "fallback channel used for the emergency contact."),
        ("Mapping services:", " A commercial routing provider for geocoding, route computation and encoded polyline "
         "geometry, wrapped in an adapter that implements a degraded straight-line path when the provider is "
         "unavailable."),
        ("Security:", " Bearer-token authentication with signed claims, role-based authorisation enforced at the "
         "gateway, transport security on every endpoint, and schema validation before handler invocation."),
        ("Testing:", " pytest 9.1 for the service tier, the Flutter test harness for widget and unit tests, and an "
         "end-to-end module test that drives a request through every legal transition."),
    ]),

    ("h2", "3.5", "TOOLS USED"),
    ("p", "The following development tools supported the implementation and the evaluation."),
    ("bul2", [
        ("Visual Studio Code:", " primary editor, configured with the Dart, Flutter and Python extensions and with "
         "the integrated debugger for both tiers."),
        ("Android Studio:", " emulator management and device profiling, used to observe the achieved sensor sampling "
         "interval on different vendor builds."),
        ("Git and GitHub:", " version control, branch-per-increment workflow, and review of each increment before it "
         "was merged."),
        ("Postman:", " interface testing and payload benchmarking, including the negative cases in which a malformed "
         "or unauthorised request must be rejected."),
        ("MongoDB Compass:", " inspection of request records and of the allocation log during debugging."),
        ("pytest:", " execution of the service-tier suite and generation of the test report summarised in Chapter 5."),
        ("Python scientific stack:", " NumPy and Matplotlib for the simulator and for the charts reported in Chapter "
         "6."),
        ("Draw.io and Matplotlib:", " production of the architecture, lifecycle and flow diagrams used in this "
         "report."),
        ("Microsoft Word and LaTeX:", " preparation of this report and of the accompanying manuscript."),
    ]),

    ("h2", "3.6", "SUMMARY"),
    ("p", "This chapter presented the three-tier architecture of RoadResQ, explained why responsibility is separated by "
          "the kind of decision each tier may make, and enumerated the seven modules through which the platform is "
          "implemented. It also recorded the software stack and the development tools. The separation of the "
          "allocation engine as a pure, stateless component and the confinement of lifecycle authority to a single "
          "orchestrator are the two structural decisions on which the remaining chapters depend: the first makes the "
          "decision testable and repeatable, and the second makes the audit trail complete."),
]
