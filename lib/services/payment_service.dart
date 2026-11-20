import 'package:firebase_database/firebase_database.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

/// PaymentService
/// - Uses Razorpay for payments
/// - Updates Firebase with payment status when completed
class PaymentService {
  final Razorpay _razorpay = Razorpay();
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  PaymentService() {
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  void dispose() {
    _razorpay.clear();
  }

  /// Open razorpay checkout for a given job
  /// amount is in INR rupees (e.g., 150.0), internal conversion to paise is required
  void openCheckout(
      {required String jobId,
      required double amount,
      required String userName,
      String? contact,
      String? email}) {
    final options = {
      'key': 'rzp_test_SbTmM0x0VYHxcN', // TODO: set from secure config or env
      'amount': (amount * 100).toInt(), // paise
      'name': 'RoadResQ',
      'description': 'Payment for job $jobId',
      'prefill': {'contact': contact ?? '', 'email': email ?? ''},
      'notes': {'jobId': jobId},
      'theme': {'color': '#FF3333'}
    };

    _razorpay.open(options);
  }

  Future<void> _handlePaymentSuccess(PaymentSuccessResponse response) async {
    // paymentId: response.paymentId
    final now = DateTime.now().toUtc().toIso8601String();

    final paymentKey = response.paymentId ?? now;
    await _db.child('payments').child(paymentKey).set({
      'paymentId': response.paymentId,
      'orderId': response.orderId ?? '',
      'signature': response.signature ?? '',
      'status': 'success',
      'createdAt': now,
    });
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    final now = DateTime.now().toUtc().toIso8601String();
    _db.child('payments').child('errors').child(now).set({
      'code': response.code,
      'message': response.message,
    });
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    // handle if user selects external wallet
  }
}
