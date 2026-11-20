import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/geohash.dart';

/// MatchingService — Client for the 2-Man Matching engine.
///
/// Two responsibilities:
/// 1. `persistCrewGeohash` — Writes the crew's `geohash` field to Firestore
///    so the Cloud Function can use geohash prefix queries for proximity matching.
/// 2. `dispatchTwoManCrew` — Invokes the `dispatchTwoManCrew` Cloud Function
///    which finds 1 mechanic + 1 assistant within 10km using geohash.
///
/// The persistence is done client-side (matching the Dart Geohash encoder)
/// AND enforced server-side via the `onCrewLocationUpdate` Firestore trigger.
class MatchingService {
  MatchingService._internal();
  static final MatchingService _instance = MatchingService._internal();
  factory MatchingService() => _instance;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// Persist the geohash for a crew's current location.
  ///
  /// Geohash precision is chosen to cover a ~10km cell (precision 5 ≈ 4.9km),
  /// matching the cloud function's search precision for the 10km radius.
  Future<bool> persistCrewGeohash({
    required String crewId,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final geohash = Geohash.encode(
        latitude: latitude,
        longitude: longitude,
        precision: 7, // ~153m cell — good for live location
      );

      await _firestore
          .collection(AppConstants.collectionCrews)
          .doc(crewId)
          .update({
        'geohash': geohash,
        'currentLocation': GeoPoint(latitude, longitude),
        'geohashPrecision': 7,
        'locationUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      debugPrint('MatchingService.persistCrewGeohash error: $e');
      return false;
    }
  }

  /// Invoke the 2-Man matching Cloud Function.
  ///
  /// Finds 1 mechanic + 1 assistant near [userLat]/[userLng] within
  /// the configured matching radius (default 10km) and creates jobs.
  Future<Map<String, dynamic>> dispatchTwoManCrew({
    required String userId,
    required double userLat,
    required double userLng,
    required String requestId,
    String? userZone,
    double radiusKm = AppConstants.maxCrewRadiusKm,
  }) async {
    try {
      final result = await _functions.httpsCallable('dispatchTwoManCrew').call({
        'userId': userId,
        'userLat': userLat,
        'userLng': userLng,
        'requestId': requestId,
        'userZone': userZone ?? '',
        'radiusKm': radiusKm,
      });

      final data = result.data;
      if (data is Map<String, dynamic>) {
        return data;
      }
      return {'success': false, 'message': 'Unexpected response format'};
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
          'MatchingService.dispatchTwoManCrew error: ${e.code} - ${e.message}');
      return {
        'success': false,
        'message': e.message ?? 'Dispatch failed',
        'code': e.code,
      };
    } catch (e) {
      debugPrint('MatchingService.dispatchTwoManCrew error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }
}
