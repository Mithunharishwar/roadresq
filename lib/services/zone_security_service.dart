// IMPORTANT: Set Firestore Rules to allow read/write for testing
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../core/constants/app_constants.dart';
import '../models/zone_model.dart';
import 'api_service.dart';

/// ZoneSecurityService (FEATURE 3)
/// - Reads urban/rural zones from the RoadResQ backend (`GET /api/zones`).
/// - Provides real point-in-bounds containment (matches the Cloud Function).
/// - For rural jobs at night, periodically updates location for enhanced
///   safety tracking.
///
/// This used to read the Firestore `zones` collection. That read can never
/// succeed — there is no Firebase Auth session, so every rule beginning with
/// isAuthenticated() denies it — and it logged "PERMISSION_DENIED: Check
/// Firestore Rules" on every SOS submission. See core/utils/firestore_failure.dart.
class ZoneSecurityService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<Position>? _positionSub;
  Timer? _periodicTimer;
  bool _isTracking = false;

  /// Fetch all zones from Firestore (cached).
  List<ZoneModel> _zones = [];
  Future<void> _zonesLoaded = Future.value();

  ZoneSecurityService() {
    _loadZones();
  }

  Future<void> _loadZones() async {
    _zonesLoaded = _fetchZones();
    await _zonesLoaded;
  }

  Future<void> _fetchZones() async {
    try {
      // Zones come from the backend now — see the class comment. A failure here
      // is not fatal: checkZone below returns the conservative 'rural'
      // classification, which is the safe default for a rescue.
      final raw = await ApiService.fetchZones();
      _zones = raw
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (e) => ZoneModel.fromMap(
              Map<String, dynamic>.from(e),
              (e['id'] ?? e['_id'] ?? '').toString(),
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('ZoneSecurityService._fetchZones error: $e');
      // Fallback: keep empty; checkZone will return the 'rural' default.
      _zones = [];
    }
  }

  /// Zones from the backend, emitted once per subscription.
  ///
  /// This was a Firestore `.snapshots()` listener, which never emitted because
  /// the read was denied. The backend has no realtime zone channel, so this
  /// fetches and emits the current list; there are no callers today.
  Stream<List<ZoneModel>> streamZones() async* {
    await _loadZones();
    yield _zones;
  }

  /// Returns 'urban', 'rural', or 'unknown' with zone details.
  Future<Map<String, dynamic>> checkZone(double lat, double lng) async {
    await _zonesLoaded;

    for (final z in _zones) {
      if (z.contains(lat, lng)) {
        return {
          'zone': z.type,
          'zoneName': z.name,
          'securityLevel': z.securityLevel,
          'requiresEmergencySms': z.requiresEmergencySms,
          'requiresPhotoVerification': z.requiresPhotoVerification,
          'verificationCount': z.verificationCount,
        };
      }
    }

    // If no zone matches, treat as rural for safety (fallback).
    return {
      'zone': 'rural',
      'zoneName': 'uncategorised_area',
      'securityLevel': 'high',
      'requiresEmergencySms': true,
      'requiresPhotoVerification': true,
      'verificationCount': 2,
    };
  }

  /// Whether the current IST hour falls in the night window (8pm-6am).
  bool isNightWindow() {
    final now = DateTime.now();
    final hour = now.hour;
    return hour >= AppConstants.nightStartHour ||
        hour < AppConstants.nightEndHour;
  }

  /// For rural jobs: periodically update location to Firebase every [intervalSeconds].
  /// Call this when a job is created in a rural zone to increase safety tracking.
  /// Returns a function to cancel the tracking (cleanup).
  ///
  /// NOTE: has no callers, and still writes to the Firestore `jobs` collection,
  /// which the app cannot write (no Firebase Auth session). Wiring this up for
  /// real needs a backend endpoint for crew position against a job — the
  /// existing ones are keyed on a request id
  /// (`/api/rescueRequests/<id>/mechanic-location`), not on the
  /// realtime-database job id used here.
  Function startRuralTracking({
    required String jobRole,
    required String jobId,
    required Stream<Position> positionStream,
    int intervalSeconds = 30,
  }) {
    // Cancel any existing tracking first.
    stopTracking();

    Position? last;

    // Subscribe to the incoming position stream and cache latest.
    _positionSub = positionStream.listen((pos) {
      last = pos;
      _firestore.collection('jobs').doc(jobId).set({
        'crewRole': jobRole,
        'location': {
          'lat': pos.latitude,
          'lng': pos.longitude,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        },
      }, SetOptions(merge: true));
    });

    // Timer to ensure updates at fixed interval (in case stream is sparse).
    _periodicTimer =
        Timer.periodic(Duration(seconds: intervalSeconds), (_) async {
      if (last != null) {
        await _firestore.collection('jobs').doc(jobId).set({
          'crewRole': jobRole,
          'location': {
            'lat': last!.latitude,
            'lng': last!.longitude,
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          },
        }, SetOptions(merge: true));
      }
    });

    _isTracking = true;

    return () {
      stopTracking();
    };
  }

  /// Stops all active tracking (position subscription and timer).
  void stopTracking() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _positionSub?.cancel();
    _positionSub = null;
    _isTracking = false;
  }

  /// Returns whether rural tracking is currently active.
  bool get isTracking => _isTracking;
}
