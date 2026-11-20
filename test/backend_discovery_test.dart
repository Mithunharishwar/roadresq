// Integration tests for the LAN discovery that replaced the hardcoded backend
// address.
//
// These talk to a real backend on 127.0.0.1:5050 (and to its UDP beacon), because
// the behaviour being verified is "does the app find a live server", which a mock
// cannot answer. Run with the backend up:
//
//   .\start_backend.ps1
//   flutter test test/backend_discovery_test.dart
//
// The tests skip themselves when nothing answers, so they never break a build on
// a machine that is not running the server.

@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:roadresq/core/config/app_config.dart';
import 'package:roadresq/services/backend_discovery.dart';

/// A syntactically valid address on the LAN that nothing is listening on.
/// 10.11.189.61 is the address the app was stuck on when the failure was
/// reported: the PC had moved to a different lease and every attempt ended in
/// `SocketException: No route to host (errno = 113)`.
const String staleHost = 'http://10.11.189.61:5050';

void main() {
  setUp(BackendDiscovery.resetCacheForTest);
  tearDown(AppConfig.resetForTest);

  test('probe accepts the RoadResQ backend and rejects a dead address',
      () async {
    final alive = await BackendDiscovery.probe('http://127.0.0.1:5050');
    if (!alive) {
      markTestSkipped('backend not running on 127.0.0.1:5050');
      return;
    }
    expect(alive, isTrue);
    expect(
      await BackendDiscovery.probe(staleHost,
          timeout: const Duration(milliseconds: 800)),
      isFalse,
    );
  });

  test('a stale configured host is replaced by the live one', () async {
    if (!await BackendDiscovery.probe('http://127.0.0.1:5050')) {
      markTestSkipped('backend not running on 127.0.0.1:5050');
      return;
    }

    AppConfig.setHost(staleHost);
    BackendDiscovery.resetCacheForTest();

    final result = await BackendDiscovery.ensureReachable(
      reason: 'test',
      force: true,
    );

    expect(result.found, isTrue,
        reason: 'discovery should locate the running backend: $result');
    expect(result.host, isNot(staleHost));
    // Either path is valid; which one wins depends on whether the beacon reaches
    // the loopback interface before the sweep finishes.
    expect(result.method, anyOf('beacon', 'subnet-sweep', 'known-host'));
  });

  test('hosts are adopted for both REST and the socket', () async {
    await AppConfig.adoptHost('http://192.168.1.77:5050');
    expect(AppConfig.host, 'http://192.168.1.77:5050');
    expect(AppConfig.apiBaseUrl, 'http://192.168.1.77:5050/api');
    expect(AppConfig.socketBaseUrl, 'http://192.168.1.77:5050');
  });
}
