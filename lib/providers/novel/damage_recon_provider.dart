/// AR Damage Recon — Evidence Capture Provider (novel module).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/novel/damage_recon_model.dart';
import '../../services/novel/damage_recon_service.dart';

/// ─── State ───
class DamageReconState {
  final bool isLoading;
  final String? errorMessage;
  final List<DamageCapture> captures;
  final String? lastCaptureId;
  final String? lastHash;

  const DamageReconState({
    this.isLoading = false,
    this.errorMessage,
    this.captures = const [],
    this.lastCaptureId,
    this.lastHash,
  });

  DamageReconState copyWith({
    bool? isLoading,
    String? errorMessage,
    List<DamageCapture>? captures,
    String? lastCaptureId,
    String? lastHash,
  }) {
    return DamageReconState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      captures: captures ?? this.captures,
      lastCaptureId: lastCaptureId ?? this.lastCaptureId,
      lastHash: lastHash ?? this.lastHash,
    );
  }
}

/// ─── Notifier ───
class DamageReconNotifier extends StateNotifier<DamageReconState> {
  final DamageReconService _service;

  DamageReconNotifier(this._service) : super(const DamageReconState());

  /// Capture a damage record.
  Future<void> capture({
    required String jobId,
    required String userId,
    required String crewId,
    required String phase,
    required String imageUrl,
    required double lat,
    required double lng,
    String caption = '',
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    final result = await _service.capture(
      jobId: jobId,
      userId: userId,
      crewId: crewId,
      phase: phase,
      imageUrl: imageUrl,
      lat: lat,
      lng: lng,
      caption: caption,
    );
    state = state.copyWith(
      isLoading: false,
      lastCaptureId: result['captureId']?.toString(),
      lastHash: result['hash']?.toString(),
    );
  }

  /// Load captures for a job.
  Future<void> loadForJob(String jobId) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    final captures = await _service.listForJob(jobId);
    state = state.copyWith(isLoading: false, captures: captures);
  }

  /// Verify the integrity of a capture.
  bool verifyIntegrity(DamageCapture capture) {
    return _service.verifyIntegrity(capture);
  }

  void reset() => state = const DamageReconState();
}

/// ─── Provider ───
final damageReconProvider =
    StateNotifierProvider<DamageReconNotifier, DamageReconState>((ref) {
  return DamageReconNotifier(DamageReconService());
});
