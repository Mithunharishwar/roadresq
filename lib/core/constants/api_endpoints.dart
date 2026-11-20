/// RoadResQ API Endpoints - Cloud Functions
/// All Firebase Cloud Function endpoints centralized here.
class ApiEndpoints {
  ApiEndpoints._();

  // Base URLs (configured per environment)
  static const String baseUrl =
      'https://us-central1-roadresq-e4b7b.cloudfunctions.net';

  // ──────────── Auth ────────────
  static const String sendOtp = '$baseUrl/sendOtp';
  static const String verifyOtp = '$baseUrl/verifyOtp';
  static const String refreshToken = '$baseUrl/refreshToken';

  // ──────────── Dispatch ────────────
  static const String findNearestCrew = '$baseUrl/findNearestCrew';
  static const String assignCrew = '$baseUrl/assignCrew';
  static const String escalateRequest = '$baseUrl/escalateRequest';
  static const String dispatchTwoManCrew = '$baseUrl/dispatchTwoManCrew';

  // ──────────── Payment ────────────
  static const String createRazorpayOrder = '$baseUrl/createRazorpayOrder';
  static const String verifyPayment = '$baseUrl/verifyPayment';
  static const String generateInvoice = '$baseUrl/generateInvoice';
  static const String processCommission = '$baseUrl/processCommission';

  // ──────────── Token ────────────
  static const String generateToken = '$baseUrl/generateToken';
  static const String validateToken = '$baseUrl/validateToken';
  static const String updateTokenStatus = '$baseUrl/updateTokenStatus';

  // ──────────── Zone Security ────────────
  static const String checkZoneSecurity = '$baseUrl/checkZoneSecurity';
  static const String sendEmergencySms = '$baseUrl/sendEmergencySms';

  // ──────────── Admin ────────────
  static const String getAnalytics = '$baseUrl/getAnalytics';
  static const String processRefund = '$baseUrl/processRefund';
  static const String resolveDispute = '$baseUrl/resolveDispute';
}
