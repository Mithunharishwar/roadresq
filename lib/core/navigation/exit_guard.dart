// FILE: lib/core/navigation/exit_guard.dart
//
// What a back press does at the root of a module.
//
// WHY THIS EXISTS
// ---------------
// The four dashboards are `go_router` pages, but several exits used to replace
// them with an imperative `MaterialPageRoute` (logout, emergency access). Once
// that happened the router held no pages of its own, so pressing back popped the
// last remaining route and left the Navigator with nothing to show: a black
// screen that stayed black, because there is no route left to draw or pop.
//
// Two things fix that class of bug:
//   * the exits now navigate through the router (`context.go`), so the router
//     always owns the page stack; and
//   * this guard, which makes a back press at a dashboard root an explicit
//     decision instead of a pop that could empty the stack.
//
// Behaviour: "Leave RoadResQ?" — Exit closes the app, Cancel stays. Back never
// leaves a blank screen.

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

class ExitGuard extends StatelessWidget {
  const ExitGuard({super.key, required this.child});

  final Widget child;

  Future<void> _confirmExit(BuildContext context) async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave RoadResQ?'),
        content: const Text(
          'You are signed in. Closing the app keeps your session, so you will '
          'come back to this dashboard.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Exit'),
          ),
        ],
      ),
    );

    if (leave == true) {
      // Hand the back press to Android: this is the one place where leaving the
      // app is the intended outcome, and it must not go through the Navigator.
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _confirmExit(context);
      },
      child: child,
    );
  }
}
