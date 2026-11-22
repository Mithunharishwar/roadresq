import 'dart:convert';
import 'package:material_ui/material_ui.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../services/payment_split_service.dart';

class PaymentScreen extends StatefulWidget {
  final String requestId;
  final String userName;
  final String userPhone;
  final String userEmail;
  final int amount; // service amount in rupees

  const PaymentScreen({
    super.key,
    required this.requestId,
    required this.userName,
    required this.userPhone,
    required this.userEmail,
    required this.amount,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  late Razorpay _razorpay;
  bool isPaymentProcessing = false;
  bool paymentSuccess = false;
  Map<String, dynamic>? lastReceipt;

  /// Publishable Razorpay key id, fetched from the backend.
  ///
  /// This used to be a literal compiled into the app. A key in source cannot be
  /// rotated without shipping a new build, and it silently pointed every build
  /// at the same test account. `/api/payments/config` now supplies it.
  String razorpayKey = '';
  bool _paymentsReady = false;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
    _loadLastReceipt();
    _loadPaymentConfig();
  }

  /// Read the key from the server. If the deployment has no live keys, payment
  /// stays disabled and the screen says so instead of opening a checkout that
  /// cannot succeed.
  Future<void> _loadPaymentConfig() async {
    try {
      final config = await ApiService.fetchPaymentConfig();
      if (!mounted) return;
      setState(() {
        razorpayKey = (config['keyId'] ?? '').toString();
        _paymentsReady = razorpayKey.isNotEmpty;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _paymentsReady = false);
      debugPrint('PaymentScreen: could not load payment config: $e');
    }
  }

  Future<void> _loadLastReceipt() async {
    final prefs = await SharedPreferences.getInstance();
    final receiptData = prefs.getString('receipt_${widget.requestId}');
    if (receiptData != null && mounted) {
      setState(() {
        lastReceipt = jsonDecode(receiptData) as Map<String, dynamic>;
        paymentSuccess = true;
      });
    }
  }

  void openRazorpayPayment() {
    // Without a key there is no checkout to open. Saying so is better than
    // launching Razorpay with an empty key and showing a provider error.
    if (!_paymentsReady || razorpayKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Card payment is not configured on this server. '
            'Set RAZORPAY_KEY_ID / RAZORPAY_KEY_SECRET, or collect cash.',
          ),
        ),
      );
      return;
    }

    setState(() => isPaymentProcessing = true);

    final int gst = (widget.amount * 0.18).round();
    final int totalAmount = widget.amount + gst;

    final options = {
      'key': razorpayKey,
      'amount': totalAmount * 100,
      'name': 'RoadResQ',
      'description': 'Roadside Assistance Service',
      'currency': 'INR',
      'prefill': {
        'contact': widget.userPhone,
        'email': widget.userEmail,
        'name': widget.userName,
      },
      'notes': {'request_id': widget.requestId, 'app': 'RoadResQ'},
      'theme': {'color': '#0D47A1'},
    };

    try {
      _razorpay.open(options);
    } catch (e) {
      if (!mounted) return;
      setState(() => isPaymentProcessing = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Payment error: $e")));
    }
  }

  Future<void> _handlePaymentSuccess(PaymentSuccessResponse response) async {
    if (!mounted) return;
    setState(() => isPaymentProcessing = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Payment Successful: ${response.paymentId}"),
        backgroundColor: Colors.green,
      ),
    );

    // Generate receipt data
    final gst = (widget.amount * 0.18).round();
    final totalAmount = widget.amount + gst;
    final receipt = {
      'receiptId': 'RCP-${DateTime.now().millisecondsSinceEpoch}',
      'requestId': widget.requestId,
      'customerName': widget.userName,
      'customerPhone': widget.userPhone,
      'customerEmail': widget.userEmail,
      'serviceAmount': widget.amount,
      'gst': gst,
      'totalAmount': totalAmount,
      'paymentId': response.paymentId ?? '',
      'orderId': response.orderId ?? '',
      'paymentMethod': 'Razorpay',
      'paidAt': DateTime.now().toIso8601String(),
      'status': 'success',
    };

    // Store receipt locally
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('receipt_${widget.requestId}', jsonEncode(receipt));
    await prefs.setString('last_receipt', jsonEncode(receipt));

    // Save to receipts list
    final receiptsList = prefs.getStringList('receipts') ?? [];
    receiptsList.insert(0, jsonEncode(receipt));
    if (receiptsList.length > 20) receiptsList.removeLast();
    await prefs.setStringList('receipts', receiptsList);

    try {
      await ApiService.updatePaymentStatus(
        requestId: widget.requestId,
        amount: widget.amount.toDouble(),
        paymentStatus: 'success',
        paymentId: response.paymentId ?? '',
        paymentMethod: 'razorpay',
      );
    } catch (e) {
      debugPrint('Payment backend update failed: $e');
    }

    // FEATURE 4: Collect to company, then split payout to the 2-man crew
    // (mechanic + assistant) via the Razorpay Route API. On the test key
    // (Route disabled) the Cloud Function records a pending manual split.
    try {
      final splitResult = await PaymentSplitService().splitPayment(
        requestId: widget.requestId,
        paymentId: response.paymentId ?? '',
        serviceAmount: widget.amount.toDouble(),
      );
      if (splitResult['success'] == true) {
        debugPrint(
          'Payment split queued/processed: ${splitResult['message']} '
          '(mechanic ₹${splitResult['mechanicShare']} / assistant ₹${splitResult['assistantShare']})',
        );
      } else {
        debugPrint('Payment split failed: ${splitResult['message']}');
      }
    } catch (e) {
      debugPrint('Payment split error: $e');
    }

    if (!mounted) return;
    setState(() {
      paymentSuccess = true;
      lastReceipt = receipt;
    });

    // Show receipt dialog
    _showReceiptDialog(receipt);

    Navigator.pop(context, {
      "status": "success",
      "paymentId": response.paymentId,
      "orderId": response.orderId,
      "signature": response.signature,
      "requestId": widget.requestId,
      "receipt": receipt,
    });
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    if (!mounted) return;
    setState(() => isPaymentProcessing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Payment Failed: ${response.message ?? 'Try again'}"),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    if (!mounted) return;
    setState(() => isPaymentProcessing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Wallet Selected: ${response.walletName ?? ''}")),
    );
  }

  void _showReceiptDialog(Map<String, dynamic> receipt) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.receipt_long, color: Colors.green),
            const SizedBox(width: 10),
            const Text('Payment Receipt'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _receiptRow('Receipt #', receipt['receiptId']),
              _receiptRow('Date', _formatDate(receipt['paidAt'])),
              const Divider(),
              _receiptRow('Customer', receipt['customerName']),
              _receiptRow('Phone', receipt['customerPhone']),
              _receiptRow('Payment ID', receipt['paymentId']),
              const Divider(),
              _receiptRow('Service Charge', '₹${receipt['serviceAmount']}'),
              _receiptRow('GST (18%)', '₹${receipt['gst']}'),
              const Divider(),
              _receiptRow('Total', '₹${receipt['totalAmount']}',
                  isBold: true, isTotal: true),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 18),
                    SizedBox(width: 8),
                    Text('Payment Successful',
                        style: TextStyle(
                            color: Colors.green, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _receiptRow(String label, String value,
      {bool isBold = false, bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                fontSize: isTotal ? 16 : 14,
              )),
          Text(value,
              style: TextStyle(
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                fontSize: isTotal ? 16 : 14,
                color: isTotal ? const Color(0xFF0D47A1) : null,
              )),
        ],
      ),
    );
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int gst = (widget.amount * 0.18).round();
    final int totalAmount = widget.amount + gst;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        title: const Text("Payment"),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D47A1),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.payment, color: Colors.white, size: 48),
                    const SizedBox(height: 12),
                    const Text("RoadResQ Secure Payment",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text("Request ID: ${widget.requestId}",
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withAlpha((0.06 * 255).round()),
                        blurRadius: 12),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Bill Summary",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 18),
                    _billRow("Service Charge", "₹${widget.amount}"),
                    _billRow("GST 18%", "₹$gst"),
                    const Divider(height: 28),
                    _billRow("Total Amount", "₹$totalAmount", isBold: true),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withAlpha((0.06 * 255).round()),
                        blurRadius: 12),
                  ],
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Available Payment Options",
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    SizedBox(height: 14),
                    PaymentOption(Icons.account_balance, "UPI"),
                    PaymentOption(Icons.credit_card, "Credit / Debit Card"),
                    PaymentOption(Icons.account_balance_wallet, "Wallet"),
                    PaymentOption(Icons.language, "Net Banking"),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (paymentSuccess && lastReceipt != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.check_circle,
                          color: Colors.green, size: 40),
                      const SizedBox(height: 8),
                      const Text("Payment Completed",
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green)),
                      const SizedBox(height: 4),
                      Text("Receipt: ${lastReceipt!['receiptId']}",
                          style: const TextStyle(color: Colors.black54)),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => _showReceiptDialog(lastReceipt!),
                        icon: const Icon(Icons.receipt),
                        label: const Text('View Receipt'),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: isPaymentProcessing ? null : openRazorpayPayment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D47A1),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: isPaymentProcessing
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5))
                        : Text("Pay ₹$totalAmount",
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Text("Payments are processed securely by Razorpay.",
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _billRow(String title, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: isBold ? 17 : 15,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.w500)),
          Text(value,
              style: TextStyle(
                  fontSize: isBold ? 18 : 15,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                  color: isBold ? const Color(0xFF0D47A1) : Colors.black87)),
        ],
      ),
    );
  }
}

class PaymentOption extends StatelessWidget {
  final IconData icon;
  final String title;

  const PaymentOption(this.icon, this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF0D47A1)),
          const SizedBox(width: 12),
          Text(title, style: const TextStyle(fontSize: 15)),
        ],
      ),
    );
  }
}
