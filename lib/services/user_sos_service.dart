// IMPORTANT: Set Firestore Rules to allow read/write for testing
// FILE: lib/services/user_sos_service.dart
/// UserSosService — User App Module.
///
/// Implements the spec functions:
///   - getCurrentLocation()            → GPS lat, lng, address
///   - createSOS(issue, vehicleDetails) → creates job doc with status "pending"
///   - cancelSOS(jobId)               → cancel within 2 min, else penalty
///   - getJobStatusStream(jobId)       → real-time status updates
///   - trackCrewLive(jobId)            → shows 2 crew markers on map
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../core/constants/app_constants.dart';
import 'core_util_service.dart';
import 'location_service.dart';
import 'live_tracking_service.dart';
import 'sos_security_service.dart';

/// Result of location lookup.
class LocationInfo {
  final double lat;
  final double lng;
  final String address;

  const LocationInfo({
    required this.lat,
    required this.lng,
    this.address = '',
  });
}

class UserSosService {
  UserSosService._internal();
  static final UserSosService _instance = UserSosService._internal();
  factory UserSosService() => _instance;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LocationService _locationService = LocationService();
  final LiveTrackingService _liveTracking = LiveTrackingService();

  /// getCurrentLocation() — get GPS lat, lng, address.
  Future<LocationInfo?> getCurrentLocation() async {
    final position = await _locationService.getCurrentPosition();
    if (position == null) return null;
    return LocationInfo(
      lat: position.latitude,
      lng: position.longitude,
      address:
          '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
    );
  }

  /// createSOS(issue, vehicleDetails) — creates a job with status "pending".
  Future<Map<String, dynamic>> createSOS({
    required String userId,
    required String issue,
    Map<String, dynamic>? vehicleDetails,
    double? lat,
    double? lng,
    String? userPhone,
  }) async {
    try {
      final jobRef = _firestore.collection(AppConstants.collectionJobs).doc();
      await jobRef.set({
        'userId': userId,
        'userPhone': userPhone ?? '',
        'issue': issue,
        'vehicle': vehicleDetails?['number'] ?? '',
        'vehicleType': vehicleDetails?['type'] ?? '',
        'status': 'pending',
        'pickupLocation':
            lat != null && lng != null ? GeoPoint(lat, lng) : null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return {
        'success': true,
        'jobId': jobRef.id,
        'status': 'pending',
      };
    } catch (e) {
      debugPrint('UserSosService.createSOS error: $e');
      return {'success': false, 'jobId': '', 'message': e.toString()};
    }
  }

  /// cancelSOS(jobId) — cancel within 2 min else penalty.
  Future<Map<String, dynamic>> cancelSOS({
    required String jobId,
    String? reason,
  }) async {
    try {
      final doc = await _firestore
          .collection(AppConstants.collectionJobs)
          .doc(jobId)
          .get();
      if (!doc.exists) {
        return {'success': false, 'message': 'Job not found'};
      }
      final data = Map<String, dynamic>.from(doc.data() as Map);
      final createdAt = data['createdAt'];
      final createdTime =
          createdAt is Timestamp ? createdAt.toDate() : DateTime.now();
      final ageMinutes = DateTime.now().difference(createdTime).inMinutes;

      if (ageMinutes <= 2) {
        await _firestore
            .collection(AppConstants.collectionJobs)
            .doc(jobId)
            .update({
          'status': 'cancelled',
          'cancelReason': reason ?? 'cancelled',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return {'success': true, 'penalty': false, 'message': 'SOS cancelled'};
      }

      // Late cancel → penalty via Cloud Function.
      final penalty = await SosSecurityService().cancelSosWithPenalty(
        requestId: jobId,
        reason: reason,
      );
      return {'success': true, 'penalty': true, ...penalty};
    } on FirebaseException catch (e) {
      debugPrint(
          'UserSosService.cancelSOS FirebaseException: ${e.code} - ${e.message}');
      if (e.code == 'permission-denied') {
        debugPrint('PERMISSION_DENIED: Check Firestore Rules');
      }
      return {'success': false, 'message': 'Failed to cancel'};
    } catch (e) {
      debugPrint('UserSosService.cancelSOS error: $e');
      return {'success': false, 'message': 'Failed to cancel'};
    }
  }

  /// getJobStatusStream(jobId) — real-time status updates.
  Stream<DocumentSnapshot> getJobStatusStream(String jobId) {
    return _firestore
        .collection(AppConstants.collectionJobs)
        .doc(jobId)
        .snapshots();
  }

  /// trackCrewLive(jobId) — start live tracking of 2 crew markers.
  void trackCrewLive({required String jobId}) {
    _liveTracking.startTracking(requestId: jobId);
  }

  /// Stop live tracking of crew.
  void stopTracking() {
    _liveTracking.stopTracking();
  }

  /// Expose the live-tracking updates stream (user tracking screen listens).
  Stream<LiveTrackingUpdate> get liveTrackingUpdates => _liveTracking.updates;

  /// Haversine distance helper (delegates to util).
  static double distanceKm(double lat1, double lng1, double lat2, double lng2) {
    return CoreUtilService.calculateDistance(lat1, lng1, lat2, lng2);
  }
}
