// IMPORTANT: Set Firestore Rules to allow read/write for testing
// FILE: lib/services/admin_service.dart
/// AdminService — Admin Module
///
/// Implements the spec functions:
///   - getDashboardStats()   → active jobs, revenue, crew online
///   - banUser(userId) / banCrew(crewId)
///   - manageZones()         → add/remove urban/rural polygons
///   - viewAllJobs()         → filter by status
///   - manualAssignJob(jobId, crewIds) → override matching
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../core/constants/app_constants.dart';

/// A dashboard stats snapshot.
class DashboardStats {
  final int activeJobs;
  final int pendingJobs;
  final int completedJobs;
  final double revenue;
  final int crewOnline;
  final int mechanics;
  final int assistants;

  const DashboardStats({
    this.activeJobs = 0,
    this.pendingJobs = 0,
    this.completedJobs = 0,
    this.revenue = 0,
    this.crewOnline = 0,
    this.mechanics = 0,
    this.assistants = 0,
  });
}

/// Admin service.
class AdminService {
  AdminService._internal();
  static final AdminService _instance = AdminService._internal();
  factory AdminService() => _instance;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// getDashboardStats — aggregate active jobs, revenue, crew online.
  Future<DashboardStats> getDashboardStats() async {
    try {
      final jobsSnap = await _firestore
          .collection(AppConstants.collectionJobs)
          .limit(500) // bounded sample for dashboard
          .get();

      int active = 0, pending = 0, completed = 0;
      double revenue = 0;
      for (final doc in jobsSnap.docs) {
        final data = Map<String, dynamic>.from(doc.data() as Map);
        final status = (data['status'] ?? '').toString();
        if (status == 'completed') {
          completed++;
          revenue += (data['earnings'] ?? 0).toDouble();
        } else if (status == 'pending' || status == 'assigned') {
          pending++;
          active++;
        }
      }

      // Crew online count (mechanic + assistant roles).
      final crewsSnap = await _firestore
          .collection(AppConstants.collectionCrews)
          .where('isOnline', isEqualTo: true)
          .get();
      int mech = 0, asst = 0;
      for (final doc in crewsSnap.docs) {
        final data = Map<String, dynamic>.from(doc.data() as Map);
        final role = (data['role'] ?? '').toString();
        if (role == 'mechanic') mech++;
        if (role == 'assistant') asst++;
      }

      return DashboardStats(
        activeJobs: active,
        pendingJobs: pending,
        completedJobs: completed,
        revenue: revenue,
        crewOnline: mech + asst,
        mechanics: mech,
        assistants: asst,
      );
    } on FirebaseException catch (e) {
      debugPrint(
          'AdminService.getDashboardStats FirebaseException: ${e.code} - ${e.message}');
      if (e.code == 'permission-denied') {
        debugPrint('PERMISSION_DENIED: Check Firestore Rules');
      }
      return const DashboardStats();
    } catch (e) {
      debugPrint('AdminService.getDashboardStats error: $e');
      return const DashboardStats();
    }
  }

  /// getDashboardStatsStream — real-time dashboard stats stream.
  Stream<DashboardStats> getDashboardStatsStream() {
    return _firestore
        .collection(AppConstants.collectionJobs)
        .limit(500)
        .snapshots()
        .map((jobsSnap) {
      int active = 0, pending = 0, completed = 0;
      double revenue = 0;
      for (final doc in jobsSnap.docs) {
        final data = Map<String, dynamic>.from(doc.data() as Map);
        final status = (data['status'] ?? '').toString();
        if (status == 'completed') {
          completed++;
          revenue += (data['earnings'] ?? 0).toDouble();
        } else if (status == 'pending' || status == 'assigned') {
          pending++;
          active++;
        }
      }
      return DashboardStats(
        activeJobs: active,
        pendingJobs: pending,
        completedJobs: completed,
        revenue: revenue,
      );
    });
  }

  /// banUser(userId) — set user banned flag.
  Future<bool> banUser({required String userId, bool banned = true}) async {
    try {
      await _firestore
          .collection(AppConstants.collectionUsers)
          .doc(userId)
          .update({
        'isBanned': banned,
        'bannedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } on FirebaseException catch (e) {
      debugPrint(
          'AdminService.banUser FirebaseException: ${e.code} - ${e.message}');
      if (e.code == 'permission-denied') {
        debugPrint('PERMISSION_DENIED: Check Firestore Rules');
      }
      return false;
    } catch (e) {
      debugPrint('AdminService.banUser error: $e');
      return false;
    }
  }

  /// banCrew(crewId) — set crew banned + force offline.
  Future<bool> banCrew({required String crewId, bool banned = true}) async {
    try {
      await _firestore
          .collection(AppConstants.collectionCrews)
          .doc(crewId)
          .set({
        'isBanned': banned,
        'isOnline': !banned,
        'bannedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return true;
    } on FirebaseException catch (e) {
      debugPrint(
          'AdminService.banCrew FirebaseException: ${e.code} - ${e.message}');
      if (e.code == 'permission-denied') {
        debugPrint('PERMISSION_DENIED: Check Firestore Rules');
      }
      return false;
    } catch (e) {
      debugPrint('AdminService.banCrew error: $e');
      return false;
    }
  }

  /// manageZones — add a zone polygon (urban/rural).
  Future<Map<String, dynamic>> addZone({
    required String name,
    required String type, // urban | rural
    required double latMin,
    required double latMax,
    required double lngMin,
    required double lngMax,
  }) async {
    try {
      final docRef = _firestore.collection(AppConstants.collectionZones).doc();
      await docRef.set({
        'name': name,
        'type': type,
        'latMin': latMin,
        'latMax': latMax,
        'lngMin': lngMin,
        'lngMax': lngMax,
        'securityLevel': type == 'rural' ? 'high' : 'standard',
        'requiresEmergencySms': type == 'rural',
        'createdAt': FieldValue.serverTimestamp(),
      });
      return {'success': true, 'zoneId': docRef.id};
    } on FirebaseException catch (e) {
      debugPrint(
          'AdminService.addZone FirebaseException: ${e.code} - ${e.message}');
      if (e.code == 'permission-denied') {
        debugPrint('PERMISSION_DENIED: Check Firestore Rules');
      }
      return {'success': false};
    } catch (e) {
      debugPrint('AdminService.addZone error: $e');
      return {'success': false};
    }
  }

  /// removeZone(zoneId) — delete a zone polygon.
  Future<bool> removeZone({required String zoneId}) async {
    try {
      await _firestore
          .collection(AppConstants.collectionZones)
          .doc(zoneId)
          .delete();
      return true;
    } on FirebaseException catch (e) {
      debugPrint(
          'AdminService.removeZone FirebaseException: ${e.code} - ${e.message}');
      if (e.code == 'permission-denied') {
        debugPrint('PERMISSION_DENIED: Check Firestore Rules');
      }
      return false;
    } catch (e) {
      debugPrint('AdminService.removeZone error: $e');
      return false;
    }
  }

  /// viewAllJobs — filter by status (optional).
  Future<List<Map<String, dynamic>>> viewAllJobs({String? status}) async {
    try {
      Query q = _firestore.collection(AppConstants.collectionJobs);
      if (status != null && status.isNotEmpty && status != 'all') {
        q = q.where('status', isEqualTo: status);
      }
      final snap =
          await q.orderBy('createdAt', descending: true).limit(200).get();
      return snap.docs.map((d) {
        final data = Map<String, dynamic>.from(d.data() as Map);
        return {
          'jobId': d.id,
          'requestId': data['requestId'] ?? '',
          'crewId': data['crewId'] ?? '',
          'crewRole': data['crewRole'] ?? '',
          'userId': data['userId'] ?? '',
          'status': data['status'] ?? 'pending',
          'earnings': (data['earnings'] ?? 0).toDouble(),
        };
      }).toList();
    } on FirebaseException catch (e) {
      debugPrint(
          'AdminService.viewAllJobs FirebaseException: ${e.code} - ${e.message}');
      if (e.code == 'permission-denied') {
        debugPrint('PERMISSION_DENIED: Check Firestore Rules');
      }
      return [];
    } catch (e) {
      debugPrint('AdminService.viewAllJobs error: $e');
      return [];
    }
  }

  /// viewAllJobsStream — real-time jobs list stream.
  Stream<List<Map<String, dynamic>>> viewAllJobsStream({String? status}) {
    Query q = _firestore.collection(AppConstants.collectionJobs);
    if (status != null && status.isNotEmpty && status != 'all') {
      q = q.where('status', isEqualTo: status);
    }
    return q
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final data = Map<String, dynamic>.from(d.data() as Map);
              return {
                'jobId': d.id,
                'requestId': data['requestId'] ?? '',
                'crewId': data['crewId'] ?? '',
                'crewRole': data['crewRole'] ?? '',
                'userId': data['userId'] ?? '',
                'status': data['status'] ?? 'pending',
                'earnings': (data['earnings'] ?? 0).toDouble(),
              };
            }).toList());
  }

  /// manualAssignJob(jobId, crewIds) — override matching via Cloud Function.
  Future<Map<String, dynamic>> manualAssignJob({
    required String jobId,
    String? mechanicCrewId,
    String? assistantCrewId,
  }) async {
    try {
      final result = await _functions.httpsCallable('manualAssignJob').call({
        'jobId': jobId,
        'mechanicCrewId': mechanicCrewId ?? '',
        'assistantCrewId': assistantCrewId ?? '',
      });
      final data = result.data as Map<String, dynamic>;
      return {
        'success': data['success'] == true,
        'message': data['message'] ?? '',
      };
    } catch (e) {
      debugPrint('AdminService.manualAssignJob error: $e');
      return {'success': false, 'message': 'Manual assign failed'};
    }
  }
}
