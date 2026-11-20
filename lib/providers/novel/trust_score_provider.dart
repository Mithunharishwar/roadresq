/// TrustScore — Layered Reputation & Gamified Badges Provider (novel module).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/novel/trust_profile_model.dart';
import '../../services/novel/trust_score_service.dart';

/// ─── State ───
class TrustScoreState {
  final bool isLoading;
  final String? errorMessage;
  final TrustProfile? profile;
  final bool isPersisted;

  const TrustScoreState({
    this.isLoading = false,
    this.errorMessage,
    this.profile,
    this.isPersisted = false,
  });

  TrustScoreState copyWith({
    bool? isLoading,
    String? errorMessage,
    TrustProfile? profile,
    bool? isPersisted,
  }) {
    return TrustScoreState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      profile: profile ?? this.profile,
      isPersisted: isPersisted ?? this.isPersisted,
    );
  }
}

/// ─── Notifier ───
class TrustScoreNotifier extends StateNotifier<TrustScoreState> {
  final TrustScoreService _service;

  TrustScoreNotifier(this._service) : super(const TrustScoreState());

  /// Compute the trust profile for a crew member.
  void computeProfile({
    required String crewId,
    required String role,
    double rating = 0,
    int ratingCount = 0,
    int jobsCompleted = 0,
    int onTime = 0,
    int lateCount = 0,
    int cancellations = 0,
    int respondedFast = 0,
    int zoneAdherent = 0,
    int safetyAdherent = 0,
  }) {
    state = state.copyWith(isLoading: true, errorMessage: null);
    final profile = _service.computeTrustProfile(
      crewId: crewId,
      role: role,
      rating: rating,
      ratingCount: ratingCount,
      jobsCompleted: jobsCompleted,
      onTime: onTime,
      lateCount: lateCount,
      cancellations: cancellations,
      respondedFast: respondedFast,
      zoneAdherent: zoneAdherent,
      safetyAdherent: safetyAdherent,
    );
    state = state.copyWith(isLoading: false, profile: profile);
  }

  /// Persist the current trust profile.
  Future<void> persist() async {
    final profile = state.profile;
    if (profile == null) return;
    final ok = await _service.persistTrustProfile(profile);
    state = state.copyWith(isPersisted: ok);
  }

  /// Load an existing trust profile for a crew member.
  Future<void> loadProfile(String crewId) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    final profile = await _service.fetchTrustProfile(crewId);
    state = state.copyWith(isLoading: false, profile: profile);
  }

  /// Dispatch priority multiplier for the current tier.
  double get dispatchMultiplier =>
      _service.dispatchPriorityMultiplier(state.profile?.tier ?? 'bronze');

  void reset() => state = const TrustScoreState();
}

/// ─── Provider ───
final trustScoreProvider =
    StateNotifierProvider<TrustScoreNotifier, TrustScoreState>((ref) {
  return TrustScoreNotifier(TrustScoreService());
});
