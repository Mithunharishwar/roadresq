/// RoadResQ Request Provider
/// Manages the lifecycle of a rescue/SOS request.
///
/// Flow: pending → assigned → accepted → on_the_way → reached → completed → cancelled
/// Handles request creation, status updates, and crew assignment tracking.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants/app_constants.dart';
import '../services/firestore_service.dart';
import '../services/socket_service.dart';

/// ─── State ───
class RequestState {
  final bool isLoading;
  final String? errorMessage;
  final String? currentRequestId;
  final String? status;
  final String? assignedMechanicId;
  final String? assignedAssistantId;
  final double? mechanicEtaMinutes;
  final double? assistantEtaMinutes;
  final Map<String, dynamic>? requestData;

  const RequestState({
    this.isLoading = false,
    this.errorMessage,
    this.currentRequestId,
    this.status,
    this.assignedMechanicId,
    this.assignedAssistantId,
    this.mechanicEtaMinutes,
    this.assistantEtaMinutes,
    this.requestData,
  });

  RequestState copyWith({
    bool? isLoading,
    String? errorMessage,
    String? currentRequestId,
    String? status,
    String? assignedMechanicId,
    String? assignedAssistantId,
    double? mechanicEtaMinutes,
    double? assistantEtaMinutes,
    Map<String, dynamic>? requestData,
  }) {
    return RequestState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      currentRequestId: currentRequestId ?? this.currentRequestId,
      status: status ?? this.status,
      assignedMechanicId: assignedMechanicId ?? this.assignedMechanicId,
      assignedAssistantId: assignedAssistantId ?? this.assignedAssistantId,
      mechanicEtaMinutes: mechanicEtaMinutes ?? this.mechanicEtaMinutes,
      assistantEtaMinutes: assistantEtaMinutes ?? this.assistantEtaMinutes,
      requestData: requestData ?? this.requestData,
    );
  }
}

/// ─── Notifier ───
class RequestNotifier extends StateNotifier<RequestState> {
  final FirestoreService _firestore;
  final SocketService _socket;

  RequestNotifier(this._firestore, this._socket) : super(const RequestState());

  /// ─── Create a new rescue request ───
  Future<String?> createRequest({
    required String userId,
    required String userName,
    required String userPhone,
    required double latitude,
    required double longitude,
    required String address,
    required String vehicleType,
    required String issueType,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final requestData = {
        'userId': userId,
        'userName': userName,
        'userPhone': userPhone,
        'pickupLocation': GeoPoint(latitude, longitude),
        'address': address,
        'vehicleType': vehicleType,
        'issueType': issueType,
        'status': 'pending',
        'createdAt': Timestamp.fromDate(DateTime.now()),
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      };

      final requestId = await _firestore.createDocument(
        collection: AppConstants.collectionRequests,
        data: requestData,
      );

      // Emit socket event for new request
      _socket.emit('new_request', {
        'requestId': requestId,
        'userId': userId,
        'userName': userName,
        'lat': latitude,
        'lng': longitude,
        'issue': issueType,
      });

      state = state.copyWith(
        currentRequestId: requestId,
        status: 'pending',
        isLoading: false,
        requestData: requestData,
      );

      return requestId;
    } catch (e) {
      debugPrint('RequestNotifier.createRequest error: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to create request: ${e.toString()}',
      );
      return null;
    }
  }

  /// ─── Update request status ───
  Future<void> updateStatus({
    required String requestId,
    required String status,
    String? mechanicId,
    String? assistantId,
  }) async {
    try {
      final updates = <String, dynamic>{
        'status': status,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      };

      if (mechanicId != null) updates['assignedMechanicId'] = mechanicId;
      if (assistantId != null) updates['assignedAssistantId'] = assistantId;

      await _firestore.updateDocument(
        collection: AppConstants.collectionRequests,
        documentId: requestId,
        updates: updates,
      );

      // Emit socket event
      _socket.emit('status_updated', {
        'requestId': requestId,
        'status': status,
      });

      state = state.copyWith(
        status: status,
        assignedMechanicId: mechanicId ?? state.assignedMechanicId,
        assignedAssistantId: assistantId ?? state.assignedAssistantId,
      );
    } catch (e) {
      debugPrint('RequestNotifier.updateStatus error: $e');
      state = state.copyWith(
        errorMessage: 'Failed to update status: ${e.toString()}',
      );
    }
  }

  /// ─── Fetch request by ID ───
  Future<void> fetchRequest(String requestId) async {
    state = state.copyWith(isLoading: true);

    try {
      final doc = await _firestore.getDocument(
        collection: AppConstants.collectionRequests,
        documentId: requestId,
      );

      if (doc != null && doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        state = state.copyWith(
          currentRequestId: requestId,
          status: data['status'] ?? 'pending',
          assignedMechanicId: data['assignedMechanicId'],
          assignedAssistantId: data['assignedAssistantId'],
          mechanicEtaMinutes: (data['mechanicEtaMinutes'] as num?)?.toDouble(),
          assistantEtaMinutes:
              (data['assistantEtaMinutes'] as num?)?.toDouble(),
          requestData: data,
          isLoading: false,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Request not found',
        );
      }
    } catch (e) {
      debugPrint('RequestNotifier.fetchRequest error: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to fetch request: ${e.toString()}',
      );
    }
  }

  /// ─── Listen to request updates in real-time ───
  void listenToRequest(String requestId) {
    // Socket listeners would be set up here
    // For now, we rely on Firestore real-time updates
  }

  /// Reset state
  void reset() {
    state = const RequestState();
  }
}

/// ─── Provider ───
final requestProvider =
    StateNotifierProvider<RequestNotifier, RequestState>((ref) {
  return RequestNotifier(FirestoreService(), SocketService());
});
