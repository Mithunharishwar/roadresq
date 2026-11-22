// FILE: lib/screens/mechanic_history_screen.dart
//
// A mechanic's finished jobs, read from the RoadResQ backend.
//
// This screen used to be entirely hardcoded: three invented jobs ("Arun /
// Battery Problem / + ₹250") and invented counters ("48 Completed",
// "3 Cancelled", "₹12K Earnings"). Every mechanic therefore saw the same
// fabricated earnings and history, which is worse than showing nothing.
// It now reads GET /api/mechanic/<id>/requests and derives everything from
// that response. Counters show real numbers; an empty account says so.

import 'package:material_ui/material_ui.dart';

import '../services/api_service.dart';

/// Canonical lifecycle states (backend/status_machine.py) that mean the job is
/// finished successfully, and those that mean it ended without a service.
const Set<String> _successStates = <String>{
  'SERVICE_COMPLETED',
  'PAYMENT_PENDING',
  'PAYMENT_COMPLETED',
  'RATED',
  'CLOSED',
};

const Set<String> _cancelledStates = <String>{
  'CANCELLED',
  'MECHANIC_DECLINED',
  'NO_MECHANIC_AVAILABLE',
  'PAYMENT_FAILED',
  'NETWORK_FAILURE',
};

class MechanicHistoryScreen extends StatefulWidget {
  final String mechanicId;

  const MechanicHistoryScreen({super.key, required this.mechanicId});

  @override
  State<MechanicHistoryScreen> createState() => _MechanicHistoryScreenState();
}

class _MechanicHistoryScreenState extends State<MechanicHistoryScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _finished = <Map<String, dynamic>>[];
  int _completed = 0;
  int _cancelled = 0;
  double _earnings = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static double _money(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _formatMoney(double value) {
    final rounded = value.roundToDouble();
    final whole = value == rounded
        ? rounded.toInt().toString()
        : value.toStringAsFixed(2);
    return '₹$whole';
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final raw =
          await ApiService.fetchMechanicRequests(mechanicId: widget.mechanicId);
      final rows = raw
          .whereType<Map<dynamic, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      final finished = <Map<String, dynamic>>[];
      var completed = 0;
      var cancelled = 0;
      var earnings = 0.0;

      for (final row in rows) {
        final canonical = (row['statusCanonical'] ?? '').toString();
        if (_successStates.contains(canonical)) {
          completed++;
          earnings += _money(row['amount']);
          finished.add(row);
        } else if (_cancelledStates.contains(canonical)) {
          cancelled++;
          finished.add(row);
        }
      }

      if (!mounted) return;
      setState(() {
        _finished = finished;
        _completed = completed;
        _cancelled = cancelled;
        _earnings = earnings;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Widget _buildStatsCard(String title, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withAlpha((0.12 * 255).round()),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 6),
            Text(title, style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> data) {
    final canonical = (data['statusCanonical'] ?? '').toString();
    final cancelled = _cancelledStates.contains(canonical);
    final statusColor = cancelled ? Colors.red : Colors.green;
    final amount = _money(data['amount']);

    final customer = (data['name'] ?? '').toString();
    final issue = (data['issue'] ?? '').toString();
    final vehicle = (data['vehicle'] ?? '').toString();
    final location =
        (data['locationText'] ?? data['regionName'] ?? '').toString();
    final createdAt = (data['createdAt'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha((0.05 * 255).round()),
              blurRadius: 12),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person, color: Color(0xFF0D47A1)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  customer.isEmpty ? 'Customer' : customer,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              Text(
                amount > 0 ? '+ ${_formatMoney(amount)}' : '—',
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (issue.isNotEmpty) Text('Issue: $issue'),
          if (vehicle.isNotEmpty) Text('Vehicle: $vehicle'),
          if (location.isNotEmpty) Text('Location: $location'),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.access_time, size: 14, color: Colors.black54),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  createdAt.isEmpty ? 'Time not recorded' : createdAt,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha((0.12 * 255).round()),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  (data['statusLabel'] ?? data['status'] ?? '').toString(),
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 40),
          const Icon(Icons.cloud_off, size: 48, color: Colors.black26),
          const SizedBox(height: 16),
          Text(
            'Could not load your job history.\n\n$_error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 16),
          Center(
            child: ElevatedButton(
              onPressed: _load,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D47A1),
              ),
              child: const Text('Retry'),
            ),
          ),
        ],
      );
    }

    if (_finished.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 60),
          const Icon(Icons.history, size: 48, color: Colors.black26),
          const SizedBox(height: 16),
          const Text(
            'No finished jobs yet.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.black54),
          ),
          const SizedBox(height: 10),
          const Text(
            'Jobs appear here once they are completed or cancelled.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.black38),
          ),
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ),
        ],
      );
    }

    return ListView(
      children: _finished.map(_buildHistoryCard).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                _buildStatsCard('Completed', '$_completed', Colors.green),
                const SizedBox(width: 10),
                _buildStatsCard('Cancelled', '$_cancelled', Colors.red),
                const SizedBox(width: 10),
                _buildStatsCard(
                    'Earnings', _formatMoney(_earnings), Colors.blue),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildBody(),
            ),
          ),
        ],
      ),
    );
  }
}
