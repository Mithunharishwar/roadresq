// FILE: lib/core/request_status.dart
//
// The single client-side authority on the rescue-request lifecycle.
//
// ── Why this exists ────────────────────────────────────────────────────────
// Every role screen used to carry its own hand-written `switch` over status
// strings, and they had drifted apart. The mechanic's next-step helper was:
//
//     case 'Reached': return 'Completed';
//
// but the backend state machine (backend/status_machine.py) has
//
//     ARRIVED: {SERVICE_STARTED, CANCELLED}
//
// so tapping "Mark Completed" on a reached job sent ARRIVED → SERVICE_COMPLETED
// and the server rejected it:
//
//     illegal transition ARRIVED → SERVICE_COMPLETED.
//     From ARRIVED the legal next state(s) are: CANCELLED, SERVICE_STARTED
//
// Patching that one line would leave the same class of bug in the assistant,
// mechanic-navigation, garage and user screens. Instead the lifecycle is
// declared once here — mirroring `backend/status_machine.py` exactly — and every
// role reads it. A transition the UI offers is now a transition the server
// accepts.
//
// The wire format is unchanged: the backend stores the title-case label and
// accepts legacy tokens on PUT (`in_progress`, `on_the_way`, ...). §37

import 'package:flutter/material.dart';

/// Canonical lifecycle states, in happy-path order.
///
/// [label] is the string the backend persists and the UI renders.
/// [api] is the token accepted by `PUT /api/rescueRequests/<id>/status`.
enum RequestStatus {
  pending('Pending', 'pending'),
  searching('Searching', 'searching'),
  assigned('Assigned', 'assigned'),
  accepted('Accepted', 'accepted'),
  enRoute('On The Way', 'on_the_way'),
  arrived('Reached', 'reached'),
  inProgress('In Progress', 'in_progress'),
  completed('Completed', 'completed'),
  paymentPending('Payment Pending', 'payment_pending'),
  paid('Paid', 'paid'),
  rated('Rated', 'rated'),
  closed('Closed', 'closed'),
  cancelled('Cancelled', 'cancelled'),
  noMechanic('No Mechanic Available', 'no_mechanic_available'),
  declined('Mechanic Declined', 'mechanic_declined'),
  paymentFailed('Payment Failed', 'payment_failed'),
  networkFailure('Network Failure', 'network_failure');

  const RequestStatus(this.label, this.api);

  final String label;
  final String api;

  bool get isFailure =>
      this == cancelled ||
      this == noMechanic ||
      this == declined ||
      this == paymentFailed ||
      this == networkFailure;

  /// States where a mechanic/assistant is actively working the job.
  bool get isFieldActive =>
      this == accepted ||
      this == enRoute ||
      this == arrived ||
      this == inProgress;

  bool get isFinished =>
      this == completed || this == paid || this == rated || this == closed;
}

/// Lifecycle helpers shared by every role screen.
class RequestStatusInfo {
  RequestStatusInfo._();

  /// Happy-path steps shown in progress UIs (mechanic both roles and user).
  static const List<RequestStatus> fieldSteps = <RequestStatus>[
    RequestStatus.assigned,
    RequestStatus.accepted,
    RequestStatus.enRoute,
    RequestStatus.arrived,
    RequestStatus.inProgress,
    RequestStatus.completed,
  ];

  /// Parses any accepted spelling: title-case label, canonical code, or legacy
  /// token (`on_the_way`, `in_progress`, `service_started`, ...).
  static RequestStatus? parse(String? raw) {
    if (raw == null) return null;
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return null;

    final key = cleaned.toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
    for (final status in RequestStatus.values) {
      if (status.label.toLowerCase() == cleaned.toLowerCase()) return status;
      if (status.api == key) return status;
      if (status.name.toLowerCase() == key) return status;
    }

    // Aliases that appear in the database and in older builds.
    switch (key) {
      case 'created':
      case 'new':
        return RequestStatus.pending;
      case 'enroute':
      case 'en_route':
        return RequestStatus.enRoute;
      case 'arrived':
      case 'reach':
        return RequestStatus.arrived;
      case 'started':
      case 'service_started':
      case 'inprogress':
      case 'working':
        return RequestStatus.inProgress;
      case 'service_completed':
      case 'done':
        return RequestStatus.completed;
      case 'payment_pending':
      case 'awaiting_payment':
        return RequestStatus.paymentPending;
      case 'payment_completed':
      case 'payment_success':
        return RequestStatus.paid;
      case 'canceled':
        return RequestStatus.cancelled;
      default:
        return null;
    }
  }

  /// UI label for [raw]; unknown values are returned unchanged so a new backend
  /// state is visible instead of silently mislabelled.
  static String label(String? raw) => parse(raw)?.label ?? (raw ?? '');

  /// Token for `PUT .../status`. Falls back to the legacy transformation the
  /// screens used before, so unknown states still round-trip.
  static String apiValue(String? raw) {
    final parsed = parse(raw);
    if (parsed != null) return parsed.api;
    return (raw ?? '').toLowerCase().replaceAll(' ', '_');
  }

  /// The one legal next step for a field worker, or null when the job is done.
  ///
  /// MIRRORS `status_machine.TRANSITIONS` for the ARRIVED/IN PROGRESS boundary:
  /// `Reached` must go through `In Progress` before `Completed`.
  static RequestStatus? next(String? raw) {
    switch (parse(raw)) {
      case RequestStatus.assigned:
        return RequestStatus.accepted;
      case RequestStatus.accepted:
        return RequestStatus.enRoute;
      case RequestStatus.enRoute:
        return RequestStatus.arrived;
      case RequestStatus.arrived:
        return RequestStatus.inProgress;
      case RequestStatus.inProgress:
        return RequestStatus.completed;
      default:
        return null;
    }
  }

  /// Button text for the action that moves the job to [next].
  static String nextActionLabel(String? raw, {String audience = 'mechanic'}) {
    switch (parse(raw)) {
      case RequestStatus.assigned:
        return audience == 'assistant' ? 'Accept Pickup' : 'Accept Request';
      case RequestStatus.accepted:
        return 'Start Journey';
      case RequestStatus.enRoute:
        return 'Mark Reached';
      case RequestStatus.arrived:
        return 'Start Service';
      case RequestStatus.inProgress:
        return 'Complete Service';
      case RequestStatus.completed:
        return 'Completed';
      default:
        return 'Update';
    }
  }

  /// Short description under the status chip.
  static String description(String? raw) {
    switch (parse(raw)) {
      case RequestStatus.assigned:
        return 'Customer request assigned to you';
      case RequestStatus.accepted:
        return 'You have accepted this service request';
      case RequestStatus.enRoute:
        return 'Live tracking is active towards customer location';
      case RequestStatus.arrived:
        return 'You have reached the customer';
      case RequestStatus.inProgress:
        return 'Service is in progress';
      case RequestStatus.completed:
        return 'This job has been completed';
      case RequestStatus.paymentPending:
        return 'Waiting for the customer to pay';
      case RequestStatus.paid:
        return 'Payment received';
      default:
        return 'Tracking current job';
    }
  }

  static Color color(String? raw) {
    switch (parse(raw)) {
      case RequestStatus.pending:
        return Colors.red;
      case RequestStatus.searching:
        return Colors.orange;
      case RequestStatus.assigned:
        return Colors.orange;
      case RequestStatus.accepted:
        return Colors.blue;
      case RequestStatus.enRoute:
        return Colors.deepPurple;
      case RequestStatus.arrived:
        return Colors.teal;
      case RequestStatus.inProgress:
        return Colors.indigo;
      case RequestStatus.completed:
        return Colors.green;
      case RequestStatus.paymentPending:
        return Colors.amber;
      case RequestStatus.paid:
        return Colors.green;
      case RequestStatus.cancelled:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  /// Position along the field path, 0..1 — used by the progress bar.
  static double progress(String? raw) {
    final parsed = parse(raw);
    if (parsed == null) return 0;
    if (parsed.isFailure) return 1;
    if (parsed == RequestStatus.paymentPending ||
        parsed == RequestStatus.paid ||
        parsed == RequestStatus.rated ||
        parsed == RequestStatus.closed) {
      return 1;
    }
    final idx = fieldSteps.indexOf(parsed);
    if (idx < 0) return 0;
    return (idx + 1) / fieldSteps.length;
  }
}
