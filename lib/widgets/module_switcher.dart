// FILE: lib/widgets/module_switcher.dart
//
// The "Modules" sheet: jump between the four sides of the product.
//
// WHY THIS EXISTS
// ---------------
// The app restores the last signed-in role, which is right for daily use and
// wrong for showing the product: a reviewer sees only the module that was used
// last and has no obvious way to reach the other three. This sheet is that way,
// available from every module's app bar.
//
// It performs a normal login against the seeded demo accounts (see
// demo_access.dart) and then navigates. On a server without development mode it
// fails visibly instead of pretending to switch.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/router/app_router.dart';
import '../core/theme/app_theme.dart';
import '../services/demo_access.dart';
import '../services/socket_service.dart';

class ModuleSwitcher {
  static Future<void> open(BuildContext context) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final surface = AppTheme.surfaceOf(sheetContext);
        final text = AppTheme.textOf(sheetContext);
        final muted = AppTheme.mutedOf(sheetContext);

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Switch module',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'All four sides share one workflow: a request created by a '
                  'customer is picked up by the mechanic or rider and handed to '
                  'a garage.',
                  style: TextStyle(fontSize: 12.5, height: 1.4, color: muted),
                ),
                const SizedBox(height: 12),
                _row(
                  sheetContext,
                  icon: Icons.person_pin_circle_outlined,
                  color: const Color(0xFFD32F2F),
                  title: 'Customer',
                  subtitle: 'Request help, track, pay, rate',
                  route: AppRoutes.userHome,
                  value: 'user',
                  surface: surface,
                  text: text,
                  muted: muted,
                ),
                _row(
                  sheetContext,
                  icon: Icons.build_circle_outlined,
                  color: const Color(0xFF0D47A1),
                  title: 'Mechanic',
                  subtitle: 'Accept jobs, navigate, update status',
                  route: AppRoutes.mechanicHome,
                  value: 'mechanic',
                  surface: surface,
                  text: text,
                  muted: muted,
                ),
                _row(
                  sheetContext,
                  icon: Icons.two_wheeler_outlined,
                  color: const Color(0xFF2E7D32),
                  title: 'Assistant rider',
                  subtitle: 'Pick up spare parts and support the job',
                  route: AppRoutes.assistantHome,
                  value: 'assistant',
                  surface: surface,
                  text: text,
                  muted: muted,
                ),
                _row(
                  sheetContext,
                  icon: Icons.garage_outlined,
                  color: const Color(0xFF7E57C2),
                  title: 'Garage',
                  subtitle: 'Receive the vehicle, service, collect payment',
                  route: AppRoutes.garageHome,
                  value: 'garage',
                  surface: surface,
                  text: text,
                  muted: muted,
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null || !context.mounted) return;

    // Drop the previous role's live socket before switching identity, so the
    // old listener cannot refresh a screen that is no longer mounted.
    SocketService().disconnect();

    final result = switch (selected) {
      'user' => await DemoAccess.signInUser(),
      'mechanic' => await DemoAccess.signInMechanic(),
      'assistant' => await DemoAccess.signInAssistant(),
      _ => await DemoAccess.signInGarage(),
    };

    if (!context.mounted) return;

    if (!result.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not open that module: ${result.message.isEmpty ? 'unknown error' : result.message}',
          ),
        ),
      );
      return;
    }

    final route = switch (selected) {
      'user' => AppRoutes.userHome,
      'mechanic' => AppRoutes.mechanicHome,
      'assistant' => AppRoutes.assistantHome,
      _ => AppRoutes.garageHome,
    };
    context.go(route);
  }

  static Widget _row(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required String route,
    required String value,
    required Color surface,
    required Color text,
    required Color muted,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).pop(value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  height: 42,
                  width: 42,
                  decoration: BoxDecoration(
                    color: color.withAlpha((0.12 * 255).round()),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 11.5, color: muted),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
