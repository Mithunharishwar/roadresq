// FILE: lib/main.dart
/// RoadResQ — application entry point.
///
/// Boot sequence:
///   1. resolve the backend host (compile-time define, saved override, or LAN
///      discovery) so REST and Socket.IO can never point at different servers;
///   2. restore the saved session and language choice before the first frame,
///      so the splash screen can decide between onboarding, role selection and
///      a signed-in dashboard;
///   3. install a global error boundary — a thrown build error renders a
///      readable card instead of Flutter's red screen;
///   4. run `MaterialApp.router` over [appRouter].
library;

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show GlobalCupertinoLocalizations;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalMaterialLocalizations, GlobalCupertinoLocalizations;

import 'core/config/app_config.dart';
import 'core/i18n/rq_strings.dart';
import 'core/router/app_router.dart';
import 'core/session/app_session.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'core/utils/firestore_failure.dart';
import 'firebase_options.dart';
import 'services/backend_discovery.dart';
import 'services/socket_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The backend host is resolved once by AppConfig, which both the REST client
  // and the Socket.IO client read. This removes the two-independent-constants
  // problem (and the hardcoded LAN IP) that previously let the REST and
  // realtime layers point at different machines.
  //
  //   Android emulator : flutter run --dart-define=ROADRESQ_EMULATOR=true
  //   Physical device  : flutter run --dart-define=ROADRESQ_HOST=http://<ip>:5050

  // A host saved from the in-app setting wins over the compile-time default, so
  // a build that forgot the --dart-define can still be pointed at the right
  // server from the phone. Must run before anything reads the host.
  await AppConfig.loadPersistedHost();

  // Session, language and theme are read before the first frame: the splash
  // screen's login-state check and the language switch both need them.
  await AppSession.restore();
  await RqLocale.restore();

  debugPrint('[RoadResQ] ${AppConfig.describe()}');
  debugPrint(
    '[RoadResQ] session: ${AppSession.isSignedIn ? '${AppSession.role} (${AppSession.id})' : 'none'}',
  );

  // Shout when this build has no host configured. On a physical device that
  // means every request silently times out against the emulator alias, with an
  // empty backend log — which reads exactly like a dead server or a firewall.
  final transportHint = AppConfig.transportMisconfigurationHint;
  if (transportHint != null) {
    debugPrint('[RoadResQ] WARNING — TRANSPORT MISCONFIGURED: $transportHint');
  }

  // Say it at boot when the address saved on this device does not answer.
  final hostNotice = AppConfig.startupNotice;
  if (hostNotice != null) {
    debugPrint(
      '[RoadResQ] WARNING — SAVED HOST UNREACHABLE (saved: '
      '${AppConfig.savedHost}, using: ${AppConfig.host}): $hostNotice',
    );
  }

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {
    // Firebase init is optional here — the live flows use the Python backend.
    // Fall through so the app still boots even if Firebase is unavailable.
  }

  debugPrint(
    '[RoadResQ] Firebase Auth session: '
    '${hasFirebaseSession ? FirebaseAuth.instance.currentUser?.uid : 'NONE — every Firestore rule will deny (logins authenticate against the RoadResQ backend, not Firebase)'}',
  );

  // §10 — global error boundary. Installed before runApp so a failure in the
  // first frame is also caught.
  installGlobalErrorHandling();

  unawaited(_resolveBackendAtBoot());

  runApp(const RoadResQApp());
}

/// Replace the red screen with something a tester can act on, and log every
/// uncaught async error once instead of letting it vanish.
void installGlobalErrorHandling() {
  ErrorWidget.builder = (FlutterErrorDetails details) {
    final message = details.exceptionAsString();
    debugPrint('[RoadResQ] build error: $message');
    return Material(
      color: const Color(0xFFFFEBEE),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFD32F2F), size: 36),
              const SizedBox(height: 8),
              const Text(
                'This section could not be displayed',
                textAlign: TextAlign.center,
                style: TextStyle(
                  inherit: true,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFB71C1C),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message.length > 220 ? '${message.substring(0, 220)}…' : message,
                textAlign: TextAlign.center,
                style: const TextStyle(inherit: true, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  };

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('[RoadResQ] FlutterError: ${details.exceptionAsString()}');
  };

  WidgetsBinding.instance.platformDispatcher.onError =
      (Object error, StackTrace stack) {
    debugPrint('[RoadResQ] uncaught: $error');
    return true; // handled — do not crash the isolate
  };
}

/// Probe the configured host once, and fall back to LAN discovery when it is
/// dead. Logs a single actionable line either way.
Future<void> _resolveBackendAtBoot() async {
  if (!AppConfig.autoDiscovery) return;
  try {
    if (await AppConfig.probeHost(
      AppConfig.host,
      timeout: const Duration(seconds: 3),
    )) {
      return;
    }
    debugPrint('[RoadResQ] ${AppConfig.host} did not answer — confirming the '
        'backend address on the local network');
    final result = await BackendDiscovery.ensureReachable(reason: 'boot');
    if (result.found) {
      await SocketService().retarget(
        result.host!,
        reason: 'boot discovery via ${result.method}',
      );
      debugPrint('[RoadResQ] backend found at ${result.host} '
          '(${result.method}, ${result.probed} probed, '
          '${result.elapsed.inMilliseconds}ms)');
    } else {
      debugPrint('[RoadResQ] no backend on this network. Start it with '
          '.\\start_backend.ps1, or set the server address on the login screen. '
          '${result.detail}');
    }
  } catch (e) {
    debugPrint('[RoadResQ] backend discovery failed: $e');
  }
}

class RoadResQApp extends StatelessWidget {
  const RoadResQApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Both the theme and the language are global singletons so a change on the
    // Settings screen rebuilds the whole app, not just that screen.
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance,
      builder: (context, themeMode, _) {
        return ValueListenableBuilder<Locale?>(
          valueListenable: RqLocale.locale,
          builder: (context, locale, _) {
            return MaterialApp.router(
              title: 'RoadResQ',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: themeMode,
              routerConfig: appRouter,
              locale: locale,
              supportedLocales: RqLocale.supported,
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
            );
          },
        );
      },
    );
  }
}
