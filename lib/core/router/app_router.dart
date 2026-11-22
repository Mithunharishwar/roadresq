// FILE: lib/core/router/app_router.dart
/// §8 — the application navigation table, wired into `main.dart` through
/// `MaterialApp.router`.
///
/// Two rules shaped this file:
///
///  * Every route points at a screen that is actually part of the running app.
///    The previous table pointed only at `features/**`, which nothing else
///    imported, so the entire router was dead code while `main.dart` used
///    `MaterialApp(home:)`.
///  * Routes that need an identity rebuild it from [AppSession] instead of
///    accepting arguments from a URL. A deep link therefore cannot claim to be
///    a different user, and a cold start after a killed process still lands on
///    the right dashboard.
///
/// Deep screens that already exist (job tracking, payment) are still opened
/// with their typed constructors at the call site; they carry live objects that
/// do not belong in a URL. The entry chain — splash → onboarding → role →
/// login → dashboard — plus every screen added in this pass is on the router.
library;

import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../../screens/garage_main_screen.dart';
import '../../pages/assistant_login_page.dart';
import '../../pages/garage_login_page.dart';
import '../../pages/mechanic_login_page.dart';
import '../../pages/user_login_page.dart';
import '../../screens/admin_login_page.dart';
import '../../screens/arrival_token_screen.dart';
import '../../screens/assistant_main_screen.dart';
import '../../screens/assistant_profile_screen.dart';
import '../../screens/attendance_screen.dart';
import '../../screens/chat_screen.dart';
import '../../screens/earnings_screen.dart';
import '../../screens/feedback_screen.dart';
import '../../screens/mechanic_documents_screen.dart';
import '../../screens/mechanic_main_screen.dart';
import '../../screens/mechanic_profile_edit_screen.dart';
import '../../screens/mechanic_ratings_screen.dart';
import '../../screens/nearby_mechanics_screen.dart';
import '../../screens/onboarding_screen.dart';
import '../../screens/privacy_policy_screen.dart';
import '../../screens/role_selection_screen.dart';
import '../../screens/settings_screen.dart';
import '../../screens/splash_screen.dart';
import '../../screens/user_main_screen.dart';
import '../../screens/user_home_screen.dart';
import '../session/app_session.dart';

class AppRoutes {
  AppRoutes._();

  static const String splash = '/splash';
  static const String onboarding = '/onboarding';
  static const String roleSelect = '/role-select';
  static const String userHome = '/user-home';
  static const String mechanicHome = '/mechanic-home';
  static const String assistantHome = '/assistant-home';
  static const String garageHome = '/garage-home';
  static const String admin = '/admin';
  static const String settings = '/settings';
  static const String nearbyMechanics = '/nearby-mechanics';
  static const String feedback = '/feedback';
  static const String privacy = '/privacy';
  static const String attendance = '/attendance';
  static const String mechanicProfile = '/mechanic-profile';
  static const String assistantProfile = '/assistant-profile';
  static const String documents = '/documents';
  static const String ratings = '/ratings';

  /// `/login/<role>` — one route, four login surfaces.
  static String login(String role) => '/login/$role';
}

/// Redirect helper: a dashboard requires a saved identity for that role.
String? _requireRole(String role, String fallback) {
  if (!AppSession.isSignedIn) return fallback;
  if ((AppSession.role ?? '') != role) return fallback;
  return null;
}

/// Prints every Navigator push/pop while debugging.
///
/// A black screen means the Navigator was left with no route at all, and that
/// is only visible by watching the stack: which route was pushed imperatively
/// on top of the router's pages, and which pop removed the last one.
class RouteStackLogger extends NavigatorObserver {
  static String _name(Route<dynamic>? route) {
    if (route == null) return 'null';
    final settingsName = route.settings.name;
    return settingsName ?? route.runtimeType.toString();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    debugPrint('[nav] push ${_name(route)} (over ${_name(previousRoute)})');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    debugPrint('[nav] pop ${_name(route)} (back to ${_name(previousRoute)})');
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    debugPrint('[nav] remove ${_name(route)}');
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    debugPrint('[nav] replace ${_name(oldRoute)} -> ${_name(newRoute)}');
  }
}

final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.splash,
  debugLogDiagnostics: true,
  observers: <NavigatorObserver>[RouteStackLogger()],
  routes: <RouteBase>[
    GoRoute(
      path: AppRoutes.splash,
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: AppRoutes.onboarding,
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: AppRoutes.roleSelect,
      builder: (context, state) => const RoleSelectionScreen(),
    ),
    GoRoute(
      path: '/login/:role',
      builder: (context, state) {
        switch (state.pathParameters['role']) {
          case 'mechanic':
            return const MechanicLoginPage();
          case 'assistant':
            return const AssistantLoginPage();
          case 'garage':
            return const GarageLoginPage();
          case 'user':
          default:
            return const UserLoginPage();
        }
      },
    ),
    GoRoute(
      path: AppRoutes.userHome,
      redirect: (context, state) =>
          _requireRole('user', AppRoutes.roleSelect),
      builder: (context, state) => UserMainScreen(
        name: AppSession.name ?? 'User',
        email: AppSession.email ?? '',
        homeScreen: const UserHomeScreen(),
      ),
    ),
    GoRoute(
      path: AppRoutes.mechanicHome,
      redirect: (context, state) =>
          _requireRole('mechanic', AppRoutes.roleSelect),
      builder: (context, state) => MechanicMainScreen(
        mechanicId: AppSession.id ?? '',
        mechanicName: AppSession.name ?? 'Mechanic',
        mechanicEmail: AppSession.email ?? '',
      ),
    ),
    GoRoute(
      path: AppRoutes.assistantHome,
      redirect: (context, state) =>
          _requireRole('assistant', AppRoutes.roleSelect),
      builder: (context, state) => AssistantMainScreen(
        assistantId: AppSession.id ?? '',
        assistantName: AppSession.name ?? 'Assistant',
        assistantEmail: AppSession.email ?? '',
      ),
    ),
    GoRoute(
      path: AppRoutes.garageHome,
      redirect: (context, state) =>
          _requireRole('garage', AppRoutes.login('garage')),
      builder: (context, state) => const GarageMainScreen(),
    ),
    GoRoute(
      path: AppRoutes.admin,
      builder: (context, state) => const AdminLoginPage(),
    ),
    GoRoute(
      path: AppRoutes.settings,
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: AppRoutes.nearbyMechanics,
      builder: (context, state) => const NearbyMechanicsScreen(),
    ),
    GoRoute(
      path: AppRoutes.feedback,
      builder: (context, state) =>
          FeedbackScreen(requestId: state.uri.queryParameters['job'] ?? ''),
    ),
    GoRoute(
      path: AppRoutes.privacy,
      builder: (context, state) => const PrivacyPolicyScreen(),
    ),
    GoRoute(
      path: AppRoutes.attendance,
      builder: (context, state) => const AttendanceScreen(),
    ),
    GoRoute(
      path: AppRoutes.mechanicProfile,
      builder: (context, state) => const MechanicProfileEditScreen(),
    ),
    GoRoute(
      path: AppRoutes.assistantProfile,
      builder: (context, state) => const AssistantProfileScreen(),
    ),
    GoRoute(
      path: AppRoutes.documents,
      builder: (context, state) => const MechanicDocumentsScreen(),
    ),
    GoRoute(
      path: AppRoutes.ratings,
      builder: (context, state) => const MechanicRatingsScreen(),
    ),
    GoRoute(
      path: '/earnings/:audience',
      builder: (context, state) => EarningsScreen(
        audience: state.pathParameters['audience'] == 'assistant'
            ? EarningsAudience.assistant
            : EarningsAudience.mechanic,
      ),
    ),
    GoRoute(
      path: '/chat/:requestId',
      builder: (context, state) => ChatScreen(
        requestId: state.pathParameters['requestId'] ?? '',
        myId: AppSession.id ?? '',
        myRole: AppSession.role ?? '',
        myName: AppSession.name ?? '',
        otherPartyName: state.uri.queryParameters['name'] ?? 'Crew',
      ),
    ),
    GoRoute(
      path: '/token/:requestId',
      builder: (context, state) => ArrivalTokenScreen(
        mode: state.uri.queryParameters['mode'] == 'generate'
            ? TokenMode.generate
            : TokenMode.verify,
        requestId: state.pathParameters['requestId'] ?? '',
        mechanicId: state.uri.queryParameters['mechanic'] ?? '',
      ),
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wrong_location_outlined, size: 40),
            const SizedBox(height: 10),
            Text(
              'That screen does not exist.\n${state.uri}',
              textAlign: TextAlign.center,
              style: const TextStyle(inherit: true, fontSize: 13),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () => context.go(AppRoutes.roleSelect),
              child: const Text('Go to role selection',
                  style: TextStyle(inherit: true)),
            ),
          ],
        ),
      ),
    ),
  ),
);

/// Backwards-compatible alias: some earlier code referred to `router`.
final GoRouter router = appRouter;
