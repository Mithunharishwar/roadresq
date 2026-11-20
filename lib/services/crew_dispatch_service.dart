import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

/// CrewDispatchService
/// - Implements 2-man dispatch: one mechanic + one assistant
/// - Creates jobs under `jobs/mechanic/{jobId}` and `jobs/assistant/{jobId}`
/// - Finds nearest available crew members by scanning `crews/` snapshot
/// - Calculates ETA based on straight-line distance and an assumed average speed
class CrewDispatchService {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  final Uuid _uuid = const Uuid();

  // Average speed m/s for ETA calc (e.g., 40 km/h => 11.11 m/s)
  static const double _avgSpeedMetersPerSec = 11.11;

  /// Dispatch flow:
  /// - Finds nearest mechanic and assistant
  /// - Creates separate job entries for each
  /// - Returns a jobGroupId to correlate the pair
  Future<String> dispatchTwoManCrew({
    required String userId,
    required double lat,
    required double lng,
    required String requestId,
    Map<String, dynamic>? meta,
  }) async {
    final jobGroupId = _uuid.v4();

    // Find nearest mechanic & assistant
    final mechanic =
        await _findNearestCrewMember(role: 'mechanic', lat: lat, lng: lng);
    final assistant =
        await _findNearestCrewMember(role: 'assistant', lat: lat, lng: lng);

    final now = DateTime.now().toUtc().toIso8601String();

    // Build job payload
    Future<void> createJob(String role, Map<String, dynamic>? crew) async {
      final jobId = _uuid.v4();
      final crewId = crew?['id'] ?? '';
      final distanceMeters = crew?['distanceMeters'] as double?;
      final etaSec =
          (distanceMeters != null) ? _estimateEtaSeconds(distanceMeters) : 0;

      final job = {
        'jobId': jobId,
        'groupId': jobGroupId,
        'role': role,
        'userId': userId,
        'requestId': requestId,
        'crewId': crewId,
        'crewMeta': crew ?? {},
        'status':
            'pending', // pending -> accepted -> on_the_way -> reached -> completed -> paid
        'createdAt': now,
        'assignedAt': now,
        'etaSec': etaSec,
        'meta': meta ?? {},
        'pickupLocation': {
          'lat': lat,
          'lng': lng,
        },
      };

      await _db.child('jobs/$role/$jobId').set(job);

      // Also create an entry under jobs/group for correlation & UI
      await _db
          .child('jobs/group/$jobGroupId/$role')
          .set({'jobId': jobId, 'crewId': crewId});
    }

    await createJob('mechanic', mechanic);
    await createJob('assistant', assistant);

    return jobGroupId;
  }

  /// Find nearest available crew member of given role by scanning /crews
  /// Expects `crews/{crewId}` nodes with fields: {id, role, location: {lat,lng}, status: 'available'|'busy'}
  Future<Map<String, dynamic>?> _findNearestCrewMember({
    required String role,
    required double lat,
    required double lng,
  }) async {
    final snapshot = await _db.child('crews').get();
    if (!snapshot.exists) return null;

    Map<String, dynamic>? best;
    double? bestDist;

    final data = Map<String, dynamic>.from(snapshot.value as Map);
    data.forEach((key, value) {
      final v = Map<String, dynamic>.from(value as Map);
      if (v['role'] != role) return;
      final status = v['status'] ?? 'available';
      if (status != 'available') return;

      final loc = v['location'] as Map<String, dynamic>?;
      if (loc == null) return;
      final crewLat = (loc['lat'] is num)
          ? (loc['lat'] as num).toDouble()
          : double.tryParse(loc['lat'].toString()) ?? 0.0;
      final crewLng = (loc['lng'] is num)
          ? (loc['lng'] as num).toDouble()
          : double.tryParse(loc['lng'].toString()) ?? 0.0;

      final d = Geolocator.distanceBetween(lat, lng, crewLat, crewLng);
      if (bestDist == null || d < bestDist!) {
        bestDist = d;
        best = {
          'id': key.toString(),
          'role': role,
          'status': status,
          'location': {'lat': crewLat, 'lng': crewLng},
          'distanceMeters': d,
          'name': v['name'] ?? '',
          'rating': v['rating'] ?? 0,
        };
      }
    });

    return best;
  }

  /// Estimate ETA seconds from distance (m) and average speed
  int _estimateEtaSeconds(double distanceMeters) {
    final seconds = distanceMeters / _avgSpeedMetersPerSec;
    return seconds.ceil();
  }

  /// Helper: crew accepts a job — mark job status as accepted and set acceptedAt
  Future<void> acceptJob(
      {required String role,
      required String jobId,
      required String crewId}) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.child('jobs/$role/$jobId').update({
      'status': 'accepted',
      'crewId': crewId,
      'acceptedAt': now,
    });
  }

  /// Update job status flow: on_the_way, reached, completed
  Future<void> updateJobStatus(
      {required String role,
      required String jobId,
      required String status}) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.child('jobs/$role/$jobId').update({
      'status': status,
      'updatedAt': now,
    });
  }
}
