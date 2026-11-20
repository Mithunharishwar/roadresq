"""Chapter 5 - Testing."""

BLOCKS = [
    ("chapter", "5", "TESTING"),

    ("h2", "5.1", "INTRODUCTION"),
    ("p", "A rescue platform is used at the worst moment of its user's day, on a device with an uncertain network "
          "connection, by a person who may be standing beside moving traffic. Testing therefore has to establish more "
          "than that the happy path works. It has to establish that the platform refuses correctly: that a duplicate "
          "request is rejected, that an offer cannot be accepted twice, that a crew cannot record an arrival from a "
          "position it is not at, that an unauthorised client cannot advance a request, and that a gateway failure "
          "produces a pending settlement rather than a lost job."),
    ("p", "This chapter describes the testing strategy and the system-level cases executed against the running "
          "platform. The results recorded here are observations of the implementation, not of the simulator; the "
          "simulated evaluation is reported separately in Chapter 6."),

    ("h2", "5.2", "TESTING STRATEGIES"),

    ("h3", "5.2.1", "Unit Testing"),
    ("p", "Unit tests cover the pure functions on which correctness depends. The allocation engine is deliberately "
          "written as a pure module that takes records and returns records, so that each of its functions can be "
          "tested without a database or a web framework. The unit suite covers:"),
    ("bul", [
        "Distance computation, checked against known separations between surveyed coordinates, including the "
        "degenerate case of identical points.",
        "Proximity normalisation, checked at the search radius, at zero distance and beyond the radius, including the "
        "clamping behaviour at both ends.",
        "The eligibility filter, checked predicate by predicate, and then in combination, so that an exclusion is "
        "attributed to the correct reason code rather than merely producing an empty set.",
        "The shrunk estimators, checked for the two limits that matter: a crew with no observations returns the prior, "
        "and a crew with many observations returns the observed mean within a stated tolerance.",
        "The lifecycle transition table, checked exhaustively over the cross product of states and roles, so that every "
        "illegal pair is refused and every legal pair is admitted.",
        "Payout arithmetic, checked for integer rounding, for a zero-value job and for the boundary at which the fixed "
        "fee exceeds the commission.",
        "The impact detector, driven by recorded sample sequences, so that a pothole-like spike does not validate and a "
        "sustained impact does.",
    ]),

    ("h3", "5.2.2", "Integration Testing"),
    ("p", "Integration tests exercise the interfaces between components and the consistency of the data they exchange."),
    ("bul", [
        "Request creation through the gateway, including schema validation, rejection of an unauthenticated call before "
        "the payload is inspected, and rejection of a payload that attempts to write a field owned by another role.",
        "Lifecycle progression, driven through every legal transition in order, with a check that each transition "
        "produced exactly one write to the request record and the expected downstream calls.",
        "Offer dispatch and response, including acceptance, decline, expiry and the promotion of the next candidate in "
        "rank order.",
        "Settlement, including the capture path, the pending path when the gateway is unavailable, and the replay of a "
        "completion event to confirm that the ledger does not gain a second entry.",
        "Position publication and retrieval, including the case in which a crew's position crosses the staleness bound "
        "between two queries.",
    ]),

    ("h3", "5.2.3", "System Testing"),
    ("p", "System tests exercise the platform end to end under conditions that the unit and integration suites cannot "
          "reproduce. Four classes of scenario were executed."),
    ("bul2", [
        ("Boundary scenarios.", " A request at the edge of the search radius, a request with a position accuracy radius "
         "larger than the distance to the nearest crew, and a request in a region with a single eligible crew, which "
         "exercises the division guard in the normalisation."),
        ("Failure scenarios.", " Gateway unavailable during capture, push provider unavailable during notification, and "
         "routing provider unavailable during tracking. In each case the expected outcome is a degraded mode rather "
         "than a failed request."),
        ("Trust scenarios.", " A crew client attempting to record an arrival from an inconsistent position, an owner "
         "client attempting to read another owner's request, and a replayed operation identifier attempting to create "
         "a duplicate settlement."),
        ("Accessibility scenarios.", " A request created and confirmed without typed input, using the voice keyword and "
         "then the confirmation control, which is the acceptance criterion for the hands-free requirement."),
    ]),

    ("h3", "5.2.4", "Automated Suite and Load Testing"),
    ("p", "The service-tier suite is implemented with pytest and contains unit and integration cases over the "
          "allocation module, the lifecycle module and the interface layer, together with an end-to-end module test "
          "that drives a request from creation to closure. The suite is executed on every change to the allocation or "
          "lifecycle modules, and a failure in either blocks the merge. The console transcript of a complete run is "
          "reproduced in Listing 5.1."),
    ("code", "pytest -q", """$ pytest backend/tests -q
......................                                        [100%]
22 passed in 3.87s

$ pytest backend/tests/e2e_module_test.py -q
..                                                            [100%]
2 passed in 1.42s

$ python backend/smoke_test_e2e.py
[ok] health                    200
[ok] register owner            user created
[ok] create request            CREATED
[ok] allocation                MECHANIC_ASSIGNED  (score breakdown logged)
[ok] accept offer              MECHANIC_ACCEPTED
[ok] en route / arrived        EN_ROUTE -> ARRIVED
[ok] service completed         SERVICE_COMPLETED
[ok] settle                    PAYMENT_COMPLETED  (ledger entry appended)
[ok] rate                      RATED -> CLOSED
[ok] duplicate completion      rejected (idempotency key honoured)""",
     "5.1", "Automated suite and end-to-end smoke transcript"),

    ("p", "Load behaviour was observed with a scripted client pool issuing requests against a single service process, "
          "with the position index pre-populated from seeded crew records. The purpose of the exercise was not to "
          "establish a capacity figure, which would depend on the deployment, but to confirm two properties: that the "
          "allocation path does not degrade super-linearly in the size of the candidate set, and that repeated requests "
          "do not leak memory through accumulated index entries. The first property was confirmed by measuring the "
          "retrieval and scoring stages separately at candidate-set sizes of 5, 20 and 60 crews; the second by "
          "observing the resident set of the service process across 2,000 consecutive requests, which remained stable "
          "once the initial allocation had settled."),

    ("h2", "5.3", "TEST CASES AND RESULTS"),
    ("p", "Table 5.1 records the representative system cases executed against the running platform, together with the "
          "observed result. Each case states the input, the expected behaviour and the observed behaviour, so that a "
          "failure can be reproduced rather than merely reported."),
    ("tab", "5.1", "System test cases and observed results",
     ["ID", "Scenario", "Expected behaviour", "Observed result", "Status"],
     [["TC01", "Owner creates a request with a valid position and a battery fault",
       "Record created in CREATED, classified as battery, tariff fixed before any offer",
       "Classified battery, tariff written, status CREATED", "Pass"],
      ["TC02", "Second request for the same vehicle within the duplicate interval",
       "Duplicate rejected with the identifier of the open request",
       "Rejected; open request identifier returned", "Pass"],
      ["TC03", "Request in a region with three eligible crews",
       "Ranked offer to the highest score; factor contributions logged",
       "Offer to the top-ranked crew; six term contributions recorded", "Pass"],
      ["TC04", "Top-ranked crew declines the offer",
       "Decline recorded, acceptance estimate updated, next rank offered",
       "Decline recorded; second-ranked crew offered and accepted", "Pass"],
      ["TC05", "All offers in the chain expire",
       "Escalation record created; request not silently failed",
       "Escalated with reason OFFER_CHAIN_EXHAUSTED", "Pass"],
      ["TC06", "Request with no crew in the region",
       "Radius relaxed once, request flagged degraded",
       "Served at 25 km with degraded flag set", "Pass"],
      ["TC07", "Crew records arrival from an inconsistent position",
       "Transition rejected and recorded as an anomalous arrival",
       "Rejected; anomaly logged with both positions", "Pass"],
      ["TC08", "Unauthenticated call to a mutating endpoint",
       "Rejected before payload inspection",
       "HTTP 401 returned; handler not invoked", "Pass"],
      ["TC09", "Owner attempts to read another owner's request",
       "Rejected by role scoping",
       "HTTP 403 returned", "Pass"],
      ["TC10", "Replayed completion event with the same operation identifier",
       "Single ledger entry; second call idempotent",
       "One ledger entry; replay returned the original settlement", "Pass"],
      ["TC11", "Payment gateway unavailable at completion",
       "Pending settlement state; job not lost",
       "Status PAYMENT_PENDING; queue entry created", "Pass"],
      ["TC12", "Request created and confirmed with no typed input",
       "Request created through voice keyword and confirmation only",
       "Created and confirmed; typing not required", "Pass"],
      ["TC13", "Impact detected while the device is stationary on a bench",
       "Trigger rejected by the motion-state check",
       "Rejected at the incident service; no prompt raised", "Pass"],
      ["TC14", "Sustained impact while riding, confirmation affirmed",
       "Trigger converted into a normal request",
       "Request created with source = sensor", "Pass"]],
     [0.55, 1.62, 1.68, 1.68, 0.47]),

    ("h2", "5.4", "SUMMARY"),
    ("p", "The testing programme established that the platform refuses correctly as well as works correctly. Unit tests "
          "confirmed the arithmetic of distance, normalisation, shrinkage and payout, and confirmed the transition "
          "table exhaustively. Integration tests confirmed that the lifecycle advances with exactly one write per "
          "transition, that the offer chain behaves as specified on decline and expiry, and that settlement is "
          "idempotent under replay. System tests confirmed that the platform degrades rather than fails when a "
          "dependency is unavailable, that role scoping and position validation resist a modified client, and that a "
          "request can be created and confirmed without typed input. The load observation confirmed linear growth of "
          "the retrieval stage in the candidate-set size and a stable memory footprint over repeated requests."),
]
