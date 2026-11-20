import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';
import 'socket_service.dart';

/// AssistantService
///
/// Provides API methods for assistant (rider / first-responder) operations.
/// Assistants reach the customer on 2-wheelers, assess the situation,
/// do minor fixes, or coordinate with the mechanic for towing.
///
/// This service uses the same backend base URL and pattern as ApiService
/// but for assistant-specific endpoints.
class AssistantService {
  final SocketService _socket = SocketService();
  static const Duration _timeout = Duration(seconds: 15);

  /// Register a new assistant account
  Future<Map<String, dynamic>> register({
    required String name,
    required String phone,
    required String email,
    required String password,
  }) async {
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/assistant/register');
      final response = await http
          .post(uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'name': name,
                'phone': phone,
                'email': email,
                'password': password,
              }))
          .timeout(_timeout);
      return _decode(response);
    } catch (e) {
      return {'success': false, 'message': '$e'};
    }
  }

  /// Login with email/password
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/assistant/login');
      final response = await http
          .post(uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'email': email, 'password': password}))
          .timeout(_timeout);
      return _decode(response);
    } catch (e) {
      return {'success': false, 'message': '$e'};
    }
  }

  /// Request a login OTP for an EXISTING assistant account
  /// (POST /api/assistant/login-otp).
  ///
  /// This used to call /api/mechanic/login-otp, which CREATES a mechanic account
  /// when the phone is unknown — so assistant OTP logins silently provisioned
  /// accounts with the wrong role. The dedicated route only issues an OTP for an
  /// existing role="assistant" account.
  Future<Map<String, dynamic>> loginOtp({
    required String phone,
  }) async {
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/assistant/login-otp');
      final response = await http
          .post(uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'phone': phone}))
          .timeout(_timeout);
      return _decode(response);
    } catch (e) {
      return {'success': false, 'message': '$e'};
    }
  }

  /// Verify the OTP the user actually typed (POST /api/assistant/verify-otp).
  /// Previously the OTP field was read and then discarded, so any code passed.
  Future<Map<String, dynamic>> verifyOtp({
    required String phone,
    required String otp,
  }) async {
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/assistant/verify-otp');
      final response = await http
          .post(uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'phone': phone, 'otp': otp}))
          .timeout(_timeout);
      return _decode(response);
    } catch (e) {
      return {'success': false, 'message': '$e'};
    }
  }

  /// Instant (development-only) assistant access — create if not exists.
  ///
  /// This used to post to `/mechanic/instant` and relabel the reply client-side,
  /// which provisioned the account with `role: "mechanic"`: a rider landed in
  /// the mechanic pool and carried the wrong role everywhere roles are read
  /// (allocation, listings, and Firestore rules keyed on a role claim).
  /// `/assistant/instant` creates and looks up an `assistant`.
  Future<Map<String, dynamic>> instantAccess({
    required String name,
    required String phone,
  }) async {
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/assistant/instant');
      final response = await http
          .post(uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'name': name, 'phone': phone}))
          .timeout(_timeout);
      final data = _decode(response);
      // Tolerate the legacy "mechanic" key so an older backend still works.
      if (!data.containsKey('assistant') && data.containsKey('mechanic')) {
        data['assistant'] = data['mechanic'];
      }
      return data;
    } catch (e) {
      return {'success': false, 'message': '$e'};
    }
  }

  /// Fetch jobs assigned to this assistant
  Future<List<dynamic>> fetchAssignedJobs({
    required String assistantId,
  }) async {
    try {
      final uri =
          Uri.parse('${ApiService.baseUrl}/assistant/$assistantId/jobs');
      final response = await http.get(uri).timeout(_timeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) return data;
      }
      return [];
    } catch (e) {
      debugPrint('AssistantService.fetchAssignedJobs error: $e');
      return [];
    }
  }

  /// Fetch available (unassigned) jobs for assistant
  Future<List<dynamic>> fetchAvailableJobs() async {
    try {
      return await ApiService.fetchAvailableRequests();
    } catch (e) {
      return [];
    }
  }

  /// Accept a job as assistant (calls backend assign-assistant)
  Future<Map<String, dynamic>> acceptJob({
    required String requestId,
    required String assistantId,
    String assistantName = '',
  }) async {
    try {
      return await ApiService.assignAssistant(
        requestId: requestId,
        assistantId: assistantId,
        assistantName: assistantName,
      );
    } catch (e) {
      // If ApiService throws, fall back to direct HTTP
      try {
        final uri = Uri.parse(
            '${ApiService.baseUrl}/rescueRequests/$requestId/assign-assistant');
        final response = await http
            .put(uri,
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'assistantId': assistantId,
                  'assistantName': assistantName,
                }))
            .timeout(_timeout);
        final data = _decode(response);
        return (data['request'] as Map<String, dynamic>?) ?? data;
      } catch (e2) {
        return {'success': false, 'message': '$e2'};
      }
    }
  }

  /// Update assistant location for a request
  Future<void> updateLocation({
    required String requestId,
    required String assistantId,
    required double lat,
    required double lng,
    String assistantStatus = 'active',
  }) async {
    try {
      await ApiService.updateAssistantLocation(
        requestId: requestId,
        assistantId: assistantId,
        lat: lat,
        lng: lng,
      );

      // Emit via socket for real-time updates
      _socket.emit('assistant_location_update', {
        'assistantId': assistantId,
        'requestId': requestId,
        'lat': lat,
        'lng': lng,
      });
    } catch (e) {
      debugPrint('AssistantService.updateLocation error: $e');
    }
  }

  /// Update job status (on_the_way, reached, completed)
  Future<void> updateJobStatus({
    required String requestId,
    required String status,
  }) async {
    try {
      await ApiService.updateRequestStatus(
        requestId: requestId,
        status: status,
      );

      _socket.emit('assistant_status_update', {
        'requestId': requestId,
        'assistantStatus': status,
      });
    } catch (e) {
      debugPrint('AssistantService.updateJobStatus error: $e');
    }
  }

  /// Update online status
  Future<Map<String, dynamic>> updateOnlineStatus({
    required String assistantId,
    required bool online,
  }) async {
    try {
      final uri =
          Uri.parse('${ApiService.baseUrl}/assistant/$assistantId/online');
      final response = await http
          .put(uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'online': online}))
          .timeout(_timeout);
      return _decode(response);
    } catch (e) {
      return {'success': false, 'message': '$e'};
    }
  }

  /// ================= Internal Helpers =================

  Map<String, dynamic> _decode(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      return {'success': false, 'message': 'Invalid response format'};
    } catch (_) {
      return {'success': false, 'message': 'Invalid JSON response'};
    }
  }

  // For debugPrint usage
  void debugPrint(String message) {
    // ignore: avoid_print
    print(message);
  }
}
