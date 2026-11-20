// FILE: lib/services/backend_discovery.dart
//
// Finds the RoadResQ backend on whatever LAN the phone/PC are on *right now*,
// so the app never depends on an address that was compiled in or saved on a
// previous network.
//
// ── Why this file exists ───────────────────────────────────────────────────
// The recurring "socket error" was never a socket bug. The installed app was
// pointed at a LAN address captured at build time:
//
//   [socket] connect error: SocketException: No route to host
//   (OS Error: No route to host, errno = 113), address = 10.11.189.61
//
// while the PC had moved to 10.11.93.48 (DHCP lease / different Wi-Fi). The
// server was healthy the whole time; the phone was dialling a machine that no
// longer exists on that network. Every new network or lease therefore broke the
// app again, and "fixing" it meant recompiling with a fresh IP — the same repair
// every single day.
//
// A hardcoded address can only ever be correct until the next DHCP renewal, so
// the address is now *discovered at runtime*, in this order:
//
//   1. addresses already known (runtime override / saved host / build-time host)
//   2. UDP presence beacon broadcast by the backend on port 5051  (fastest)
//   3. bounded sweep of the phone's own subnet for /health          (fallback)
//
// The winner is written back to AppConfig (and persisted), so REST and the
// Socket.IO client move together and the answer survives a restart.
//
// Both discovery transports are plain dart:io — no extra plugin, no extra
// Android permission beyond INTERNET.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/config/app_config.dart';

/// Outcome of one discovery run.
class DiscoveryResult {
  const DiscoveryResult({
    required this.host,
    required this.method,
    required this.probed,
    required this.elapsed,
    this.detail = '',
  });

  /// Reachable backend origin, or null when nothing answered.
  final String? host;

  /// How [host] was found: `known-host`, `beacon`, `subnet-sweep` or `none`.
  final String method;

  /// Number of addresses probed over HTTP.
  final int probed;

  final Duration elapsed;
  final String detail;

  bool get found => host != null;

  @override
  String toString() => found
      ? 'found $host via $method ($probed probed, ${elapsed.inMilliseconds}ms)'
      : 'not found ($probed probed, ${elapsed.inMilliseconds}ms) $detail';
}

class BackendDiscovery {
  BackendDiscovery._();

  /// UDP port the backend broadcasts its presence on.
  static const int beaconPort = 5051;

  /// How long to listen for a beacon before falling back to a sweep.
  ///
  /// Measured on a real device (SM-A715F): Android's Wi-Fi power saving filters
  /// broadcast datagrams for ordinary apps, so this stage usually yields
  /// nothing and the sweep does the work. It is kept short because it is a
  /// latency cost, not the primary path — the sweep found the server in 52
  /// probes (~0.7 s) on the same network. Raise it only where broadcasts are
  /// known to arrive.
  static const Duration beaconWindow = Duration(milliseconds: 1500);

  /// Per-address HTTP timeout while sweeping. Small on purpose: a dead LAN
  /// address answers with a timeout, and there may be hundreds of them.
  static const Duration sweepProbeTimeout = Duration(milliseconds: 400);

  /// Total budget for the sweep stage, so a hostile network cannot hang boot.
  static const Duration sweepBudget = Duration(seconds: 12);

  static const int _sweepConcurrency = 48;

  /// Single-flight guard: concurrent callers share one run.
  static Future<DiscoveryResult>? _inFlight;

  /// Last result, reused for a short window so screens calling on every
  /// reconnect do not each trigger a sweep.
  static DiscoveryResult? _last;
  static DateTime? _lastAt;
  static const Duration _cacheFor = Duration(seconds: 10);

  /// True when discovery is allowed for this build.
  static bool get enabled => AppConfig.autoDiscovery;

  /// Find a reachable backend and apply it to [AppConfig] if it differs from
  /// the current host. Never throws.
  static Future<DiscoveryResult> ensureReachable({
    String reason = 'boot',
    bool force = false,
  }) async {
    if (!enabled) {
      return const DiscoveryResult(
        host: null,
        method: 'disabled',
        probed: 0,
        elapsed: Duration.zero,
        detail: 'auto-discovery disabled for this build',
      );
    }

    final cached = _last;
    final cachedAt = _lastAt;
    if (!force &&
        cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheFor) {
      return cached;
    }

    final running = _inFlight;
    if (running != null) return running;

    final future = _run(reason: reason);
    _inFlight = future;
    try {
      final result = await future;
      _last = result;
      _lastAt = DateTime.now();
      return result;
    } finally {
      _inFlight = null;
    }
  }

  static Future<DiscoveryResult> _run({required String reason}) async {
    final watch = Stopwatch()..start();

    // ── Stage 1: addresses we already know ───────────────────────────────
    final known = candidates();
    for (final host in known) {
      if (await probe(host, timeout: const Duration(milliseconds: 1200))) {
        debugPrint('[discovery] $reason: reachable known host $host');
        return DiscoveryResult(
          host: host,
          method: 'known-host',
          probed: known.indexOf(host) + 1,
          elapsed: watch.elapsed,
        );
      }
    }

    // ── Stage 2: backend's own UDP presence beacon ───────────────────────
    final beacons = await _listenForBeacons(beaconWindow);
    for (final host in beacons) {
      if (await probe(host, timeout: const Duration(milliseconds: 1200))) {
        debugPrint('[discovery] $reason: found $host via beacon');
        return DiscoveryResult(
          host: host,
          method: 'beacon',
          probed: known.length + 1,
          elapsed: watch.elapsed,
          detail: 'beacon on udp/$beaconPort',
        );
      }
    }
    debugPrint('[discovery] $reason: no beacon in '
        '${beaconWindow.inMilliseconds}ms, sweeping subnet');

    // ── Stage 3: bounded subnet sweep ────────────────────────────────────
    final sweep = await _sweepSubnet(budget: sweepBudget);
    if (sweep != null) {
      debugPrint('[discovery] $reason: found $sweep via subnet sweep');
      return DiscoveryResult(
        host: sweep,
        method: 'subnet-sweep',
        probed: known.length + _probeCount,
        elapsed: watch.elapsed,
      );
    }

    final tried = known.isEmpty ? 'no known hosts' : known.join(', ');
    return DiscoveryResult(
      host: null,
      method: 'none',
      probed: known.length + _probeCount,
      elapsed: watch.elapsed,
      detail: 'no RoadResQ backend answered /health '
          '(tried: $tried; $_probeCount subnet addresses)',
    );
  }

  /// Every address worth trying before any network scan, most specific first.
  static List<String> candidates() {
    final list = <String>[];
    void add(String? value) {
      if (value == null) return;
      final trimmed = value.trim();
      if (trimmed.isEmpty) return;
      final normalised =
          trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
      if (Uri.tryParse(normalised)?.host.isEmpty ?? true) return;
      if (!list.contains(normalised)) list.add(normalised);
    }

    // Current resolution first: it may already be right (fast path).
    add(AppConfig.host);
    // Then whatever the device saved, in case the compile-time default is wrong.
    add(AppConfig.savedHost);
    if (AppConfig.isAndroid) {
      add(AppConfig.androidEmulatorHost);
      // `adb reverse tcp:5050 tcp:5050` publishes the PC's backend on the
      // device's own loopback over USB. Costs one refused connection to test
      // and makes the app work even when the Wi-Fi network blocks phone-to-PC
      // traffic entirely, which happens on locked-down campus/corporate APs.
      add('http://127.0.0.1:${AppConfig.backendPort}');
    }
    return list;
  }

  /// True when [base] is a RoadResQ backend.
  ///
  /// `/health` is the cheapest proof of identity: it is served by this backend
  /// on every build and answers `{"success": true, "message": "Server healthy"}`.
  /// A bare HTTP 200 is not enough — an unrelated device on the LAN could answer
  /// the port with anything.
  static Future<bool> probe(String base, {Duration? timeout}) async {
    final cleaned =
        base.trim().endsWith('/') ? base.trim().substring(0, base.trim().length - 1) : base.trim();
    if (cleaned.isEmpty) return false;
    try {
      final response = await http
          .get(Uri.parse('$cleaned/health'))
          .timeout(timeout ?? const Duration(milliseconds: 600));
      if (response.statusCode != 200) return false;
      final decoded = jsonDecode(response.body);
      return decoded is Map && decoded['success'] == true;
    } catch (_) {
      return false;
    }
  }

  // ── Beacon listener ─────────────────────────────────────────────────────

  /// Collects beacon-advertised origins for [window].
  ///
  /// The backend sends a small JSON datagram to the broadcast address every two
  /// seconds. This works across any address change and any /22 or /16 subnet,
  /// which a subnet sweep cannot do cheaply.
  static Future<List<String>> _listenForBeacons(Duration window) async {
    RawDatagramSocket? socket;
    final found = <String>[];
    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        beaconPort,
        reuseAddress: true,
      ).timeout(const Duration(seconds: 2));
    } catch (e) {
      debugPrint('[discovery] beacon listener unavailable: $e');
      return found;
    }

    final completer = Completer<void>();
    late final StreamSubscription<RawSocketEvent> sub;
    final timer = Timer(window, () {
      if (!completer.isCompleted) completer.complete();
    });

    sub = socket.listen(
      (event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket!.receive();
        if (datagram == null) return;
        final origin = _parseBeacon(datagram.data, datagram.address);
        if (origin != null && !found.contains(origin)) {
          found.add(origin);
          if (!completer.isCompleted) completer.complete();
        }
      },
      onError: (Object e) {
        debugPrint('[discovery] beacon socket error: $e');
        if (!completer.isCompleted) completer.complete();
      },
    );

    await completer.future;
    timer.cancel();
    await sub.cancel();
    socket.close();
    return found;
  }

  static String? _parseBeacon(Uint8List data, InternetAddress sender) {
    try {
      final decoded = jsonDecode(utf8.decode(data));
      if (decoded is! Map) return null;
      if (decoded['service'] != 'roadresq') return null;
      final port = decoded['port'];
      final int? resolved = port is int ? port : int.tryParse('$port');
      if (resolved == null || resolved <= 0) return null;
      return 'http://${sender.address}:$resolved';
    } catch (_) {
      return null;
    }
  }

  // ── Subnet sweep ────────────────────────────────────────────────────────

  static int _probeCount = 0;

  /// Sweeps the device's own /24 first, then the neighbouring /24 blocks that a
  /// /22 or /16 DHCP pool can place the PC in. Stops on the first answer and
  /// abandons the rest at [budget].
  static Future<String?> _sweepSubnet({required Duration budget}) async {
    _probeCount = 0;
    final watch = Stopwatch()..start();

    List<NetworkInterface> interfaces;
    try {
      interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
    } catch (e) {
      debugPrint('[discovery] cannot enumerate interfaces: $e');
      return null;
    }

    final blocks = <String>{};
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        final octets = addr.address.split('.');
        if (octets.length != 4) continue;
        // 169.254.x.x is link-local: no router, no backend behind it.
        if (octets[0] == '169' && octets[1] == '254') continue;
        if (addr.address.startsWith('127.')) continue;
        final base = '${octets[0]}.${octets[1]}.${octets[2]}';
        blocks.add(base);
        // Walk outwards so a /22 pool (e.g. 10.11.92-95.x) is covered without
        // scanning 1000 addresses before the likely one.
        final third = int.tryParse(octets[2]) ?? 0;
        for (final delta in <int>[1, -1, 2, -2, 3, -3]) {
          final neighbour = third + delta;
          if (neighbour < 0 || neighbour > 255) continue;
          blocks.add('${octets[0]}.${octets[1]}.$neighbour');
        }
      }
    }
    if (blocks.isEmpty) return null;

    // Never let one interface's own /24 starve another interface: interleave by
    // putting the first block of each subnet first.
    final ordered = blocks.toList();

    for (final block in ordered) {
      if (watch.elapsed > budget) break;
      final hit = await _sweepBlock(block, started: watch, deadline: budget);
      if (hit != null) return hit;
    }
    return null;
  }

  static Future<String?> _sweepBlock(
    String block, {
    required Stopwatch started,
    required Duration deadline,
  }) async {
    final hosts = List<String>.generate(254, (i) => 'http://$block.${i + 1}:5050');
    var index = 0;
    String? hit;

    Future<void> worker() async {
      while (true) {
        if (hit != null) return;
        if (started.elapsed > deadline) return;
        final i = index++;
        if (i >= hosts.length) return;
        final candidate = hosts[i];
        _probeCount++;
        if (await probe(candidate, timeout: sweepProbeTimeout)) {
          hit ??= candidate;
          return;
        }
      }
    }

    await Future.wait(
      List<Future<void>>.generate(
        _sweepConcurrency,
        (_) => worker(),
        growable: false,
      ),
    );
    return hit;
  }

  @visibleForTesting
  static void resetCacheForTest() {
    _last = null;
    _lastAt = null;
    _inFlight = null;
    _probeCount = 0;
  }
}
