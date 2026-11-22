import 'package:material_ui/material_ui.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/theme_controller.dart';

class ProfileScreen extends StatelessWidget {
  final String name;
  final String email;
  final String role;

  /// True when hosted as a tab: the shell already provides the title, so the
  /// screen must not add a second AppBar (it showed "Profile" twice).
  final bool embedded;

  /// Optional real values. Anything not supplied is hidden rather than replaced
  /// with a placeholder: the panel used to show a blank Email row and a
  /// hardcoded "4.8 / 5.0" rating for every mechanic, which reads as broken.
  final String phone;
  final double? rating;
  final String zone;

  /// Opens the module switcher; supplied by every shell that hosts this tab.
  final VoidCallback? onSwitchModule;

  const ProfileScreen({
    super.key,
    required this.name,
    required this.email,
    required this.role,
    this.embedded = false,
    this.phone = '',
    this.rating,
    this.zone = '',
    this.onSwitchModule,
  });

  Widget buildInfoTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.borderOf(context)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha((0.05 * 255).round()),
              blurRadius: 10),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor:
                const Color(0xFF0D47A1).withAlpha((0.12 * 255).round()),
            child: Icon(icon, color: const Color(0xFF0D47A1)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: AppTheme.mutedOf(context)),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildBadge(String title, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha((0.12 * 255).round()),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        title,
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget buildThemeTile(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance,
      builder: (context, mode, _) {
        final isDark = mode == ThemeMode.dark;
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surfaceOf(context),
            border: Border.all(color: AppTheme.borderOf(context)),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha((0.05 * 255).round()),
                blurRadius: 10,
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: AppTheme.fieldOf(context),
                child: Icon(
                  isDark ? Icons.dark_mode : Icons.light_mode,
                  color: AppTheme.textOf(context),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Appearance',
                      style: TextStyle(color: AppTheme.mutedOf(context)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isDark ? 'Dark Mode' : 'Light Mode',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: isDark,
                onChanged: (_) => ThemeController.instance.toggle(),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMechanic = role.toLowerCase().contains('mechanic');

    return Scaffold(
      backgroundColor: AppTheme.backgroundOf(context),
      appBar: embedded ? null : AppBar(
        title: const Text('Profile'),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 42,
                    backgroundColor: Colors.white,
                    child: Icon(
                      Icons.person,
                      size: 42,
                      color: Color(0xFF0D47A1),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (email.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(email, style: const TextStyle(color: Colors.white70)),
                  ],
                  const SizedBox(height: 12),
                  buildBadge(role, Colors.white),
                ],
              ),
            ),
            const SizedBox(height: 18),
            buildInfoTile(
              context: context,
              icon: Icons.badge_outlined,
              title: 'Role',
              value: role,
            ),
            if (email.trim().isNotEmpty)
              buildInfoTile(
                context: context,
                icon: Icons.mail_outline,
                title: 'Email',
                value: email,
              ),
            if (phone.trim().isNotEmpty)
              buildInfoTile(
                context: context,
                icon: Icons.phone_outlined,
                title: 'Mobile',
                value: phone,
              ),
            buildInfoTile(
              context: context,
              icon: Icons.person_outline,
              title: 'Full Name',
              value: name,
            ),
            if (isMechanic) ...[
              buildInfoTile(
                context: context,
                icon: Icons.verified_outlined,
                title: 'Partner Status',
                value: 'Verified Mechanic Partner',
              ),
              if (zone.trim().isNotEmpty)
                buildInfoTile(
                  context: context,
                  icon: Icons.location_on_outlined,
                  title: 'Service Zone',
                  value: zone,
                ),
              if (rating != null)
                buildInfoTile(
                  context: context,
                  icon: Icons.star_outline,
                  title: 'Captain Rating',
                  value: '${rating!.toStringAsFixed(1)} / 5.0',
                ),
            ],
            const SizedBox(height: 6),
            if (onSwitchModule != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  color: AppTheme.surfaceOf(context),
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: onSwitchModule,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppTheme.borderOf(context)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            height: 42,
                            width: 42,
                            decoration: BoxDecoration(
                              color: const Color(0xFFD32F2F)
                                  .withAlpha((0.12 * 255).round()),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.grid_view_rounded,
                                color: Color(0xFFD32F2F), size: 20),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Switch module',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textOf(context),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Customer · Mechanic · Rider · Garage',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: AppTheme.mutedOf(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right,
                              color: AppTheme.mutedOf(context)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            buildThemeTile(context),
            // Accessibility / about
            buildInfoTile(
              context: context,
              icon: Icons.info_outline,
              title: 'Version',
              value: 'RoadResQ 1.0.0',
            ),
          ],
        ),
      ),
    );
  }
}
