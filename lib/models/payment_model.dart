/// PaymentModel — Handles billing, receipts, GST invoices, and platform commission.
/// Used for Razorpay integration and digital receipt generation.
class PaymentModel {
  final String id;
  final String requestId;
  final String userId;
  final String? crewId;
  final double serviceAmount;
  final double gstAmount;
  final double platformCommission;
  final double totalAmount;
  final String currency;
  final String status; // pending, success, failed, refunded
  final String? razorpayOrderId;
  final String? razorpayPaymentId;
  final String? razorpaySignature;
  final String? invoiceUrl;
  final String? receiptNumber;
  final String paymentMethod; // razorpay, cash, wallet
  final DateTime createdAt;
  final DateTime? paidAt;
  final DateTime? refundedAt;

  PaymentModel({
    required this.id,
    required this.requestId,
    required this.userId,
    this.crewId,
    required this.serviceAmount,
    required this.gstAmount,
    required this.platformCommission,
    required this.totalAmount,
    this.currency = 'INR',
    this.status = 'pending',
    this.razorpayOrderId,
    this.razorpayPaymentId,
    this.razorpaySignature,
    this.invoiceUrl,
    this.receiptNumber,
    this.paymentMethod = 'razorpay',
    DateTime? createdAt,
    this.paidAt,
    this.refundedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Generate a formatted receipt for display
  Map<String, dynamic> generateReceipt() {
    return {
      'receiptNumber':
          receiptNumber ?? 'RCP-${DateTime.now().millisecondsSinceEpoch}',
      'requestId': requestId,
      'serviceAmount': serviceAmount,
      'gstAmount': gstAmount,
      'platformCommission': platformCommission,
      'totalAmount': totalAmount,
      'currency': currency,
      'status': status,
      'paymentId': razorpayPaymentId ?? '',
      'paymentMethod': paymentMethod,
      'paidAt': paidAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
    };
  }

  /// Calculate GST (18%) on service amount
  static double calculateGst(double serviceAmount) {
    return serviceAmount * 0.18;
  }

  /// Calculate platform commission (10%) on service amount
  static double calculateCommission(double serviceAmount) {
    return serviceAmount * 0.10;
  }

  /// Calculate total with GST + commission
  static double calculateTotal(double serviceAmount) {
    return serviceAmount +
        calculateGst(serviceAmount) +
        calculateCommission(serviceAmount);
  }

  /// Generate receipt number in format: RCP-YYYYMMDD-XXXX
  static String generateReceiptNumber() {
    final now = DateTime.now();
    final date =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final random =
        (now.millisecondsSinceEpoch % 10000).toString().padLeft(4, '0');
    return 'RCP-$date-$random';
  }
}
