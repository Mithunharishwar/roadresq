// FILE: lib/screens/allocation_insights_screen.dart
/// Live view of the regional mechanic allocation engine.
///
/// This screen calls the real backend (`POST /api/allocation/find` in dry-run
/// mode) and renders exactly what the engine decided:
///
///   * which region the GPS point resolved to,
///   * how many mechanics were considered and how many were eligible,
///   * for every rejected mechanic, the machine-readable reason,
///   * for every eligible mechanic, its rank and score breakdown,
///   * the server-measured assignment latency.
///
/// It is the fastest way to see the research contribution working end to end,
/// and it doubles as the evidence-capture screen for the journal.
///
/// Nothing is simulated here: if the backend is unreachable the screen says so
/// rather than showing placeholder results.
library;

import 'package:material_ui/material_ui.dart';

import '../core/config/app_config.dart';
import '../models/allocation_model.dart';
import '../services/allocation_service.dart';

class AllocationInsightsScreen extends StatefulWidget {
  const AllocationInsightsScreen({super.key});

  @override
  State<AllocationInsightsScreen> createState() =>
      _AllocationInsightsScreenState();
}

class _AllocationInsightsScreenState extends State<AllocationInsightsScreen> {
  // Chennai Central — matches backend/seed_demo_data.py so the seeded
  // mechanics are in range. Editable, so any GPS point can be probed.
  final TextEditingController _latController =
      TextEditingController(text: '13.0827');
  final TextEditingController _lngController =
      TextEditingController(text: '80.2707');

  String _issue = AppConfig.serviceCategories.first;
  String _vehicle = 'Car';

  bool _loading = false;
  String? _error;
  AllocationDecision? _decision;
  Map<String, dynamic>? _config;
  Map<String, dynamic>? _dashboard;

  @override
  void initState() {
    super.initState();
    _loadContext();
  }

  @override
  void dispose() {
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  Future<void> _loadContext() async {
    try {
      final config = await AllocationService.publicConfig();
      if (!mounted) return;
      setState(() => _config = config);
    } catch (e) {
      debugPrint('publicConfig failed: $e');
    }

    try {
      final dashboard = await AllocationService.adminDashboard();
      if (!mounted) return;
      setState(() => _dashboard = dashboard);
    } catch (e) {
      debugPrint('adminDashboard failed: $e');
    }
  }

  Future<void> _runAllocation() async {
    final lat = double.tryParse(_latController.text.trim());
    final lng = double.tryParse(_lngController.text.trim());

    if (lat == null || lng == null) {
      setState(() => _error = 'Enter numeric latitude and longitude.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _decision = null;
    });

    try {
      final decision = await AllocationService.dryRun(
        lat: lat,
        lng: lng,
        issue: _issue,
        vehicle: _vehicle,
      );
      if (!mounted) return;
      setState(() => _decision = decision);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not reach the backend at '
          '${AppConfig.apiBaseUrl}.\n$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        title: const Text('Allocation Engine'),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _backendCard(),
          const SizedBox(height: 12),
          _probeCard(),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null) _errorCard(_error!),
          if (_decision != null) ..._decisionSections(_decision!),
          const SizedBox(height: 12),
          _metricsCard(),
        ],
      ),
    );
  }

  // ── Cards ─────────────────────────────────────────────────────────────
  Widget _card({required Widget child, Color? border}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: border == null ? null : Border.all(color: border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha((0.05 * 255).round()),
              blurRadius: 10,
            ),
          ],
        ),
        child: child,
      );

  Widget _backendCard() {
    final devMode = _config?['devMode'];
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Backend',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 6),
          Text(
            AppConfig.apiBaseUrl,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12.5,
              color: Color(0xFF0D47A1),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            AppConfig.isExplicitlyConfigured
                ? 'Host supplied via --dart-define.'
                : 'Host resolved from the platform default. For a physical '
                    'device run: flutter run --dart-define=ROADRESQ_HOST='
                    'http://<your-ip>:5050',
            style: const TextStyle(fontSize: 11.5, color: Colors.black54),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _chip(
                devMode == true ? 'DEV MODE' : 'PRODUCTION MODE',
                devMode == true ? Colors.orange : Colors.green,
              ),
              const SizedBox(width: 8),
              _chip(
                '${AppConfig.serviceCategories.length} services',
                Colors.blueGrey,
              ),
              const SizedBox(width: 8),
              _chip('${AppConfig.vehicleCategories.length} vehicles',
                  Colors.blueGrey),
            ],
          ),
        ],
      ),
    );
  }

  Widget _probeCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Probe a GPS point',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 4),
          const Text(
            'Runs a dry run: the engine evaluates every mechanic and reports '
            'its decision without creating or modifying anything.',
            style: TextStyle(fontSize: 11.5, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _latController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Latitude',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _lngController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Longitude',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _issue,
            decoration: const InputDecoration(
              labelText: 'Service',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: AppConfig.serviceCategories
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _issue = value);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _vehicle,
            decoration: const InputDecoration(
              labelText: 'Vehicle',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: AppConfig.vehicleCategories
                .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _vehicle = value);
            },
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _loading ? null : _runAllocation,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D47A1),
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Run allocation'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard(String message) => _card(
        border: Colors.red.shade200,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red.shade700),
                const SizedBox(width: 8),
                const Text(
                  'Could not complete the request',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(message, style: const TextStyle(fontSize: 12.5)),
          ],
        ),
      );

  List<Widget> _decisionSections(AllocationDecision decision) {
    final eligible =
        decision.candidates.where((c) => c.eligible).toList(growable: false);
    final rejected =
        decision.candidates.where((c) => !c.eligible).toList(growable: false);

    return [
      _card(
        border:
            decision.assigned ? Colors.green.shade200 : Colors.orange.shade200,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  decision.assigned ? Icons.check_circle : Icons.info_outline,
                  color: decision.assigned
                      ? Colors.green.shade700
                      : Colors.orange.shade800,
                ),
                const SizedBox(width: 8),
                Text(
                  decision.assigned
                      ? 'Mechanic selected'
                      : 'No mechanic selected',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _kv('Status', decision.status),
            _kv('Region',
                '${decision.regionName ?? 'not resolved'}${decision.regionId != null ? ' (${decision.regionId})' : ''}'),
            _kv('Candidates evaluated', '${decision.candidateCount}'),
            _kv('Eligible', '${decision.eligibleCount}'),
            if (decision.escalationUsed)
              _kv('Escalation', 'wider radius used (region had nobody)'),
            if (decision.assignmentTimeMs != null)
              _kv('Assignment latency', '${decision.assignmentTimeMs} ms'),
            if (decision.failureReason != null)
              _kv('Dominant failure reason', decision.failureReason!),
            if (decision.selected != null) ...[
              const Divider(height: 22),
              _kv('Selected', decision.selected!.name),
              _kv('Rank', '${decision.selected!.rank ?? '-'}'),
              _kv(
                'Distance',
                decision.selected!.distanceKm == null
                    ? 'unavailable'
                    : '${decision.selected!.distanceKm!.toStringAsFixed(2)} km',
              ),
              _kv(
                'ETA (estimated)',
                decision.selected!.etaMinutes == null
                    ? 'unavailable'
                    : '${decision.selected!.etaMinutes!.toStringAsFixed(1)} min',
              ),
              _kv('Score', decision.selected!.score?.toStringAsFixed(4) ?? '-'),
            ],
            const SizedBox(height: 10),
            const Text(
              AllocationDecision.distanceNote,
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      if (decision.selected != null)
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Why this mechanic won',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              const SizedBox(height: 10),
              ..._scoreBreakdown(decision.selected!),
            ],
          ),
        ),
      const SizedBox(height: 12),
      if (eligible.isNotEmpty)
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Eligible mechanics (${eligible.length})',
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              const SizedBox(height: 8),
              ...eligible.map(_candidateTile),
            ],
          ),
        ),
      const SizedBox(height: 12),
      if (rejected.isNotEmpty)
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Rejected mechanics (${rejected.length})',
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              const SizedBox(height: 4),
              const Text(
                'Each rejection carries the rule that removed it. An ineligible '
                'mechanic is never silently assigned.',
                style: TextStyle(fontSize: 11.5, color: Colors.black54),
              ),
              const SizedBox(height: 10),
              ...rejected.map(_candidateTile),
            ],
          ),
        ),
      const SizedBox(height: 12),
      if (decision.readableTrace.isNotEmpty)
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Engine trace',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text(
                    decision.readableTrace,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Color(0xFF93C5FD),
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _scoreBreakdown(AllocationCandidate candidate) {
    final weights =
        (_config?['allocation'] as Map?)?['weights'] as Map? ?? const {};
    final labels = <String, String>{
      'proximity': 'Proximity',
      'serviceMatch': 'Service match',
      'availability': 'Availability',
      'verification': 'Verification',
      'workloadFactor': 'Workload',
      'ratingFactor': 'Rating',
    };

    final children = <Widget>[];
    candidate.components.forEach((key, value) {
      final weight = (weights[key] as num?)?.toDouble();
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      labels[key] ?? key,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    value.toStringAsFixed(3) +
                        (weight != null
                            ? '  × ${weight.toStringAsFixed(2)}'
                            : ''),
                    style:
                        const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: value.clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: const Color(0xFFE5E7EB),
                ),
              ),
            ],
          ),
        ),
      );
    });

    children.add(
      const Text(
        'Weights are configuration, not a validated optimum.',
        style: TextStyle(fontSize: 11, color: Colors.black54),
      ),
    );
    return children;
  }

  Widget _candidateTile(AllocationCandidate candidate) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: candidate.eligible
            ? Colors.green.withAlpha((0.06 * 255).round())
            : Colors.red.withAlpha((0.05 * 255).round()),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (candidate.rank != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D47A1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '#${candidate.rank}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800),
                  ),
                ),
              Expanded(
                child: Text(
                  candidate.name.isEmpty
                      ? candidate.mechanicId
                      : candidate.name,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ),
              if (candidate.distanceKm != null)
                Text(
                  '${candidate.distanceKm!.toStringAsFixed(2)} km',
                  style: const TextStyle(fontSize: 11.5),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            candidate.eligible
                ? 'eligible • score ${candidate.score?.toStringAsFixed(4) ?? '-'} • '
                    'ETA ${candidate.etaMinutes?.toStringAsFixed(1) ?? '-'} min'
                : candidate.reasonsText,
            style: TextStyle(
              fontSize: 11,
              color: candidate.eligible
                  ? Colors.green.shade800
                  : Colors.red.shade800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricsCard() {
    final dashboard = _dashboard;
    if (dashboard == null) {
      return _card(
        child: const Text(
          'Admin metrics unavailable. Sign-in may be required, or the backend '
          'is not reachable.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
      );
    }

    final allocation = (dashboard['allocation'] as Map?) ?? const {};
    final overview = (dashboard['overview'] as Map?) ?? const {};

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Measured allocation metrics',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 4),
          const Text(
            'Aggregated from stored allocation records on the server.',
            style: TextStyle(fontSize: 11.5, color: Colors.black54),
          ),
          const SizedBox(height: 10),
          _kv('Attempts', '${allocation['totalAllocationAttempts'] ?? 0}'),
          _kv('Successful assignments',
              '${allocation['successfulAssignments'] ?? 0}'),
          _kv('No-mechanic cases', '${allocation['noMechanicCases'] ?? 0}'),
          _kv('Success rate', _rate(allocation['assignmentSuccessRate'])),
          _kv('Acceptance rate', _rate(allocation['mechanicAcceptanceRate'])),
          _kv('Avg assignment time', _ms(allocation['avgAssignmentTimeMs'])),
          _kv('Avg assigned distance',
              _km(allocation['avgAssignedDistanceKm'])),
          _kv('Avg ETA', _minutes(allocation['avgEtaMinutes'])),
          const Divider(height: 22),
          _kv('Mechanics', '${overview['totalMechanics'] ?? 0}'),
          _kv('Online mechanics', '${overview['onlineMechanics'] ?? 0}'),
          _kv('Total requests', '${overview['totalRequests'] ?? 0}'),
          const SizedBox(height: 8),
          const Text(
            'A metric with no underlying data is reported as null, never '
            'estimated.',
            style: TextStyle(fontSize: 11, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  // ── Small helpers ─────────────────────────────────────────────────────
  Widget _kv(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 150,
              child: Text(
                label,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withAlpha((0.12 * 255).round()),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      );

  static String _rate(dynamic value) {
    if (value == null) return 'not measured yet';
    final n = (value as num).toDouble();
    return '${(n * 100).toStringAsFixed(1)}%';
  }

  static String _ms(dynamic value) =>
      value == null ? 'not measured yet' : '$value ms';

  static String _km(dynamic value) =>
      value == null ? 'not measured yet' : '$value km';

  static String _minutes(dynamic value) =>
      value == null ? 'not measured yet' : '$value min';
}
