import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// SosSecurityService (FEATURE 6)
///
/// Fake SOS prevention:
///  - OTP-verifies the phone before an SOS can be dispatched.
///  - Enforces a 3-SOS/day limit via the `verifySosOtp` Cloud Function.
///  - Records a penalty for fake/late cancellation via `cancelSosWithPenalty`.
///
/// Each method delegates to the matching Cloud Function so the enforcement
/// is server-side (atomic, not bypassable by a malicious client).
class SosSecurityService {
  SosSecurityService._internal();
  static final SosSecurityService _instance = SosSecurityService._internal();
  factory SosSecurityService() => _instance;

  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// Send an OTP to the user's phone for SOS verification.
  /// Returns the (dev) OTP so the flow can be exercised end-to-end in demo.
  Future<Map<String, dynamic>> sendSosOtp({
    required String phone,
  }) async {
    try {
      final result =
          await _functions.httpsCallable('sendSosOtp').call({'phone': phone});
      final data = result.data as Map<String, dynamic>;
      return {
        'success': data['success'] == true,
        'message': data['message'] ?? '',
        'devOtp': data['devOtp'] ?? '',
        'expiresInMin': data['expiresInMin'] ?? 5,
      };
    } on FirebaseFunctionsException catch (e) {
      debugPrint('SosSecurityService.sendSosOtp error: ${e.code} ${e.message}');
      return {'success': false, 'message': e.message ?? 'Failed to send OTP'};
    } catch (e) {
      debugPrint('SosSecurityService.sendSosOtp error: $e');
      return {'success': false, 'message': 'Failed to send OTP'};
    }
  }

  /// Verify the OTP. Enforces the 3-SOS/day limit server-side.
  /// Returns `sosToday` and `sosRemaining` on success.
  Future<Map<String, dynamic>> verifySosOtp({
    required String otp,
  }) async {
    try {
      final result =
          await _functions.httpsCallable('verifySosOtp').call({'otp': otp});
      final data = result.data as Map<String, dynamic>;
      return {
        'success': data['success'] == true,
        'message': data['message'] ?? '',
        'sosToday': data['sosToday'] ?? 0,
        'sosRemaining': data['sosRemaining'] ?? 0,
      };
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
          'SosSecurityService.verifySosOtp error: ${e.code} ${e.message}');
      return {
        'success': false,
        'message': e.message ?? 'OTP verification failed'
      };
    } catch (e) {
      debugPrint('SosSecurityService.verifySosOtp error: $e');
      return {'success': false, 'message': 'OTP verification failed'};
    }
  }

  /// Cancel an SOS after it has been dispatched. Records a ₹50 penalty.
  Future<Map<String, dynamic>> cancelSosWithPenalty({
    required String requestId,
    String? reason,
  }) async {
    try {
      final result = await _functions
          .httpsCallable('cancelSosWithPenalty')
          .call({'requestId': requestId, 'reason': reason ?? ''});
      final data = result.data as Map<String, dynamic>;
      return {
        'success': data['success'] == true,
        'message': data['message'] ?? '',
        'penaltyAmount': data['penaltyAmount'] ?? 0,
      };
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
          'SosSecurityService.cancelSosWithPenalty error: ${e.code} ${e.message}');
      return {'success': false, 'message': e.message ?? 'Failed to cancel'};
    } catch (e) {
      debugPrint('SosSecurityService.cancelSosWithPenalty error: $e');
      return {'success': false, 'message': 'Failed to cancel'};
    }
  }
}
