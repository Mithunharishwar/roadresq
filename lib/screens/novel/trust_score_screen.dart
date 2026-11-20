/// TrustScore — Layered Reputation & Gamified Badges Screen (novel module).
///
/// Shows a crew member's computed trust profile, badges, and tier, and
/// exposes the dispatch priority multiplier benefit.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/novel/trust_score_provider.dart';
import '../../widgets/novel/novel_widgets.dart';

class TrustScoreScreen extends ConsumerStatefulWidget {
  final String crewId;
  final String role;

  const TrustScoreScreen({
    super.key,
    this.crewId = 'Crew001',
    this.role = 'mechanic',
  });

  @override
  ConsumerState<TrustScoreScreen> createState() => _TrustScoreScreenState();
}

class _TrustScoreScreenState extends ConsumerState<TrustScoreScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(trustScoreProvider.notifier).computeProfile(
            crewId: widget.crewId,
            role: widget.role,
            rating: 4.6,
            ratingCount: 32,
            jobsCompleted: 48,
            onTime: 41,
            lateCount: 4,
            cancellations: 2,
            respondedFast: 40,
            zoneAdherent: 45,
            safetyAdherent: 46,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(trustScoreProvider);
    final profile = state.profile;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const NovelHero(
              title: 'TrustScore',
              subtitle: 'Layered Reputation & Gamified Badges',
              icon: Icons.workspace_premium,
              colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)],
            ),
            const SizedBox(height: 20),
            if (profile == null)
              const NovelEmptyCard(
                message: 'No trust profile computed yet.',
                icon: Icons.workspace_premium_outlined,
              )
            else ...[
              // Overall trust score
              _trustGauge(profile.trustScore),

              const SizedBox(height: 20),
              NovelSectionTitle(
                title: 'Behavioral Dimensions',
                icon: Icons.donut_small,
                color: const Color(0xFF2E7D32),
              ),
              const SizedBox(height: 12),
              _dimensionBar('Reliability', profile.reliabilityScore),
              _dimensionBar('Response', profile.responseScore),
              _dimensionBar('Rating', profile.ratingScore),
              _dimensionBar('Zone Consistency', profile.zoneConsistencyScore),
              _dimensionBar('Safety', profile.safetyScore),

              const SizedBox(height: 20),
              NovelSectionTitle(
                title: 'Earned Badges',
                icon: Icons.emoji_events,
                color: const Color(0xFFFF8F00),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: profile.badges.map((b) {
                  return NovelStatusPill(
                    text: _badgeLabel(b),
                    color: const Color(0xFFFF8F00),
                  );
                }).toList(),
              ),

              const SizedBox(height: 20),
              NovelSectionTitle(
                title: 'Tier Benefit',
                icon: Icons.bolt,
                color: const Color(0xFF7B1FA2),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color:
                      const Color(0xFF7B1FA2).withAlpha((0.08 * 255).round()),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Text(profile.tierIcon,
                        style: const TextStyle(fontSize: 30)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${_tierLabel(profile.tier)} member',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 16)),
                          const SizedBox(height: 4),
                          Text(
                            'Dispatch priority multiplier: '
                            '${ref.read(trustScoreProvider.notifier).dispatchMultiplier.toStringAsFixed(2)}×',
                            style: const TextStyle(
                                fontSize: 13, color: Colors.black87),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _trustGauge(double score) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha((0.06 * 255).round()),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            score.toStringAsFixed(1),
            style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          const Text('Trust Score / 100',
              style: TextStyle(fontSize: 13, color: Colors.black54)),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: score / 100,
            minHeight: 10,
            backgroundColor: const Color(0xFFE0E0E0),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2E7D32)),
          ),
        ],
      ),
    );
  }

  Widget _dimensionBar(String label, double score) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: const TextStyle(fontSize: 13, color: Colors.black87)),
              Text(score.toStringAsFixed(0),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: score / 100,
              minHeight: 7,
              backgroundColor: const Color(0xFFE0E0E0),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFF2E7D32)),
            ),
          ),
        ],
      ),
    );
  }

  String _badgeLabel(String badge) {
    switch (badge) {
      case 'experience_warrior':
        return '⚔️ Experience Warrior';
      case 'road_veteran':
        return '🏆 Road Veteran';
      case 'punctual_pro':
        return '⏱️ Punctual Pro';
      case 'rapid_responder':
        return '⚡ Rapid Responder';
      case 'zone_guardian':
        return '🛡️ Zone Guardian';
      case 'safety_champion':
        return '🦺 Safety Champion';
      case 'trust_elite':
        return '💎 Trust Elite';
      case 'rising_star':
        return '🌟 Rising Star';
      default:
        return badge;
    }
  }

  String _tierLabel(String tier) {
    switch (tier) {
      case 'gold':
        return 'Gold';
      case 'platinum':
        return 'Platinum';
      case 'silver':
        return 'Silver';
      default:
        return 'Bronze';
    }
  }
}
