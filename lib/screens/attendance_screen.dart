// FILE: lib/screens/attendance_screen.dart
/// §41 — assistant attendance: check in, check out, and see the trail.
///
/// The server stores one open shift per day per assistant and computes the
/// minutes when the shift closes, so the totals here are derived from stored
/// timestamps rather than a device timer.
library;

import 'package:flutter/material.dart';

import '../core/session/app_session.dart';
import '../core/theme/role_colors.dart';
import '../services/module_api.dart';
import '../widgets/rq_async.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key, this.assistantId});

  final String? assistantId;

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  List<Map<String, dynamic>> _records = const [];
  Map<String, dynamic> _today = const {};
  double _totalHours = 0;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  String get _id => widget.assistantId ?? AppSession.id ?? '';

  bool get _isCheckedIn => (_today['status'] ?? '') == 'open';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_id.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'No assistant is signed in.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final body = await ModuleApi.attendance(_id, days: 14);
      final rows = (body['records'] as List?) ?? const [];
      final records = rows
          .whereType<Map>()
          .map((r) => r.cast<String, dynamic>())
          .toList();

      final todayKey = DateTime.now().toIso8601String().substring(0, 10);
      final todays = records.where((r) => (r['date'] ?? '') == todayKey);

      if (!mounted) return;
      setState(() {
        _records = records;
        _today = todays.isEmpty ? const {} : todays.first;
        _totalHours = (body['totalHours'] as num?)?.toDouble() ?? 0.0;
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

  Future<void> _toggle() async {
    setState(() => _busy = true);
    try {
      if (_isCheckedIn) {
        await ModuleApi.checkOut(_id);
      } else {
        await ModuleApi.checkIn(_id);
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isCheckedIn ? 'Checked out.' : 'Checked in — shift is open.',
            style: const TextStyle(inherit: true),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(rqMessage(e), style: const TextStyle(inherit: true))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _time(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return '—';
    final local = parsed.isUtc ? parsed.toLocal() : parsed;
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final checkedIn = _isCheckedIn;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance', style: TextStyle(inherit: true)),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const RqLoading(label: 'Loading attendance…')
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
                          color: RoleColors.tint(
                              checkedIn
                                  ? RoleColors.assistant
                                  : RoleColors.neutral,
                              opacity: 0.10),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: RoleColors.tint(
                                checkedIn
                                    ? RoleColors.assistant
                                    : RoleColors.neutral,
                                opacity: 0.35),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              checkedIn ? 'On shift' : 'Not on shift',
                              style: TextStyle(
                                inherit: true,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: checkedIn
                                    ? RoleColors.assistant
                                    : RoleColors.neutral,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              checkedIn
                                  ? 'Checked in at '
                                      '${_time(_today['checkInAt'] as String?)}'
                                  : 'Check in when you start, check out when '
                                      'your shift ends.',
                              style: const TextStyle(
                                  inherit: true,
                                  fontSize: 12,
                                  color: RoleColors.neutral),
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              height: 46,
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: checkedIn
                                      ? RoleColors.user
                                      : RoleColors.assistant,
                                ),
                                onPressed: _busy ? null : _toggle,
                                icon: _busy
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white))
                                    : Icon(checkedIn
                                        ? Icons.logout
                                        : Icons.login),
                                label: Text(
                                  checkedIn ? 'Check out' : 'Check in',
                                  style: const TextStyle(
                                      inherit: true,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _stat('Hours (14 days)',
                                _totalHours.toStringAsFixed(1)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _stat('Shifts', '${_records.length}'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text('Recent shifts',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(
                                  inherit: true,
                                  fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      if (_records.isEmpty)
                        const RqEmpty(
                          icon: Icons.event_available_outlined,
                          title: 'No shifts recorded',
                          message:
                              'Your check-ins appear here with their duration.',
                        )
                      else
                        ..._records.map((record) {
                          final status = (record['status'] ?? 'open') == 'open';
                          final minutes =
                              (record['minutes'] as num?)?.toInt() ?? 0;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  status
                                      ? Icons.timelapse
                                      : Icons.check_circle_outline,
                                  size: 18,
                                  color: status
                                      ? RoleColors.garage
                                      : RoleColors.assistant,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        (record['date'] ?? '').toString(),
                                        style: const TextStyle(
                                            inherit: true,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600),
                                      ),
                                      Text(
                                        '${_time(record['checkInAt'] as String?)}'
                                        ' → ${_time(record['checkOutAt'] as String?)}',
                                        style: const TextStyle(
                                            inherit: true,
                                            fontSize: 11,
                                            color: RoleColors.neutral),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  status
                                      ? 'Open'
                                      : '${(minutes / 60).toStringAsFixed(1)} h',
                                  style: TextStyle(
                                    inherit: true,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: status
                                        ? RoleColors.garage
                                        : RoleColors.assistant,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
    );
  }

  Widget _stat(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: const TextStyle(
                  inherit: true,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          Text(label,
              style: const TextStyle(
                  inherit: true, fontSize: 11, color: RoleColors.neutral)),
        ],
      ),
    );
  }
}
