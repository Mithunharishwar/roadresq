// FILE: lib/screens/privacy_policy_screen.dart
/// §54 — privacy policy, written to describe what this app actually stores.
library;

import 'package:flutter/material.dart';

import '../core/theme/role_colors.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const List<(String, String)> _sections = <(String, String)>[
    (
      'What we store on your device',
      'Your sign-in role and identifier, the last rescue request id, your theme '
          'and language choice, and your local notification preference. None of '
          'this leaves the device except the role and identifier sent with a '
          'request you make yourself.',
    ),
    (
      'What the server stores',
      'Account name, phone and email; the rescue requests you create (issue, '
          'location, status history); job chat messages; attendance records for '
          'assistants; ratings you submit; and documents a mechanic uploads for '
          'verification. Passwords are stored as one-way hashes, never as text.',
    ),
    (
      'Location',
      'Location is read only while you are requesting a rescue or tracking one. '
          'A crew member\'s position is published to the customer of the job they '
          'are attending. There is no background location collection when the app '
          'is closed.',
    ),
    (
      'Who can see your data',
      'The customer of a job sees the assigned crew\'s name, phone and live '
          'position. Crew see the customer\'s name, phone and pickup location. '
          'The admin console sees aggregate counts and job records for support '
          'and verification.',
    ),
    (
      'Your controls',
      'You can log out at any time, which clears the stored session on this '
          'device. You can request deletion of your account data by contacting '
          'support. Uploaded documents can be replaced from the Documents screen.',
    ),
    (
      'Third parties',
      'Maps are rendered by Google Maps. Payments are processed by Razorpay when '
          'credentials are configured. RoadResQ does not sell data and does not '
          'send your contact details to advertisers.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy policy', style: TextStyle(inherit: true)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'RoadResQ privacy policy',
            style: theme.textTheme.titleMedium
                ?.copyWith(inherit: true, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'This describes the behaviour of the code in this build. It is not '
            'a substitute for legal review before a public launch.',
            style: TextStyle(
                inherit: true, fontSize: 12, color: RoleColors.neutral),
          ),
          const SizedBox(height: 18),
          for (final section in _sections) ...[
            Text(
              section.$1,
              style: theme.textTheme.titleSmall
                  ?.copyWith(inherit: true, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              section.$2,
              style: theme.textTheme.bodySmall?.copyWith(
                inherit: true,
                height: 1.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
          ],
          const Divider(),
          const SizedBox(height: 8),
          const Text(
            'Contact: support@roadresq.com',
            style: TextStyle(inherit: true, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
