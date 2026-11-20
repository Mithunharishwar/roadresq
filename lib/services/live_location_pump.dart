// FILE: lib/services/live_location_pump.dart
/// §15 — one place that turns a Geolocator position stream into socket
/// `update_location` events for a job.
///
/// Before this, the crew screens polled a REST timer and the socket emitter
/// (`CrewJobService.streamLocation`) was never instantiated, so the customer's
/// live marker depended entirely on HTTP polling. This pump is deliberately
/// independent of any screen: start it when a job becomes active, stop it when
/// the job completes, and it survives tab switches.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../core/constants/app_constants.dart';
import 'socket_service.dart';

class LiveLocationPump {
  LiveLocationPump._();

  static final LiveLocationPump instance = LiveLocationPump._();

  StreamSubscription<Position>? _subscription;
  String? _requestId;
  String? _role;
  String? _ownerId;
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);
  bool _active = false;

  bool get isActive => _active;
  String? get requestId => _requestId;

  /// Begin publishing this device's position for [requestId].
  ///
  /// [role] is `mechanic` or `assistant`; [ownerId] is that crew member's id.
  /// Safe to call repeatedly — a call for the job already being tracked is a
  /// no-op, and a call for a different job restarts the stream.
  Future<bool> start({
    required String requestId,
    required String role,
    required String ownerId,
  }) async {
    if (requestId.isEmpty) return false;
    if (_active && _requestId == requestId) return true;

    await stop();

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('[LocationPump] location services are off');
        return false;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint('[LocationPump] permission denied ($permission)');
        return false;
      }

      _requestId = requestId;
      _role = role;
      _ownerId = ownerId;
      _active = true;

      SocketService().connect();

      _subscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen(_publish, onError: (Object error) {
        debugPrint('[LocationPump] stream error: $error');
      });

      // Publish an immediate fix so the customer is not left waiting for the
      // first movement.
      final current = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 10));
      _publish(current, force: true);

      debugPrint('[LocationPump] publishing for $role on $requestId');
      return true;
    } catch (e) {
      debugPrint('[LocationPump] start failed: $e');
      await stop();
      return false;
    }
  }

  void _publish(Position position, {bool force = false}) {
    if (!_active || _requestId == null) return;

    final now = DateTime.now();
    if (!force &&
        now.difference(_lastSent).inMilliseconds <
            AppConstants.normalLocationIntervalMs) {
      return;
    }
    _lastSent = now;

    SocketService().emit('update_location', <String, dynamic>{
      'requestId': _requestId,
      'id': _ownerId,
      'role': _role,
      'lat': position.latitude,
      'lng': position.longitude,
      'accuracy': position.accuracy,
      'heading': position.heading,
      'speed': position.speed,
      'timestamp': now.toIso8601String(),
    });
  }

  /// Stop publishing. Call on job completion, logout and sign-out.
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    if (_active) {
      debugPrint('[LocationPump] stopped for $_requestId');
    }
    _active = false;
    _requestId = null;
    _role = null;
    _ownerId = null;
  }
}

