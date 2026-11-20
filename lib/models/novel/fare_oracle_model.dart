/// FareOracle — Smart Dynamic Pricing Engine Model (novel module).
///
/// Represents a single live fare estimate plus the factors that influence
/// surge pricing: demand index, weather, time-of-day, traffic, availability.
class PriceFactor {
  final String name;
  final double weight; // 0-1 contribution to the multiplier
  final String detail;

  const PriceFactor({
    required this.name,
    required this.weight,
    required this.detail,
  });

  factory PriceFactor.fromJson(Map<String, dynamic> json) => PriceFactor(
        name: json['name']?.toString() ?? '',
        weight: (json['weight'] as num?)?.toDouble() ?? 0,
        detail: json['detail']?.toString() ?? '',
      );
}

class FareEstimate {
  final String estimateId;
  final String serviceType;
  final double distanceKm;
  final int etaMinutes;
  final double baseFare;
  final double surgeMultiplier; // 1.0 = normal
  final double fare;
  final double gst;
  final double total;
  final String fareTier; // low, normal, surge, high_surge
  final int expectedAvailableCrews;
  final List<PriceFactor> factors;
  final DateTime createdAt;

  FareEstimate({
    this.estimateId = '',
    this.serviceType = 'general',
    this.distanceKm = 0,
    this.etaMinutes = 0,
    this.baseFare = 0,
    this.surgeMultiplier = 1.0,
    this.fare = 0,
    this.gst = 0,
    this.total = 0,
    this.fareTier = 'normal',
    this.expectedAvailableCrews = 0,
    this.factors = const [],
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory FareEstimate.fromJson(Map<String, dynamic> json) => FareEstimate(
        estimateId: json['estimateId']?.toString() ?? '',
        serviceType: json['serviceType']?.toString() ?? 'general',
        distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0,
        etaMinutes: (json['etaMinutes'] as num?)?.toInt() ?? 0,
        baseFare: (json['baseFare'] as num?)?.toDouble() ?? 0,
        surgeMultiplier: (json['surgeMultiplier'] as num?)?.toDouble() ?? 1.0,
        fare: (json['fare'] as num?)?.toDouble() ?? 0,
        gst: (json['gst'] as num?)?.toDouble() ?? 0,
        total: (json['total'] as num?)?.toDouble() ?? 0,
        fareTier: json['fareTier']?.toString() ?? 'normal',
        expectedAvailableCrews:
            (json['expectedAvailableCrews'] as num?)?.toInt() ?? 0,
        factors: (json['factors'] as List?)
                ?.map((e) =>
                    PriceFactor.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            const [],
      );

  Map<String, dynamic> toJson() => {
        'estimateId': estimateId,
        'serviceType': serviceType,
        'distanceKm': distanceKm,
        'etaMinutes': etaMinutes,
        'baseFare': baseFare,
        'surgeMultiplier': surgeMultiplier,
        'fare': fare,
        'gst': gst,
        'total': total,
        'fareTier': fareTier,
        'expectedAvailableCrews': expectedAvailableCrews,
        'factors': factors
            .map((f) => {
                  'name': f.name,
                  'weight': f.weight,
                  'detail': f.detail,
                })
            .toList(),
        'createdAt': createdAt.toIso8601String(),
      };
}
