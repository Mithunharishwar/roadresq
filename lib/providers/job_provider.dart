// IMPORTANT: Set Firestore Rules to allow read/write for testing
/// RoadResQ Job Provider
/// Manages the lifecycle of a crew job (Mechanic or Assistant).
///
/// Tracks: pending → accepted → on_the_way → reached → completed → cancelled
/// Handles crew job acceptance, status updates, earnings tracking.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants/app_constants.dart';
import '../models/job_model.dart';
import '../services/firestore_service.dart';
import '../services/socket_service.dart';

/// ─── State ───
class JobState {
  final bool isLoading;
  final String? errorMessage;
  final List<JobModel> pendingJobs;
  final List<JobModel> activeJobs;
  final List<JobModel> completedJobs;
  final JobModel? currentJob;
  final double totalEarnings;

  const JobState({
    this.isLoading = false,
    this.errorMessage,
    this.pendingJobs = const [],
    this.activeJobs = const [],
    this.completedJobs = const [],
    this.currentJob,
    this.totalEarnings = 0.0,
  });

  JobState copyWith({
    bool? isLoading,
    String? errorMessage,
    List<JobModel>? pendingJobs,
    List<JobModel>? activeJobs,
    List<JobModel>? completedJobs,
    JobModel? currentJob,
    double? totalEarnings,
  }) {
    return JobState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      pendingJobs: pendingJobs ?? this.pendingJobs,
      activeJobs: activeJobs ?? this.activeJobs,
      completedJobs: completedJobs ?? this.completedJobs,
      currentJob: currentJob ?? this.currentJob,
      totalEarnings: totalEarnings ?? this.totalEarnings,
    );
  }
}

/// ─── Notifier ───
class JobNotifier extends StateNotifier<JobState> {
  final FirestoreService _firestore;
  final SocketService _socket;

  JobNotifier(this._firestore, this._socket) : super(const JobState());

  /// ─── Fetch all jobs for a crew member ───
  Future<void> fetchCrewJobs(String crewId) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final docs = await _firestore.queryDocuments(
        collection: AppConstants.collectionJobs,
        whereClauses: [
          WhereClause(field: 'crewId', isEqualTo: crewId),
        ],
        orderBy: 'createdAt',
        descending: true,
        limit: 50,
      );

      final allJobs = docs.map((doc) => JobModel.fromFirestore(doc)).toList();

      final pending = allJobs.where((j) => j.status == 'pending').toList();
      final active = allJobs
          .where((j) =>
              j.status == 'accepted' ||
              j.status == 'on_the_way' ||
              j.status == 'reached')
          .toList();
      final completed = allJobs
          .where((j) => j.status == 'completed' || j.status == 'cancelled')
          .toList();
      final earnings = completed
          .where((j) => j.status == 'completed')
          .fold<double>(0, (acc, j) => acc + j.earnings);

      state = state.copyWith(
        pendingJobs: pending,
        activeJobs: active,
        completedJobs: completed,
        totalEarnings: earnings,
        isLoading: false,
      );
    } on FirebaseException catch (e) {
      debugPrint(
          'JobNotifier.fetchCrewJobs FirebaseException: ${e.code} - ${e.message}');
      if (e.code == 'permission-denied') {
        debugPrint('PERMISSION_DENIED: Check Firestore Rules');
      }
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to fetch jobs: ${e.toString()}',
      );
    } catch (e) {
      debugPrint('JobNotifier.fetchCrewJobs error: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to fetch jobs: ${e.toString()}',
      );
    }
  }

  /// ─── Stream all jobs for a crew member (real-time, no timeout) ───
  Stream<List<JobModel>> streamCrewJobs(String crewId) {
    return _firestore
        .streamCollection(
          collection: AppConstants.collectionJobs,
          whereClauses: [
            WhereClause(field: 'crewId', isEqualTo: crewId),
          ],
          orderBy: 'createdAt',
          descending: true,
          limit: 50,
        )
        .map((snap) =>
            snap.docs.map((doc) => JobModel.fromFirestore(doc)).toList());
  }

  /// ─── Accept a job ───
  Future<void> acceptJob(String jobId) async {
    try {
      final now = DateTime.now();
      await _firestore.updateDocument(
        collection: AppConstants.collectionJobs,
        documentId: jobId,
        updates: {
          'status': 'accepted',
          'acceptedAt': Timestamp.fromDate(now),
          'updatedAt': Timestamp.fromDate(now),
        },
      );

      _socket.emit('accept_request', {
        'jobId': jobId,
        'status': 'accepted',
      });

      _updateLocalJobStatus(jobId, 'accepted');
    } catch (e) {
      debugPrint('JobNotifier.acceptJob error: $e');
      state =
          state.copyWith(errorMessage: 'Failed to accept job: ${e.toString()}');
    }
  }

  /// ─── Update job status (on_the_way, reached, completed) ───
  Future<void> updateJobStatus(String jobId, String status) async {
    try {
      final now = DateTime.now();
      final updates = <String, dynamic>{
        'status': status,
        'updatedAt': Timestamp.fromDate(now),
      };

      switch (status) {
        case 'on_the_way':
          updates['startedAt'] = Timestamp.fromDate(now);
          break;
        case 'reached':
          updates['reachedAt'] = Timestamp.fromDate(now);
          break;
        case 'completed':
          updates['completedAt'] = Timestamp.fromDate(now);
          break;
      }

      await _firestore.updateDocument(
        collection: AppConstants.collectionJobs,
        documentId: jobId,
        updates: updates,
      );

      _socket.emit('status_updated', {
        'jobId': jobId,
        'status': status,
      });

      _updateLocalJobStatus(jobId, status);
    } catch (e) {
      debugPrint('JobNotifier.updateJobStatus error: $e');
      state =
          state.copyWith(errorMessage: 'Failed to update job: ${e.toString()}');
    }
  }

  /// ─── Complete a job and set earnings ───
  Future<void> completeJob({
    required String jobId,
    required double earnings,
  }) async {
    try {
      final now = DateTime.now();
      await _firestore.updateDocument(
        collection: AppConstants.collectionJobs,
        documentId: jobId,
        updates: {
          'status': 'completed',
          'earnings': earnings,
          'completedAt': Timestamp.fromDate(now),
          'updatedAt': Timestamp.fromDate(now),
        },
      );

      _socket.emit('complete_request', {
        'jobId': jobId,
        'status': 'completed',
        'earnings': earnings,
      });

      _updateLocalJobStatus(jobId, 'completed');

      // Update total earnings
      final currentTotal = state.totalEarnings + earnings;
      state = state.copyWith(totalEarnings: currentTotal);
    } catch (e) {
      debugPrint('JobNotifier.completeJob error: $e');
      state = state.copyWith(
          errorMessage: 'Failed to complete job: ${e.toString()}');
    }
  }

  /// ─── Cancel a job ───
  Future<void> cancelJob({
    required String jobId,
    String? reason,
    String? cancelledBy,
  }) async {
    try {
      await _firestore.updateDocument(
        collection: AppConstants.collectionJobs,
        documentId: jobId,
        updates: {
          'status': 'cancelled',
          'cancellationReason': reason ?? 'Cancelled',
          'cancelledBy': cancelledBy ?? 'crew',
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        },
      );

      _updateLocalJobStatus(jobId, 'cancelled');
    } catch (e) {
      debugPrint('JobNotifier.cancelJob error: $e');
      state =
          state.copyWith(errorMessage: 'Failed to cancel job: ${e.toString()}');
    }
  }

  /// ─── Update local state after status change ───
  void _updateLocalJobStatus(String jobId, String newStatus) {
    final allPending = [...state.pendingJobs];
    final allActive = [...state.activeJobs];
    final allCompleted = [...state.completedJobs];

    // Find and move job between lists
    JobModel? job;

    final pendingIdx = allPending.indexWhere((j) => j.id == jobId);
    if (pendingIdx != -1) {
      job = allPending.removeAt(pendingIdx);
    }

    final activeIdx = allActive.indexWhere((j) => j.id == jobId);
    if (activeIdx != -1) {
      job = allActive.removeAt(activeIdx);
    }

    if (job != null) {
      final updated = job.copyWith(status: newStatus);

      if (newStatus == 'completed' || newStatus == 'cancelled') {
        allCompleted.add(updated);
      } else if (newStatus == 'accepted' ||
          newStatus == 'on_the_way' ||
          newStatus == 'reached') {
        allActive.add(updated);
      } else {
        allPending.add(updated);
      }
    }

    state = state.copyWith(
      pendingJobs: allPending,
      activeJobs: allActive,
      completedJobs: allCompleted,
      currentJob: state.currentJob?.id == jobId
          ? (job?.copyWith(status: newStatus) ?? state.currentJob)
          : state.currentJob,
    );
  }

  /// ─── Set the currently viewed job ───
  void setCurrentJob(JobModel job) {
    state = state.copyWith(currentJob: job);
  }

  /// Reset state
  void reset() {
    state = const JobState();
  }
}

/// ─── Provider ───
final jobProvider = StateNotifierProvider<JobNotifier, JobState>(
  (ref) {
    return JobNotifier(FirestoreService(), SocketService());
  },
);
