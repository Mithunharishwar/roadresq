// Regression tests for the saved-host validation in AppConfig.
//
// THE BUG THESE LOCK DOWN
// A host saved from the in-app setting wins over every other source. That is
// how a stale LAN address (192.168.29.46 after moving to another Wi-Fi) survived
// forever: every request died at the 15s timeout, the backend log stayed empty,
// and the same opaque error appeared on every field of every screen.
//
// The fix probes the saved address once at boot and either uses it, replaces it
// with a reachable build-time host, or keeps it and publishes a notice. These
// tests cover the branch that hardware cannot easily reproduce: no build-time
// host, saved host dead.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:roadresq/core/config/app_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal stand-in for the RoadResQ backend: answers every request with 200.
Future<HttpServer> _stubBackend() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) {
    request.response
      ..statusCode = 200
      ..write('[]');
    request.response.close();
  });
  return server;
}

void main() {
  // Deliberately NO TestWidgetsFlutterBinding.ensureInitialized(): it installs
  // an HttpOverrides that answers every request with 400, which would make a
  // reachability probe report "dead" for a live stub server.
  setUp(() {
    AppConfig.resetForTest();
  });

  test('probeHost reports reachable for a live endpoint and dead otherwise',
      () async {
    final server = await _stubBackend();
    addTearDown(() => server.close(force: true));

    expect(
      await AppConfig.probeHost('http://127.0.0.1:${server.port}'),
      isTrue,
    );
    expect(
      await AppConfig.probeHost(
        'http://127.0.0.1:${server.port}',
        timeout: const Duration(milliseconds: 500),
      ),
      isTrue,
    );
  });

  test('probeHost never throws on an unroutable address', () async {
    // Port 1 on loopback is refused immediately on every platform.
    expect(
      await AppConfig.probeHost(
        'http://127.0.0.1:1',
        timeout: const Duration(milliseconds: 500),
      ),
      isFalse,
    );
  });

  test('reachable saved host is applied with no notice', () async {
    final server = await _stubBackend();
    addTearDown(() => server.close(force: true));

    final host = 'http://127.0.0.1:${server.port}';
    SharedPreferences.setMockInitialValues({'backendBaseUrl': host});

    await AppConfig.loadPersistedHost(
      probeTimeout: const Duration(milliseconds: 800),
    );

    expect(AppConfig.savedHost, host);
    expect(AppConfig.host, host);
    expect(AppConfig.startupNotice, isNull);
  });

  test('dead saved host with no build-time host is kept and explained',
      () async {
    const dead = 'http://192.168.29.46:5050';
    SharedPreferences.setMockInitialValues({'backendBaseUrl': dead});

    await AppConfig.loadPersistedHost(
      probeTimeout: const Duration(milliseconds: 800),
    );

    // Kept, because falling back would land on the emulator alias — just as
    // unroutable on hardware, but harder to explain.
    expect(AppConfig.savedHost, dead);
    expect(AppConfig.host, dead);

    final notice = AppConfig.startupNotice;
    expect(notice, isNotNull);
    expect(notice, contains(dead));
    expect(notice!.toLowerCase(), contains('not responding'));
  });

  test('no saved host leaves the defaults and no notice', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await AppConfig.loadPersistedHost(
      probeTimeout: const Duration(milliseconds: 400),
    );

    expect(AppConfig.savedHost, isNull);
    expect(AppConfig.startupNotice, isNull);
  });

  test('saving a new host clears the stale-address notice', () async {
    SharedPreferences.setMockInitialValues({'backendBaseUrl': 'http://127.0.0.1:1'});
    await AppConfig.loadPersistedHost(
      probeTimeout: const Duration(milliseconds: 400),
    );
    expect(AppConfig.startupNotice, isNotNull);

    final error = await AppConfig.persistHost('http://127.0.0.1:5050');

    expect(error, isNull);
    expect(AppConfig.startupNotice, isNull);
    expect(AppConfig.savedHost, 'http://127.0.0.1:5050');
  });
}
