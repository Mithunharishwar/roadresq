/// EcoRide — Green Rescue & Carbon Intelligence Model (novel module).
///
/// Represents the carbon impact of a single rescue and the aggregated
/// EcoScore for a user or crew. Powers the "Green Rescue" accreditation.
class EcoImpact {
  final String id;
  final String? userId;
  final String? crewId;
  final String serviceType; // flat_tyre, towing, fuel, battery, lockout
  final double distanceKm;
  final String fuelType; // petrol, diesel, ev, manual
  final double co2Kg; // CO2 emitted for this rescue
  final double co2SavedKg; // CO2 offset / saved vs baseline (tow-truck)
  final double ecoScore; // 0-100 per-rescue green score
  final DateTime createdAt;

  EcoImpact({
    this.id = '',
    this.userId,
    this.crewId,
    this.serviceType = 'general',
    this.distanceKm = 0,
    this.fuelType = 'petrol',
    this.co2Kg = 0,
    this.co2SavedKg = 0,
    this.ecoScore = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory EcoImpact.fromJson(Map<String, dynamic> json) => EcoImpact(
        id: json['id']?.toString() ?? '',
        userId: json['userId']?.toString(),
        crewId: json['crewId']?.toString(),
        serviceType: json['serviceType']?.toString() ?? 'general',
        distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0,
        fuelType: json['fuelType']?.toString() ?? 'petrol',
        co2Kg: (json['co2Kg'] as num?)?.toDouble() ?? 0,
        co2SavedKg: (json['co2SavedKg'] as num?)?.toDouble() ?? 0,
        ecoScore: (json['ecoScore'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'crewId': crewId,
        'serviceType': serviceType,
        'distanceKm': distanceKm,
        'fuelType': fuelType,
        'co2Kg': co2Kg,
        'co2SavedKg': co2SavedKg,
        'ecoScore': ecoScore,
        'createdAt': createdAt.toIso8601String(),
      };
}

/// Aggregated EcoScore for a user or crew member.
class EcoScore {
  final String id;
  final String name;
  final int rescues;
  final double totalCo2Kg;
  final double totalCo2SavedKg;
  final double ecoScore; // 0-100 weighted composite
  final String greenTier; // eco_beginner, eco_saver, eco_guardian, eco_elite
  final int treesEquivalent; // offset trees worth of CO2 saved
  final List<EcoImpact> recentImpacts;

  EcoScore({
    this.id = '',
    this.name = '',
    this.rescues = 0,
    this.totalCo2Kg = 0,
    this.totalCo2SavedKg = 0,
    this.ecoScore = 0,
    this.greenTier = 'eco_beginner',
    this.treesEquivalent = 0,
    this.recentImpacts = const [],
  });

  factory EcoScore.fromJson(Map<String, dynamic> json) => EcoScore(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        rescues: (json['rescues'] as num?)?.toInt() ?? 0,
        totalCo2Kg: (json['totalCo2Kg'] as num?)?.toDouble() ?? 0,
        totalCo2SavedKg: (json['totalCo2SavedKg'] as num?)?.toDouble() ?? 0,
        ecoScore: (json['ecoScore'] as num?)?.toDouble() ?? 0,
        greenTier: json['greenTier']?.toString() ?? 'eco_beginner',
        treesEquivalent: (json['treesEquivalent'] as num?)?.toInt() ?? 0,
        recentImpacts: (json['recentImpacts'] as List?)
                ?.map((e) =>
                    EcoImpact.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            const [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'rescues': rescues,
        'totalCo2Kg': totalCo2Kg,
        'totalCo2SavedKg': totalCo2SavedKg,
        'ecoScore': ecoScore,
        'greenTier': greenTier,
        'treesEquivalent': treesEquivalent,
        'recentImpacts': recentImpacts.map((e) => e.toJson()).toList(),
      };
}
