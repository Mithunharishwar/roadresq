// IMPORTANT: Set Firestore Rules to allow read/write for testing
// FILE: lib/services/crew_job_service.dart
/// CrewJobService — Crew App Module (Mechanic + Assistant).
///
/// Implements the spec functions:
///   - setCrewStatus(status)          → online / offline / busy
///   - streamLocation(jobId)          → send live GPS via Socket.IO
///   - getJobRequestStream()          → listen for new job assignments
///   - acceptJob(jobId)              → updates job with mechanicId/assistantId
///   - rejectJob(jobId)              → returns job to pool
///   - updateJobStatus(jobId, status) → accepted > reached > in_progress
///   - generateToken(jobId)          → Cloud Function 6-digit + QR
///   - uploadJobPhotos(jobId, images) → before/after pics to Storage
///   - addServiceNotes(jobId, notes) → what work was done
///   - viewEarnings()                → weekly payout history
library;

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../core/constants/app_constants.dart';
import 'socket_service.dart';

class CrewJobService {
  CrewJobService._internal();
  static final CrewJobService _instance = CrewJobService._internal();
  factory CrewJobService() => _instance;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final SocketService _socket = SocketService();
  Timer? _locationTimer;

  /// Handles for the job-request listeners started by [getJobRequestStream].
  final List<SocketSubscription> _jobSubs = <SocketSubscription>[];

  /// setCrewStatus(status) — set online/offline/busy.
  Future<bool> setCrewStatus({
    required String crewId,
    required String status, // online | offline | busy
  }) async {
    try {
      await _firestore
          .collection(AppConstants.collectionCrews)
          .doc(crewId)
          .update({
        'status': status,
        'isOnline': status == 'online' || status == 'busy',
        'isBusy': status == 'busy',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } on FirebaseException catch (e) {
      debugPrint(
          'CrewJobService.setCrewStatus FirebaseException: ${e.code} - ${e.message}');
      if (e.code == 'permission-denied') {
        debugPrint('PERMISSION_DENIED: Check Firestore Rules');
      }
      return false;
    } catch (e) {
      debugPrint('CrewJobService.setCrewStatus error: $e');
      return false;
    }
  }

  /// streamLocation(jobId) — send live GPS every 3 sec via Socket.IO.
  void streamLocation({
    required String jobId,
    required String crewId,
    required double Function() getLatitude,
    required double Function() getLongitude,
  }) {
    stopStreaming();
    _socket.connect();
    _socket.emit('crew_online', {'crewId': crewId});

    _locationTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      final lat = getLatitude();
      final lng = getLongitude();
      if (lat == 0 && lng == 0) return;
      _socket.emit('update_location', {
        'jobId': jobId,
        'crewId': crewId,
        'lat': lat,
        'lng': lng,
      });
    });
  }

  void stopStreaming() {
    _locationTimer?.cancel();
    _locationTimer = null;
    // Drop this service's job-request listeners too, so a restart cannot
    // accumulate duplicate handlers.
    for (final sub in _jobSubs) {
      sub.cancel();
    }
    _jobSubs.clear();
  }

  /// getJobRequestStream() — listen for new job assignments via socket.
  void getJobRequestStream(void Function(dynamic data) handler) {
    _socket.connect();
    _jobSubs.add(_socket.onNewRequest(handler));
    _jobSubs.add(_socket.onRequestAssigned(handler));
  }

  /// acceptJob(jobId) — update job with crew assignment.
  Future<bool> acceptJob({
    required String jobId,
    required String crewId,
    required String crewRole,
  }) async {
    try {
      await _firestore
          .collection(AppConstants.collectionJobs)
          .doc(jobId)
          .update({
        'crewId': crewId,
        'crewRole': crewRole,
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _socket.emit('accept_request', {'jobId': jobId, 'crewId': crewId});
      return true;
    } on FirebaseException catch (e) {
      debugPrint(
          'CrewJobService.acceptJob FirebaseException: ${e.code} - ${e.message}');
      if (e.code == 'permission-denied') {
        debugPrint('PERMISSION_DENIED: Check Firestore Rules');
      }
      return false;
    } catch (e) {
      debugPrint('CrewJobService.acceptJob error: $e');
      return false;
    }
  }

  /// rejectJob(jobId) — return job to pool (status reassignable).
  Future<bool> rejectJob({
    required String jobId,
    String? reason,
  }) async {
    try {
      await _firestore
          .collection(AppConstants.collectionJobs)
          .doc(jobId)
          .update({
        'status': 'pending',
        'rejectReason': reason ?? 'rejected',
        'rejectedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } on FirebaseException catch (e) {
      debugPrint(
          'CrewJobService.rejectJob FirebaseException: ${e.code} - ${e.message}');
      if (e.code == 'permission-denied') {
        debugPrint('PERMISSION_DENIED: Check Firestore Rules');
      }
      return false;
    } catch (e) {
      debugPrint('CrewJobService.rejectJob error: $e');
      return false;
    }
  }

  /// updateJobStatus(jobId, status) — accepted > reached > in_progress.
  Future<bool> updateJobStatus({
    required String jobId,
    required String status,
  }) async {
    try {
      final updates = <String, dynamic>{
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (status == 'reached') {
        updates['reachedAt'] = FieldValue.serverTimestamp();
      }
      if (status == 'in_progress') {
        updates['startedAt'] = FieldValue.serverTimestamp();
      }
      if (status == 'completed') {
        updates['completedAt'] = FieldValue.serverTimestamp();
      }

      await _firestore
          .collection(AppConstants.collectionJobs)
          .doc(jobId)
          .update(updates);
      _socket.emit('status_updated', {'jobId': jobId, 'status': status});
      return true;
    } on FirebaseException catch (e) {
      debugPrint(
          'CrewJobService.updateJobStatus FirebaseException: ${e.code} - ${e.message}');
      if (e.code == 'permission-denied') {
        debugPrint('PERMISSION_DENIED: Check Firestore Rules');
      }
      return false;
    } catch (e) {
      debugPrint('CrewJobService.updateJobStatus error: $e');
      return false;
    }
  }

  /// generateToken(jobId) — call Cloud Function, get 6-digit + QR.
  Future<Map<String, dynamic>> generateToken({
    required String jobId,
    required String userId,
    required String crewId,
    required String garageId,
    required String vehicleNumber,
  }) async {
    try {
      final result = await _functions.httpsCallable('generateToken').call({
        'userId': userId,
        'crewId': crewId,
        'jobId': jobId,
        'garageId': garageId,
        'vehicleNumber': vehicleNumber,
      });
      final data = result.data as Map<String, dynamic>;
      return {
        'success': data['success'] == true,
        'tokenId': data['tokenId'] ?? '',
        'tokenCode': data['tokenCode'] ?? '${data['token'] ?? ''}',
        'qrData': data['qrData'] ?? '',
      };
    } catch (e) {
      debugPrint('CrewJobService.generateToken error: $e');
      return {'success': false, 'tokenId': '', 'tokenCode': '', 'qrData': ''};
    }
  }

  /// uploadJobPhotos(jobId, images) — placeholder for Storage upload.
  /// The actual bytes are uploaded via StorageService; this records metadata.
  Future<bool> uploadJobPhotos({
    required String jobId,
    required List<String> imageUrls,
  }) async {
    try {
      await _firestore
          .collection(AppConstants.collectionJobs)
          .doc(jobId)
          .update({
        'photos': FieldValue.arrayUnion(imageUrls),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } on FirebaseException catch (e) {
      debugPrint(
          'CrewJobService.uploadJobPhotos FirebaseException: ${e.code} - ${e.message}');
      if (e.code == 'permission-denied') {
        debugPrint('PERMISSION_DENIED: Check Firestore Rules');
      }
      return false;
    } catch (e) {
      debugPrint('CrewJobService.uploadJobPhotos error: $e');
      return false;
    }
  }

  /// addServiceNotes(jobId, notes) — record what work was done.
  Future<bool> addServiceNotes({
    required String jobId,
    required String notes,
  }) async {
    try {
      await _firestore
          .collection(AppConstants.collectionJobs)
          .doc(jobId)
          .update({
        'serviceNotes': notes,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } on FirebaseException catch (e) {
      debugPrint(
          'CrewJobService.addServiceNotes FirebaseException: ${e.code} - ${e.message}');
      if (e.code == 'permission-denied') {
        debugPrint('PERMISSION_DENIED: Check Firestore Rules');
      }
      return false;
    } catch (e) {
      debugPrint('CrewJobService.addServiceNotes error: $e');
      return false;
    }
  }

  /// viewEarnings() — weekly payout history from commissions.
  Future<List<Map<String, dynamic>>> viewEarnings({
    required String crewId,
    int limit = 50,
  }) async {
    try {
      final snap = await _firestore
          .collection('commissions')
          .where('crewId', isEqualTo: crewId)
          .orderBy('processedAt', descending: true)
          .limit(limit)
          .get();
      return snap.docs.map((d) {
        final data = Map<String, dynamic>.from(d.data() as Map);
        return {
          'commissionId': d.id,
          'jobId': data['jobId'] ?? '',
          'crewRole': data['crewRole'] ?? '',
          'totalEarnings': (data['totalEarnings'] ?? 0).toDouble(),
          'platformCommission': (data['platformCommission'] ?? 0).toDouble(),
          'crewPayout': (data['crewPayout'] ?? 0).toDouble(),
          'status': data['status'] ?? 'processed',
        };
      }).toList();
    } on FirebaseException catch (e) {
      debugPrint(
          'CrewJobService.viewEarnings FirebaseException: ${e.code} - ${e.message}');
      if (e.code == 'permission-denied') {
        debugPrint('PERMISSION_DENIED: Check Firestore Rules');
      }
      return [];
    } catch (e) {
      debugPrint('CrewJobService.viewEarnings error: $e');
      return [];
    }
  }

  /// viewEarningsStream() — real-time earnings stream.
  Stream<List<Map<String, dynamic>>> viewEarningsStream({
    required String crewId,
    int limit = 50,
  }) {
    return _firestore
        .collection('commissions')
        .where('crewId', isEqualTo: crewId)
        .orderBy('processedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final data = Map<String, dynamic>.from(d.data() as Map);
              return {
                'commissionId': d.id,
                'jobId': data['jobId'] ?? '',
                'crewRole': data['crewRole'] ?? '',
                'totalEarnings': (data['totalEarnings'] ?? 0).toDouble(),
                'platformCommission':
                    (data['platformCommission'] ?? 0).toDouble(),
                'crewPayout': (data['crewPayout'] ?? 0).toDouble(),
                'status': data['status'] ?? 'processed',
              };
            }).toList());
  }
}
