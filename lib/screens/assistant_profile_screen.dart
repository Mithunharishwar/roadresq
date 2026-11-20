// FILE: lib/screens/assistant_profile_screen.dart
/// §37 — assistant profile, including the mechanic they are working with.
///
/// `GET /api/assistant/<id>/profile` joins the most recent assigned job so the
/// assigned mechanic is a real stored link, not a hardcoded label.
library;

import 'package:flutter/material.dart';

import '../core/session/app_session.dart';
import '../core/theme/role_colors.dart';
import '../services/module_api.dart';
import '../widgets/rq_async.dart';
import 'attendance_screen.dart';
import 'earnings_screen.dart';
import 'settings_screen.dart';

class AssistantProfileScreen extends StatefulWidget {
  const AssistantProfileScreen({
    super.key,
    this.assistantId,
    this.assistantName,
    this.assistantEmail,
  });

  final String? assistantId;
  final String? assistantName;
  final String? assistantEmail;

  @override
  State<AssistantProfileScreen> createState() =>
      _AssistantProfileScreenState();
}

class _AssistantProfileScreenState extends State<AssistantProfileScreen> {
  Map<String, dynamic> _profile = const {};
  bool _loading = true;
  String? _error;

  String get _id => widget.assistantId ?? AppSession.id ?? '';

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
    try {
      final profile = await ModuleApi.assistantProfile(_id);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = rqMessage(e);
      });
    }
  }

  void _open(Widget screen) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.assistantName ??
            _profile['name']?.toString() ??
            AppSession.name ??
            'Assistant')
        .toString();
    final mechanicName =
        (_profile['assignedMechanicName'] ?? '').toString();
    final currentJob = (_profile['currentJobId'] ?? '').toString();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Assistant profile',
            style: TextStyle(inherit: true)),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const RqLoading(label: 'Loading profile…')
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                RqHeaderCard(
                  name: name,
                  role: 'Assistant crew',
                  color: RoleColors.assistant,
                  id: _id,
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  RqError(message: _error!, onRetry: _load)
                else ...[
                  RqCard(
                    child: Column(
                      children: [
                        RqDetailRow(
                          label: 'Phone',
                          value: (_profile['phone'] ?? '').toString(),
                          icon: Icons.phone_outlined,
                        ),
                        RqDetailRow(
                          label: 'Email',
                          value: (widget.assistantEmail ??
                                  (_profile['email'] ?? ''))
                              .toString(),
                          icon: Icons.mail_outline,
                        ),
                        RqDetailRow(
                          label: 'On duty',
                          value: _profile['online'] == true ? 'Yes' : 'No',
                          icon: Icons.circle,
                          valueColor: _profile['online'] == true
                              ? RoleColors.assistant
                              : RoleColors.neutral,
                        ),
                        RqDetailRow(
                          label: 'Assigned mechanic',
                          value: mechanicName.isEmpty
                              ? 'Not assigned to a job yet'
                              : mechanicName,
                          icon: Icons.handyman_outlined,
                        ),
                        RqDetailRow(
                          label: 'Current job',
                          value: currentJob.isEmpty ? 'None' : currentJob,
                          icon: Icons.assignment_outlined,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  RqCard(
                    child: Column(
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.login),
                          title: const Text('Attendance',
                              style: TextStyle(inherit: true)),
                          subtitle: const Text('Check in / check out',
                              style: TextStyle(
                                  inherit: true,
                                  fontSize: 11,
                                  color: RoleColors.neutral)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () =>
                              _open(AttendanceScreen(assistantId: _id)),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.account_balance_wallet_outlined),
                          title: const Text('Earnings & incentives',
                              style: TextStyle(inherit: true)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _open(const EarningsScreen(
                              audience: EarningsAudience.assistant)),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.settings_outlined),
                          title: const Text('Settings',
                              style: TextStyle(inherit: true)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _open(const SettingsScreen()),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Your assigned mechanic comes from the job records. It '
                    'changes automatically when a dispatcher pairs you with '
                    'another mechanic.',
                    style: TextStyle(
                        inherit: true,
                        fontSize: 11,
                        color: RoleColors.neutral,
                        height: 1.4),
                  ),
                ],
              ],
            ),
    );
  }
}
