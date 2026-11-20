/// CrewPulse — AI Performance & Churn Analytics Screen (novel module).
///
/// Shows a crew member's composite performance score, percentile rank,
/// performance tier, a productivity trend, and a churn-risk prediction with
/// actionable retention recommendations.
library;

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/novel/crew_pulse_model.dart';
import '../../providers/novel/crew_pulse_provider.dart';
import '../../widgets/novel/novel_widgets.dart';

class CrewPulseScreen extends ConsumerStatefulWidget {
  const CrewPulseScreen({super.key});

  @override
  ConsumerState<CrewPulseScreen> createState() => _CrewPulseScreenState();
}

class _CrewPulseScreenState extends ConsumerState<CrewPulseScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(crewPulseProvider.notifier).loadDemo();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(crewPulseProvider);
    final report = state.report;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FB),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const NovelHero(
              title: 'CrewPulse',
              subtitle: 'AI Performance & Churn Analytics',
              icon: Icons.monitor_heart,
              colors: [Color(0xFF0D47A1), Color(0xFF7B1FA2)],
            ),
            const SizedBox(height: 20),
            if (state.isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (report == null)
              const NovelEmptyCard(
                message: 'No crew report available.',
                icon: Icons.monitor_heart_outlined,
              )
            else ...[
              _scoreHeader(report),
              const SizedBox(height: 16),
              _metricsGrid(report),
              const SizedBox(height: 20),
              const NovelSectionTitle(
                title: 'Productivity Trend',
                icon: Icons.show_chart,
                color: Color(0xFF00897B),
              ),
              const SizedBox(height: 12),
              _trendCard(report),
              const SizedBox(height: 20),
              const NovelSectionTitle(
                title: 'Churn-Risk Prediction',
                icon: Icons.warning_amber,
                color: Colors.deepOrange,
              ),
              const SizedBox(height: 12),
              _churnCard(report.churnRisk),
              const SizedBox(height: 20),
              const NovelSectionTitle(
                title: 'Retention Recommendations',
                icon: Icons.lightbulb_outline,
                color: Color(0xFF7B1FA2),
              ),
              const SizedBox(height: 12),
              ...report.churnRisk.recommendations
                  .map((r) => _recommendationTile(r)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _scoreHeader(CrewPulseReport report) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D47A1), Color(0xFF7B1FA2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D47A1).withAlpha((0.30 * 255).round()),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            height: 84,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 84,
                  height: 84,
                  child: CircularProgressIndicator(
                    value: report.overallScore / 100,
                    strokeWidth: 8,
                    backgroundColor: Colors.white24,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Color(0xFFFFD54F)),
                  ),
                ),
                Text(
                  report.overallScore.toStringAsFixed(0),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  report.metrics.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_role(report.metrics.role)} • '
                  '${_tierLabel(report.performanceTier)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Text(
                  'Top ${report.percentileRank}% of crew',
                  style: const TextStyle(
                    color: Color(0xFFFFD54F),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricsGrid(CrewPulseReport report) {
    final m = report.metrics;
    return Row(
      children: [
        Expanded(
          child: NovelStatCard(
            title: 'Acceptance',
            value: '${(m.dispatchAcceptance * 100).toStringAsFixed(0)}%',
            color: const Color(0xFF0D47A1),
            icon: Icons.check_circle_outline,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: NovelStatCard(
            title: 'On-time',
            value: '${(m.onTimeRate * 100).toStringAsFixed(0)}%',
            color: const Color(0xFF2E7D32),
            icon: Icons.timer_outlined,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: NovelStatCard(
            title: 'Rating',
            value: m.rating.toStringAsFixed(1),
            color: const Color(0xFFFF8F00),
            icon: Icons.star_outline,
          ),
        ),
      ],
    );
  }

  Widget _trendCard(CrewPulseReport report) {
    final maxScore = report.trend.isEmpty
        ? 100.0
        : report.trend.map((p) => p.score).reduce((a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha((0.05 * 255).round()),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Text('Weekly performance',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${maxScore.toStringAsFixed(0)} peak',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final p in report.trend)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(p.score.toStringAsFixed(0),
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.black54)),
                          const SizedBox(height: 2),
                          Container(
                            height: (p.score / max(100, maxScore)) * 90,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF0D47A1), Color(0xFF7B1FA2)],
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${p.date.day}/${p.date.month}',
                            style: const TextStyle(
                                fontSize: 9, color: Colors.black38),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _churnCard(ChurnRisk churn) {
    final color = _churnColor(churn.level);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withAlpha((0.08 * 255).round()),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withAlpha((0.3 * 255).round())),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber, color: color, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${_churnLabel(churn.level)} risk • '
                  '${(churn.riskScore * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: churn.riskScore,
              minHeight: 10,
              backgroundColor: const Color(0xFFE0E0E0),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 10),
          Text(churn.insight,
              style: const TextStyle(fontSize: 13, color: Colors.black87)),
        ],
      ),
    );
  }

  Widget _recommendationTile(String rec) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha((0.05 * 255).round()),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.lightbulb_outline,
              color: Color(0xFF7B1FA2), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(rec,
                style: const TextStyle(fontSize: 13, color: Colors.black87)),
          ),
        ],
      ),
    );
  }

  String _role(String role) => role == 'assistant' ? 'Assistant' : 'Mechanic';

  String _tierLabel(String tier) {
    switch (tier) {
      case 'platinum':
        return 'Platinum';
      case 'gold':
        return 'Gold';
      case 'silver':
        return 'Silver';
      default:
        return 'Bronze';
    }
  }

  String _churnLabel(String level) {
    switch (level) {
      case 'high':
        return 'High';
      case 'medium':
        return 'Medium';
      default:
        return 'Low';
    }
  }

  Color _churnColor(String level) {
    switch (level) {
      case 'high':
        return const Color(0xFFD32F2F);
      case 'medium':
        return const Color(0xFFFF8F00);
      default:
        return const Color(0xFF2E7D32);
    }
  }
}
