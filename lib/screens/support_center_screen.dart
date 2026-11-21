// FILE: lib/screens/support_center_screen.dart
/// §49 — help centre with real FAQ content and a working support call.
///
/// Every tile used to show a "… clicked" snackbar. Now:
///   * Emergency contact dials the support number;
///   * FAQs expand to answers that describe this build's actual behaviour;
///   * Feedback opens the complaint form that stores a trackable ticket.
library;

import 'package:flutter/material.dart';

import 'package:url_launcher/url_launcher.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/role_colors.dart';
import 'feedback_screen.dart';

class SupportCenterScreen extends StatelessWidget {
  const SupportCenterScreen({
    super.key,
    required this.isMechanic,
    this.embedded = false,
  });

  /// See MyRequestsScreen.embedded — same duplicate-header bug.
  final bool embedded;

  final bool isMechanic;

  static const List<(String, String)> _faqs = <(String, String)>[
    (
      'How long does a rescue take?',
      'The app shows an ETA as soon as a crew accepts. It is calculated from '
          'the straight-line distance at an assumed average speed, so traffic '
          'can change it. The live map is the accurate signal.',
    ),
    (
      'What if no mechanic accepts my request?',
      'The backend watches every open request. If nobody accepts inside the '
          'escalation window (5 minutes by default) the request is escalated '
          'and the search widens to a larger radius automatically.',
    ),
    (
      'How do I confirm the crew actually arrived?',
      'Ask for their 6-digit arrival code and enter it on the job screen. The '
          'server checks it against the job and marks the arrival time. The '
          'code cannot be reused.',
    ),
    (
      'When can I rate a rescue?',
      'After the payment is marked complete. The rating then appears on the '
          'mechanic\'s public rating and counts toward dispatch priority.',
    ),
    (
      'How are payments handled?',
      'Cash and UPI are recorded against the job. Card payments go through '
          'Razorpay when server credentials are configured; without them the '
          'server flags the order as simulated instead of pretending it was '
          'charged.',
    ),
    (
      'Is my location shared all the time?',
      'No. Location is read only while you request a rescue or track one, and '
          'a crew position is visible only to the customer of the job they are '
          'attending.',
    ),
    (
      'How do I change my phone number?',
      'Open Profile (or Settings) from the bottom bar. Mechanic and assistant '
          'profiles are editable; customer details are set at signup and can be '
          'changed by support.',
    ),
  ];

  Future<void> _call(BuildContext context) async {
    final uri = Uri.parse('tel:${AppConstants.supportPhone}');
    if (await launchUrl(uri)) return;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Could not start a call. Support: ${AppConstants.supportPhone}',
          style: const TextStyle(inherit: true),
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle, {
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha((0.05 * 255).round()),
            blurRadius: 10,
          ),
        ],
      ),
      child: ListTile(
        leading: Icon(icon, color: RoleColors.user),
        title: Text(title, style: const TextStyle(inherit: true)),
        subtitle: Text(subtitle, style: const TextStyle(inherit: true)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roleTitle =
        isMechanic ? 'Mechanic Support' : 'Customer Support';

    return Scaffold(
      appBar: embedded ? null : AppBar(
        title: Text(roleTitle, style: const TextStyle(inherit: true)),
        backgroundColor: RoleColors.user,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _tile(
            context,
            Icons.support_agent,
            'Call RoadResQ support',
            'Talk to a person about an active job',
            onTap: () => _call(context),
          ),
          _tile(
            context,
            Icons.phone_in_talk,
            'Emergency: 112',
            'Police, fire and ambulance (India)',
            onTap: () async {
              final uri = Uri.parse('tel:112');
              if (!await launchUrl(uri) && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Could not open the dialler. Call 112.',
                        style: TextStyle(inherit: true)),
                  ),
                );
              }
            },
          ),
          _tile(
            context,
            Icons.feedback_outlined,
            'Send feedback or a complaint',
            'Tracked ticket with a status trail',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FeedbackScreen()),
            ),
          ),
          _tile(
            context,
            Icons.mail_outline,
            'Email us',
            AppConstants.supportEmail,
            onTap: () async {
              final uri = Uri(
                scheme: 'mailto',
                path: AppConstants.supportEmail,
                query: 'subject=RoadResQ support',
              );
              if (!await launchUrl(uri) && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'No mail app found. Write to '
                      '${AppConstants.supportEmail}',
                      style: const TextStyle(inherit: true),
                    ),
                  ),
                );
              }
            },
          ),
          const SizedBox(height: 10),
          Text(
            'Frequently asked',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(inherit: true, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ..._faqs.map(
            (faq) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ExpansionTile(
                title: Text(
                  faq.$1,
                  style: const TextStyle(
                      inherit: true, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                childrenPadding:
                    const EdgeInsets.fromLTRB(16, 0, 16, 14),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    faq.$2,
                    style: const TextStyle(
                        inherit: true,
                        fontSize: 12,
                        height: 1.5,
                        color: RoleColors.neutral),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              '${AppConstants.appName} v${AppConstants.appVersion}',
              style: const TextStyle(
                  inherit: true, fontSize: 10, color: RoleColors.neutral),
            ),
          ),
        ],
      ),
    );
  }
}
