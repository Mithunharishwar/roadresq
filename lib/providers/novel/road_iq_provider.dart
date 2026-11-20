/// RoadIQ — Predictive Demand & Dispatch Intelligence Provider (novel module).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/novel/prediction_model.dart';
import '../../services/novel/road_iq_service.dart';

/// ─── State ───
class RoadIqState {
  final bool isLoading;
  final String? errorMessage;
  final List<DemandPrediction> forecasts;
  final List<HeatmapCell> heatmap;
  final bool isForecastPersisted;

  const RoadIqState({
    this.isLoading = false,
    this.errorMessage,
    this.forecasts = const [],
    this.heatmap = const [],
    this.isForecastPersisted = false,
  });

  RoadIqState copyWith({
    bool? isLoading,
    String? errorMessage,
    List<DemandPrediction>? forecasts,
    List<HeatmapCell>? heatmap,
    bool? isForecastPersisted,
  }) {
    return RoadIqState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      forecasts: forecasts ?? this.forecasts,
      heatmap: heatmap ?? this.heatmap,
      isForecastPersisted: isForecastPersisted ?? this.isForecastPersisted,
    );
  }
}

/// ─── Notifier ───
class RoadIqNotifier extends StateNotifier<RoadIqState> {
  final RoadIqService _service;

  RoadIqNotifier(this._service) : super(const RoadIqState());

  /// Generate a demand forecast for a given hour.
  void generateForecast({
    required int hour,
    List<Map<String, dynamic>>? historicalJobs,
    List<Map<String, dynamic>>? zones,
  }) {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final forecasts = _service.forecastDemand(
        hour: hour,
        historicalJobs: historicalJobs,
        zones: zones,
      );
      state = state.copyWith(isLoading: false, forecasts: forecasts);
    } catch (e) {
      state =
          state.copyWith(isLoading: false, errorMessage: 'Forecast failed: $e');
    }
  }

  /// Build a live demand heatmap from recent jobs.
  void buildHeatmap({
    required List<Map<String, dynamic>> recentJobs,
    Map<String, List<double>>? anchorPoints,
  }) {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final heatmap = _service.buildHeatmap(
        recentJobs: recentJobs,
        anchorPoints: anchorPoints,
      );
      state = state.copyWith(isLoading: false, heatmap: heatmap);
    } catch (e) {
      state =
          state.copyWith(isLoading: false, errorMessage: 'Heatmap failed: $e');
    }
  }

  /// Refine an ETA using smart traffic + load factors.
  double refineEta({
    required double baseEtaMinutes,
    double trafficFactor = 1.0,
    int activeJobsForCrew = 0,
    double distanceKm = 0,
  }) {
    return _service.refineEta(
      baseEtaMinutes: baseEtaMinutes,
      trafficFactor: trafficFactor,
      activeJobsForCrew: activeJobsForCrew,
      distanceKm: distanceKm,
    );
  }

  /// Recommend optimal crew count for a zone.
  int recommendCrews({
    required double predictedDemand,
    double serviceLevel = 0.9,
  }) {
    return _service.recommendCrews(
      predictedDemand: predictedDemand,
      serviceLevel: serviceLevel,
    );
  }

  /// Persist the current forecast batch.
  Future<void> persistForecast() async {
    final ok = await _service.persistForecast(state.forecasts);
    state = state.copyWith(isForecastPersisted: ok);
  }

  void reset() => state = const RoadIqState();
}

/// ─── Provider ───
final roadIqProvider =
    StateNotifierProvider<RoadIqNotifier, RoadIqState>((ref) {
  return RoadIqNotifier(RoadIqService());
});
