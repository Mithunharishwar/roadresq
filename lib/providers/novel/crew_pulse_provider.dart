/// CrewPulse — AI Performance & Churn Analytics Provider (novel module).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/novel/crew_pulse_model.dart';
import '../../services/novel/crew_pulse_service.dart';

/// ─── State ───
class CrewPulseState {
  final bool isLoading;
  final String? errorMessage;
  final CrewPulseReport? report;
  final bool isPersisted;

  const CrewPulseState({
    this.isLoading = false,
    this.errorMessage,
    this.report,
    this.isPersisted = false,
  });

  CrewPulseState copyWith({
    bool? isLoading,
    String? errorMessage,
    CrewPulseReport? report,
    bool? isPersisted,
  }) {
    return CrewPulseState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      report: report ?? this.report,
      isPersisted: isPersisted ?? this.isPersisted,
    );
  }
}

/// ─── Notifier ───
class CrewPulseNotifier extends StateNotifier<CrewPulseState> {
  final CrewPulseService _service;

  CrewPulseNotifier(this._service) : super(const CrewPulseState());

  /// Build a report for a specific crew.
  void analyze({
    required CrewMetrics metrics,
    List<CrewMetrics>? peerCohort,
    List<double>? trendScores,
  }) {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final report = _service.buildReport(
        metrics: metrics,
        peerCohort: peerCohort,
        trendScores: trendScores,
      );
      state = state.copyWith(isLoading: false, report: report);
    } catch (e) {
      state =
          state.copyWith(isLoading: false, errorMessage: 'Analysis failed: $e');
    }
  }

  /// Load a demo report so the screen is self-contained.
  void loadDemo() {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final report = _service.sampleReport();
      state = state.copyWith(isLoading: false, report: report);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: 'Load failed: $e');
    }
  }

  void reset() => state = const CrewPulseState();
}

/// ─── Provider ───
final crewPulseProvider =
    StateNotifierProvider<CrewPulseNotifier, CrewPulseState>((ref) {
  return CrewPulseNotifier(CrewPulseService());
});
