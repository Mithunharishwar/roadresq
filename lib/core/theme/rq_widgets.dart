import 'package:material_ui/material_ui.dart';

import 'app_theme.dart';

/// A collection of reusable, polished UI primitives used across the
/// RoadResQ home screens to give the app a vibrant, modern look.
class RQ {
  RQ._();

  /// Common brand colors.
  static const Color red = Color(0xFFD32F2F);
  static const Color orange = Color(0xFFFF7043);
  static const Color blue = Color(0xFF0D47A1);
  static const Color green = Color(0xFF2E7D32);
  static const Color teal = Color(0xFF00897B);
  static const Color purple = Color(0xFF7B1FA2);

  /// A rounded, gradient header card used at the top of home screens.
  static Widget gradientHeader({
    required BuildContext context,
    required List<Color> colors,
    required Widget child,
    double radius = 32,
    EdgeInsets padding = const EdgeInsets.fromLTRB(22, 28, 22, 28),
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(radius)),
      ),
      child: child,
    );
  }

  /// Section title with a leading icon.
  static Widget sectionTitle(String title, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: color.withAlpha((0.12 * 255).round()),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppTheme.textDynamic,
          ),
        ),
      ],
    );
  }

  /// A stat tile card used in dashboard rows.
  static Widget statCard({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
    double? flexValue,
  }) {
    return Expanded(
      flex: flexValue?.toInt() ?? 1,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceDynamic,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha((0.06 * 255).round()),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withAlpha((0.12 * 255).round()),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.mutedDynamic,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A quick-action button (icon + label) used in grids.
  static Widget quickAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceDynamic,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha((0.05 * 255).round()),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color, color.withAlpha((0.7 * 255).round())],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.textDynamic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// An info row with icon + title + value.
  static Widget infoRow(IconData icon, String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.black54),
          const SizedBox(width: 8),
          Text(
            '$title: ',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.black87)),
          ),
        ],
      ),
    );
  }

  /// A status pill chip.
  static Widget statusPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  /// Empty-state card.
  static Widget emptyCard(String message,
      {IconData icon = Icons.inbox_outlined}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDynamic,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.black26, size: 34),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }

  /// ─────────────────────────────────────────────────────────────
  /// Clean role dashboard header.
  ///
  /// A simple, professional, flat gradient header — no glow blobs, no
  /// firework bursts. Keeps headings **linear, light & presentable**:
  /// an icon emblem, a stacked title/subtitle, and an optional trailing
  /// widgets row. [title] / [subtitle] are the linear heading.
  /// [trailing] is a row placed to the right of the emblem (e.g. notifications
  /// bell + online toggle). [child] is optional extra content below the heading
  /// (e.g. earnings strip / zone bar) that stays inside the header.
  static Widget moduleHeader({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> colors,
    Color glow = const Color(0xFFD32F2F),
    Widget? trailing,
    Widget? child,
    double radius = 34,
  }) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(radius)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 28, 22, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Emblem
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha((0.22 * 255).round()),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                // Linear heading
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing,
                ],
              ],
            ),
            if (child != null) ...[
              const SizedBox(height: 18),
              child,
            ],
          ],
        ),
      ),
    );
  }
}
