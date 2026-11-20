/// Community Safety Mesh — Crowd-Sourced Rescue Layer Service (novel module).
///
/// Maintains verified community helpers (safety-vouched bystanders) as a
/// fallback rescue layer and manages emergency beacon broadcasts to nearby
/// helpers + family + admin.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../models/novel/community_helper_model.dart';

class CommunityMeshService {
  CommunityMeshService._internal();
  static final CommunityMeshService _instance =
      CommunityMeshService._internal();
  factory CommunityMeshService() => _instance;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// ─── Find nearby verified & available helpers ───
  Future<List<CommunityHelper>> findNearbyHelpers({
    required double lat,
    required double lng,
    double radiusKm = 5,
    int limit = 10,
  }) async {
    try {
      final snap = await _firestore
          .collection('community_helpers')
          .where('isVerified', isEqualTo: true)
          .where('isAvailable', isEqualTo: true)
          .limit(50)
          .get();

      final helpers = <CommunityHelper>[];
      for (final doc in snap.docs) {
        final h = CommunityHelper.fromJson(
            Map<String, dynamic>.from(doc.data() as Map));
        final id = doc.id;
        final helper = CommunityHelper(
          id: id,
          name: h.name,
          phone: h.phone,
          photoUrl: h.photoUrl,
          lat: h.lat,
          lng: h.lng,
          isAvailable: h.isAvailable,
          isVerified: h.isVerified,
          vouchesReceived: h.vouchesReceived,
          responseScore: h.responseScore,
          skills: h.skills,
        );
        final d = _distanceKm(lat, lng, helper.lat, helper.lng);
        if (d <= radiusKm) helpers.add(helper);
      }
      helpers.sort((a, b) => b.responseScore.compareTo(a.responseScore));
      return helpers.take(limit).toList();
    } catch (e) {
      debugPrint('CommunityMeshService.findNearbyHelpers error: $e');
      return [];
    }
  }

  /// ─── Broadcast an emergency beacon ───
  Future<Map<String, dynamic>> broadcastBeacon({
    required String userId,
    required String userName,
    required String userPhone,
    required double lat,
    required double lng,
    String message = '',
    List<String> familyIds = const [],
  }) async {
    try {
      final helpers = await findNearbyHelpers(lat: lat, lng: lng);
      final beacon = EmergencyBeacon(
        userId: userId,
        userName: userName,
        userPhone: userPhone,
        lat: lat,
        lng: lng,
        message: message.isEmpty
            ? 'Emergency! Roadside assistance needed at my location.'
            : message,
        notifiedHelperIds: helpers.map((h) => h.id).toList(),
        notifiedFamilyIds: familyIds,
      );

      final ref = await _firestore.collection('emergency_beacons').add({
        'userId': userId,
        'userName': userName,
        'userPhone': userPhone,
        'lat': lat,
        'lng': lng,
        'message': beacon.message,
        'status': 'active',
        'notifiedHelperIds': beacon.notifiedHelperIds,
        'notifiedFamilyIds': beacon.notifiedFamilyIds,
        'createdAt': FieldValue.serverTimestamp(),
      });

      return {
        'success': true,
        'beaconId': ref.id,
        'helpersNotified': helpers.length,
      };
    } catch (e) {
      debugPrint('CommunityMeshService.broadcastBeacon error: $e');
      return {'success': false, 'beaconId': '', 'helpersNotified': 0};
    }
  }

  /// ─── Update beacon status ───
  Future<bool> resolveBeacon(String beaconId, String status) async {
    try {
      await _firestore.collection('emergency_beacons').doc(beaconId).update({
        'status': status,
        'resolvedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('CommunityMeshService.resolveBeacon error: $e');
      return false;
    }
  }

  /// ─── Register / update a community helper ───
  Future<bool> upsertHelper(CommunityHelper helper) async {
    try {
      await _firestore
          .collection('community_helpers')
          .doc(helper.id.isEmpty ? helper.phone : helper.id)
          .set(helper.toJson(), SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('CommunityMeshService.upsertHelper error: $e');
      return false;
    }
  }

  double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
    // Haversine distance in km.
    const R = 6371.0;
    final p = 0.017453292519943295; // pi / 180
    final dLat = (lat2 - lat1) * p;
    final dLng = (lng2 - lng1) * p;
    final a = (dLat / 2) * (dLat / 2) +
        _cosV(lat1 * p) * _cosV(lat2 * p) * (dLng / 2) * (dLng / 2);
    return R * 2 * _atanSq(a);
  }

  double _cosV(double x) => 1 - x * x / 2 + x * x * x * x / 24;

  /// Approximate 2 * asin(sqrt(a)).
  double _atanSq(double a) {
    final s = a < 0 || a > 1 ? 0.0 : a;
    final c = 1 - s;
    final y = _sqrtV(s);
    final x = _sqrtV(c);
    if (x == 0) return y > 0 ? 1.5707963267948966 : -1.5707963267948966;
    final r = y / x;
    final t = r / (1 + 0.28 * r * r);
    return x < 0 ? t + 3.141592653589793 : t;
  }

  double _sqrtV(double x) {
    if (x <= 0) return 0;
    double g = x;
    for (int i = 0; i < 6; i++) {
      g = (g + x / g) / 2;
    }
    return g;
  }
}
