/// FareOracle — Smart Dynamic Pricing Engine Provider (novel module).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/novel/fare_oracle_model.dart';
import '../../services/novel/fare_oracle_service.dart';

/// ─── State ───
class FareOracleState {
  final bool isLoading;
  final String? errorMessage;
  final FareEstimate? estimate;
  final bool isPersisted;

  const FareOracleState({
    this.isLoading = false,
    this.errorMessage,
    this.estimate,
    this.isPersisted = false,
  });

  FareOracleState copyWith({
    bool? isLoading,
    String? errorMessage,
    FareEstimate? estimate,
    bool? isPersisted,
  }) {
    return FareOracleState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      estimate: estimate ?? this.estimate,
      isPersisted: isPersisted ?? this.isPersisted,
    );
  }
}

/// ─── Notifier ───
class FareOracleNotifier extends StateNotifier<FareOracleState> {
  final FareOracleService _service;

  FareOracleNotifier(this._service) : super(const FareOracleState());

  /// Compute a live fare estimate from the fused price signals.
  void estimate({
    required String serviceType,
    required double distanceKm,
    double demandIndex = 0.5,
    String weather = 'clear',
    int hour = 12,
    double trafficFactor = 1.0,
    int availableCrews = 10,
  }) {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final estimate = _service.estimateFare(
        serviceType: serviceType,
        distanceKm: distanceKm,
        demandIndex: demandIndex,
        weather: weather,
        hour: hour,
        trafficFactor: trafficFactor,
        availableCrews: availableCrews,
      );
      state = state.copyWith(isLoading: false, estimate: estimate);
    } catch (e) {
      state =
          state.copyWith(isLoading: false, errorMessage: 'Estimate failed: $e');
    }
  }

  /// Load a demo estimate so the screen is self-contained.
  void loadDemo() {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final estimate = _service.sampleEstimate();
      state = state.copyWith(isLoading: false, estimate: estimate);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: 'Load failed: $e');
    }
  }

  /// Persist the current estimate.
  Future<void> persist() async {
    final estimate = state.estimate;
    if (estimate == null) return;
    final ok = await _service.persistEstimate(estimate);
    state = state.copyWith(isPersisted: ok);
  }

  void reset() => state = const FareOracleState();
}

/// ─── Provider ───
final fareOracleProvider =
    StateNotifierProvider<FareOracleNotifier, FareOracleState>((ref) {
  return FareOracleNotifier(FareOracleService());
});
