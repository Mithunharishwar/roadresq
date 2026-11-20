// FILE: lib/core/services/backend_auth_service.dart
/// BackendAuthService — OTP login via the RoadResQ Python + MongoDB backend.
///
/// Replaces Firebase Phone Auth. The backend validates any 10-digit phone and
/// returns the demo OTP `1234` (see backend/roadresq_backend.py), so login
/// works instantly with no Firebase console configuration.
///
/// Endpoints used:
///   POST /api/user/login-otp      { phone }        -> { success, otp, user }
///   POST /api/user/verify-otp     { phone, otp }   -> { success, user }
///   POST /api/mechanic/login-otp  { phone }        -> { success, otp, mechanic }
///   POST /api/mechanic/verify-otp { phone, otp }   -> { success, mechanic }
library;

import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// Base URL for the Python backend.
///
/// Resolves through [AppConfig] — the same single source of truth used by
/// [ApiService] and [SocketService] — instead of a hardcoded LAN address.
///
/// WHY THIS IS A GETTER, NOT A CONST
/// This was previously pinned to `http://192.168.31.206:5050/api`. That address
/// belonged to a DHCP lease this machine no longer holds, so the OTP flow kept
/// dialling a host that no longer exists on the network: every call died at the
/// 15s timeout while the backend log stayed empty, which reads exactly like a
/// dead server. Because [AppConfig] honours the in-app saved host and the
/// `--dart-define=ROADRESQ_HOST=...` override, delegating here means the OTP
/// path can never drift away from the REST and socket clients again.
class BackendAuthService {
  static String get baseUrl => AppConfig.apiBaseUrl;

  static const Duration _timeout = Duration(seconds: 15);

  /// Sends an OTP for the given [phone] and [role].
  ///
  /// Returns a map with `success`, `message`, `otp` (demo `1234`) and the
  /// created/found profile doc. Throws on network/HTTP errors.
  static Future<Map<String, dynamic>> sendOtp({
    required String phone,
    required String role,
  }) async {
    final rolePath = _rolePath(role);
    final uri = Uri.parse('$baseUrl/$rolePath/login-otp');

    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'phone': phone}),
        )
        .timeout(_timeout);

    if (response.statusCode == 200) {
      return _decode(response);
    }
    throw _error('Send OTP failed', response);
  }

  /// Verifies the [code] for the given [phone] and [role].
  ///
  /// Returns the map from the backend (includes the profile doc). Throws on
  /// invalid OTP or network/HTTP errors.
  static Future<Map<String, dynamic>> verifyOtp({
    required String phone,
    required String code,
    required String role,
  }) async {
    final rolePath = _rolePath(role);
    final uri = Uri.parse('$baseUrl/$rolePath/verify-otp');

    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'phone': phone, 'otp': code}),
        )
        .timeout(_timeout);

    if (response.statusCode == 200) {
      return _decode(response);
    }
    throw _error('Verify OTP failed', response);
  }

  /// Maps a role to the backend path segment (`user`, `mechanic`, ...).
  static String _rolePath(String role) {
    switch (role) {
      case 'mechanic':
        return 'mechanic';
      case 'assistant':
        return 'mechanic'; // assistant reuses mechanic OTP for the demo
      case 'garage':
        return 'mechanic';
      default:
        return 'user';
    }
  }

  static Map<String, dynamic> _decode(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return {'success': false, 'message': 'Invalid response format'};
    } catch (_) {
      return {'success': false, 'message': 'Invalid JSON response'};
    }
  }

  static Exception _error(String prefix, http.Response response) {
    final data = _decode(response);
    return Exception('$prefix: ${data['message'] ?? response.body}');
  }
}
