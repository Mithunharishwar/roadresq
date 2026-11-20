/// CrewPulse — AI Performance & Churn Analytics Service (novel module).
///
/// Computes a composite performance score, derives a percentile rank against
/// a peer cohort, predicts churn risk from multiple signals, and builds a
/// productivity trend. Additive & self-contained.
library;

import '../../models/novel/crew_pulse_model.dart';

class CrewPulseService {
  CrewPulseService._internal();
  static final CrewPulseService _instance = CrewPulseService._internal();
  factory CrewPulseService() => _instance;

  /// ─── Build a full CrewPulse report for a single crew ───
  CrewPulseReport buildReport({
    required CrewMetrics metrics,
    List<CrewMetrics>? peerCohort,
    List<double>? trendScores,
  }) {
    // Composite performance score (weighted).
    final overall = (metrics.dispatchAcceptance * 25) +
        (metrics.onTimeRate * 20) +
        ((metrics.rating / 5) * 20) +
        (metrics.earningsScore / 100 * 20) +
        (metrics.safetyScore / 100 * 15);

// Percentile rank vs cohort (int 1-99).
    final cohort = peerCohort ?? _defaultCohort();
    final percentile = _percentileRank(overall, cohort);

    // Churn-risk prediction.
    final churn = _predictChurn(metrics, overall);

    // Productivity trend (weighted history).
    final trend = _buildTrend(metrics, trendScores);

    return CrewPulseReport(
      metrics: metrics,
      overallScore: overall.clamp(0.0, 100.0),
      performanceTier: _tierFor(overall),
      percentileRank: percentile,
      churnRisk: churn,
      trend: trend,
    );
  }

  int _percentileRank(double score, List<CrewMetrics> cohort) {
    final scores = cohort
        .map((c) =>
            (c.dispatchAcceptance * 25) +
            (c.onTimeRate * 20) +
            ((c.rating / 5) * 20) +
            (c.earningsScore / 100 * 20) +
            (c.safetyScore / 100 * 15))
        .toList();
    if (scores.isEmpty) return 50;
    final below = scores.where((s) => s < score).length;
    return ((below / scores.length) * 99).round().clamp(1, 99);
  }

  ChurnRisk _predictChurn(CrewMetrics metrics, double overall) {
    var risk = 0.0;
    // Low earning score → financial dissatisfaction.
    if (metrics.earningsScore < 40) risk += 0.25;
    // Low dispatch acceptance → disengaged.
    if (metrics.dispatchAcceptance < 0.5) risk += 0.2;
    // Low on-time → reliability concerns / burnout.
    if (metrics.onTimeRate < 0.5) risk += 0.15;
    // Few active days → dropping activity.
    if (metrics.activeDays < 10) risk += 0.2;
    // Low rating → poor experience / disputes.
    if (metrics.rating < 3.5) risk += 0.15;

    risk = risk.clamp(0.0, 1.0);

    final level = risk >= 0.6 ? 'high' : (risk >= 0.35 ? 'medium' : 'low');

    final members = metrics.name;
    final insight = level == 'high'
        ? '$members shows strong signs of disengagement. '
            'Combined low earnings, activity and acceptance point to churn soon.'
        : level == 'medium'
            ? '$members is moderately at risk. A few metrics are below '
                'the healthy threshold and need attention.'
            : '$members is healthy and engaged. Risk is low.';

    final recommendations = <String>[
      if (risk >= 0.6)
        'Offer a targeted incentive / earnings-guarantee program.',
      if (risk >= 0.6)
        'Provide advanced training to rebuild dispatch acceptance.',
      if (risk >= 0.35)
        'Schedule a check-in and review weekly dispatch allocation.',
      if (metrics.activeDays < 10)
        'Offer flexible shift preferences to boost active days.',
      'Maintain current engagement incentives to sustain performance.',
    ];

    return ChurnRisk(
      riskScore: risk,
      level: level,
      insight: insight,
      recommendations: recommendations,
    );
  }

  List<ProductivityPoint> _buildTrend(
      CrewMetrics metrics, List<double>? trendScores) {
    final now = DateTime.now();
    final scores = trendScores ?? _defaultTrend();
    return List.generate(scores.length, (i) {
      final daysAgo = scores.length - 1 - i;
      final date = now.subtract(Duration(days: daysAgo * 7));
      return ProductivityPoint(date: date, score: scores[i]);
    });
  }

  String _tierFor(double score) {
    if (score >= 85) return 'platinum';
    if (score >= 70) return 'gold';
    if (score >= 55) return 'silver';
    return 'bronze';
  }

  /// ─── Default peer cohort (self-contained demo) ───
  List<CrewMetrics> _defaultCohort() => [
        CrewMetrics(
            name: 'Ramesh',
            dispatchAcceptance: 0.9,
            onTimeRate: 0.85,
            rating: 4.7,
            earningsScore: 82,
            safetyScore: 95,
            totalJobs: 120,
            activeDays: 28),
        CrewMetrics(
            name: 'Vijay',
            dispatchAcceptance: 0.7,
            onTimeRate: 0.6,
            rating: 3.9,
            earningsScore: 55,
            safetyScore: 70,
            totalJobs: 65,
            activeDays: 18),
        CrewMetrics(
            name: 'Suresh',
            dispatchAcceptance: 0.4,
            onTimeRate: 0.45,
            rating: 3.2,
            earningsScore: 30,
            safetyScore: 60,
            totalJobs: 40,
            activeDays: 8),
        CrewMetrics(
            name: 'Anil',
            dispatchAcceptance: 0.8,
            onTimeRate: 0.75,
            rating: 4.2,
            earningsScore: 70,
            safetyScore: 88,
            totalJobs: 95,
            activeDays: 24),
      ];

  List<double> _defaultTrend() => [55, 60, 58, 66, 72, 70, 78];

  /// ─── Demo report ───
  CrewPulseReport sampleReport() => buildReport(
        metrics: const CrewMetrics(
          id: 'crew_demo',
          name: 'Ramesh',
          role: 'mechanic',
          dispatchAcceptance: 0.9,
          onTimeRate: 0.85,
          rating: 4.7,
          earningsScore: 82,
          safetyScore: 95,
          totalJobs: 120,
          activeDays: 28,
        ),
      );
}
