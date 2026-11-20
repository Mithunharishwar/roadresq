// FILE: lib/screens/garage_history_screen.dart
//
// Garage job history — the garage's equivalent of `MechanicHistoryScreen` and
// `AssistantHistoryScreen`.
//
// The garage dashboard only ever showed the working queue, so a completed job
// disappeared from the app the moment it was billed. This screen lists the
// finished jobs (service completed, paid, rated, closed) with their amount and
// date, read from the same `GET /api/garage/<id>/jobs` endpoint the dashboard
// uses — one record, two views, no second source of truth.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/request_status.dart';
import '../core/utils/error_handler.dart';
import '../services/api_service.dart';

class GarageHistoryScreen extends StatefulWidget {
  const GarageHistoryScreen({super.key, this.onLogout});

  /// Supplied by the shell so the tab header can offer logout, the same action
  /// the other three roles expose from their profile screens.
  final Future<void> Function()? onLogout;

  @override
  State<GarageHistoryScreen> createState() => _GarageHistoryScreenState();
}

class _GarageHistoryScreenState extends State<GarageHistoryScreen> {
  static const Color _purple = Color(0xFF7E57C2);

  List<Map<String, dynamic>> history = <Map<String, dynamic>>[];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool spinner = true}) async {
    if (spinner && mounted) setState(() => loading = true);

    final prefs = await SharedPreferences.getInstance();
    final garageId = (prefs.getString('garageId') ?? '').trim();

    if (garageId.isEmpty) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = 'No garage is signed in on this device.';
      });
      return;
    }

    try {
      final jobs = await ApiService.fetchGarageJobs(garageId);
      final finished = jobs.cast<Map<String, dynamic>>().where((job) {
        final status = RequestStatusInfo.parse('${job['statusCanonical'] ?? job['status'] ?? ''}');
        return status?.isFinished ?? false;
      }).toList()
        ..sort((a, b) {
          final ad = DateTime.tryParse('${a['updatedAt'] ?? a['createdAt'] ?? ''}');
          final bd = DateTime.tryParse('${b['updatedAt'] ?? b['createdAt'] ?? ''}');
          if (ad == null || bd == null) return 0;
          return bd.compareTo(ad);
        });

      if (!mounted) return;
      setState(() {
        history = finished;
        loading = false;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = ErrorHandler.getFriendlyMessage(e);
      });
    }
  }

  double _amount(Map<String, dynamic> job) {
    final value = job['amount'];
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }

  String _date(Map<String, dynamic> job) {
    final raw = '${job['updatedAt'] ?? job['createdAt'] ?? ''}';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return '';
    final local = parsed.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final total = history.fold<double>(0, (sum, job) => sum + _amount(job));

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      body: SafeArea(
        bottom: false,
        child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            color: _purple,
            child: Row(
              children: [
                const Icon(Icons.history, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Garage History',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: () => _load(),
                  icon: const Icon(Icons.refresh, color: Colors.white),
                ),
                if (widget.onLogout != null)
                  IconButton(
                    tooltip: 'Logout',
                    onPressed: widget.onLogout,
                    icon: const Icon(Icons.logout, color: Colors.white),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
        color: _purple,
        onRefresh: () => _load(spinner: false),
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _stat('Jobs', '${history.length}'),
                        ),
                        Expanded(
                          child: _stat('Billed', '₹${total.toStringAsFixed(0)}'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (error != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Text(error!, style: const TextStyle(color: Colors.red)),
                          const SizedBox(height: 10),
                          ElevatedButton(
                            onPressed: () => _load(),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  else if (history.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Text(
                        'No finished jobs yet. Once a job is completed and paid '
                        'it will be listed here with its billed amount.',
                        style: TextStyle(color: Colors.black54),
                      ),
                    )
                  else
                    ...history.map(_buildRow),
                ],
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ],
    );
  }

  Widget _buildRow(Map<String, dynamic> job) {
    final status = RequestStatusInfo.parse(
      '${job['statusCanonical'] ?? job['status'] ?? ''}',
    );
    final paid = '${job['paymentStatus'] ?? ''}'.toLowerCase() == 'success' ||
        status == RequestStatus.paid;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (paid ? Colors.green : _purple).withAlpha(30),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              paid ? Icons.check_circle_outline : Icons.build_outlined,
              color: paid ? Colors.green : _purple,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (job['name'] ?? 'Customer').toString(),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if ((job['issue'] ?? '').toString().isNotEmpty)
                      job['issue'].toString(),
                    if ((job['vehicle'] ?? '').toString().isNotEmpty)
                      job['vehicle'].toString(),
                    _date(job),
                  ].join(' • '),
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₹${_amount(job).toStringAsFixed(0)}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                paid ? 'Paid' : (status?.label ?? 'Closed'),
                style: TextStyle(
                  fontSize: 11,
                  color: paid ? Colors.green : Colors.black54,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
