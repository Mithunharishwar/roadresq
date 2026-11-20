/// RoadResQ Dispatch Provider
/// Core Patent: 2-Man Crew Dispatch System with Weighted Matching Algorithm
///
/// Manages the entire dispatch lifecycle:
/// 1. Finds nearest mechanic + assistant within 5km radius
/// 2. Weighted scoring: Distance (40%) + Rating (25%) + Active Status (20%) + Zone (15%)
/// 3. Creates job records for both crew members
/// 4. Handles timeouts, escalation, and backup crew dispatch
library;

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants/app_constants.dart';
import '../models/crew_model.dart';
import '../services/firestore_service.dart';
import '../services/matching_service.dart';
import '../services/offline_queue_service.dart';
import '../services/socket_service.dart';

/// ─── State ───
class DispatchState {
  final bool isLoading;
  final String? errorMessage;
  final String? jobGroupId;
  final CrewModel? assignedMechanic;
  final CrewModel? assignedAssistant;
  final String? requestId;
  final double mechanicEtaMinutes;
  final double assistantEtaMinutes;
  final bool isSearching;
  final bool isEscalated;
  final int searchElapsedSeconds;

  const DispatchState({
    this.isLoading = false,
    this.errorMessage,
    this.jobGroupId,
    this.assignedMechanic,
    this.assignedAssistant,
    this.requestId,
    this.mechanicEtaMinutes = 0,
    this.assistantEtaMinutes = 0,
    this.isSearching = false,
    this.isEscalated = false,
    this.searchElapsedSeconds = 0,
  });

  DispatchState copyWith({
    bool? isLoading,
    String? errorMessage,
    String? jobGroupId,
    CrewModel? assignedMechanic,
    CrewModel? assignedAssistant,
    String? requestId,
    double? mechanicEtaMinutes,
    double? assistantEtaMinutes,
    bool? isSearching,
    bool? isEscalated,
    int? searchElapsedSeconds,
  }) {
    return DispatchState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      jobGroupId: jobGroupId ?? this.jobGroupId,
      assignedMechanic: assignedMechanic ?? this.assignedMechanic,
      assignedAssistant: assignedAssistant ?? this.assignedAssistant,
      requestId: requestId ?? this.requestId,
      mechanicEtaMinutes: mechanicEtaMinutes ?? this.mechanicEtaMinutes,
      assistantEtaMinutes: assistantEtaMinutes ?? this.assistantEtaMinutes,
      isSearching: isSearching ?? this.isSearching,
      isEscalated: isEscalated ?? this.isEscalated,
      searchElapsedSeconds: searchElapsedSeconds ?? this.searchElapsedSeconds,
    );
  }
}

/// ─── Notifier ───
class DispatchNotifier extends StateNotifier<DispatchState> {
  final FirestoreService _firestore;
  final SocketService _socket;
  Timer? _searchTimer;
  int _elapsed = 0;

  DispatchNotifier(this._firestore, this._socket)
      : super(const DispatchState());

  @override
  void dispose() {
    _searchTimer?.cancel();
    super.dispose();
  }

  /// ─── MAIN ENTRY POINT: Dispatch 2-Man Crew ───
  ///
  /// Patent: Simultaneous dispatch of Mechanic + Assistant for a single SOS.
  /// Algorithm: Weighted scoring using Distance + Rating + Active + Zone.
  Future<void> dispatchTwoManCrew({
    required String userId,
    required double userLat,
    required double userLng,
    required String requestId,
    String? userZone,
  }) async {
    state = state.copyWith(
      isLoading: true,
      errorMessage: null,
      requestId: requestId,
      isSearching: true,
      searchElapsedSeconds: 0,
    );

    _elapsed = 0;
    _searchTimer?.cancel();
    _searchTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsed++;
      state = state.copyWith(searchElapsedSeconds: _elapsed);

      // Timeout after 5 minutes → escalate to admin + backup crews
      if (_elapsed >= AppConstants.sosTimeoutSeconds) {
        _escalateRequest(requestId);
      }
    });

    try {
      // Step 1: Invoke the geohash-based 2-Man matching Cloud Function.
      // The backend finds 1 mechanic + 1 assistant within 10km using geohash
      // prefix queries, creates jobs, marks crews busy, and updates the request.
      final result = await MatchingService().dispatchTwoManCrew(
        userId: userId,
        userLat: userLat,
        userLng: userLng,
        requestId: requestId,
        userZone: userZone,
      );

// If the cloud function reported no crews found, escalate.
      if ((result['success'] ?? false) == false) {
        _searchTimer?.cancel();
        state = state.copyWith(
          isLoading: false,
          isSearching: false,
          errorMessage: result['message']?.toString() ?? 'No crew found nearby',
        );

        // FEATURE 5: Queue the offline job so it can be delivered via FCM
        // when any crew member for the required role comes back online.
        _queueOfflineJobForMissingCrews(
          requestId: requestId,
          userLat: userLat,
          userLng: userLng,
          userZone: userZone,
          mechanic: result['mechanic'],
          assistant: result['assistant'],
        );

        _escalateRequest(requestId);
        return;
      }

      final jobGroupId =
          result['jobGroupId']?.toString() ?? _generateJobGroupId();
      final mechanicId = result['mechanic']?['id']?.toString() ?? '';
      final assistantId = result['assistant']?['id']?.toString() ?? '';
      final mechanicEta =
          (result['mechanic']?['etaMinutes'] as num?)?.toDouble() ?? 0;
      final assistantEta =
          (result['assistant']?['etaMinutes'] as num?)?.toDouble() ?? 0;

      // Step 2: Emit socket event so the UI updates in real-time.
      _socket.emit('request_assigned', {
        'requestId': requestId,
        'mechanicId': mechanicId,
        'assistantId': assistantId,
        'status': 'assigned',
        'jobGroupId': jobGroupId,
      });

      _searchTimer?.cancel();

      state = state.copyWith(
        isLoading: false,
        isSearching: false,
        jobGroupId: jobGroupId,
        mechanicEtaMinutes: mechanicEta,
        assistantEtaMinutes: assistantEta,
      );
    } catch (e) {
      debugPrint('DispatchNotifier.dispatchTwoManCrew error: $e');
      _searchTimer?.cancel();
      state = state.copyWith(
        isLoading: false,
        isSearching: false,
        errorMessage: 'Dispatch failed: ${e.toString()}',
      );
    }
  }

  /// ─── FEATURE 5: Queue offline jobs for missing crew roles ───
  ///
  /// When the dispatch function cannot find a crew member for [mechanic] or
  /// [assistant], we queue the job for that role so it can be delivered via
  /// FCM the next time an available crew of that role comes online.
  Future<void> _queueOfflineJobForMissingCrews({
    required String requestId,
    required double userLat,
    required double userLng,
    String? userZone,
    dynamic mechanic,
    dynamic assistant,
  }) async {
    final offlineQueue = OfflineQueueService();

    // Queue a job for the mechanic role if no mechanic was found.
    if (mechanic == null || (mechanic is Map && mechanic['id'] == null)) {
      await offlineQueue.queueOfflineJob(
        requestId: requestId,
        role: 'mechanic',
        lat: userLat,
        lng: userLng,
        zone: userZone ?? '',
      );
    }

    // Queue a job for the assistant role if no assistant was found.
    if (assistant == null || (assistant is Map && assistant['id'] == null)) {
      await offlineQueue.queueOfflineJob(
        requestId: requestId,
        role: 'assistant',
        lat: userLat,
        lng: userLng,
        zone: userZone ?? '',
      );
    }
  }

  /// ─── PATENT: Weighted Crew Matching Algorithm ───
  ///
  /// Finds the best available crew member of a given role using:
  /// - Distance (40%): Closer crews score higher
  /// - Rating (25%): Higher-rated crews score higher
  /// - Active Status (20%): Online crews score higher
  /// - Zone (15%): Preferred zone crews score higher
  // ignore: unused_element
  Future<CrewModel?> _findBestCrew({
    required String role,
    required double userLat,
    required double userLng,
    String? userZone,
  }) async {
    try {
      final docs = await _firestore.queryDocuments(
        collection: AppConstants.collectionCrews,
        whereClauses: [
          WhereClause(field: 'role', isEqualTo: role),
          WhereClause(field: 'isOnline', isEqualTo: true),
          WhereClause(field: 'isKycVerified', isEqualTo: true),
        ],
      );

      if (docs.isEmpty) return null;

      CrewModel? bestCrew;
      double bestScore = -1;

      for (final doc in docs) {
        final crew = CrewModel.fromFirestore(doc);
        final crewLat = crew.currentLocation?.latitude ?? 0;
        final crewLng = crew.currentLocation?.longitude ?? 0;

        // Skip if location is invalid
        if (crewLat == 0 && crewLng == 0) continue;

        final distanceKm = Geolocator.distanceBetween(
              userLat,
              userLng,
              crewLat,
              crewLng,
            ) /
            1000;

        // Skip if outside max radius
        if (distanceKm > AppConstants.maxCrewRadiusKm) continue;

        final isInPreferredZone = crew.serviceZone == userZone ||
            (userZone == null && crew.serviceZone == null);

        final score = crew.computeDispatchScore(
          distanceKm: distanceKm,
          maxDistance: AppConstants.maxCrewRadiusKm,
          isInPreferredZone: isInPreferredZone,
        );

        if (score > bestScore) {
          bestScore = score;
          bestCrew = crew;
        }
      }

      return bestCrew;
    } catch (e) {
      debugPrint('DispatchNotifier._findBestCrew error: $e');
      return null;
    }
  }

  /// ─── Create a job record for a crew member ───
  // ignore: unused_element
  Future<void> _createJob({
    required String jobGroupId,
    required String role,
    required CrewModel crew,
    required String userId,
    required String requestId,
    required double userLat,
    required double userLng,
    required DateTime createdAt,
  }) async {
    final crewLat = crew.currentLocation?.latitude ?? userLat;
    final crewLng = crew.currentLocation?.longitude ?? userLng;
    final distanceKm = Geolocator.distanceBetween(
          userLat,
          userLng,
          crewLat,
          crewLng,
        ) /
        1000;
    final etaMinutes = _calculateEta(userLat, userLng, crewLat, crewLng);

    final jobData = {
      'requestId': requestId,
      'jobGroupId': jobGroupId,
      'crewId': crew.id,
      'crewName': crew.name,
      'crewRole': role,
      'userId': userId,
      'status':
          'pending', // pending → accepted → on_the_way → reached → completed
      'distanceKm': distanceKm,
      'etaMinutes': etaMinutes,
      'earnings': 0.0,
      'pickupLocation': GeoPoint(userLat, userLng),
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(createdAt),
    };

    await _firestore.createDocument(
      collection: AppConstants.collectionJobs,
      data: jobData,
    );
  }

  /// ─── Escalate when no crew found or timeout ───
  Future<void> _escalateRequest(String requestId) async {
    _searchTimer?.cancel();
    state = state.copyWith(isEscalated: true, isSearching: false);

    // Update request status to escalated
    await _firestore.updateDocument(
      collection: AppConstants.collectionRequests,
      documentId: requestId,
      updates: {'status': 'escalated'},
    );

    // Emit escalation event
    _socket.emit('escalate_request', {
      'requestId': requestId,
      'reason':
          'No crew found within ${AppConstants.sosTimeoutSeconds} seconds',
    });

    // Try backup crews
    await _dispatchBackupCrews(requestId);
  }

  /// ─── Dispatch backup crews (up to 3) ───
  Future<void> _dispatchBackupCrews(String requestId) async {
    try {
      final docs = await _firestore.queryDocuments(
        collection: AppConstants.collectionRequests,
        whereClauses: [
          WhereClause(field: 'status', isEqualTo: 'escalated'),
        ],
        limit: AppConstants.maxBackupCrews,
      );

      for (final _ in docs) {
        // Notify each backup crew via notification
        _socket.emit('backup_crew_notification', {
          'requestId': requestId,
          'priority': 'high',
        });
      }
    } catch (e) {
      debugPrint('DispatchNotifier._dispatchBackupCrews error: $e');
    }
  }

  /// ─── Calculate ETA in minutes ───
  double _calculateEta(
    double userLat,
    double userLng,
    double crewLat,
    double crewLng,
  ) {
    final distanceKm = Geolocator.distanceBetween(
          userLat,
          userLng,
          crewLat,
          crewLng,
        ) /
        1000;
    // Average speed: 30 km/h for mechanics (towing vehicle)
    // Average speed: 50 km/h for assistants (2-wheeler)
    final avgSpeed = 30.0; // km/h
    final minutes = (distanceKm / avgSpeed) * 60;
    return double.parse(minutes.toStringAsFixed(1));
  }

  /// ─── Generate unique job group ID ───
  String _generateJobGroupId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return 'JG-$now-${now % 10000}';
  }

  /// ─── Reset dispatch state ───
  void reset() {
    _searchTimer?.cancel();
    state = const DispatchState();
  }

  /// ─── Cancel dispatch search ───
  void cancelSearch() {
    _searchTimer?.cancel();
    state = state.copyWith(isSearching: false, isLoading: false);
  }
}

/// ─── Provider ───
final dispatchProvider = StateNotifierProvider<DispatchNotifier, DispatchState>(
  (ref) {
    return DispatchNotifier(FirestoreService(), SocketService());
  },
);
