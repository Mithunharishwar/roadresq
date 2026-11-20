// FILE: lib/screens/settings_screen.dart
/// §54 — settings: language, appearance, notifications, privacy, support.
///
/// Everything on this screen is backed by a persisted preference. The theme
/// switch drives [ThemeController]; the language choice drives
/// [RqLocale] and therefore `MaterialApp.locale`; the notification switch is
/// read by [NotificationService.push] before anything is stored.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/config/app_config.dart';
import '../core/constants/app_constants.dart';
import '../core/i18n/rq_strings.dart';
import '../core/session/app_session.dart';
import '../core/theme/role_colors.dart';
import '../core/theme/theme_controller.dart';
import '../services/notification_service.dart';
import '../services/session_service.dart';
import '../services/socket_service.dart';
import 'feedback_screen.dart';
import 'privacy_policy_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.showLogout = true});

  /// Hidden on the admin console, which has no customer session to clear.
  final bool showLogout;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _loadingPrefs = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final enabled = await NotificationService.isEnabled();
    if (!mounted) return;
    setState(() {
      _notificationsEnabled = enabled;
      _loadingPrefs = false;
    });
  }

  Future<void> _setNotifications(bool value) async {
    setState(() => _notificationsEnabled = value);
    await NotificationService.setEnabled(value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value
              ? 'Notifications are on.'
              : 'Notifications are off. Job updates still appear on the job '
                  'screen.',
          style: const TextStyle(inherit: true),
        ),
      ),
    );
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?', style: TextStyle(inherit: true)),
        content: const Text(
          'This clears the session stored on this device. You will need your '
          'password or OTP to sign in again.',
          style: TextStyle(inherit: true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay signed in',
                style: TextStyle(inherit: true)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Log out', style: TextStyle(inherit: true)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await AppSession.clear();
    await SessionService.clear();
    SocketService().disconnect();
    if (!mounted) return;
    context.go('/role-select');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roleColor = RoleColors.forRole(AppSession.role);

    return Scaffold(
      appBar: AppBar(
        title: Text(RqStrings.of('settings'),
            style: const TextStyle(inherit: true)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Identity ──────────────────────────────────────────────────
          RqHeaderCard(
            name: AppSession.name ?? 'Guest',
            role: RoleColors.labelForRole(AppSession.role),
            color: roleColor,
            id: AppSession.id ?? '',
          ),
          const SizedBox(height: 18),

          // ── Language ─────────────────────────────────────────────────
          _sectionTitle(context, RqStrings.of('language')),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: RqLocale.names.entries.map((entry) {
                final selected = RqLocale.code == entry.key;
                return RadioListTile<String>(
                  value: entry.key,
                  // ignore: deprecated_member_use
                  groupValue: RqLocale.code,
                  // ignore: deprecated_member_use
                  onChanged: (value) async {
                    if (value == null) return;
                    await RqLocale.set(value);
                    setState(() {});
                  },
                  title: Text(entry.value,
                      style: const TextStyle(inherit: true)),
                  subtitle: selected
                      ? Text(
                          'Active — shell labels update immediately',
                          style: theme.textTheme.bodySmall?.copyWith(
                              inherit: true, color: RoleColors.neutral),
                        )
                      : null,
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Translated: navigation and settings labels. Feature screens '
              'remain in English in this build.',
              style: TextStyle(
                  inherit: true, fontSize: 11, color: RoleColors.neutral),
            ),
          ),
          const SizedBox(height: 18),

          // ── Appearance ───────────────────────────────────────────────
          _sectionTitle(context, RqStrings.of('appearance')),
          Card(
            margin: EdgeInsets.zero,
            child: ValueListenableBuilder<ThemeMode>(
              valueListenable: ThemeController.instance,
              builder: (context, mode, _) {
                return Column(
                  children: [
                    SwitchListTile(
                      value: mode == ThemeMode.dark,
                      onChanged: (_) => ThemeController.instance.toggle(),
                      secondary: const Icon(Icons.dark_mode_outlined),
                      title: Text(RqStrings.of('dark_mode'),
                          style: const TextStyle(inherit: true)),
                    ),
                    ListTile(
                      leading: const Icon(Icons.brightness_auto_outlined),
                      title: const Text('Follow system theme',
                          style: TextStyle(inherit: true)),
                      trailing: Switch(
                        value: mode == ThemeMode.system,
                        onChanged: (on) => ThemeController.instance.setMode(
                            on ? ThemeMode.system : ThemeMode.light),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 18),

          // ── Notifications ────────────────────────────────────────────
          _sectionTitle(context, RqStrings.of('notifications')),
          Card(
            margin: EdgeInsets.zero,
            child: SwitchListTile(
              value: _notificationsEnabled,
              onChanged: _loadingPrefs ? null : _setNotifications,
              secondary: const Icon(Icons.notifications_active_outlined),
              title: Text(RqStrings.of('notifications'),
                  style: const TextStyle(inherit: true)),
              subtitle: Text(
                'In-app alerts for new requests and status changes',
                style: theme.textTheme.bodySmall
                    ?.copyWith(inherit: true, color: RoleColors.neutral),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // ── Privacy & support ────────────────────────────────────────
          _sectionTitle(context, 'Privacy & support'),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: Text(RqStrings.of('privacy'),
                      style: const TextStyle(inherit: true)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const PrivacyPolicyScreen()),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.feedback_outlined),
                  title: const Text('Feedback & complaints',
                      style: TextStyle(inherit: true)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FeedbackScreen()),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('About this build',
                      style: TextStyle(inherit: true)),
                  subtitle: Text(
                    'v${AppConstants.appVersion} · ${AppConfig.host}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(inherit: true, color: RoleColors.neutral),
                  ),
                ),
              ],
            ),
          ),

          if (widget.showLogout) ...[
            const SizedBox(height: 24),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: RoleColors.user,
                  side: const BorderSide(color: RoleColors.user),
                ),
                onPressed: _logout,
                icon: const Icon(Icons.logout, size: 18),
                label: Text(RqStrings.of('logout'),
                    style: const TextStyle(
                        inherit: true, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Center(
            child: Text(
              AppConstants.companyName,
              style: const TextStyle(
                  inherit: true, fontSize: 10, color: RoleColors.neutral),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                inherit: true,
                fontWeight: FontWeight.w700,
                color: RoleColors.neutral,
              ),
        ),
      );
}

/// Compact identity header reused by settings and profile screens.
class RqHeaderCard extends StatelessWidget {
  const RqHeaderCard({
    super.key,
    required this.name,
    required this.role,
    required this.color,
    this.id = '',
  });

  final String name;
  final String role;
  final Color color;
  final String id;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RoleColors.tint(color, opacity: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RoleColors.tint(color, opacity: 0.3)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: RoleColors.tint(color, opacity: 0.2),
            child: Text(
              name.isEmpty ? '?' : name.characters.first.toUpperCase(),
              style: TextStyle(
                inherit: true,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                      inherit: true,
                      fontSize: 16,
                      fontWeight: FontWeight.w700),
                ),
                Text(
                  role,
                  style: TextStyle(
                      inherit: true, fontSize: 12, color: color),
                ),
                if (id.isNotEmpty)
                  Text(
                    'ID ${id.length > 10 ? id.substring(id.length - 10) : id}',
                    style: const TextStyle(
                        inherit: true,
                        fontSize: 10,
                        color: RoleColors.neutral),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
