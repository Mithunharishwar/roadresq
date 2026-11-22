/// RoadIQ — Predictive Demand & Dispatch Intelligence Screen (novel module).
///
/// Displays a demand forecast for a selected hour, a live demand heatmap,
/// smart ETA refinement, and pre-warm crew recommendations.
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/novel/road_iq_provider.dart';
import '../../widgets/novel/novel_widgets.dart';

class RoadIqScreen extends ConsumerStatefulWidget {
  const RoadIqScreen({super.key});

  @override
  ConsumerState<RoadIqScreen> createState() => _RoadIqScreenState();
}

class _RoadIqScreenState extends ConsumerState<RoadIqScreen> {
  int _selectedHour = DateTime.now().hour;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(roadIqProvider.notifier).generateForecast(hour: _selectedHour);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(roadIqProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const NovelHero(
              title: 'RoadIQ',
              subtitle: 'Predictive Demand & Smart Dispatch Intelligence',
              icon: Icons.insights,
              colors: [Color(0xFF0D47A1), Color(0xFF1E88E5)],
            ),
            const SizedBox(height: 20),

            // Hour selector
            NovelSectionTitle(
              title: 'Demand Forecast',
              icon: Icons.access_time,
              color: const Color(0xFF0D47A1),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: List.generate(24, (h) {
                  final isSelected = h == _selectedHour;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('${h.toString().padLeft(2, '0')}:00'),
                      selected: isSelected,
                      onSelected: (_) {
                        setState(() => _selectedHour = h);
                        ref
                            .read(roadIqProvider.notifier)
                            .generateForecast(hour: h);
                      },
                      selectedColor: const Color(0xFF0D47A1),
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 16),

            if (state.isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (state.forecasts.isEmpty)
              const NovelEmptyCard(
                message: 'No forecast data available for this hour.',
                icon: Icons.query_stats,
              )
            else
              ...state.forecasts.map((p) => _forecastTile(p)),

            const SizedBox(height: 20),
            NovelSectionTitle(
              title: 'Smart ETA Refinement',
              icon: Icons.route,
              color: const Color(0xFF00897B),
            ),
            const SizedBox(height: 12),
            _etaCard(state),

            const SizedBox(height: 20),
            NovelSectionTitle(
              title: 'Crew Pre-warm Recommendation',
              icon: Icons.groups,
              color: const Color(0xFF7B1FA2),
            ),
            const SizedBox(height: 12),
            _crewRecommendation(state),
          ],
        ),
      ),
    );
  }

  Widget _forecastTile(dynamic p) {
    final demand = (p.predictedDemand as num).toDouble();
    final crews = (p.recommendedCrews as num).toInt();
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${p.zoneName} • ${_prettyType(p.serviceType)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
              NovelStatusPill(text: _tier(demand), color: _tierColor(demand)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: demand / 100,
              minHeight: 8,
              backgroundColor: const Color(0xFFE0E0E0),
              valueColor: AlwaysStoppedAnimation<Color>(_tierColor(demand)),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Demand: ${demand.toStringAsFixed(1)}%',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
              Text('Crews: $crews',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
              Text('Conf: ${(p.confidence * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _etaCard(RoadIqState state) {
    final notifier = ref.read(roadIqProvider.notifier);
    final base = 15.0;
    final refined = notifier.refineEta(
      baseEtaMinutes: base,
      trafficFactor: 1.2,
      activeJobsForCrew: 2,
      distanceKm: 6,
    );
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
      child: Row(
        children: [
          const Icon(Icons.timer_outlined, color: Color(0xFF00897B), size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Base ETA',
                    style: TextStyle(fontSize: 12, color: Colors.black54)),
                Text('$base min',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward, color: Colors.black26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Smart ETA',
                    style: TextStyle(fontSize: 12, color: Colors.black54)),
                Text('${refined.toStringAsFixed(1)} min',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF00897B))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _crewRecommendation(RoadIqState state) {
    final notifier = ref.read(roadIqProvider.notifier);
    final top = state.forecasts.isNotEmpty ? state.forecasts.first : null;
    final demand = top != null ? (top.predictedDemand as num).toDouble() : 60.0;
    final recommended = notifier.recommendCrews(predictedDemand: demand);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF7B1FA2).withAlpha((0.08 * 255).round()),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_add_alt, color: Color(0xFF7B1FA2), size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Recommend keeping $recommended crew${recommended == 1 ? '' : 's'} '
              'available to maintain service level for the top demand zone.',
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
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
        return 'General';
    }
  }

  String _tier(double demand) {
    if (demand >= 75) return 'High';
    if (demand >= 40) return 'Med';
    return 'Low';
  }

  Color _tierColor(double demand) {
    if (demand >= 75) return const Color(0xFFD32F2F);
    if (demand >= 40) return const Color(0xFFFF8F00);
    return const Color(0xFF2E7D32);
  }
}
