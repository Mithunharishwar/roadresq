// FILE: lib/screens/recent_activity_screen.dart
//
// The user's recent rescue activity, read from ActivityService.
//
// This screen used to show three hardcoded sample entries ("Tire Puncture /
// Anna Nagar, Chennai / July 10, 2026" and so on) with the comment "This is a
// placeholder list for demonstration". Every user saw the same invented
// history, including dates that had not happened yet. It now reads the real
// local activity log that ActivityService writes as requests progress.

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

import '../core/request_status.dart';
import '../core/session/app_session.dart';
import '../services/activity_service.dart';
import '../services/api_service.dart';

class RecentActivityScreen extends StatefulWidget {
  const RecentActivityScreen({super.key});

  @override
  State<RecentActivityScreen> createState() => _RecentActivityScreenState();
}

class _RecentActivityScreenState extends State<RecentActivityScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _activities = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    var items =
        await ActivityService.getActivities(ActivityService.userActivityKey);

    // The local log only knows about actions taken *on this device*. A rescue
    // fulfilled by a mechanic or a garage leaves no local write, so a customer
    // with a completed, paid job still saw "No recent activity yet". The
    // request record is the source of truth, so it fills the list whenever the
    // local log is thin.
    // Prefer the server's request history. The local log fills with
    // "Tracking Started" repeats that pushed the actual jobs off the screen.
    if (true) {
      try {
        final phone = AppSession.phone ?? '';
        final requests = await ApiService.fetchUserRequests(phone);
        final fromServer = requests
            .cast<Map<String, dynamic>>()
            .map((r) => <String, dynamic>{
                  'title':
                      '${r['issue'] ?? 'Rescue'} · ${r['vehicle'] ?? ''}'.trim(),
                  'subtitle': [
                    RequestStatusInfo.label(
                        (r['status'] ?? '').toString()),
                    (r['locationText'] ?? '').toString(),
                  ].where((part) => part.trim().isNotEmpty).join(' · '),
                  'time': (r['updatedAt'] ?? r['createdAt'] ?? '').toString(),
                })
            .toList();
        if (fromServer.isNotEmpty) items = fromServer;
        // Local entries only matter when the server has nothing to say.
        else if (items.isNotEmpty) items = items;
      } catch (e) {
        debugPrint('RecentActivityScreen: could not load server history: $e');
      }
    }

    if (!mounted) return;
    setState(() {
      _activities = items;
      _loading = false;
    });
  }

  /// ActivityService stores an ISO-8601 timestamp; render it locally and
  /// briefly. Returns null when absent or unparseable.
  static String? _formatTime(dynamic raw) {
    final text = raw?.toString();
    if (text == null || text.isEmpty) return null;
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return null;
    final local = parsed.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Recent Activity'),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_activities.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.history, size: 48, color: Colors.black26),
              const SizedBox(height: 16),
              Text(
                'No recent activity yet.',
                style: TextStyle(fontSize: 16, color: AppTheme.mutedOf(context)),
              ),
              const SizedBox(height: 10),
              Text(
                'Your rescue requests and their status changes will be listed '
                'here as they happen.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.black38),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _activities.length,
        itemBuilder: (context, index) {
          final activity = _activities[index];
          final title = (activity['title'] ?? 'Activity').toString();
          final subtitle = (activity['subtitle'] ?? '').toString();
          final time = _formatTime(activity['time']);

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              leading: CircleAvatar(
                backgroundColor: const Color(0xFF0D47A1)
                    .withAlpha((0.1 * 255).round()),
                child: const Icon(Icons.local_shipping,
                    color: Color(0xFF0D47A1)),
              ),
              title: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                subtitle.isEmpty
                    ? (time ?? '')
                    : (time == null ? subtitle : '$subtitle\n$time'),
                style: TextStyle(color: AppTheme.mutedOf(context), height: 1.4),
              ),
              isThreeLine: subtitle.isNotEmpty && time != null,
            ),
          );
        },
      ),
    );
  }
}
