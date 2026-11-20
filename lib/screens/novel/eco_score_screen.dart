/// EcoRide — Green Rescue & Carbon Intelligence Screen (novel module).
///
/// Shows the user/crew Green Tier, composite EcoScore, aggregate CO2 saved,
/// an offset "trees equivalent" counter, and a per-rescue impact breakdown.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/novel/eco_score_model.dart';
import '../../providers/novel/eco_score_provider.dart';
import '../../widgets/novel/novel_widgets.dart';

class EcoScoreScreen extends ConsumerStatefulWidget {
  const EcoScoreScreen({super.key});

  @override
  ConsumerState<EcoScoreScreen> createState() => _EcoScoreScreenState();
}

class _EcoScoreScreenState extends ConsumerState<EcoScoreScreen> {
  final _serviceTypeCtrl = TextEditingController(text: 'flat_tyre');
  final _distanceCtrl = TextEditingController(text: '3.2');
  String _fuelType = 'petrol';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(ecoScoreProvider.notifier).loadDemo();
    });
  }

  @override
  void dispose() {
    _serviceTypeCtrl.dispose();
    _distanceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ecoScoreProvider);
    final profile = state.profile;

    return Scaffold(
      backgroundColor: const Color(0xFFF4FBF5),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const NovelHero(
              title: 'EcoRide',
              subtitle: 'Green Rescue & Carbon Intelligence',
              icon: Icons.eco,
              colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)],
            ),
            const SizedBox(height: 20),
            if (state.isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (profile == null)
              const NovelEmptyCard(
                message: 'No eco profile yet. Add your first rescue impact.',
                icon: Icons.eco_outlined,
              )
            else ...[
              _scoreHeader(profile),
              const SizedBox(height: 16),
              _statsRow(profile),
              const SizedBox(height: 20),
              const NovelSectionTitle(
                title: 'Add Rescue Impact',
                icon: Icons.add_circle_outline,
                color: Color(0xFF2E7D32),
              ),
              const SizedBox(height: 12),
              _impactForm(),
              const SizedBox(height: 20),
              const NovelSectionTitle(
                title: 'Recent Impacts',
                icon: Icons.list_alt,
                color: Color(0xFF00897B),
              ),
              const SizedBox(height: 12),
              if (profile.recentImpacts.isEmpty)
                const NovelEmptyCard(message: 'No impacts recorded yet.')
              else
                ...profile.recentImpacts.take(6).map((i) => _impactTile(i)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _scoreHeader(EcoScore profile) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2E7D32), Color(0xFF4CAF50)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2E7D32).withAlpha((0.30 * 255).round()),
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
                    value: profile.ecoScore / 100,
                    strokeWidth: 8,
                    backgroundColor: Colors.white24,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Color(0xFFFFC107)),
                  ),
                ),
                Text(
                  profile.ecoScore.toStringAsFixed(0),
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
                const Text(
                  'EcoScore',
                  style: TextStyle(
                      color: Colors.white70, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  _tierLabel(profile.greenTier),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${profile.rescues} green rescues',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsRow(EcoScore profile) {
    return Row(
      children: [
        Expanded(
          child: NovelStatCard(
            title: 'CO₂ Saved',
            value: '${profile.totalCo2SavedKg.toStringAsFixed(1)} kg',
            color: const Color(0xFF2E7D32),
            icon: Icons.cloud_off,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: NovelStatCard(
            title: 'Trees',
            value: '${profile.treesEquivalent}',
            color: const Color(0xFF00897B),
            icon: Icons.park,
          ),
        ),
      ],
    );
  }

  Widget _impactForm() {
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
          TextField(
            controller: _serviceTypeCtrl,
            decoration: const InputDecoration(
              labelText: 'Service type',
              prefixIcon: Icon(Icons.car_repair),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _distanceCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Distance (km)',
              prefixIcon: Icon(Icons.straighten),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _fuelType,
            decoration: const InputDecoration(
              labelText: 'Crew vehicle fuel',
              prefixIcon: Icon(Icons.local_gas_station),
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'petrol', child: Text('Petrol')),
              DropdownMenuItem(value: 'diesel', child: Text('Diesel')),
              DropdownMenuItem(value: 'ev', child: Text('Electric')),
              DropdownMenuItem(value: 'manual', child: Text('Manual / Cycle')),
            ],
            onChanged: (v) => setState(() => _fuelType = v ?? 'petrol'),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                final notifier = ref.read(ecoScoreProvider.notifier);
                notifier.computeImpact(
                  name: 'You',
                  serviceType: _serviceTypeCtrl.text.trim().isEmpty
                      ? 'general'
                      : _serviceTypeCtrl.text.trim(),
                  distanceKm: double.tryParse(_distanceCtrl.text) ?? 3.0,
                  fuelType: _fuelType,
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Impact computed & added to your profile.'),
                  ),
                );
              },
              icon: const Icon(Icons.eco),
              label: const Text('Compute Impact'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _impactTile(EcoImpact impact) {
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
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF2E7D32).withAlpha((0.12 * 255).round()),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.eco, color: Color(0xFF2E7D32), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _prettyType(impact.serviceType),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  '${impact.distanceKm.toStringAsFixed(1)} km • '
                  '${impact.co2Kg.toStringAsFixed(2)} kg emitted • '
                  '${impact.co2SavedKg.toStringAsFixed(2)} kg saved',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
          NovelStatusPill(
            text: impact.ecoScore.toStringAsFixed(0),
            color: const Color(0xFF2E7D32),
          ),
        ],
      ),
    );
  }

  String _tierLabel(String tier) {
    switch (tier) {
      case 'eco_elite':
        return '🌳 Eco Elite';
      case 'eco_guardian':
        return '🌿 Eco Guardian';
      case 'eco_saver':
        return '🍃 Eco Saver';
      default:
        return '🌱 Eco Beginner';
    }
  }

  String _prettyType(String type) {
    switch (type) {
      case 'flat_tyre':
        return 'Flat Tyre';
      case 'battery':
        return 'Battery';
      case 'fuel':
        return 'Fuel';
      case 'towing':
        return 'Towing';
      case 'lockout':
        return 'Lockout';
      default:
        return type.isEmpty ? 'General' : type;
    }
  }
}
