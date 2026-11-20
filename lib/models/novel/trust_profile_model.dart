/// TrustScore Model — novel module.
///
/// Layered reputation profile for a crew member. Computed from multiple
/// behavioral dimensions and surfaced as a verifiable trust ledger with
/// gamified badges + trust tiers that unlock platform perks.
class TrustProfile {
  final String crewId;
  final String role;
  final double trustScore; // 0-100 overall
  final double reliabilityScore; // consistency of accepting jobs
  final double responseScore; // speed of accepting / reaching
  final double ratingScore; // normalized 0-100 from user ratings
  final double zoneConsistencyScore; // works within preferred zones
  final double safetyScore; // adherence to zone security protocol
  final int jobsCompletedTotal;
  final int onTimeCount;
  final int lateCount;
  final int cancellations;
  final List<String> badges;
  final String tier; // bronze, silver, gold, platinum
  final DateTime updatedAt;

  TrustProfile({
    this.crewId = '',
    this.role = '',
    this.trustScore = 0,
    this.reliabilityScore = 0,
    this.responseScore = 0,
    this.ratingScore = 0,
    this.zoneConsistencyScore = 0,
    this.safetyScore = 0,
    this.jobsCompletedTotal = 0,
    this.onTimeCount = 0,
    this.lateCount = 0,
    this.cancellations = 0,
    this.badges = const [],
    this.tier = 'bronze',
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  factory TrustProfile.fromJson(Map<String, dynamic> json) => TrustProfile(
        crewId: json['crewId']?.toString() ?? '',
        role: json['role']?.toString() ?? '',
        trustScore: (json['trustScore'] as num?)?.toDouble() ?? 0,
        reliabilityScore: (json['reliabilityScore'] as num?)?.toDouble() ?? 0,
        responseScore: (json['responseScore'] as num?)?.toDouble() ?? 0,
        ratingScore: (json['ratingScore'] as num?)?.toDouble() ?? 0,
        zoneConsistencyScore:
            (json['zoneConsistencyScore'] as num?)?.toDouble() ?? 0,
        safetyScore: (json['safetyScore'] as num?)?.toDouble() ?? 0,
        jobsCompletedTotal: (json['jobsCompletedTotal'] as num?)?.toInt() ?? 0,
        onTimeCount: (json['onTimeCount'] as num?)?.toInt() ?? 0,
        lateCount: (json['lateCount'] as num?)?.toInt() ?? 0,
        cancellations: (json['cancellations'] as num?)?.toInt() ?? 0,
        badges: (json['badges'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        tier: json['tier']?.toString() ?? 'bronze',
      );

  Map<String, dynamic> toJson() => {
        'crewId': crewId,
        'role': role,
        'trustScore': trustScore,
        'reliabilityScore': reliabilityScore,
        'responseScore': responseScore,
        'ratingScore': ratingScore,
        'zoneConsistencyScore': zoneConsistencyScore,
        'safetyScore': safetyScore,
        'jobsCompletedTotal': jobsCompletedTotal,
        'onTimeCount': onTimeCount,
        'lateCount': lateCount,
        'cancellations': cancellations,
        'badges': badges,
        'tier': tier,
        'updatedAt': updatedAt.toIso8601String(),
      };

  /// Icon for the tier (used by UI).
  String get tierIcon {
    switch (tier) {
      case 'gold':
        return '🏅';
      case 'platinum':
        return '💎';
      case 'silver':
        return '🥈';
      default:
        return '🥉';
    }
  }
}
