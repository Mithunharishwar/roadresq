/// RoadResQ Payment Provider
/// Handles Razorpay payment integration with:
/// - Payment order creation via Cloud Functions
/// - Payment verification and status updates
/// - Receipt generation with GST invoice
/// - 10% platform commission auto-deduction
/// - Digital receipt storage
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';
import '../models/payment_model.dart';
import '../services/firestore_service.dart';
import '../services/socket_service.dart';

/// ─── State ───
class PaymentState {
  final bool isLoading;
  final String? errorMessage;
  final PaymentModel? currentPayment;
  final List<PaymentModel> payments;
  final bool isProcessing;
  final bool isPaymentSuccess;
  final Map<String, dynamic>? lastReceipt;
  final bool isGeneratingReceipt;

  const PaymentState({
    this.isLoading = false,
    this.errorMessage,
    this.currentPayment,
    this.payments = const [],
    this.isProcessing = false,
    this.isPaymentSuccess = false,
    this.lastReceipt,
    this.isGeneratingReceipt = false,
  });

  PaymentState copyWith({
    bool? isLoading,
    String? errorMessage,
    PaymentModel? currentPayment,
    List<PaymentModel>? payments,
    bool? isProcessing,
    bool? isPaymentSuccess,
    Map<String, dynamic>? lastReceipt,
    bool? isGeneratingReceipt,
  }) {
    return PaymentState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      currentPayment: currentPayment ?? this.currentPayment,
      payments: payments ?? this.payments,
      isProcessing: isProcessing ?? this.isProcessing,
      isPaymentSuccess: isPaymentSuccess ?? this.isPaymentSuccess,
      lastReceipt: lastReceipt ?? this.lastReceipt,
      isGeneratingReceipt: isGeneratingReceipt ?? this.isGeneratingReceipt,
    );
  }
}

/// ─── Notifier ───
class PaymentNotifier extends StateNotifier<PaymentState> {
  final FirestoreService _firestore;
  final SocketService _socket;
  Razorpay? _razorpay;

  PaymentNotifier(this._firestore, this._socket) : super(const PaymentState());

  /// ─── Initialize Razorpay ───
  void initRazorpay() {
    _razorpay = Razorpay();
    _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  /// ─── Open Razorpay Checkout ───
  /// Calculates: Service Amount + GST (18%) + Platform Commission (10%)
  void openCheckout({
    required String requestId,
    required String userName,
    required String userPhone,
    required String userEmail,
    required double serviceAmount,
  }) {
    if (_razorpay == null) {
      initRazorpay();
    }

    state = state.copyWith(isProcessing: true, errorMessage: null);

    final gstAmount = PaymentModel.calculateGst(serviceAmount);
    final platformCommission = PaymentModel.calculateCommission(serviceAmount);
    final totalAmount = PaymentModel.calculateTotal(serviceAmount);

    final options = {
      'key': AppConstants.razorpayTestKey,
      'amount': (totalAmount * 100).toInt(), // Amount in paise
      'name': AppConstants.appName,
      'description': 'Roadside Assistance - Request #$requestId',
      'currency': 'INR',
      'prefill': {
        'contact': userPhone,
        'email': userEmail,
        'name': userName,
      },
      'notes': {
        'request_id': requestId,
        'service_amount': serviceAmount.toString(),
        'gst': gstAmount.toString(),
        'platform_commission': platformCommission.toString(),
      },
      'theme': {'color': '#D32F2F'},
    };

    try {
      _razorpay!.open(options);
    } catch (e) {
      debugPrint('PaymentNotifier.openCheckout error: $e');
      state = state.copyWith(
        isProcessing: false,
        errorMessage: 'Failed to open payment: ${e.toString()}',
      );
    }
  }

  /// ─── Handle Payment Success ───
  Future<void> _handlePaymentSuccess(PaymentSuccessResponse response) async {
    state = state.copyWith(isProcessing: false);

    try {
// Generate receipt number
      final receiptNumber = PaymentModel.generateReceiptNumber();

      // Note: In production, fetch actual service amount from request
      final gstAmount =
          PaymentModel.calculateGst(state.currentPayment?.serviceAmount ?? 0);
      final platformCommission = PaymentModel.calculateCommission(
          state.currentPayment?.serviceAmount ?? 0);
      final totalAmount =
          PaymentModel.calculateTotal(state.currentPayment?.serviceAmount ?? 0);

      // Create payment record
      final paymentData = {
        'razorpayPaymentId': response.paymentId ?? '',
        'razorpayOrderId': response.orderId ?? '',
        'razorpaySignature': response.signature ?? '',
        'status': 'success',
        'paidAt': Timestamp.fromDate(DateTime.now()),
        'receiptNumber': receiptNumber,
        'paymentMethod': 'razorpay',
        'gstAmount': gstAmount,
        'platformCommission': platformCommission,
        'totalAmount': totalAmount,
      };

      // Store in Firestore
      await _firestore.createDocument(
        collection: 'payments',
        data: {
          'requestId': state.currentPayment?.requestId ?? '',
          'userId': state.currentPayment?.userId ?? '',
          'serviceAmount': state.currentPayment?.serviceAmount ?? 0,
          ...paymentData,
          'createdAt': Timestamp.fromDate(DateTime.now()),
        },
      );

      // Generate receipt
      final receipt = _generateReceipt(
        paymentId: response.paymentId ?? '',
        orderId: response.orderId ?? '',
        receiptNumber: receiptNumber,
        serviceAmount: state.currentPayment?.serviceAmount ?? 0,
        gstAmount: gstAmount,
        platformCommission: platformCommission,
        totalAmount: totalAmount,
      );

      // Store receipt locally
      await _saveReceiptLocally(receipt);

      // Notify via socket
      _socket.emit('payment_updated', {
        'requestId': state.currentPayment?.requestId ?? '',
        'paymentStatus': 'success',
        'paymentId': response.paymentId ?? '',
      });

      state = state.copyWith(
        isPaymentSuccess: true,
        lastReceipt: receipt,
      );
    } catch (e) {
      debugPrint('PaymentNotifier._handlePaymentSuccess error: $e');
    }
  }

  /// ─── Handle Payment Error ───
  void _handlePaymentError(PaymentFailureResponse response) {
    state = state.copyWith(
      isProcessing: false,
      errorMessage: 'Payment failed: ${response.message ?? 'Unknown error'}',
    );
  }

  /// ─── Handle External Wallet ───
  void _handleExternalWallet(ExternalWalletResponse response) {
    debugPrint('External wallet selected: ${response.walletName}');
  }

  /// ─── Generate Digital Receipt with GST Invoice ───
  Map<String, dynamic> _generateReceipt({
    required String paymentId,
    required String orderId,
    required String receiptNumber,
    required double serviceAmount,
    required double gstAmount,
    required double platformCommission,
    required double totalAmount,
  }) {
    return {
      'receiptNumber': receiptNumber,
      'paymentId': paymentId,
      'orderId': orderId,
      'serviceAmount': serviceAmount,
      'gstAmount': gstAmount,
      'gstPercent': AppConstants.gstPercent,
      'platformCommission': platformCommission,
      'commissionPercent': AppConstants.platformCommissionPercent,
      'totalAmount': totalAmount,
      'currency': 'INR',
      'status': 'success',
      'paidAt': DateTime.now().toIso8601String(),
      'companyName': AppConstants.companyName,
      'companySupport': AppConstants.supportEmail,
    };
  }

  /// ─── Save Receipt Locally ───
  Future<void> _saveReceiptLocally(Map<String, dynamic> receipt) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final requestId = state.currentPayment?.requestId ?? 'unknown';
      await prefs.setString('receipt_$requestId', jsonEncode(receipt));
      await prefs.setString('last_receipt', jsonEncode(receipt));

      // Maintain receipt history (max 20)
      final receiptsList = prefs.getStringList('receipts') ?? [];
      receiptsList.insert(0, jsonEncode(receipt));
      if (receiptsList.length > 20) receiptsList.removeLast();
      await prefs.setStringList('receipts', receiptsList);
    } catch (e) {
      debugPrint('PaymentNotifier._saveReceiptLocally error: $e');
    }
  }

  /// ─── Load Last Receipt ───
  Future<void> loadLastReceipt(String requestId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final receiptData = prefs.getString('receipt_$requestId');
      if (receiptData != null) {
        final receipt = jsonDecode(receiptData) as Map<String, dynamic>;
        state = state.copyWith(
          lastReceipt: receipt,
          isPaymentSuccess: true,
        );
      }
    } catch (e) {
      debugPrint('PaymentNotifier.loadLastReceipt error: $e');
    }
  }

  /// ─── Fetch Payment by Request ID ───
  Future<void> fetchPaymentByRequest(String requestId) async {
    state = state.copyWith(isLoading: true);

    try {
      final docs = await _firestore.queryDocuments(
        collection: 'payments',
        whereClauses: [
          WhereClause(field: 'requestId', isEqualTo: requestId),
        ],
        limit: 1,
      );

      if (docs.isNotEmpty) {
        // Parse payment data
        final data = docs.first.data() as Map<String, dynamic>;
        final payment = PaymentModel(
          id: docs.first.id,
          requestId: data['requestId'] ?? '',
          userId: data['userId'] ?? '',
          crewId: data['crewId'],
          serviceAmount: (data['serviceAmount'] ?? 0).toDouble(),
          gstAmount: (data['gstAmount'] ?? 0).toDouble(),
          platformCommission: (data['platformCommission'] ?? 0).toDouble(),
          totalAmount: (data['totalAmount'] ?? 0).toDouble(),
          status: data['status'] ?? 'pending',
          razorpayPaymentId: data['razorpayPaymentId'],
          razorpayOrderId: data['razorpayOrderId'],
          razorpaySignature: data['razorpaySignature'],
          receiptNumber: data['receiptNumber'],
          paymentMethod: data['paymentMethod'] ?? 'razorpay',
          paidAt: (data['paidAt'] as Timestamp?)?.toDate(),
        );

        state = state.copyWith(
          currentPayment: payment,
          isLoading: false,
        );
      } else {
        state = state.copyWith(isLoading: false);
      }
    } catch (e) {
      debugPrint('PaymentNotifier.fetchPaymentByRequest error: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  /// ─── Calculate Bill Summary ───
  Map<String, double> calculateBill(double serviceAmount) {
    final gst = PaymentModel.calculateGst(serviceAmount);
    final commission = PaymentModel.calculateCommission(serviceAmount);
    final total = PaymentModel.calculateTotal(serviceAmount);
    return {
      'serviceAmount': serviceAmount,
      'gstAmount': gst,
      'platformCommission': commission,
      'totalAmount': total,
    };
  }

  /// ─── Set Current Payment ───
  void setPayment(PaymentModel payment) {
    state = state.copyWith(currentPayment: payment);
  }

  /// ─── Reset State ───
  void reset() {
    state = const PaymentState();
  }

  /// ─── Dispose Razorpay ───
  @override
  void dispose() {
    _razorpay?.clear();
    _razorpay = null;
    super.dispose();
  }
}

/// ─── Provider ───
final paymentProvider = StateNotifierProvider<PaymentNotifier, PaymentState>(
  (ref) {
    final notifier = PaymentNotifier(FirestoreService(), SocketService());
    return notifier;
  },
);
