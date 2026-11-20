import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/sos_security_service.dart';

/// SosSecurityState (FEATURE 6)
/// Tracks the OTP/SOS verification flow for fake-SOS prevention.
class SosSecurityState {
  final bool isSendingOtp;
  final bool isVerifyingOtp;
  final bool verified;
  final String? errorMessage;
  final String? devOtp;
  final int sosToday;
  final int sosRemaining;
  final bool limitReached;

  const SosSecurityState({
    this.isSendingOtp = false,
    this.isVerifyingOtp = false,
    this.verified = false,
    this.errorMessage,
    this.devOtp,
    this.sosToday = 0,
    this.sosRemaining = 3,
    this.limitReached = false,
  });

  SosSecurityState copyWith({
    bool? isSendingOtp,
    bool? isVerifyingOtp,
    bool? verified,
    String? errorMessage,
    String? devOtp,
    int? sosToday,
    int? sosRemaining,
    bool? limitReached,
  }) {
    return SosSecurityState(
      isSendingOtp: isSendingOtp ?? this.isSendingOtp,
      isVerifyingOtp: isVerifyingOtp ?? this.isVerifyingOtp,
      verified: verified ?? this.verified,
      errorMessage: errorMessage,
      devOtp: devOtp ?? this.devOtp,
      sosToday: sosToday ?? this.sosToday,
      sosRemaining: sosRemaining ?? this.sosRemaining,
      limitReached: limitReached ?? this.limitReached,
    );
  }
}

class SosSecurityNotifier extends StateNotifier<SosSecurityState> {
  final SosSecurityService _service;

  SosSecurityNotifier(this._service) : super(const SosSecurityState());

  /// Send OTP to the user's phone before SOS dispatch.
  Future<bool> sendOtp({required String phone}) async {
    state = state.copyWith(isSendingOtp: true, errorMessage: null);
    final result = await _service.sendSosOtp(phone: phone);
    if (result['success'] == true && mounted) {
      state = state.copyWith(
        isSendingOtp: false,
        devOtp: result['devOtp'] ?? '',
      );
      return true;
    }
    state = state.copyWith(
      isSendingOtp: false,
      errorMessage: result['message'] ?? 'Failed to send OTP',
    );
    return false;
  }

  /// Verify OTP; enforces the 3-SOS/day limit server-side.
  Future<bool> verifyOtp({required String otp}) async {
    state = state.copyWith(isVerifyingOtp: true, errorMessage: null);
    final result = await _service.verifySosOtp(otp: otp);
    final success = result['success'] == true;
    final sosToday = result['sosToday'] ?? 0;
    final sosRemaining = result['sosRemaining'] ?? 0;
    final limitReached =
        !success && (result['message'] ?? '').toLowerCase().contains('limit');

    state = state.copyWith(
      isVerifyingOtp: false,
      verified: success,
      sosToday: sosToday,
      sosRemaining: sosRemaining,
      limitReached: limitReached,
      errorMessage: success ? null : result['message'] ?? 'Verification failed',
    );
    return success;
  }

  /// Cancel an SOS with penalty (fake cancel).
  Future<Map<String, dynamic>> cancelWithPenalty({
    required String requestId,
    String? reason,
  }) {
    return _service.cancelSosWithPenalty(requestId: requestId, reason: reason);
  }

  void reset() {
    state = const SosSecurityState();
  }
}

final sosSecurityProvider =
    StateNotifierProvider<SosSecurityNotifier, SosSecurityState>((ref) {
  return SosSecurityNotifier(SosSecurityService());
});
