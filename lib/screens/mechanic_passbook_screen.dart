// FILE: lib/screens/mechanic_passbook_screen.dart
//
// A mechanic's earnings, read from the RoadResQ backend.
//
// Every figure on this screen used to be hardcoded — "Available Balance
// ₹4,850", "Today Earnings ₹850", "Weekly Bonus ₹600", "Acceptance Rate 92%",
// plus invented awards ("Top Captain - Chennai Central") and invented
// transactions ("Payout Settled - ₹2,000"). Mechanics were shown fabricated
// money. Everything below is derived from real requests returned by
// GET /api/mechanic/<id>/requests, and a mechanic with no paid jobs sees an
// honest empty state instead of a made-up balance.
//
// The "Achievements" section is gone: there is no data behind it anywhere in
// the system, so it could not be made truthful.

import 'package:material_ui/material_ui.dart';

import '../services/api_service.dart';

/// Canonical states (backend/status_machine.py) where the job produced income.
const Set<String> _earnedStates = <String>{
  'SERVICE_COMPLETED',
  'PAYMENT_PENDING',
  'PAYMENT_COMPLETED',
  'RATED',
  'CLOSED',
};

class MechanicPassbookScreen extends StatefulWidget {
  final String mechanicId;

  const MechanicPassbookScreen({super.key, required this.mechanicId});

  @override
  State<MechanicPassbookScreen> createState() => _MechanicPassbookScreenState();
}

class _MechanicPassbookScreenState extends State<MechanicPassbookScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _entries = <Map<String, dynamic>>[];
  double _total = 0;
  double _today = 0;

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

  /// True when an ISO timestamp falls on today's local date.
  static bool _isToday(String? iso) {
    if (iso == null || iso.isEmpty) return false;
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return false;
    final local = parsed.toLocal();
    final now = DateTime.now();
    return local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
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

      final entries = <Map<String, dynamic>>[];
      var total = 0.0;
      var today = 0.0;

      for (final row in rows) {
        final canonical = (row['statusCanonical'] ?? '').toString();
        if (!_earnedStates.contains(canonical)) continue;

        final amount = _money(row['amount']);
        total += amount;
        if (_isToday(row['createdAt']?.toString())) today += amount;
        entries.add(row);
      }

      if (!mounted) return;
      setState(() {
        _entries = entries;
        _total = total;
        _today = today;
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

  Widget _buildTopCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required List<Color> colors,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white.withAlpha((0.18 * 255).round()),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withAlpha((0.05 * 255).round()),
                blurRadius: 12),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransaction(Map<String, dynamic> data) {
    final amount = _money(data['amount']);
    final issue = (data['issue'] ?? 'Rescue job').toString();
    final customer = (data['name'] ?? '').toString();
    final location =
        (data['locationText'] ?? data['regionName'] ?? '').toString();
    final time = (data['createdAt'] ?? '').toString();

    final subtitleParts = <String>[
      if (customer.isNotEmpty) 'Customer: $customer',
      if (location.isNotEmpty) location,
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: Colors.green.withAlpha((0.18 * 255).round())),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.green.withAlpha((0.12 * 255).round()),
            child: const Icon(Icons.currency_rupee, color: Colors.green),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  issue,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitleParts.isEmpty
                      ? 'Completed rescue job'
                      : subtitleParts.join(' • '),
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 2),
                Text(
                  time.isEmpty ? 'Time not recorded' : time,
                  style: const TextStyle(fontSize: 11, color: Colors.black38),
                ),
              ],
            ),
          ),
          Text(
            amount > 0 ? '+ ${_formatMoney(amount)}' : '—',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.green,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF0D47A1)),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.only(top: 120),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 60),
            const Icon(Icons.cloud_off, size: 48, color: Colors.black26),
            const SizedBox(height: 16),
            Text(
              'Could not load your passbook.\n\n$_error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _load,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D47A1),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        _buildTopCard(
          title: 'Total Earned',
          value: _formatMoney(_total),
          subtitle: 'Across ${_entries.length} completed '
              '${_entries.length == 1 ? 'job' : 'jobs'}',
          icon: Icons.account_balance_wallet,
          colors: const [Color(0xFF0D47A1), Color(0xFF1976D2)],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _buildMiniCard(
              title: "Today's Earnings",
              value: _formatMoney(_today),
              icon: Icons.currency_rupee,
              color: Colors.green,
            ),
            const SizedBox(width: 12),
            _buildMiniCard(
              title: 'Completed Jobs',
              value: '${_entries.length}',
              icon: Icons.check_circle_outline,
              color: Colors.blue,
            ),
          ],
        ),
        const SizedBox(height: 22),
        _sectionTitle('Earnings by Job', Icons.receipt_long_outlined),
        const SizedBox(height: 12),
        if (_entries.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Column(
              children: [
                Icon(Icons.receipt_long_outlined,
                    size: 44, color: Colors.black26),
                SizedBox(height: 12),
                Text(
                  'No earnings recorded yet.',
                  style: TextStyle(fontSize: 15, color: Colors.black54),
                ),
                SizedBox(height: 8),
                Text(
                  'Once a rescue you complete is paid, it appears here with '
                  'its amount.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.black38),
                ),
              ],
            ),
          )
        else
          ..._entries.map(_buildTransaction),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // No Scaffold/AppBar here: MechanicMainScreen already supplies the app bar
    // for this tab, and nesting one produced a doubled header.
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: _buildBody(),
      ),
    );
  }
}
