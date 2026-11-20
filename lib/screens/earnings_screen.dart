// FILE: lib/screens/earnings_screen.dart
/// §30 / §42 — earnings for a mechanic or an assistant.
///
/// Data comes from `GET /api/mechanic/<id>/earnings` or
/// `GET /api/assistant/<id>/earnings`. Both compute totals from the `amount`
/// recorded on completed jobs; the assistant figure applies the configured
/// incentive percentage. The screen prints that basis at the bottom so the
/// number is never mistaken for a payroll statement.
library;

import 'package:flutter/material.dart';

import '../core/session/app_session.dart';
import '../core/theme/role_colors.dart';
import '../services/module_api.dart';
import '../widgets/rq_async.dart';

enum EarningsAudience { mechanic, assistant }

class EarningsScreen extends StatefulWidget {
  const EarningsScreen({
    super.key,
    required this.audience,
    this.crewId,
  });

  final EarningsAudience audience;
  final String? crewId;

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  Map<String, dynamic> _data = const {};
  bool _loading = true;
  String? _error;

  bool get _isMechanic => widget.audience == EarningsAudience.mechanic;
  String get _id => widget.crewId ?? AppSession.id ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_id.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'No crew member is signed in.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = _isMechanic
          ? await ModuleApi.mechanicEarnings(_id)
          : await ModuleApi.assistantEarnings(_id);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = rqMessage(e);
      });
    }
  }

  double _num(String key) => (_data[key] as num?)?.toDouble() ?? 0.0;
  int _int(String key) => (_data[key] as num?)?.toInt() ?? 0;
  String get _currency => (_data['currency'] ?? 'INR').toString();

  @override
  Widget build(BuildContext context) {
    final color =
        _isMechanic ? RoleColors.mechanic : RoleColors.assistant;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isMechanic ? 'Earnings' : 'Earnings & incentives',
            style: const TextStyle(inherit: true)),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const RqLoading(label: 'Loading earnings…')
          : _error != null
              ? RqError(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              RoleColors.tint(color, opacity: 0.16),
                              RoleColors.tint(color, opacity: 0.05),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: RoleColors.tint(color, opacity: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Today',
                              style: TextStyle(
                                  inherit: true,
                                  fontSize: 12,
                                  color: color,
                                  fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$_currency ${_num('today').toStringAsFixed(2)}',
                              style: const TextStyle(
                                  inherit: true,
                                  fontSize: 32,
                                  fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'This week $_currency '
                              '${_num('week').toStringAsFixed(2)}',
                              style: const TextStyle(
                                  inherit: true,
                                  fontSize: 12,
                                  color: RoleColors.neutral),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _stat('Total', _num('total'),
                                Icons.account_balance_wallet_outlined, color),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _stat('Jobs done', _int('totalJobs')
                                .toDouble(), Icons.task_alt, color,
                                isCount: true),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _stat('Assigned', _int('assignedJobs')
                                .toDouble(), Icons.assignment_outlined, color,
                                isCount: true),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _stat(
                              _isMechanic ? 'Avg ticket' : 'Incentive %',
                              _isMechanic
                                  ? _num('averageJobValue')
                                  : _num('incentivePercent'),
                              _isMechanic
                                  ? Icons.receipt_long_outlined
                                  : Icons.percent,
                              color,
                              isCount: !_isMechanic,
                              suffix: _isMechanic ? '' : '%',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Text('Last 7 days',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(inherit: true,
                                  fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      ..._dailyBars(color),
                      const SizedBox(height: 18),
                      if (_data['basis'] != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: RoleColors.tint(RoleColors.neutral,
                                opacity: 0.07),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'Basis: ${_data['basis']}',
                            style: const TextStyle(
                                inherit: true,
                                fontSize: 11,
                                color: RoleColors.neutral,
                                height: 1.4),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _stat(String label, double value, IconData icon, Color color,
      {bool isCount = false, String suffix = ''}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 8),
          Text(
            isCount
                ? '${value.toStringAsFixed(0)}$suffix'
                : '$_currency ${value.toStringAsFixed(2)}',
            style: const TextStyle(
                inherit: true, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          Text(label,
              style: const TextStyle(
                  inherit: true, fontSize: 11, color: RoleColors.neutral)),
        ],
      ),
    );
  }

  List<Widget> _dailyBars(Color color) {
    final raw = _data['daily'];
    final rows = raw is List
        ? raw.whereType<Map>().map((r) => r.cast<String, dynamic>()).toList()
        : <Map<String, dynamic>>[];

    if (rows.isEmpty) {
      return const [
        RqEmpty(
          icon: Icons.bar_chart,
          title: 'No completed jobs yet',
          message: 'Daily figures appear once a job is completed.',
        ),
      ];
    }

    final maxAmount = rows
        .map((r) => (r['amount'] as num?)?.toDouble() ?? 0.0)
        .fold<double>(1.0, (a, b) => b > a ? b : a);

    return rows.map((row) {
      final amount = (row['amount'] as num?)?.toDouble() ?? 0.0;
      final jobs = (row['jobs'] as num?)?.toInt() ?? 0;
      final ratio = maxAmount == 0 ? 0.0 : amount / maxAmount;
      final date = (row['date'] ?? '').toString();

      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            SizedBox(
              width: 74,
              child: Text(
                date.length >= 10 ? date.substring(5) : date,
                style: const TextStyle(
                    inherit: true, fontSize: 11, color: RoleColors.neutral),
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 12,
                  backgroundColor:
                      RoleColors.tint(RoleColors.neutral, opacity: 0.10),
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 92,
              child: Text(
                '${amount.toStringAsFixed(0)} · $jobs job${jobs == 1 ? '' : 's'}',
                textAlign: TextAlign.right,
                style: const TextStyle(inherit: true, fontSize: 10),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }
}
