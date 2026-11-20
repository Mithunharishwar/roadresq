// FILE: lib/models/allocation_model.dart
/// Models for the regional mechanic allocation engine (research core).
///
/// These types mirror the payload returned by `POST /api/allocation/find` and
/// `GET /api/allocation/<requestId>`, including the per-candidate evidence the
/// backend records for every decision. The evidence is the point: the UI can
/// show *why* a mechanic was chosen, and the same structure is what the
/// research export consumes.
///
/// Nothing here invents values. Fields the backend did not send stay null, and
/// [AllocationDecision.distanceNote] spells out that distances are
/// straight-line, not road distances.
library;

/// One evaluated mechanic, with its eligibility verdict and score breakdown.
class AllocationCandidate {
  const AllocationCandidate({
    required this.mechanicId,
    required this.name,
    required this.eligible,
    required this.reasons,
    this.rank,
    this.score,
    this.components = const <String, double>{},
    this.distanceKm,
    this.distanceMeters,
    this.etaMinutes,
    this.sameRegion = false,
    this.verified = false,
    this.online = false,
    this.available = false,
    this.serviceCompatible = false,
    this.vehicleCompatible = false,
    this.locationAvailable = false,
    this.workload = 0,
    this.rating = 0,
    this.ratingCount = 0,
    this.regionId,
    this.hubId,
  });

  final String mechanicId;
  final String name;

  /// True when the mechanic passed every eligibility rule.
  final bool eligible;

  /// Machine-readable rejection reasons when [eligible] is false. Never empty
  /// for a rejected candidate — the backend guarantees at least one reason.
  final List<String> reasons;

  final int? rank;
  final double? score;

  /// Score components: proximity, serviceMatch, availability, verification,
  /// workloadFactor, ratingFactor.
  final Map<String, double> components;

  /// Straight-line distance. NOT a road distance.
  final double? distanceKm;
  final double? distanceMeters;

  /// Estimated from an assumed average speed, not measured.
  final double? etaMinutes;

  final bool sameRegion;
  final bool verified;
  final bool online;
  final bool available;
  final bool serviceCompatible;
  final bool vehicleCompatible;
  final bool locationAvailable;
  final int workload;
  final double rating;
  final int ratingCount;
  final String? regionId;
  final String? hubId;

  factory AllocationCandidate.fromJson(Map<String, dynamic> json) {
    final rawComponents =
        (json['components'] as Map?)?.cast<String, dynamic>() ?? const {};

    return AllocationCandidate(
      mechanicId: (json['mechanicId'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      eligible: json['eligible'] == true,
      reasons: ((json['reasons'] as List?) ?? const [])
          .map((r) => r.toString())
          .toList(growable: false),
      rank: (json['rank'] as num?)?.toInt(),
      score: (json['score'] as num?)?.toDouble(),
      components: rawComponents.map(
        (key, value) => MapEntry(key, (value as num?)?.toDouble() ?? 0.0),
      ),
      distanceKm: (json['distanceKm'] as num?)?.toDouble(),
      distanceMeters: (json['distanceMeters'] as num?)?.toDouble(),
      etaMinutes: (json['etaMinutes'] as num?)?.toDouble(),
      sameRegion: json['sameRegion'] == true,
      verified: json['verified'] == true,
      online: json['online'] == true,
      available: json['available'] == true,
      serviceCompatible: json['serviceCompatible'] == true,
      vehicleCompatible: json['vehicleCompatible'] == true,
      locationAvailable: json['locationAvailable'] == true,
      workload: (json['workload'] as num?)?.toInt() ?? 0,
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      ratingCount: (json['ratingCount'] as num?)?.toInt() ?? 0,
      regionId: json['regionId']?.toString(),
      hubId: json['hubId']?.toString(),
    );
  }

  /// Human-readable form of the rejection reasons.
  String get reasonsText =>
      reasons.isEmpty ? 'eligible' : reasons.map(_humanReason).join(', ');

  static String _humanReason(String code) {
    switch (code) {
      case 'NOT_VERIFIED':
        return 'not verified';
      case 'OFFLINE':
        return 'offline';
      case 'UNAVAILABLE':
        return 'already on a job';
      case 'AT_CAPACITY':
        return 'at capacity';
      case 'SERVICE_MISMATCH':
        return 'cannot perform this service';
      case 'VEHICLE_MISMATCH':
        return 'does not handle this vehicle type';
      case 'LOCATION_MISSING':
        return 'no location published';
      case 'LOCATION_STALE':
        return 'location is stale';
      case 'REGION_MISMATCH':
        return 'different region';
      case 'OUT_OF_RADIUS':
        return 'outside the search radius';
      case 'BANNED':
        return 'suspended';
      default:
        return code.toLowerCase().replaceAll('_', ' ');
    }
  }
}

/// The full decision returned by the allocation engine.
class AllocationDecision {
  const AllocationDecision({
    required this.success,
    required this.status,
    required this.message,
    this.selected,
    this.ranked = const <AllocationCandidate>[],
    this.candidates = const <AllocationCandidate>[],
    this.readableTrace = '',
    this.requestId,
    this.regionId,
    this.regionName,
    this.hubId,
    this.candidateCount = 0,
    this.eligibleCount = 0,
    this.assignmentTimeMs,
    this.escalationUsed = false,
    this.failureReason,
    this.allocationLogId,
  });

  final bool success;

  /// `ASSIGNED`, `NO_MECHANIC_AVAILABLE`, `NO_REGION_RESOLVED`, ...
  final String status;
  final String message;

  /// The chosen mechanic, or null when nobody was eligible.
  final AllocationCandidate? selected;

  /// Eligible candidates, best first, each carrying its rank and score.
  final List<AllocationCandidate> ranked;

  /// Every mechanic that was evaluated, including the rejected ones.
  final List<AllocationCandidate> candidates;

  /// Operator-readable trace produced by the backend.
  final String readableTrace;

  final String? requestId;
  final String? regionId;
  final String? regionName;
  final String? hubId;
  final int candidateCount;
  final int eligibleCount;

  /// Measured server-side assignment latency in milliseconds.
  final int? assignmentTimeMs;

  /// True when the in-region search found nobody and the wider radius was used.
  final bool escalationUsed;

  /// Dominant rejection reason when nothing was assigned.
  final String? failureReason;

  final String? allocationLogId;

  bool get assigned => status == 'ASSIGNED' && selected != null;

  /// Explicit reminder that distances here are great-circle distances.
  static const String distanceNote =
      'Distances are straight-line (great-circle) and ETAs assume a fixed '
      'average speed. Neither is a measured road route.';

  factory AllocationDecision.fromJson(Map<String, dynamic> json) {
    final explain =
        (json['explain'] as Map?)?.cast<String, dynamic>() ?? const {};
    final selectedJson = json['selected'];
    final rankedJson = (json['rankedMechanics'] ?? json['ranked']) as List?;
    final candidatesJson = json['candidates'] as List?;

    return AllocationDecision(
      success: json['success'] == true,
      status: (json['status'] ?? 'UNKNOWN').toString(),
      message: (json['message'] ?? '').toString(),
      selected: selectedJson is Map<String, dynamic>
          ? AllocationCandidate.fromJson(selectedJson)
          : selectedJson is Map
              ? AllocationCandidate.fromJson(
                  selectedJson.cast<String, dynamic>())
              : null,
      ranked: (rankedJson ?? const [])
          .whereType<Map>()
          .map((e) => AllocationCandidate.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false),
      candidates: (candidatesJson ?? const [])
          .whereType<Map>()
          .map((e) => AllocationCandidate.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false),
      readableTrace: (json['readableTrace'] ?? '').toString(),
      requestId: explain['requestId']?.toString(),
      regionId: explain['regionId']?.toString(),
      regionName: explain['regionName']?.toString(),
      hubId: explain['hubId']?.toString(),
      candidateCount: (explain['candidateCount'] as num?)?.toInt() ?? 0,
      eligibleCount: (explain['eligibleCount'] as num?)?.toInt() ?? 0,
      assignmentTimeMs: (explain['assignmentTimeMs'] as num?)?.toInt(),
      escalationUsed: explain['escalationUsed'] == true,
      failureReason: explain['failureReason']?.toString(),
      allocationLogId: json['allocationLogId']?.toString(),
    );
  }
}

/// A single line of an itemised price quote.
class PriceLineItem {
  const PriceLineItem({
    required this.label,
    required this.amount,
    this.description = '',
  });

  final String label;
  final String description;
  final double amount;

  factory PriceLineItem.fromJson(Map<String, dynamic> json) => PriceLineItem(
        label: (json['label'] ?? '').toString(),
        description: (json['description'] ?? '').toString(),
        amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      );
}

/// The itemised quote shown to the user before payment.
class PriceQuote {
  const PriceQuote({
    required this.currency,
    required this.lineItems,
    required this.subtotal,
    required this.tax,
    required this.taxPercent,
    required this.total,
    required this.totalMinorUnits,
    this.note = '',
  });

  final String currency;
  final List<PriceLineItem> lineItems;
  final double subtotal;
  final double tax;
  final double taxPercent;
  final double total;

  /// Total in the smallest currency unit, as the payment gateway expects.
  final int totalMinorUnits;

  /// Surfaces the backend's own caveat about the rate card.
  final String note;

  factory PriceQuote.fromJson(Map<String, dynamic> json) {
    final assumptions =
        (json['assumptions'] as Map?)?.cast<String, dynamic>() ?? const {};

    return PriceQuote(
      currency: (json['currency'] ?? 'INR').toString(),
      lineItems: ((json['lineItems'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => PriceLineItem.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false),
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0.0,
      tax: (json['tax'] as num?)?.toDouble() ?? 0.0,
      taxPercent: (json['taxPercent'] as num?)?.toDouble() ?? 0.0,
      total: (json['total'] as num?)?.toDouble() ?? 0.0,
      totalMinorUnits: (json['totalMinorUnits'] as num?)?.toInt() ?? 0,
      note: (assumptions['note'] ?? '').toString(),
    );
  }
}
