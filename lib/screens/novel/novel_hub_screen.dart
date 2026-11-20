/// RoadResQ Novel Modules — Hub Screen.
///
/// A single entry point that surfaces all 6 additive novel feature modules
/// so they can be demoed / accessed without touching any existing screens.
library;

import 'package:flutter/material.dart';
import '../../widgets/novel/novel_widgets.dart';
import 'road_iq_screen.dart';
import 'trust_score_screen.dart';
import 'vehicle_journal_screen.dart';
import 'community_mesh_screen.dart';
import 'wallet_screen.dart';
import 'damage_recon_screen.dart';
import 'eco_score_screen.dart';
import 'fare_oracle_screen.dart';
import 'crew_pulse_screen.dart';

class NovelHubScreen extends StatelessWidget {
  const NovelHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const NovelHero(
              title: 'RoadResQ Intelligence',
              subtitle: '9 Novel Modules — Enhanced Rescue Ecosystem',
              icon: Icons.auto_awesome,
              colors: [Color(0xFF0D47A1), Color(0xFF7B1FA2)],
            ),
            const SizedBox(height: 20),
            NovelSectionTitle(
              title: 'Intelligence & Operations',
              icon: Icons.psychology,
              color: const Color(0xFF0D47A1),
            ),
            const SizedBox(height: 12),
            _moduleCard(
              context,
              icon: Icons.insights,
              title: 'RoadIQ',
              subtitle: 'Predictive demand & smart dispatch',
              colors: const [Color(0xFF0D47A1), Color(0xFF1E88E5)],
              screen: const RoadIqScreen(),
            ),
            _moduleCard(
              context,
              icon: Icons.workspace_premium,
              title: 'TrustScore',
              subtitle: 'Crew reputation & gamified badges',
              colors: const [Color(0xFF2E7D32), Color(0xFF66BB6A)],
              screen: const TrustScoreScreen(),
            ),
            _moduleCard(
              context,
              icon: Icons.build_circle_outlined,
              title: 'Digital Garage',
              subtitle: 'Vehicle service journal & health',
              colors: const [Color(0xFFE65100), Color(0xFFFF9800)],
              screen: const VehicleJournalScreen(),
            ),
            const SizedBox(height: 20),
            NovelSectionTitle(
              title: 'Safety & Community',
              icon: Icons.health_and_safety,
              color: const Color(0xFF00695C),
            ),
            const SizedBox(height: 12),
            _moduleCard(
              context,
              icon: Icons.people_outline,
              title: 'Community Mesh',
              subtitle: 'Crowd-sourced rescue & beacon',
              colors: const [Color(0xFF00695C), Color(0xFF26A69A)],
              screen: const CommunityMeshScreen(),
            ),
            _moduleCard(
              context,
              icon: Icons.camera_alt_outlined,
              title: 'Damage Recon',
              subtitle: 'Tamper-evident evidence capture',
              colors: const [Color(0xFF4A148C), Color(0xFF9C27B0)],
              screen: const DamageReconScreen(),
            ),
            const SizedBox(height: 20),
            NovelSectionTitle(
              title: 'Rewards',
              icon: Icons.redeem,
              color: const Color(0xFFB71C1C),
            ),
            const SizedBox(height: 12),
            _moduleCard(
              context,
              icon: Icons.account_balance_wallet,
              title: 'Wallet & Loyalty',
              subtitle: 'Cashback, referrals & member tiers',
              colors: const [Color(0xFFB71C1C), Color(0xFFE53935)],
              screen: const WalletScreen(),
            ),
            const SizedBox(height: 20),
            NovelSectionTitle(
              title: 'Ecosystem Intelligence',
              icon: Icons.auto_graph,
              color: const Color(0xFF4A148C),
            ),
            const SizedBox(height: 12),
            _moduleCard(
              context,
              icon: Icons.eco,
              title: 'EcoRide',
              subtitle: 'Green rescue & carbon impact scoring',
              colors: const [Color(0xFF2E7D32), Color(0xFF66BB6A)],
              screen: const EcoScoreScreen(),
            ),
            _moduleCard(
              context,
              icon: Icons.payments,
              title: 'FareOracle',
              subtitle: 'Transparent live dynamic pricing engine',
              colors: const [Color(0xFFE65100), Color(0xFFFFB300)],
              screen: const FareOracleScreen(),
            ),
            _moduleCard(
              context,
              icon: Icons.monitor_heart,
              title: 'CrewPulse',
              subtitle: 'AI performance & churn-risk analytics',
              colors: const [Color(0xFF0D47A1), Color(0xFF7B1FA2)],
              screen: const CrewPulseScreen(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _moduleCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Color> colors,
    required Widget screen,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => screen),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
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
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: colors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 12.5, color: Colors.black54)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black26),
            ],
          ),
        ),
      ),
    );
  }
}
