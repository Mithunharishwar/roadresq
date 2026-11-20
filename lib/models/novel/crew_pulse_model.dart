/// CrewPulse — AI Performance & Churn Analytics Model (novel module).
///
/// Represents a single crew-member performance snapshot and a full
/// CrewPulse report including percentile rank, productivity trend and a
/// churn-risk prediction with retention recommendations.
class CrewMetrics {
  final String id;
  final String name;
  final String role; // mechanic / assistant
  final double dispatchAcceptance; // 0-1
  final double onTimeRate; // 0-1
  final double rating; // 1-5
  final double earningsScore; // 0-100
  final double safetyScore; // 0-100
  final int totalJobs;
  final int activeDays;

  const CrewMetrics({
    this.id = '',
    this.name = '',
    this.role = 'mechanic',
    this.dispatchAcceptance = 0,
    this.onTimeRate = 0,
    this.rating = 0,
    this.earningsScore = 0,
    this.safetyScore = 0,
    this.totalJobs = 0,
    this.activeDays = 0,
  });

  factory CrewMetrics.fromJson(Map<String, dynamic> json) => CrewMetrics(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        role: json['role']?.toString() ?? 'mechanic',
        dispatchAcceptance:
            (json['dispatchAcceptance'] as num?)?.toDouble() ?? 0,
        onTimeRate: (json['onTimeRate'] as num?)?.toDouble() ?? 0,
        rating: (json['rating'] as num?)?.toDouble() ?? 0,
        earningsScore: (json['earningsScore'] as num?)?.toDouble() ?? 0,
        safetyScore: (json['safetyScore'] as num?)?.toDouble() ?? 0,
        totalJobs: (json['totalJobs'] as num?)?.toInt() ?? 0,
        activeDays: (json['activeDays'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'role': role,
        'dispatchAcceptance': dispatchAcceptance,
        'onTimeRate': onTimeRate,
        'rating': rating,
        'earningsScore': earningsScore,
        'safetyScore': safetyScore,
        'totalJobs': totalJobs,
        'activeDays': activeDays,
      };
}

/// A single point on the productivity trend line.
class ProductivityPoint {
  final DateTime date;
  final double score;

  const ProductivityPoint({required this.date, required this.score});
}

/// Churn-risk classification result.
class ChurnRisk {
  final double riskScore; // 0-1
  final String level; // low, medium, high
  final String insight;
  final List<String> recommendations;

  const ChurnRisk({
    this.riskScore = 0,
    this.level = 'low',
    this.insight = '',
    this.recommendations = const [],
  });
}

/// Full CrewPulse report for one crew member.
class CrewPulseReport {
  final CrewMetrics metrics;
  final double overallScore; // 0-100
  final String performanceTier; // bronze, silver, gold, platinum
  final int percentileRank; // 1-99
  final ChurnRisk churnRisk;
  final List<ProductivityPoint> trend;

  const CrewPulseReport({
    required this.metrics,
    this.overallScore = 0,
    this.performanceTier = 'bronze',
    this.percentileRank = 50,
    required this.churnRisk,
    this.trend = const [],
  });
}
