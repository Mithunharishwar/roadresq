/// EcoRide — Green Rescue & Carbon Intelligence Provider (novel module).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/novel/eco_score_model.dart';
import '../../services/novel/eco_score_service.dart';

/// ─── State ───
class EcoScoreState {
  final bool isLoading;
  final String? errorMessage;
  final EcoScore? profile;
  final EcoImpact? lastImpact;
  final bool isPersisted;

  const EcoScoreState({
    this.isLoading = false,
    this.errorMessage,
    this.profile,
    this.lastImpact,
    this.isPersisted = false,
  });

  EcoScoreState copyWith({
    bool? isLoading,
    String? errorMessage,
    EcoScore? profile,
    EcoImpact? lastImpact,
    bool? isPersisted,
  }) {
    return EcoScoreState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      profile: profile ?? this.profile,
      lastImpact: lastImpact ?? this.lastImpact,
      isPersisted: isPersisted ?? this.isPersisted,
    );
  }
}

/// ─── Notifier ───
class EcoScoreNotifier extends StateNotifier<EcoScoreState> {
  final EcoScoreService _service;

  EcoScoreNotifier(this._service) : super(const EcoScoreState());

  /// Compute a single rescue's impact and update the aggregate profile.
  void computeImpact({
    required String name,
    required String serviceType,
    required double distanceKm,
    String fuelType = 'petrol',
  }) {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final impact = _service.computeRescueImpact(
        serviceType: serviceType,
        distanceKm: distanceKm,
        fuelType: fuelType,
      );
      final existing = state.profile;
      final impacts = [
        ...(existing?.recentImpacts ?? const <EcoImpact>[]),
        impact,
      ].take(20).toList();
      final profile = _service.aggregateScore(name: name, impacts: impacts);
      state = state.copyWith(
        isLoading: false,
        profile: profile,
        lastImpact: impact,
      );
    } catch (e) {
      state = state.copyWith(
          isLoading: false, errorMessage: 'Impact compute failed: $e');
    }
  }

  /// Load a demo profile so the screen is self-contained.
  void loadDemo({String name = 'You'}) {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final impacts = _service.sampleImpacts();
      final profile = _service.aggregateScore(name: name, impacts: impacts);
      state = state.copyWith(isLoading: false, profile: profile);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: 'Load failed: $e');
    }
  }

  /// Persist the current profile.
  Future<void> persist(String id) async {
    final profile = state.profile;
    if (profile == null) return;
    final ok = await _service.persistEcoScore(
      EcoScore(
          id: id,
          name: profile.name,
          rescues: profile.rescues,
          totalCo2Kg: profile.totalCo2Kg,
          totalCo2SavedKg: profile.totalCo2SavedKg,
          ecoScore: profile.ecoScore,
          greenTier: profile.greenTier,
          treesEquivalent: profile.treesEquivalent,
          recentImpacts: profile.recentImpacts),
    );
    state = state.copyWith(isPersisted: ok);
  }

  void reset() => state = const EcoScoreState();
}

/// ─── Provider ───
final ecoScoreProvider =
    StateNotifierProvider<EcoScoreNotifier, EcoScoreState>((ref) {
  return EcoScoreNotifier(EcoScoreService());
});
