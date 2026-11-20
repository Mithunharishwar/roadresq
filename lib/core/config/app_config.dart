// FILE: lib/core/config/app_config.dart
/// RoadResQ runtime configuration — the single source of truth for the
/// backend host used by both REST (`ApiService`) and realtime
/// (`SocketService`).
///
/// WHY THIS EXISTS
/// The API base URL and the socket base URL were previously two independent
/// constants in two files:
///
///   ApiService.defaultBaseUrl    = 'http://192.168.31.206:5050/api'
///   SocketService.defaultSocketBaseUrl = 'http://192.168.31.206:5050'
///
/// They could silently drift apart (and a stale LAN IP broke both), which is
/// exactly the hardcoded-development-IP defect this replaces.
///
/// RESOLUTION ORDER
///   1. A host saved from the in-app setting ([loadPersistedHost]) — survives
///      restarts and needs no rebuild.
///   2. `--dart-define=ROADRESQ_HOST=http://<ip>:5050`  (explicit)
///   3. `--dart-define=ROADRESQ_EMULATOR=true`          (Android emulator loopback)
///   4. Platform default:
///        Android emulator  -> http://10.0.2.2:5050
///        everything else   -> http://127.0.0.1:5050
///
/// There is deliberately NO hardcoded LAN address. A physical device must be
/// told the host: either saved in-app at runtime, or compiled in —
///
///   flutter run --dart-define=ROADRESQ_HOST=http://192.168.1.20:5050
///
/// The in-app route exists because the compile-time one is easy to forget, and
/// forgetting it is invisible: the app quietly targets `10.0.2.2`, an alias
/// that only exists on an emulator, so every request times out on hardware
/// while the server log stays empty. See [transportMisconfigurationHint].
library;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  AppConfig._();

  // ── Compile-time overrides ────────────────────────────────────────────
  static const String _hostOverride = String.fromEnvironment('ROADRESQ_HOST');
  static const bool _forceEmulator =
      bool.fromEnvironment('ROADRESQ_EMULATOR', defaultValue: false);

  /// Whether the app may look for the backend on the local network at runtime.
  ///
  /// On by default. A compile-time host is only correct until the next DHCP
  /// lease, so discovery is what keeps the app working across networks without
  /// a rebuild; disable it only for a fixed deployment:
  ///   flutter run --dart-define=ROADRESQ_AUTO_DISCOVERY=false
  static const bool _autoDiscoveryEnv =
      bool.fromEnvironment('ROADRESQ_AUTO_DISCOVERY', defaultValue: true);

  static bool get autoDiscovery => _autoDiscoveryEnv;

  // ── Well-known development endpoints ──────────────────────────────────
  /// Android emulator loopback to the host machine.
  static const String androidEmulatorHost = 'http://10.0.2.2:5050';

  /// Local loopback, used for desktop and web builds.
  static const String localhostHost = 'http://127.0.0.1:5050';

  /// Backend port. Kept here so it is written down exactly once.
  static const int backendPort = 5050;

  // ── Resolved host ─────────────────────────────────────────────────────
  static String? _runtimeOverride;

  /// The address exactly as it was saved on the device, or null when nothing
  /// was ever saved. Kept separately from [_runtimeOverride] because the boot
  /// check may *discard* an unreachable saved host — support tickets still need
  /// to know which address was persisted.
  static String? _persistedHostRaw;

  /// A boot-time warning about the saved host, or null when everything is
  /// fine. Rendered on the server-address tile so the cause of a timeout is
  /// visible on screen, not only in logcat.
  static String? _startupNotice;

  /// The address saved on this device, if any.
  static String? get savedHost => _persistedHostRaw;

  /// Boot-time warning about the saved host (see [loadPersistedHost]).
  static String? get startupNotice => _startupNotice;

  /// Drop the boot-time warning once the address is confirmed working.
  static void clearStartupNotice() => _startupNotice = null;

  /// Returns the resolver to its initial state. Tests only — the statics are
  /// process-wide, so one test's saved host would otherwise leak into the next.
  @visibleForTesting
  static void resetForTest() {
    _runtimeOverride = null;
    _persistedHostRaw = null;
    _startupNotice = null;
  }

  /// True when the app is running on the Android emulator.
  ///
  /// Android is the only target whose loopback differs from the host machine's
  /// own loopback, so it needs `10.0.2.2` rather than `127.0.0.1`.
  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// The backend origin, e.g. `http://192.168.1.20:5050` (no trailing slash).
  static String get host {
    if (_runtimeOverride != null && _runtimeOverride!.isNotEmpty) {
      return _stripTrailingSlash(_runtimeOverride!);
    }
    if (_hostOverride.isNotEmpty) {
      return _stripTrailingSlash(_hostOverride);
    }
    if (_forceEmulator) {
      return androidEmulatorHost;
    }
    return isAndroid ? androidEmulatorHost : localhostHost;
  }

  /// REST base URL consumed by [ApiService].
  static String get apiBaseUrl => '$host/api';

  /// Socket.IO base URL consumed by [SocketService].
  static String get socketBaseUrl => host;

  /// True when the host came from an explicit developer override.
  static bool get isExplicitlyConfigured =>
      _hostOverride.isNotEmpty ||
      (_runtimeOverride != null && _runtimeOverride!.isNotEmpty);

  /// Whether this host is a development loopback address.
  static bool get isDevelopmentHost =>
      host.contains('127.0.0.1') ||
      host.contains('localhost') ||
      host.contains('10.0.2.2');

  /// True when the app fell back to the Android-emulator alias because NO host
  /// was configured for this build.
  ///
  /// This is the trap that makes every request fail with a bare timeout:
  /// building for a real phone WITHOUT `--dart-define=ROADRESQ_HOST=...`
  /// resolves to `10.0.2.2`, an emulator-only alias. On physical hardware that
  /// address is unroutable, so the SYN gets no reply and every call dies at
  /// [requestTimeout] — with NOTHING in the backend log, which makes it look
  /// exactly like a dead backend or a blocked firewall. Verified on a real
  /// SM-A715F: a build missing the define logged
  /// `source: platform default` and timed out on every request, while the same
  /// request from `adb shell curl` succeeded.
  static bool get isUnconfiguredEmulatorDefault =>
      !isExplicitlyConfigured && !_forceEmulator && isAndroid;

  /// A caution to surface wherever a transport timeout is reported, or null
  /// when the host was configured explicitly.
  static String? get transportMisconfigurationHint =>
      isUnconfiguredEmulatorDefault
          ? 'No host was configured for this build, so the app targets '
              '$androidEmulatorHost — the Android EMULATOR alias. On a physical '
              'device that address is unroutable: every request times out after '
              '${requestTimeout.inSeconds}s and the backend log stays empty. '
              'Rebuild with '
              '--dart-define=ROADRESQ_HOST=http://<your-lan-ip>:5050'
          : null;

  /// Override the host at runtime (used by the in-app developer settings).
  static void setHost(String value) {
    _runtimeOverride = _stripTrailingSlash(value.trim());
  }

  /// Drop any runtime override and fall back to the compile-time resolution.
  static void clearHostOverride() {
    _runtimeOverride = null;
  }

  static const String _persistedHostKey = 'backendBaseUrl';

  /// Apply a host saved from the in-app setting, if one exists.
  ///
  /// WHY THIS EXISTS
  /// A build without `--dart-define=ROADRESQ_HOST` resolves to `10.0.2.2`, the
  /// Android emulator alias. On physical hardware that address is unroutable,
  /// so every request dies at [requestTimeout] and the backend log stays empty.
  /// Relying on a build flag for that has repeatedly been forgotten, which made
  /// a perfectly good server look dead. A saved runtime host fixes it on the
  /// device, with no rebuild.
  ///
  /// Call this once, before anything reads [host]. A saved value deliberately
  /// wins over the compile-time default.
  ///
  /// THE STALE-ADDRESS TRAP
  /// "Wins over everything" is also how a dead address survives forever: change
  /// Wi-Fi, get a new DHCP lease, and the saved host still points at the old
  /// LAN IP. Nothing recovers from that on its own — every request dies at
  /// [requestTimeout], the backend log stays empty, and the same timeout error
  /// appears on every field of every screen with no clue as to why.
  ///
  /// So the saved address is now probed once at boot:
  ///   * reachable  -> apply it, no notice;
  ///   * unreachable and a compile-time `ROADRESQ_HOST` exists -> use the
  ///     compile-time host and say so;
  ///   * unreachable and nothing better to fall back to -> keep it applied (any
  ///     fallback would be `10.0.2.2`, which is just as dead on hardware) and
  ///     publish an actionable [startupNotice].
  ///
  /// The probe costs at most [probeTimeout] and only when a saved host exists.
  /// Set [validate] to false for tests that must not do network I/O.
  static Future<void> loadPersistedHost({
    bool validate = true,
    Duration probeTimeout = const Duration(seconds: 3),
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_persistedHostKey)?.trim();
      if (saved == null || saved.isEmpty) return;

      _persistedHostRaw = saved;
      setHost(saved);
      if (!validate) return;

      if (await probeHost(saved, timeout: probeTimeout)) {
        _startupNotice = null;
        return;
      }

      final compiled = _stripTrailingSlash(_hostOverride);
      if (compiled.isNotEmpty &&
          compiled != _stripTrailingSlash(saved) &&
          await probeHost(compiled, timeout: probeTimeout)) {
        _runtimeOverride = null;
        _startupNotice =
            'The saved server $saved is not responding — using the build-time '
            'server $compiled instead.';
        return;
      }

      _startupNotice =
          'The saved server $saved is not responding. Start the backend, or set '
          'this to the computer\'s current LAN address.';
    } catch (_) {
      // No saved host, or storage unavailable. Fall back to the defaults.
    }
  }

  /// Checks whether [base] answers as a RoadResQ backend.
  ///
  /// Uses `/api/zones` — a small read-only endpoint present on every build —
  /// and never throws: "is this address usable?" has a plain `false` answer.
  static Future<bool> probeHost(
    String base, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final cleaned = _stripTrailingSlash(base.trim());
    if (cleaned.isEmpty) return false;
    try {
      final response =
          await http.get(Uri.parse('$cleaned/api/zones')).timeout(timeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Validate and store [value] as the backend host. Returns an error message
  /// suitable for display, or null when the value was accepted.
  static Future<String?> persistHost(String value) async {
    final cleaned = _stripTrailingSlash(value.trim());
    if (cleaned.isEmpty) {
      return 'Enter the server address, e.g. http://192.168.31.206:5050';
    }
    if (!cleaned.startsWith('http://') && !cleaned.startsWith('https://')) {
      return 'Include the scheme, e.g. http://192.168.31.206:5050';
    }
    final uri = Uri.tryParse(cleaned);
    if (uri == null || uri.host.isEmpty) {
      return 'That does not look like a valid address.';
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_persistedHostKey, cleaned);
    } catch (e) {
      return 'Could not save the address: $e';
    }
    setHost(cleaned);
    // A freshly chosen address invalidates any boot-time complaint about the
    // previous one.
    _persistedHostRaw = cleaned;
    _startupNotice = null;
    return null;
  }

  /// Apply an address found by [BackendDiscovery] and remember it.
  ///
  /// Differs from [persistHost] in that it does not validate the user's typing
  /// — the address has already answered `/health`, which is stronger evidence
  /// than a scheme check. The value is written to storage so the next cold start
  /// begins from a working address instead of a compiled-in one.
  static Future<void> adoptHost(String value) async {
    final cleaned = _stripTrailingSlash(value.trim());
    if (cleaned.isEmpty) return;
    setHost(cleaned);
    _persistedHostRaw = cleaned;
    _startupNotice = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_persistedHostKey, cleaned);
    } catch (_) {
      // Storage unavailable: the runtime override still applies for this run.
    }
  }

  /// Forget the saved host and fall back to the compile-time default.
  static Future<void> clearPersistedHost() async {    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_persistedHostKey);
    } catch (_) {
      // Nothing saved; nothing to do.
    }
    _persistedHostRaw = null;
    _startupNotice = null;
    clearHostOverride();
  }

  /// Human-readable summary for diagnostics screens and support tickets.
  static String describe() {
    final source = _runtimeOverride != null && _runtimeOverride!.isNotEmpty
        ? 'runtime override'
        : _hostOverride.isNotEmpty
            ? '--dart-define=ROADRESQ_HOST'
            : _forceEmulator
                ? '--dart-define=ROADRESQ_EMULATOR'
                : 'platform default';
    return 'API: $apiBaseUrl  •  socket: $socketBaseUrl  •  source: $source';
  }

  static String _stripTrailingSlash(String value) =>
      value.endsWith('/') ? value.substring(0, value.length - 1) : value;

  // ── Domain vocabulary (mirrors the backend `config.py`) ───────────────
  /// Vehicle categories accepted by the request workflow. §11
  static const List<String> vehicleCategories = <String>[
    'Bike',
    'Scooter',
    'Car',
    'SUV',
    'Van',
    'Truck',
  ];

  /// Service categories accepted by the request workflow. §12
  static const List<String> serviceCategories = <String>[
    'Flat Tyre',
    'Battery Problem',
    'Fuel Delivery',
    'Engine Trouble',
    'Towing',
    'General Service',
  ];

  // ── Timeouts ──────────────────────────────────────────────────────────
  static const Duration requestTimeout = Duration(seconds: 15);

  /// Socket.IO transport preference. THE FIRST ENTRY MUST BE `websocket`.
  ///
  /// This is not a preference — it is a hard requirement of
  /// `socket_io_client` 2.0.3+1 on the Dart VM, and getting it wrong breaks
  /// every connection. The chain:
  ///
  ///  1. engine.io writes the FIRST entry of this list into the handshake
  ///     query:  `query['transport'] = transports[0]`.
  ///  2. On the Dart VM the transport factory in
  ///     `socket_io_client/src/engine/transport/io_transports.dart` then
  ///     IGNORES that name and always returns an `IOWebSocketTransport`:
  ///
  ///         static Transport newInstance(String name, options) {
  ///           // only support websocket here.
  ///           return IOWebSocketTransport(options);
  ///         }
  ///
  ///  3. So if `polling` is listed first, the client opens a *WebSocket* to
  ///     `ws://<host>/socket.io/?EIO=4&transport=polling`. The server reads the
  ///     request as a plain long-poll GET and answers HTTP 200 instead of the
  ///     101 Switching Protocols a WebSocket handshake needs.
  ///  4. `dart:io` raises:
  ///
  ///         WebSocketException: Connection to '...transport=polling#' was not
  ///         upgraded to websocket, HTTP status code: 200
  ///
  ///     which surfaces as `connect_error` on every single attempt, forever.
  ///
  /// Listing `websocket` first makes step 1 write `transport=websocket`, which
  /// is what the VM transport actually is, and the handshake completes
  /// normally. Measured: 0 connects / 4 connect_errors in 12s before, versus a
  /// connection established in ~85ms and stable for 150s after.
  ///
  /// The server does support WebSocket here: it runs Flask-SocketIO in
  /// `threading` mode with `simple-websocket` installed, and its handshake
  /// advertises `"upgrades":["websocket"]`.
  static const List<String> socketTransports = <String>['websocket'];
}
