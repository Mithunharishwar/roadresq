// FILE: test/socket_service_test.dart
//
// Exercises the REAL SocketService (not a replica) against a running backend.
// It exists because the defect it guards against was invisible to static
// analysis: the client silently connected over the wrong transport and failed
// every attempt at runtime.
//
// Start the backend, then:
//   flutter test test/socket_service_test.dart
//
// The backend binds 0.0.0.0:5050, so loopback is reachable from the test VM.

import 'package:flutter_test/flutter_test.dart';
import 'package:roadresq/core/config/app_config.dart';
import 'package:roadresq/services/api_service.dart';
import 'package:roadresq/services/socket_service.dart';

/// The backend's own bind address, reachable from the test process.
const String _backend = 'http://127.0.0.1:5050';

Future<bool> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return condition();
}

/// The transport the engine actually settled on (`websocket` or `polling`).
String? _activeTransport(SocketService socket) =>
    socket.rawSocket?.io.engine?.transport?.name;

/// Guards the build-configuration trap that cost a whole debugging session: an
/// APK built without `--dart-define=ROADRESQ_HOST` resolves to the emulator
/// alias `10.0.2.2`, which is unroutable from a real phone, so every request
/// times out with an empty backend log. This asserts the app can at least
/// RECOGNISE that state and say so.
void _misconfigurationHintGroup() {
  group('host misconfiguration detection', () {
    // Restore (not clear) the host: the transport tests after this group rely
    // on setUpAll having pointed AppConfig at the loopback backend.
    tearDown(() => AppConfig.setHost(_backend));

    test('an unconfigured build is flagged and names the emulator alias', () {
      // Tests run without --dart-define, and flutter_test reports
      // TargetPlatform.android, which is exactly the unconfigured case.
      AppConfig.clearHostOverride();
      expect(AppConfig.isExplicitlyConfigured, isFalse);
      expect(AppConfig.isUnconfiguredEmulatorDefault, isTrue);
      expect(AppConfig.transportMisconfigurationHint, isNotNull);
      expect(AppConfig.transportMisconfigurationHint, contains('10.0.2.2'));
      expect(
        AppConfig.transportMisconfigurationHint,
        contains('ROADRESQ_HOST'),
        reason: 'the hint must tell the reader how to fix it',
      );
    });

    test('a configured LAN host clears the hint', () {
      AppConfig.setHost('http://192.168.31.206:5050');
      expect(AppConfig.isExplicitlyConfigured, isTrue);
      expect(AppConfig.isUnconfiguredEmulatorDefault, isFalse);
      expect(AppConfig.transportMisconfigurationHint, isNull);
    });
  });
}

void main() {
  _misconfigurationHintGroup();

  setUpAll(() {
    // Loopback override; AppConfig otherwise resolves to the Android
    // emulator alias (10.0.2.2), which is unreachable from the test VM.
    AppConfig.setHost(_backend);
  });

  tearDown(() {
    SocketService().disconnect();
  });

  test('configured transports put websocket first', () {
    // On the Dart VM the transport factory ignores this list's NAME and always
    // builds a WebSocket transport, while engine.io still writes entry 0 into
    // the handshake query. If entry 0 is not 'websocket' the handshake is sent
    // to a URL claiming transport=polling and the server answers HTTP 200
    // instead of 101 — every connection fails.
    expect(AppConfig.socketTransports.first, 'websocket');
    expect(AppConfig.socketTransports, contains('websocket'));
  });

  test('connects and stays connected over websocket', () async {
    final socket = SocketService();

    socket.connect();

    final connected = await _waitFor(() => socket.isConnected);

    expect(
      connected,
      isTrue,
      reason: 'SocketService never connected. ${socket.describeConnectivity()}',
    );
    expect(_activeTransport(socket), 'websocket');

    // Hold the connection briefly to prove it is not a flapping success.
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(socket.isConnected, isTrue);
  }, timeout: const Timeout(Duration(seconds: 45)));

  test('repeated connect() calls reuse one live socket', () async {
    final socket = SocketService();

    socket.connect();
    expect(await _waitFor(() => socket.isConnected), isTrue,
        reason: socket.describeConnectivity());

    final firstSocket = socket.rawSocket;

    // This is what every screen's initState does. It must not tear down the
    // existing connection (the old implementation disposed and rebuilt it).
    for (var i = 0; i < 5; i++) {
      socket.connect();
    }

    expect(identical(socket.rawSocket, firstSocket), isTrue,
        reason: 'connect() replaced the live socket object');
    expect(socket.isConnected, isTrue);

    await Future<void>.delayed(const Duration(seconds: 2));
    expect(socket.isConnected, isTrue,
        reason: 'socket dropped after repeated connect() calls');
  }, timeout: const Timeout(Duration(seconds: 45)));

  test('cancel() removes only its own listener', () async {
    final socket = SocketService();

    socket.connect();
    expect(await _waitFor(() => socket.isConnected), isTrue);

    var firstFired = 0;
    var secondFired = 0;

    final first = socket.onStatusUpdated((_) => firstFired++);
    socket.onStatusUpdated((_) => secondFired++);

    // One screen going away must not silence another screen's handler.
    first.cancel();

    // The server re-broadcasts status_updated to every client, including the
    // sender, so this is a full client -> server -> client round trip.
    socket.emit('status_updated', <String, dynamic>{
      'requestId': 'socket-service-test',
      'mechanicId': 'test-mechanic',
      'status': 'Accepted',
    });

    final delivered = await _waitFor(() => secondFired > 0,
        timeout: const Duration(seconds: 10));

    expect(delivered, isTrue, reason: 'round-trip event never arrived');
    expect(firstFired, 0,
        reason: 'cancelled listener still received the event');
    expect(secondFired, greaterThan(0));
  }, timeout: const Timeout(Duration(seconds: 45)));

  test('clearAllListeners() stops delivery app-wide', () async {
    final socket = SocketService();

    socket.connect();
    expect(await _waitFor(() => socket.isConnected), isTrue);

    var fired = 0;
    socket.onStatusUpdated((_) => fired++);

    socket.emit('status_updated', <String, dynamic>{
      'requestId': 'socket-service-test-2',
      'status': 'Accepted',
    });
    expect(await _waitFor(() => fired > 0), isTrue);

    socket.clearAllListeners();
    final before = fired;

    socket.emit('status_updated', <String, dynamic>{
      'requestId': 'socket-service-test-3',
      'status': 'Accepted',
    });
    await Future<void>.delayed(const Duration(seconds: 3));

    expect(fired, before,
        reason: 'a listener survived clearAllListeners()');
  }, timeout: const Timeout(Duration(seconds: 45)));

  group('auth failures are typed, not generic', () {
    // The garage page used to print the same "Login failed: ..." for every
    // possible cause, so someone with no account at all could not tell that no
    // account existed. The page now branches on the HTTP status, which is only
    // possible if the client reports it. This asserts that contract.
    test('bad garage credentials surface as a 401 auth failure', () async {
      await expectLater(
        ApiService.garageLogin(
          garageId: 'NO-SUCH-GARAGE-XX',
          password: 'definitely-wrong',
        ),
        throwsA(
          isA<ApiAuthException>().having(
            (e) => e.isUnauthorized,
            'isUnauthorized',
            isTrue,
          ),
        ),
      );
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('registering a duplicate garage reports a 409 conflict', () async {
      // Uses a garage that cannot exist twice: the first call registers, the
      // second must conflict. Both are cleaned up by deleting the document.
      const id = 'TEST-CONFLICT-XX';
      try {
        await ApiService.garageRegister(
          garageId: id,
          name: 'Conflict Probe',
          password: 'probe1234',
        );
      } on ApiAuthException {
        // Left over from an earlier run — acceptable, the conflict is next.
      }

      await expectLater(
        ApiService.garageRegister(
          garageId: id,
          name: 'Conflict Probe',
          password: 'probe1234',
        ),
        throwsA(
          isA<ApiAuthException>().having(
            (e) => e.isConflict,
            'isConflict',
            isTrue,
          ),
        ),
      );
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
