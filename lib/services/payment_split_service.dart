import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// PaymentSplitService (FEATURE 4)
///
/// Payment split via Razorpay Route API.
/// Collects to company account, then splits payout to 2 crew
/// (mechanic + assistant) using the `splitPayment` Cloud Function.
///
/// The Cloud Function uses `razorpay.payments.transfer` and records a
/// `payment_splits` document. On a test key (Route disabled) it fails
/// over to a "pending" manual split record.
class PaymentSplitService {
  PaymentSplitService._internal();
  static final PaymentSplitService _instance = PaymentSplitService._internal();
  factory PaymentSplitService() => _instance;

  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// Split a successful payment between mechanic + assistant.
  ///
  /// [serviceAmount] is the pre-GST service fee (INR). The function deducts
  /// the 10% platform commission and splits the crew pool (default 60/40).
  Future<Map<String, dynamic>> splitPayment({
    required String requestId,
    required String paymentId,
    required double serviceAmount,
    String? mechanicId,
    double? mechanicPayout,
    String? assistantId,
    double? assistantPayout,
  }) async {
    try {
      final result = await _functions.httpsCallable('splitPayment').call({
        'requestId': requestId,
        'paymentId': paymentId,
        'serviceAmount': serviceAmount,
        'mechanicId': mechanicId ?? '',
        'mechanicPayout': mechanicPayout,
        'assistantId': assistantId ?? '',
        'assistantPayout': assistantPayout,
      });
      final data = result.data as Map<String, dynamic>;
      return {
        'success': data['success'] == true,
        'splitId': data['splitId'] ?? '',
        'status': data['status'] ?? 'pending',
        'platformCommission': data['platformCommission'] ?? 0,
        'mechanicShare': data['mechanicShare'] ?? 0,
        'assistantShare': data['assistantShare'] ?? 0,
        'message': data['message'] ?? '',
      };
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
          'PaymentSplitService.splitPayment error: ${e.code} ${e.message}');
      return {'success': false, 'message': e.message ?? 'Split failed'};
    } catch (e) {
      debugPrint('PaymentSplitService.splitPayment error: $e');
      return {'success': false, 'message': 'Split failed'};
    }
  }
}
