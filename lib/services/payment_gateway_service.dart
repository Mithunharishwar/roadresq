// IMPORTANT: Set Firestore Rules to allow read/write for testing
// FILE: lib/services/payment_gateway_service.dart
/// PaymentGatewayService — Razorpay + Invoice Module
///
/// Implements the spec functions:
///   - createRazorpayOrder(amount)      → Cloud Function
///   - openRazorpayCheckout(orderId)    → client SDK
///   - verifyPaymentSignature()         → Cloud Function (webhook verified server-side)
///   - splitPayoutToCrew(jobId)        → Razorpay Route to 2 crew
///   - getInvoicePDF(jobId)             → invoice/payment record
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../core/constants/app_constants.dart';

/// Payment gateway + invoicing service.
class PaymentGatewayService {
  PaymentGatewayService._internal();
  static final PaymentGatewayService _instance =
      PaymentGatewayService._internal();
  factory PaymentGatewayService() => _instance;

  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Razorpay? _razorpay;

  Razorpay _getRazorpay() {
    _razorpay ??= Razorpay();
    return _razorpay!;
  }

  /// createRazorpayOrder(amount) — server-side order creation.
  Future<Map<String, dynamic>> createRazorpayOrder({
    required double amount,
    String currency = 'INR',
    String receipt = '',
  }) async {
    try {
      final result =
          await _functions.httpsCallable('createRazorpayOrder').call({
        'amount': amount,
        'currency': currency,
        'receipt': receipt,
      });
      final data = result.data as Map<String, dynamic>;
      return {
        'success': data['success'] == true,
        'orderId': data['orderId'] ?? '',
        'amount': data['amount'] ?? 0,
        'currency': data['currency'] ?? 'INR',
        'key': data['key'] ?? '',
      };
    } catch (e) {
      debugPrint('PaymentGatewayService.createRazorpayOrder error: $e');
      return {'success': false, 'orderId': '', 'amount': 0};
    }
  }

  /// openRazorpayCheckout(orderId) — launch the Razorpay SDK.
  void openRazorpayCheckout({
    required String orderId,
    required double amount,
    required String userName,
    String? contact,
    String? email,
    required void Function(String paymentId) onSuccess,
    void Function(String code, String message)? onError,
  }) {
    final rzp = _getRazorpay();
    rzp.clear();

    rzp.on(Razorpay.EVENT_PAYMENT_SUCCESS, (response) {
      final paymentId = response.paymentId ?? '';
      onSuccess(paymentId);
    });
    rzp.on(Razorpay.EVENT_PAYMENT_ERROR, (response) {
      onError?.call(response.code ?? '', response.message ?? '');
    });

    final options = {
      'key': AppConstants.razorpayTestKey,
      'order_id': orderId,
      'amount': (amount * 100).toInt(),
      'name': 'RoadResQ',
      'description': 'Roadside assistance payment',
      'prefill': {'contact': contact ?? '', 'email': email ?? ''},
      'theme': {'color': '#D32F2F'},
    };
    rzp.open(options);
  }

  /// verifyPaymentSignature() — verify a Razorpay signature via the webhook.
  /// The actual signature verification is done server-side; this method
  /// submits the payment + signature to the Cloud Function for verification
  /// and returns the result.
  Future<Map<String, dynamic>> verifyPaymentSignature({
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    try {
      final result =
          await _functions.httpsCallable('verifyPaymentSignature').call({
        'orderId': orderId,
        'paymentId': paymentId,
        'signature': signature,
      });
      final data = result.data as Map<String, dynamic>;
      return {
        'success': data['success'] == true,
        'message': data['message'] ?? '',
        'verified': data['verified'] == true,
      };
    } catch (e) {
      debugPrint('PaymentGatewayService.verifyPaymentSignature error: $e');
      return {
        'success': false,
        'verified': false,
        'message': 'Verification failed'
      };
    }
  }

  /// splitPayoutToCrew(jobId) — split a completed payment to 2 crew via Route API.
  Future<Map<String, dynamic>> splitPayoutToCrew({
    required String jobId,
    required String paymentId,
    required double serviceAmount,
    String? mechanicId,
    String? assistantId,
  }) async {
    try {
      final result = await _functions.httpsCallable('splitPayment').call({
        'requestId': jobId,
        'paymentId': paymentId,
        'serviceAmount': serviceAmount,
        'mechanicId': mechanicId ?? '',
        'assistantId': assistantId ?? '',
      });
      final data = result.data as Map<String, dynamic>;
      return {
        'success': data['success'] == true,
        'splitId': data['splitId'] ?? '',
        'status': data['status'] ?? 'pending',
        'mechanicShare': data['mechanicShare'] ?? 0,
        'assistantShare': data['assistantShare'] ?? 0,
      };
    } catch (e) {
      debugPrint('PaymentGatewayService.splitPayoutToCrew error: $e');
      return {'success': false, 'status': 'failed'};
    }
  }

  /// getInvoicePDF(jobId) — fetch the invoice/payment record (a receipt).
  Future<Map<String, dynamic>> getInvoicePDF({required String jobId}) async {
    try {
      final doc = await _firestore.collection('invoices').doc(jobId).get();
      if (doc.exists) {
        final d = doc.data()!;
        return {
          'success': true,
          'invoiceId': doc.id,
          'receiptNumber': d['receiptNumber'] ?? '',
          'serviceAmount': (d['serviceAmount'] ?? 0).toDouble(),
          'gstAmount': (d['gstAmount'] ?? 0).toDouble(),
          'platformCommission': (d['platformCommission'] ?? 0).toDouble(),
          'totalAmount': (d['totalAmount'] ?? 0).toDouble(),
          'status': d['status'] ?? 'generated',
        };
      }
      return {'success': false, 'message': 'Invoice not found'};
    } on FirebaseException catch (e) {
      debugPrint(
          'PaymentGatewayService.getInvoicePDF FirebaseException: ${e.code} - ${e.message}');
      if (e.code == 'permission-denied') {
        debugPrint('PERMISSION_DENIED: Check Firestore Rules');
      }
      return {'success': false, 'message': 'Failed to fetch invoice'};
    } catch (e) {
      debugPrint('PaymentGatewayService.getInvoicePDF error: $e');
      return {'success': false, 'message': 'Failed to fetch invoice'};
    }
  }

  void dispose() {
    _razorpay?.clear();
  }
}
