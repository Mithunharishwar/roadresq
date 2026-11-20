/// Community Safety Mesh — Crowd-Sourced Rescue Layer Provider (novel module).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/novel/community_helper_model.dart';
import '../../services/novel/community_mesh_service.dart';

/// ─── State ───
class CommunityMeshState {
  final bool isLoading;
  final String? errorMessage;
  final List<CommunityHelper> nearbyHelpers;
  final String? lastBeaconId;
  final int helpersNotified;

  const CommunityMeshState({
    this.isLoading = false,
    this.errorMessage,
    this.nearbyHelpers = const [],
    this.lastBeaconId,
    this.helpersNotified = 0,
  });

  CommunityMeshState copyWith({
    bool? isLoading,
    String? errorMessage,
    List<CommunityHelper>? nearbyHelpers,
    String? lastBeaconId,
    int? helpersNotified,
  }) {
    return CommunityMeshState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      nearbyHelpers: nearbyHelpers ?? this.nearbyHelpers,
      lastBeaconId: lastBeaconId ?? this.lastBeaconId,
      helpersNotified: helpersNotified ?? this.helpersNotified,
    );
  }
}

/// ─── Notifier ───
class CommunityMeshNotifier extends StateNotifier<CommunityMeshState> {
  final CommunityMeshService _service;

  CommunityMeshNotifier(this._service) : super(const CommunityMeshState());

  /// Find nearby verified & available helpers.
  Future<void> findNearbyHelpers({
    required double lat,
    required double lng,
    double radiusKm = 5,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    final helpers = await _service.findNearbyHelpers(
      lat: lat,
      lng: lng,
      radiusKm: radiusKm,
    );
    state = state.copyWith(isLoading: false, nearbyHelpers: helpers);
  }

  /// Broadcast an emergency beacon to nearby helpers + family.
  Future<void> broadcastBeacon({
    required String userId,
    required String userName,
    required String userPhone,
    required double lat,
    required double lng,
    String message = '',
    List<String> familyIds = const [],
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    final result = await _service.broadcastBeacon(
      userId: userId,
      userName: userName,
      userPhone: userPhone,
      lat: lat,
      lng: lng,
      message: message,
      familyIds: familyIds,
    );
    state = state.copyWith(
      isLoading: false,
      lastBeaconId: result['beaconId']?.toString(),
      helpersNotified: (result['helpersNotified'] as num?)?.toInt() ?? 0,
    );
  }

  /// Resolve an active beacon.
  Future<void> resolveBeacon(String beaconId) async {
    await _service.resolveBeacon(beaconId, 'resolved');
  }

  /// Register / update a community helper.
  Future<bool> upsertHelper(CommunityHelper helper) async {
    return _service.upsertHelper(helper);
  }

  void reset() => state = const CommunityMeshState();
}

/// ─── Provider ───
final communityMeshProvider =
    StateNotifierProvider<CommunityMeshNotifier, CommunityMeshState>((ref) {
  return CommunityMeshNotifier(CommunityMeshService());
});
