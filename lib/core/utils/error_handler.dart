import 'package:material_ui/material_ui.dart';

import '../config/app_config.dart';

/// Centralized Error Handler for RoadResQ
/// Provides user-friendly error messages and fallback actions.
class ErrorHandler {
  ErrorHandler._();

  /// True when [error] means "the request never reached a server" rather than
  /// "the server said no".
  ///
  /// The distinction matters on the login screens: a `TimeoutException` used to
  /// be reported as "Invalid OTP" / "Invalid email or password", which sent
  /// people looking at their input instead of at the unreachable backend.
  static bool isTransportFailure(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    return errorStr.contains('timeout') ||
        errorStr.contains('timed out') ||
        errorStr.contains('socketexception') ||
        errorStr.contains('connection refused') ||
        errorStr.contains('failed host lookup') ||
        errorStr.contains('network is unreachable') ||
        errorStr.contains('connection reset');
  }

  /// Turns a dead endpoint into the next action to take.
  ///
  /// A bare "request timed out" is what made this failure so expensive to
  /// diagnose: the same opaque message appeared on every field of every screen
  /// while the real problem was a stale LAN address. Naming the address — and
  /// the boot-time probe result when there is one — turns it into something
  /// fixable from the phone.
  static String _transportHint() {
    final notice = AppConfig.startupNotice;
    if (notice != null) return notice;
    if (AppConfig.isUnconfiguredEmulatorDefault) {
      return 'This build has no server address configured, so it is trying the '
          'Android emulator alias ${AppConfig.androidEmulatorHost}, which does '
          'not exist on a real phone.';
    }
    return 'Check that the backend is running and that this phone is on the '
        'same Wi-Fi as the computer.';
  }

  /// Returns a user-friendly message for common error types.
  static String getFriendlyMessage(dynamic error) {
    final errorStr = error.toString().toLowerCase();

    if (errorStr.contains('socketexception') ||
        errorStr.contains('connection refused') ||
        errorStr.contains('failed host lookup') ||
        errorStr.contains('network')) {
      return 'Cannot reach the RoadResQ server at ${AppConfig.host}. '
          '${_transportHint()}';
    }

    if (errorStr.contains('timeout')) {
      return 'The RoadResQ server at ${AppConfig.host} did not answer in time. '
          '${_transportHint()}';
    }

    if (errorStr.contains('permission') && errorStr.contains('denied')) {
      return 'Permission denied. Please grant the required permissions in Settings.';
    }

    if (errorStr.contains('location') && errorStr.contains('disabled')) {
      return 'Location services are disabled. Please enable GPS.';
    }

    if (errorStr.contains('not found') || errorStr.contains('404')) {
      return 'The requested resource was not found.';
    }

    if (errorStr.contains('unauthorized') || errorStr.contains('401')) {
      return 'Session expired. Please login again.';
    }

    if (errorStr.contains('firebase') && errorStr.contains('invalid')) {
      return 'Invalid credentials. Please check your input.';
    }

    if (errorStr.contains('no crew') || errorStr.contains('no mechanic')) {
      return 'No available crew found nearby. We\'ve notified admin for manual dispatch.';
    }

    // A rejected login must say WHY. The backend answers "Invalid OTP" and the
    // screen used to replace that with "Something went wrong" — the user then
    // retypes a correct code and still cannot tell what is wrong.
    if (errorStr.contains('invalid otp') || errorStr.contains('otp')) {
      return 'That OTP is not correct. Check the code and try again.';
    }

    final serverMessage = _serverMessage(error);
    if (serverMessage != null) return serverMessage;

    if (errorStr.contains('payment') || errorStr.contains('razorpay')) {
      return 'Payment failed. Please try again or use a different method.';
    }

    // Default fallback
    return 'Something went wrong. Please try again later.';
  }

  /// The server's own explanation, when the exception carries one.
  ///
  /// ApiService builds errors as `Exception('<operation> failed: <server msg>')`,
  /// so the useful half is after the first ':'.
  static String? _serverMessage(dynamic error) {
    var text = error.toString();
    if (text.startsWith('Exception: ')) {
      text = text.substring('Exception: '.length);
    }
    final idx = text.indexOf(': ');
    if (idx == -1 || idx + 2 >= text.length) return null;
    final tail = text.substring(idx + 2).trim();
    if (tail.isEmpty || tail.length > 160) return null;
    return tail;
  }

  /// Shows a user-friendly SnackBar for an error.
  static void showSnackBar(BuildContext context, dynamic error) {
    final message = getFriendlyMessage(error);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: () {},
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Shows an error dialog for critical failures.
  static Future<void> showErrorDialog(
    BuildContext context,
    dynamic error, {
    String? title,
    VoidCallback? onRetry,
  }) {
    final ctx = context;
    return showDialog<void>(
      context: ctx,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 8),
            Text(title ?? 'Error'),
          ],
        ),
        content: Text(getFriendlyMessage(error)),
        actions: [
          if (onRetry != null)
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                onRetry();
              },
              child: const Text('Retry'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
