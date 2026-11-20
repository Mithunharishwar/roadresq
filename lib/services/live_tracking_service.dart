// IMPORTANT: Set Firestore Rules to allow read/write for testing
import 'dart:async';
import 'package:flutter/foundation.dart';

import 'api_service.dart';
import 'socket_service.dart';

/// LiveTrackingService (FEATURE 1)
///
/// Battery-safe live tracking for User + Mechanic + Assistant.
///
/// Strategy (Rapido-style):
///  - Primary: Socket.IO events for real-time location updates.
///  - Fallback: Firestore `onSnapshot` polled every 5 seconds.
///  - Lifecycle: Only streams while the job status is "active"
///    (accepted / on_the_way / reached). Stops streaming on
///    pending / completed / cancelled to conserve battery.
///
/// The service exposes a single `Stream<LiveTrackingUpdate>` that
/// screens can listen to, and centrally manages connect/disconnect.
class LiveTrackingUpdate {
  final String requestId;
  final String status;
  final LatLngData? mechanic;
  final LatLngData? assistant;
  final String? paymentStatus;
  final DateTime timestamp;

  LiveTrackingUpdate({
    required this.requestId,
    required this.status,
    this.mechanic,
    this.assistant,
    this.paymentStatus,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class LatLngData {
  final double lat;
  final double lng;
  const LatLngData(this.lat, this.lng);
}

class LiveTrackingService {
  LiveTrackingService._internal();
  static final LiveTrackingService _instance = LiveTrackingService._internal();
  factory LiveTrackingService() => _instance;

  final SocketService _socket = SocketService();

  /// Polls the backend as a fallback while tracking (see
  /// [_startBackendFallback]). Replaced a Firestore snapshot subscription.
  Timer? _fallbackTimer;

  /// Consecutive fallback-poll failures. Drives an exponential pause so a
  /// backend that is down does not produce a log line every 5 seconds.
  int _fallbackFailures = 0;
  DateTime? _fallbackPausedUntil;
  bool _active = false;

  /// Handles for the socket listeners started by [startTracking], so
  /// [stopTracking] can remove exactly those and leave other screens' intact.
  final List<SocketSubscription> _socketSubs = <SocketSubscription>[];

  final StreamController<LiveTrackingUpdate> _controller =
      StreamController<LiveTrackingUpdate>.broadcast();

  /// Stream of live tracking updates.
  Stream<LiveTrackingUpdate> get updates => _controller.stream;

  bool get isActive => _active;

  /// Whether a job status counts as "active" (should stream).
  /// Only these statuses stream to save battery on pending/completed.
  static bool isActiveStatus(String status) {
    final s = status.toLowerCase();
    return s == 'accepted' ||
        s == 'on_the_way' ||
        s == 'on the way' ||
        s == 'reached' ||
        s == 'assigned';
  }

  /// Start live tracking for a given request.
  /// [requestId] the Firestore request document to watch.
  void startTracking({required String requestId}) {
    if (_active) {
      debugPrint('LiveTrackingService: already tracking, ignoring start');
      return;
    }

    _active = true;
    _socket.connect();

    // ─── Socket listeners (primary) ───
    _socketSubs.add(_socket.onMechanicLocationUpdated((data) {
      final reqId = (data['requestId'] ?? '').toString();
      if (reqId != requestId) return;
      _emitFromSocket(data, requestId);
    }));

    _socketSubs.add(_socket.onAssistantLocationUpdated((data) {
      final reqId = (data['requestId'] ?? '').toString();
      if (reqId != requestId) return;
      _emitFromSocket(data, requestId);
    }));

    _socketSubs.add(_socket.onStatusUpdated((data) {
      final reqId = (data['requestId'] ?? '').toString();
      if (reqId != requestId) return;
      final status = (data['status'] ?? 'pending').toString();

      // Battery-safe: stop streaming when job is no longer active.
      if (!isActiveStatus(status)) {
        _emitStatus(requestId, status);
        stopTracking();
        return;
      }
      _emitStatus(requestId, status);
    }));

    // ─── Backend fallback (every 5 seconds) ───
    _startBackendFallback(requestId);
  }

  void _emitFromSocket(Map<String, dynamic> data, String requestId) {
    final status = (data['status'] ?? 'active').toString();
    final mech = data['lat'] != null && data['lng'] != null
        ? LatLngData(
            (data['lat'] as num).toDouble(), (data['lng'] as num).toDouble())
        : null;
    final asst = data['assistantLat'] != null && data['assistantLng'] != null
        ? LatLngData((data['assistantLat'] as num).toDouble(),
            (data['assistantLng'] as num).toDouble())
        : null;

    _controller.add(
      LiveTrackingUpdate(
          requestId: requestId,
          status: status,
          mechanic: mech,
          assistant: asst),
    );
  }

  void _emitStatus(String requestId, String status,
      {LatLngData? mechanic, LatLngData? assistant}) {
    if (!_controller.isClosed) {
      _controller.add(LiveTrackingUpdate(
        requestId: requestId,
        status: status,
        mechanic: mechanic,
        assistant: assistant,
      ));
    }
  }

  /// Read a `{lat, lng}` map as produced by the backend's serializer.
  ///
  /// This replaced GeoPoint handling: the data now comes from JSON over HTTP,
  /// not from a Firestore document.
  static LatLngData? _latLngFrom(dynamic value) {
    if (value is! Map) return null;
    final lat = value['lat'];
    final lng = value['lng'];
    if (lat is! num || lng is! num) return null;
    return LatLngData(lat.toDouble(), lng.toDouble());
  }

  /// Poll the backend for request state while tracking.
  ///
  /// This replaced a Firestore `.snapshots()` listener on `requests`. That
  /// listener never delivered anything — the app holds no Firebase Auth session,
  /// so the stream failed with permission-denied and was logged as "Check
  /// Firestore Rules" — which meant live tracking had no safety net at all when
  /// a socket packet was missed. Socket.IO is still the primary channel;
  /// this now reads the same backend the rest of the app uses.
  void _startBackendFallback(String requestId) {
    _fallbackTimer?.cancel();
    _fallbackFailures = 0;
    _fallbackPausedUntil = null;
    _fallbackTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!_active) return;

      // Back off while the backend is unreachable. With a fixed 5 s poll, a
      // stopped server produced a stack trace every 5 s for as long as the
      // screen stayed open — the "socket error" noise in the terminal — while
      // achieving nothing. The socket self-heal is what recovers the address;
      // this only needs to resume once it succeeds.
      final pausedUntil = _fallbackPausedUntil;
      if (pausedUntil != null && DateTime.now().isBefore(pausedUntil)) return;

      try {
        final data = await ApiService.fetchRequestById(requestId);
        final status = (data['status'] ?? 'pending').toString();

        // Battery-safe: stop streaming once the request is no longer active.
        if (!isActiveStatus(status)) {
          _emitStatus(requestId, status);
          stopTracking();
          return;
        }

        _fallbackFailures = 0;
        _fallbackPausedUntil = null;
        _emitStatus(
          requestId,
          status,
          mechanic: _latLngFrom(data['mechanicLocation']),
          assistant: _latLngFrom(data['assistantLocation']),
        );
      } catch (e) {
        // A request the server no longer has can never become trackable. Stop,
        // rather than re-asking every 5 seconds for the life of the screen —
        // that yielded a steady stream of 404s and no output at all.
        if (e is ApiNotFoundException) {
          debugPrint(
            'LiveTrackingService: request $requestId no longer exists — '
            'stopping tracking',
          );
          stopTracking();
          return;
        }
        _fallbackFailures++;
        // 5 s, 10 s, 20 s, 40 s, then once a minute.
        final pauseSeconds =
            (5 * (1 << (_fallbackFailures - 1).clamp(0, 3))).clamp(5, 60);
        _fallbackPausedUntil =
            DateTime.now().add(Duration(seconds: pauseSeconds));
        if (_fallbackFailures == 1 || _fallbackFailures % 6 == 0) {
          debugPrint(
            'LiveTrackingService: backend unreachable '
            '($_fallbackFailures in a row) — retrying in ${pauseSeconds}s: $e',
          );
        }
      }
    });
  }

  /// Stop all live tracking, disconnect listeners, save battery.
  void stopTracking() {
    if (!_active) return;
    _active = false;

    _fallbackTimer?.cancel();
    _fallbackTimer = null;

    // Remove only the listeners this service started. Calling the app-wide
    // clearAllListeners() here also unsubscribed every open screen, so
    // stopping tracking silently killed their live updates too.
    for (final sub in _socketSubs) {
      sub.cancel();
    }
    _socketSubs.clear();
  }

  /// Dispose the broadcast stream. Call once when the app exits.
  void dispose() {
    stopTracking();
    _controller.close();
  }
}

typedef LiveTrackingListener = void Function(LiveTrackingUpdate update);
