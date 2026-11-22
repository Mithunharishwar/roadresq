// FILE: lib/widgets/rq_async.dart
/// Shared loading / empty / error widgets.
///
/// Every screen used to draw its own bare `CircularProgressIndicator` and, on
/// failure, print a raw exception. These widgets give one consistent answer to
/// "nothing yet", "that failed" and "loading", including a Retry button so a
/// timeout never leaves a dead screen.
library;

import 'package:material_ui/material_ui.dart';

import '../core/theme/role_colors.dart';

/// Centred spinner with an optional label.
class RqLoading extends StatelessWidget {
  const RqLoading({super.key, this.label, this.color});

  final String? label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: color ?? Theme.of(context).colorScheme.primary,
              ),
            ),
            if (label != null) ...[
              const SizedBox(height: 14),
              Text(
                label!,
                style: TextStyle(
                  inherit: true,
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Friendly empty state. Never an empty `Container()`.
class RqEmpty extends StatelessWidget {
  const RqEmpty({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: RoleColors.neutral),
            const SizedBox(height: 12),
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(inherit: true),
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                style: theme.textTheme.bodySmall?.copyWith(
                  inherit: true,
                  color: RoleColors.neutral,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(actionLabel!,
                    style: const TextStyle(inherit: true)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Error state with the server's own message and a Retry button.
class RqError extends StatelessWidget {
  const RqError({
    super.key,
    required this.message,
    this.onRetry,
    this.title = 'Could not load this',
  });

  final String message;
  final VoidCallback? onRetry;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 42, color: RoleColors.user),
            const SizedBox(height: 12),
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(inherit: true),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                inherit: true,
                color: RoleColors.neutral,
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Try again',
                    style: TextStyle(inherit: true)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One place to convert any thrown object into copy a user can act on.
String rqMessage(Object error) {
  final text = error.toString();
  if (text.startsWith('ModuleFailure: ')) {
    return text.replaceFirst('ModuleFailure: ', '');
  }
  if (text.contains('TimeoutException')) {
    return 'The server took too long to answer. Check the backend and retry.';
  }
  if (text.contains('SocketException') ||
      text.contains('ClientException') ||
      text.contains('Failed host lookup')) {
    return 'No connection to the RoadResQ server. Check the backend address '
        'on the login screen.';
  }
  return text.replaceFirst('Exception: ', '');
}

/// A section card used by the detail screens. Keeps spacing consistent.
class RqCard extends StatelessWidget {
  const RqCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(14);
    return Material(
      color: color ?? Theme.of(context).cardColor,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Small labelled value row — used across profile, job detail and invoices.
class RqDetailRow extends StatelessWidget {
  const RqDetailRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.valueColor,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: RoleColors.neutral),
            const SizedBox(width: 8),
          ],
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(inherit: true, color: RoleColors.neutral),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: theme.textTheme.bodyMedium?.copyWith(
                inherit: true,
                color: valueColor ??
                    Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
