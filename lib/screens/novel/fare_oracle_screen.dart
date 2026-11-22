/// FareOracle — Smart Dynamic Pricing Engine Screen (novel module).
///
/// Lets a user tune the pricing signals (demand, weather, time, traffic,
/// availability) and instantly see a transparent surge multiplier + full
/// fare breakdown with a "why am I paying this" factor list.
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/novel/fare_oracle_model.dart';
import '../../providers/novel/fare_oracle_provider.dart';
import '../../widgets/novel/novel_widgets.dart';

class FareOracleScreen extends ConsumerStatefulWidget {
  const FareOracleScreen({super.key});

  @override
  ConsumerState<FareOracleScreen> createState() => _FareOracleScreenState();
}

class _FareOracleScreenState extends ConsumerState<FareOracleScreen> {
  String _serviceType = 'flat_tyre';
  double _distance = 4.5;
  double _demand = 0.72;
  String _weather = 'rain';
  int _hour = 20;
  double _traffic = 1.3;
  int _availableCrews = 6;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(fareOracleProvider.notifier).loadDemo();
    });
  }

  void _recompute() {
    ref.read(fareOracleProvider.notifier).estimate(
          serviceType: _serviceType,
          distanceKm: _distance,
          demandIndex: _demand,
          weather: _weather,
          hour: _hour,
          trafficFactor: _traffic,
          availableCrews: _availableCrews,
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fareOracleProvider);
    final estimate = state.estimate;

    return Scaffold(
      backgroundColor: const Color(0xFFFBF5F0),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const NovelHero(
              title: 'FareOracle',
              subtitle: 'Transparent Dynamic Pricing Engine',
              icon: Icons.payments,
              colors: [Color(0xFFE65100), Color(0xFFFFB300)],
            ),
            const SizedBox(height: 20),

            // Pricing signal controls
            const NovelSectionTitle(
              title: 'Pricing Signals',
              icon: Icons.tune,
              color: Color(0xFFE65100),
            ),
            const SizedBox(height: 12),
            _signalsCard(),
            const SizedBox(height: 16),

            ElevatedButton.icon(
              onPressed: _recompute,
              icon: const Icon(Icons.calculate),
              label: const Text('Predict Fare'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65100),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 20),

            if (state.isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (estimate == null)
              const NovelEmptyCard(
                message: 'Tune the signals and tap "Predict Fare".',
                icon: Icons.payments_outlined,
              )
            else ...[
              _fareCard(estimate),
              const SizedBox(height: 20),
              const NovelSectionTitle(
                title: 'Why am I paying this?',
                icon: Icons.info_outline,
                color: Color(0xFF00897B),
              ),
              const SizedBox(height: 12),
              ...estimate.factors.map((f) => _factorTile(f)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _signalsCard() {
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
          DropdownButtonFormField<String>(
            initialValue: _serviceType,
            decoration: const InputDecoration(
              labelText: 'Service type',
              prefixIcon: Icon(Icons.car_repair),
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'flat_tyre', child: Text('Flat Tyre')),
              DropdownMenuItem(value: 'battery', child: Text('Battery')),
              DropdownMenuItem(value: 'fuel', child: Text('Fuel')),
              DropdownMenuItem(value: 'towing', child: Text('Towing')),
              DropdownMenuItem(value: 'lockout', child: Text('Lockout')),
            ],
            onChanged: (v) => setState(() => _serviceType = v ?? 'flat_tyre'),
          ),
          const SizedBox(height: 12),
          _slider('Distance', '${_distance.toStringAsFixed(1)} km', _distance,
              1, 15, (v) => setState(() => _distance = v)),
          _slider('Demand index', '${(_demand * 100).toStringAsFixed(0)}%',
              _demand, 0, 1, (v) => setState(() => _demand = v)),
          _slider(
              'Traffic congestion',
              '${(_traffic * 100).toStringAsFixed(0)}%',
              _traffic,
              1.0,
              2.0,
              (v) => setState(() => _traffic = v)),
          _slider(
              'Crews available',
              '$_availableCrews',
              _availableCrews.toDouble(),
              0,
              20,
              (v) => setState(() => _availableCrews = v.round())),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _weather,
            decoration: const InputDecoration(
              labelText: 'Weather',
              prefixIcon: Icon(Icons.wb_sunny),
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'clear', child: Text('Clear')),
              DropdownMenuItem(value: 'rain', child: Text('Rain')),
              DropdownMenuItem(value: 'storm', child: Text('Storm')),
              DropdownMenuItem(value: 'fog', child: Text('Fog')),
              DropdownMenuItem(value: 'hot', child: Text('Heat')),
            ],
            onChanged: (v) => setState(() => _weather = v ?? 'clear'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _hour,
            decoration: const InputDecoration(
              labelText: 'Time of day',
              prefixIcon: Icon(Icons.access_time),
              border: OutlineInputBorder(),
            ),
            items: List.generate(
                24,
                (h) => DropdownMenuItem(
                    value: h,
                    child: Text('${h.toString().padLeft(2, '0')}:00'))),
            onChanged: (v) => setState(() => _hour = v ?? 12),
          ),
        ],
      ),
    );
  }

  Widget _slider(String label, String value, double val, double min, double max,
      ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(label,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ),
        Expanded(
          child: Slider(
            value: val.clamp(min, max),
            min: min,
            max: max,
            activeColor: const Color(0xFFE65100),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 60,
          child: Text(value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ),
      ],
    );
  }

  Widget _fareCard(FareEstimate estimate) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE65100), Color(0xFFFFC107)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE65100).withAlpha((0.30 * 255).round()),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Estimated Fare',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              const Spacer(),
              NovelStatusPill(
                text: _tierLabel(estimate.fareTier),
                color: _tierColor(estimate.fareTier),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '₹ ${estimate.total.toStringAsFixed(0)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Base ₹${estimate.baseFare.toStringAsFixed(0)} × '
            '${estimate.surgeMultiplier.toStringAsFixed(2)} surge',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _miniStat('ETA', '${estimate.etaMinutes}m'),
              const SizedBox(width: 16),
              _miniStat('Fare', '₹${estimate.fare.toStringAsFixed(0)}'),
              const SizedBox(width: 16),
              _miniStat('GST', '₹${estimate.gst.toStringAsFixed(0)}'),
              const SizedBox(width: 16),
              _miniStat('Crews', '${estimate.expectedAvailableCrews}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 11)),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _factorTile(PriceFactor factor) {
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
          SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(
                    value: factor.weight.clamp(0.0, 0.5) / 0.5,
                    strokeWidth: 4,
                    backgroundColor: const Color(0xFFE0E0E0),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Color(0xFFE65100)),
                  ),
                ),
                Text(
                  '+${(factor.weight * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 10, color: Colors.black87),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(factor.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 2),
                Text(factor.detail,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _tierLabel(String tier) {
    switch (tier) {
      case 'high_surge':
        return 'High Surge';
      case 'surge':
        return 'Surge';
      case 'normal':
        return 'Normal';
      default:
        return 'Low';
    }
  }

  Color _tierColor(String tier) {
    switch (tier) {
      case 'high_surge':
        return const Color(0xFFB71C1C);
      case 'surge':
        return const Color(0xFFD32F2F);
      case 'normal':
        return const Color(0xFF2E7D32);
      default:
        return const Color(0xFF00897B);
    }
  }
}
