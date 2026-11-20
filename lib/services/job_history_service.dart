// IMPORTANT: Set Firestore Rules to allow read/write for testing
// FILE: lib/services/job_history_service.dart
/// JobHistoryService — Past jobs listing for a user.
///
/// Implements: viewJobHistory(userId)
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../core/constants/app_constants.dart';

/// A past job history entry.
class JobHistoryItem {
  final String jobId;
  final String status;
  final DateTime? createdAt;
  final double earnings;
  final String issue;
  final String vehicle;

  const JobHistoryItem({
    required this.jobId,
    required this.status,
    this.createdAt,
    this.earnings = 0,
    this.issue = '',
    this.vehicle = '',
  });
}

class JobHistoryService {
  JobHistoryService._internal();
  static final JobHistoryService _instance = JobHistoryService._internal();
  factory JobHistoryService() => _instance;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// viewJobHistory(userId) — fetch past jobs for a user.
  Future<List<JobHistoryItem>> viewJobHistory({
    required String userId,
    int limit = 50,
  }) async {
    try {
      final snap = await _firestore
          .collection(AppConstants.collectionJobs)
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      return snap.docs.map((d) {
        final data = Map<String, dynamic>.from(d.data() as Map);
        final ts = data['createdAt'];
        return JobHistoryItem(
          jobId: d.id,
          status: data['status'] ?? 'pending',
          createdAt: ts is Timestamp ? ts.toDate() : null,
          earnings: (data['earnings'] ?? 0).toDouble(),
          issue: data['issue'] ?? '',
          vehicle: data['vehicle'] ?? '',
        );
      }).toList();
    } on FirebaseException catch (e) {
      debugPrint(
          'JobHistoryService.viewJobHistory FirebaseException: ${e.code} - ${e.message}');
      if (e.code == 'permission-denied') {
        debugPrint('PERMISSION_DENIED: Check Firestore Rules');
      }
      return [];
    } catch (e) {
      debugPrint('JobHistoryService.viewJobHistory error: $e');
      return [];
    }
  }

  /// viewJobHistoryStream(userId) — real-time job history stream.
  Stream<List<JobHistoryItem>> viewJobHistoryStream({
    required String userId,
    int limit = 50,
  }) {
    return _firestore
        .collection(AppConstants.collectionJobs)
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final data = Map<String, dynamic>.from(d.data() as Map);
              final ts = data['createdAt'];
              return JobHistoryItem(
                jobId: d.id,
                status: data['status'] ?? 'pending',
                createdAt: ts is Timestamp ? ts.toDate() : null,
                earnings: (data['earnings'] ?? 0).toDouble(),
                issue: data['issue'] ?? '',
                vehicle: data['vehicle'] ?? '',
              );
            }).toList());
  }
}
