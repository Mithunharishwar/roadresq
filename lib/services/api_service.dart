// IMPORTANT: Set Firestore Rules to allow read/write for testing
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';

/// Thrown when the backend answers 404 for a specific resource.
///
/// Deliberately distinct from a transport failure. The server is reachable and
/// answered; it simply has no such record. Polling screens must tell the two
/// apart — a request that no longer exists has to stop the poll and say so
/// rather than retry every few seconds forever.
class ApiNotFoundException implements Exception {
  ApiNotFoundException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A rejected credential or a conflict, carrying the HTTP status and the
/// server's own message.
///
/// Pages need the status to react precisely:
///   401 — wrong ID/password: offer to check them or to register instead.
///   409 — already registered: offer to sign in instead.
/// A bare `Exception` cannot express that, which is how the garage page ended
/// up printing the same "Login failed: ..." for every possible cause, and why a
/// partner with no account could not tell that no account existed.
class ApiAuthException implements Exception {
  ApiAuthException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  bool get isUnauthorized => statusCode == 401;
  bool get isConflict => statusCode == 409;

  @override
  String toString() => message;
}

/// Outcome of a lifecycle transition attempt.
///
/// [allowedNext] is what the backend says may happen next (it refuses anything
/// else with 409). The garage dashboard renders those as choices, so the user
/// never has to guess which button the state machine will accept.
class StatusAttempt {
  const StatusAttempt({
    required this.ok,
    required this.message,
    this.allowedNext = const <String>[],
  });

  final bool ok;
  final String message;
  final List<String> allowedNext;

  @override
  String toString() => 'StatusAttempt(ok: $ok, message: $message, allowed: $allowedNext)';
}

class ApiService {
  /// Backend origin, resolved once by [AppConfig].
  ///
  /// This replaces a hardcoded `http://192.168.31.206:5050/api`. REST and
  /// Socket.IO now read the same value from AppConfig, so they can no longer
  /// drift apart and no development IP is compiled into the app.
  ///
  /// Physical device:
  ///   `flutter run --dart-define=ROADRESQ_HOST=http://<your-lan-ip>:5050`
  /// Android emulator:
  ///   flutter run --dart-define=ROADRESQ_EMULATOR=true
  static String get defaultBaseUrl => AppConfig.apiBaseUrl;

  /// REST base URL used by every method in this service.
  static String get baseUrl => AppConfig.apiBaseUrl;

  static const Duration _timeout = AppConfig.requestTimeout;

  static Map<String, dynamic> _decodeResponse(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return {'success': false, 'message': 'Invalid response format'};
    } catch (_) {
      return {
        'success': false,
        'message': 'Invalid JSON response',
        'raw': response.body,
      };
    }
  }

  static Exception _error(String prefix, http.Response response) {
    // Prefer the server's own message when it actually sent one.
    final body = response.body.trim();
    if (body.isNotEmpty) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map) {
          final msg = decoded['message'] ?? decoded['error'];
          if (msg != null) {
            return Exception('$prefix: $msg');
          }
        }
      } catch (_) {
        // Not JSON — fall through and describe it below.
      }
    }

    // Never report "Invalid JSON response" for an empty or HTML error body:
    // that hides the actionable fact, which is the HTTP status. A 500 means the
    // server faulted; an empty body is a server-side crash, not a client bug.
    final detail = body.isEmpty
        ? 'server returned an empty body'
        : 'non-JSON body: ${body.length > 120 ? '${body.substring(0, 120)}...' : body}';
    return Exception('$prefix: HTTP ${response.statusCode} ($detail)');
  }

  /// The server's own message for a failed response, or null when it sent none.
  ///
  /// Shared by [_error] and [_authError] so both prefer the real reason the
  /// backend gave over a generic client-side string.
  static String? _serverMessage(http.Response response) {
    final body = response.body.trim();
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final msg = decoded['message'] ?? decoded['error'];
        if (msg is String && msg.trim().isNotEmpty) return msg.trim();
      }
    } catch (_) {
      // Not JSON — no usable message.
    }
    return null;
  }

  /// A typed auth failure, so a page can tell 401 from 409.
  static ApiAuthException _authError(String prefix, http.Response response) {
    final server = _serverMessage(response);
    return ApiAuthException(
      response.statusCode,
      server ?? '$prefix (HTTP ${response.statusCode})',
    );
  }

  // ================= USER =================

  static Future<Map<String, dynamic>> userRegister({
    required String name,
    required String phone,
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse('$baseUrl/user/signup');

    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'name': name,
            'phone': phone,
            'email': email,
            'password': password,
          }),
        )
        .timeout(_timeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      return _decodeResponse(response);
    }

    throw _error('User register failed', response);
  }

  static Future<Map<String, dynamic>> userSignup({
    required String name,
    required String phone,
    required String email,
    required String password,
  }) async {
    return userRegister(
      name: name,
      phone: phone,
      email: email,
      password: password,
    );
  }

  static Future<Map<String, dynamic>> userLogin({
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse('$baseUrl/user/login');

    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(_timeout);

    if (response.statusCode == 200) {
      return _decodeResponse(response);
    }

    throw _error('User login failed', response);
  }

  static Future<Map<String, dynamic>> userLoginWithEmail({
    required String email,
    required String password,
  }) async {
    return userLogin(email: email, password: password);
  }

  // ================= MECHANIC =================

  static Future<Map<String, dynamic>> mechanicRegister({
    required String name,
    String phone = '',
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse('$baseUrl/mechanic/register');

    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'name': name,
            'phone': phone,
            'email': email,
            'password': password,
          }),
        )
        .timeout(_timeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      return _decodeResponse(response);
    }

    throw _error('Mechanic register failed', response);
  }

  static Future<Map<String, dynamic>> mechanicLogin({
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse('$baseUrl/mechanic/login');

    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(_timeout);

    if (response.statusCode == 200) {
      return _decodeResponse(response);
    }

    throw _error('Mechanic login failed', response);
  }

  static Future<Map<String, dynamic>> mechanicLoginOtp({
    required String phone,
  }) async {
    final uri = Uri.parse('$baseUrl/mechanic/login-otp');

    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'phone': phone}),
        )
        .timeout(_timeout);

    if (response.statusCode == 200) {
      return _decodeResponse(response);
    }

    throw _error('Mechanic OTP login failed', response);
  }

  static Future<Map<String, dynamic>> mechanicOtpLogin({
    required String phone,
  }) async {
    return mechanicLoginOtp(phone: phone);
  }

  static Future<Map<String, dynamic>> mechanicInstantAccess({
    required String name,
    required String phone,
  }) async {
    final uri = Uri.parse('$baseUrl/mechanic/instant');

    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'name': name, 'phone': phone}),
        )
        .timeout(_timeout);

    if (response.statusCode == 200) {
      return _decodeResponse(response);
    }

    throw _error('Mechanic instant access failed', response);
  }

// ================= OTP COMMON METHODS =================
  // These call the Python backend's /user/* and /mechanic/* OTP endpoints.
  // The backend returns demo OTP "1234" for both user and mechanic.

  static Future<Map<String, dynamic>> sendOtp({
    required String phone,
    bool isMechanic = false,
  }) async {
    if (isMechanic) {
      return mechanicLoginOtp(phone: phone);
    }

    final uri = Uri.parse('$baseUrl/user/login-otp');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'phone': phone}),
        )
        .timeout(_timeout);

    if (response.statusCode == 200) {
      return _decodeResponse(response);
    }
    throw _error('User OTP login failed', response);
  }

  static Future<Map<String, dynamic>> verifyOtp({
    required String phone,
    required String otp,
    bool isMechanic = false,
  }) async {
    final String path = isMechanic ? 'mechanic' : 'user';
    final uri = Uri.parse('$baseUrl/$path/verify-otp');

    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'phone': phone, 'otp': otp}),
        )
        .timeout(_timeout);

    if (response.statusCode == 200) {
      return _decodeResponse(response);
    }
    throw _error('OTP verification failed', response);
  }

  // ================= GARAGE AUTH =================

  /// Register a garage (POST /api/garage/register).
  static Future<Map<String, dynamic>> garageRegister({
    required String garageId,
    required String name,
    required String password,
    String phone = '',
  }) async {
    final uri = Uri.parse('$baseUrl/garage/register');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'garageId': garageId,
            'name': name,
            'password': password,
            'phone': phone,
          }),
        )
        .timeout(_timeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      return _decodeResponse(response);
    }
    throw _authError('Garage registration failed', response);
  }

  /// Authenticate a garage (POST /api/garage/login). Returns 401 on bad
  /// credentials — the previous flow performed no credential check at all.
  static Future<Map<String, dynamic>> garageLogin({
    required String garageId,
    required String password,
  }) async {
    final uri = Uri.parse('$baseUrl/garage/login');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'garageId': garageId, 'password': password}),
        )
        .timeout(_timeout);

    if (response.statusCode == 200) {
      return _decodeResponse(response);
    }
    throw _authError('Garage login failed', response);
  }

  /// Requests linked to a garage (`GET /api/garage/<garageId>/jobs`).
  ///
  /// The Garage dashboard used to stream Firestore `jobs`, which the app cannot
  /// read (no Firebase Auth session — see core/utils/firestore_failure.dart).
  /// This is the backend path that replaces it. Returns an empty list when
  /// nothing is linked yet, which is the honest answer: no `rescue_requests`
  /// document currently records a `garageId`.
  static Future<List<dynamic>> fetchGarageJobs(String garageId) async {
    if (garageId.isEmpty) return const <dynamic>[];

    final uri = Uri.parse('$baseUrl/garage/$garageId/jobs');
    final response = await http.get(uri).timeout(_timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }

    throw _error('Fetch garage jobs failed', response);
  }

  /// Requests a garage can take in (`GET /garage/<garageId>/inbox`).
  ///
  /// The companion to [fetchGarageJobs]: that list only contains work already
  /// linked to this garage, and nothing ever wrote the link — so the garage had
  /// no way to acquire a job at all. This is the intake queue.
  static Future<List<dynamic>> fetchGarageInbox(String garageId) async {
    final uri = Uri.parse('$baseUrl/garage/$garageId/inbox');
    final response = await http.get(uri).timeout(_timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }

    throw _error('Fetch garage inbox failed', response);
  }

  /// Hands a request over to a garage (`PUT /rescueRequests/<id>/garage`).
  ///
  /// This is the handover event: after it succeeds the request appears in
  /// [fetchGarageJobs] for that garage. Repeating it is a no-op, so a double tap
  /// cannot corrupt anything.
  static Future<Map<String, dynamic>> linkRequestToGarage({
    required String requestId,
    required String garageId,
  }) async {
    final uri = Uri.parse('$baseUrl/rescueRequests/$requestId/garage');
    final response = await http
        .put(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'garageId': garageId}),
        )
        .timeout(_timeout);

    if (response.statusCode == 200) {
      final data = _decodeResponse(response);
      return (data['request'] as Map<String, dynamic>?) ?? data;
    }

    throw _error('Link request to garage failed', response);
  }

  /// A status change that reports refusal instead of throwing.
  ///
  /// The backend owns the lifecycle graph (`backend/status_machine.py`) and
  /// answers 409 with `allowedNextStates`. Returning those lets the garage offer
  /// exactly the transitions the server will accept, instead of guessing and
  /// showing a red error the user cannot act on.
  static Future<StatusAttempt> tryUpdateRequestStatus({
    required String requestId,
    required String status,
  }) async {
    final uri = Uri.parse('$baseUrl/rescueRequests/$requestId/status');
    try {
      final response = await http
          .put(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'status': status}),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        return const StatusAttempt(ok: true, message: 'Status updated');
      }

      final allowed = <String>[];
      var message = 'Update failed (${response.statusCode})';
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final raw = body['allowedNextStates'];
        if (raw is List) allowed.addAll(raw.map((e) => e.toString()));
        final text = body['message'] ?? body['error'];
        if (text != null) message = text.toString();
      } catch (_) {
        // Non-JSON refusal: keep the status-code message.
      }
      return StatusAttempt(ok: false, message: message, allowedNext: allowed);
    } catch (e) {
      return StatusAttempt(ok: false, message: e.toString());
    }
  }

  /// Lightweight reachability probe for the in-app server setting.
  ///
  /// Returns true when the backend answers within [timeout]. Uses `/zones`: a
  /// small, read-only endpoint that exists on every build of this backend.
  /// Deliberately does NOT throw — the caller is asking "is this address
  /// usable?", and "no" is an ordinary answer.
  static Future<bool> probeBackend({Duration? timeout}) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/zones'))
          .timeout(timeout ?? const Duration(seconds: 6));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ================= ZONES =================

  /// Zone list (`GET /api/zones`).
  ///
  /// Replaces the Firestore `zones` read in ZoneSecurityService, which the app
  /// cannot perform (no Firebase Auth session — see
  /// core/utils/firestore_failure.dart).
  static Future<List<dynamic>> fetchZones() async {
    final uri = Uri.parse('$baseUrl/zones');
    final response = await http.get(uri).timeout(_timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }

    throw _error('Fetch zones failed', response);
  }

  // ================= RESCUE REQUEST =================

  static Future<Map<String, dynamic>> createRescueRequest({
    required String name,
    required String phone,
    required String issue,
    required String vehicle,
    required String locationText,
    required double lat,
    required double lng,
    String issueDescription = '',
    String userId = '',
  }) async {
    final uri = Uri.parse('$baseUrl/rescueRequests');

    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'name': name,
            'phone': phone,
            'issue': issue,
            'vehicle': vehicle,
            'locationText': locationText,
            'location': {'lat': lat, 'lng': lng},
            // §12 — the customer's own words, stored separately from the
            // issue category so a mechanic reads the detail before arriving.
            if (issueDescription.trim().isNotEmpty)
              'issueDescription': issueDescription.trim(),
            if (userId.trim().isNotEmpty) 'userId': userId.trim(),
          }),
        )
        .timeout(_timeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = _decodeResponse(response);
      final request =
          (data['request'] as Map<String, dynamic>?) ?? <String, dynamic>{};

      final requestId =
          request['_id']?.toString() ?? request['id']?.toString() ?? '';

      return {
        'id': requestId,
        ...request,
        'success': data['success'],
        'message': data['message'],
      };
    }

    throw _error('Create request failed', response);
  }

  static Future<List<dynamic>> getRescueRequests() async {
    final uri = Uri.parse('$baseUrl/rescueRequests');

    final response = await http.get(uri).timeout(_timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }

    throw _error('Fetch requests failed', response);
  }

  /// One customer's own requests.
  ///
  /// `getRescueRequests()` returns the whole table, which is correct for the
  /// mechanic/admin views and wrong for a customer: "My Requests" was listing
  /// other people's rescues with their location and phone number on screen.
  static Future<List<dynamic>> fetchUserRequests(String phone) async {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      debugPrint('[api] fetchUserRequests called without a phone — returning none');
      return <dynamic>[];
    }

    final uri = Uri.parse('$baseUrl/rescueRequests')
        .replace(queryParameters: {'phone': digits});

    final response = await http.get(uri).timeout(_timeout);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw _error('Fetch your requests failed', response);
  }

  static Future<List<dynamic>> fetchRequests() async {
    return getRescueRequests();
  }

  static Future<Map<String, dynamic>> getRescueRequestById(
    String requestId,
  ) async {
    final uri = Uri.parse('$baseUrl/rescueRequests/$requestId');

    final response = await http.get(uri).timeout(_timeout);

    if (response.statusCode == 200) {
      return _decodeResponse(response);
    }

    // 404 is a different situation from a transport failure: the server is up
    // and answered, it just has no such record. A screen polling a remembered
    // id must be able to tell those apart, or a request that no longer exists
    // produces an endless "failed to load" loop with nothing on screen.
    if (response.statusCode == 404) {
      throw ApiNotFoundException(
        'No rescue request with id $requestId exists on the server.',
      );
    }

    throw _error('Fetch request by id failed', response);
  }

  static Future<Map<String, dynamic>> fetchRequestById(String requestId) async {
    return getRescueRequestById(requestId);
  }

  static Future<Map<String, dynamic>> assignMechanic({
    required String requestId,
    required String mechanicId,
    String mechanicName = '',
  }) async {
    final uri = Uri.parse('$baseUrl/rescueRequests/$requestId/assign');

    final response = await http
        .put(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'mechanicId': mechanicId,
            'mechanicName': mechanicName,
          }),
        )
        .timeout(_timeout);

    if (response.statusCode == 200) {
      final data = _decodeResponse(response);
      return (data['request'] as Map<String, dynamic>?) ?? data;
    }

    throw _error('Assign mechanic failed', response);
  }

  static Future<Map<String, dynamic>> assignMechanicToRequest({
    required String requestId,
    required String mechanicId,
    String mechanicName = '',
  }) async {
    return assignMechanic(
      requestId: requestId,
      mechanicId: mechanicId,
      mechanicName: mechanicName,
    );
  }

  static Future<Map<String, dynamic>> updateRequestStatus({
    required String requestId,
    required String status,
  }) async {
    final uri = Uri.parse('$baseUrl/rescueRequests/$requestId/status');

    final response = await http
        .put(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'status': status}),
        )
        .timeout(_timeout);

    if (response.statusCode == 200) {
      final data = _decodeResponse(response);
      return (data['request'] as Map<String, dynamic>?) ?? data;
    }

    throw _error('Update status failed', response);
  }

  static Future<List<dynamic>> fetchAvailableRequests({
    String? mechanicId,
  }) async {
    final uri = Uri.parse('$baseUrl/rescueRequests/available');

    final response = await http.get(uri).timeout(_timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }

    throw _error('Fetch available requests failed', response);
  }

  static Future<List<dynamic>> fetchMechanicRequests({
    String? mechanicId,
  }) async {
    // No id means "this mechanic is unknown" — NOT "show every request".
    // This used to fall through to getRescueRequests(), the unscoped
    // /api/rescueRequests endpoint, so a mechanic screen that lost the id would
    // list every customer's request in the system. Returning nothing is the
    // only safe answer, and it matches the backend's own scoping fix (§39).
    if (mechanicId == null || mechanicId.isEmpty) {
      debugPrint(
        '[api] fetchMechanicRequests called without a mechanicId — returning '
        'nothing rather than every request',
      );
      return <dynamic>[];
    }

    final uri = Uri.parse('$baseUrl/mechanic/$mechanicId/requests');

    final response = await http.get(uri).timeout(_timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }

    throw _error('Fetch mechanic requests failed', response);
  }

  // ================= MECHANIC LIVE =================

  static Future<Map<String, dynamic>> updateMechanicOnline({
    required String mechanicId,
    required bool online,
  }) async {
    final uri = Uri.parse('$baseUrl/mechanic/$mechanicId/online');

    final response = await http
        .put(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'online': online}),
        )
        .timeout(_timeout);

    if (response.statusCode == 200) {
      final data = _decodeResponse(response);
      return (data['mechanic'] as Map<String, dynamic>?) ?? data;
    }

    throw _error('Update mechanic online failed', response);
  }

  static Future<Map<String, dynamic>> updateMechanicOnlineStatus({
    required String mechanicId,
    required bool online,
  }) async {
    return updateMechanicOnline(mechanicId: mechanicId, online: online);
  }

  static Future<Map<String, dynamic>> updateMechanicLocation({
    required String mechanicId,
    required double lat,
    required double lng,
    String requestId = '',
  }) async {
    final uri = Uri.parse('$baseUrl/mechanic/$mechanicId/location');

    final response = await http
        .put(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'lat': lat, 'lng': lng, 'requestId': requestId}),
        )
        .timeout(_timeout);

    if (response.statusCode == 200) {
      final data = _decodeResponse(response);
      return (data['mechanic'] as Map<String, dynamic>?) ?? data;
    }

    throw _error('Update mechanic location failed', response);
  }

  static Future<Map<String, dynamic>> updateRequestMechanicLocation({
    required String requestId,
    required String mechanicId,
    required double lat,
    required double lng,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/rescueRequests/$requestId/mechanic-location',
    );

    final response = await http
        .put(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'mechanicId': mechanicId, 'lat': lat, 'lng': lng}),
        )
        .timeout(_timeout);

    if (response.statusCode == 200) {
      return _decodeResponse(response);
    }

    throw _error('Update request mechanic location failed', response);
  }

  // ================= ASSISTANT (Milestone 1) =================

  static Future<Map<String, dynamic>> assignAssistant({
    required String requestId,
    required String assistantId,
    String assistantName = '',
  }) async {
    final uri = Uri.parse(
      '$baseUrl/rescueRequests/$requestId/assign-assistant',
    );

    final response = await http
        .put(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'assistantId': assistantId,
            'assistantName': assistantName,
          }),
        )
        .timeout(_timeout);

    if (response.statusCode == 200) {
      final data = _decodeResponse(response);
      return (data['request'] as Map<String, dynamic>?) ?? data;
    }

    throw _error('Assign assistant failed', response);
  }

  static Future<Map<String, dynamic>> updateAssistantLocation({
    required String requestId,
    required String assistantId,
    required double lat,
    required double lng,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/rescueRequests/$requestId/assistant-location',
    );

    final response = await http
        .put(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'assistantId': assistantId,
            'lat': lat,
            'lng': lng,
          }),
        )
        .timeout(_timeout);

    if (response.statusCode == 200) {
      return _decodeResponse(response);
    }

    throw _error('Update assistant location failed', response);
  }

  // ================= PAYMENT =================

  /// Public payment settings from the backend (publishable key id only).
  ///
  /// The client must not carry a Razorpay key in its source: it cannot be
  /// rotated without a rebuild, and every build would share one account.
  static Future<Map<String, dynamic>> fetchPaymentConfig() async {
    final uri = Uri.parse('$baseUrl/payments/config');
    final response = await http.get(uri).timeout(_timeout);
    if (response.statusCode == 200) {
      return _decodeResponse(response);
    }
    throw _error('Could not load payment settings', response);
  }

  static Future<Map<String, dynamic>> updatePaymentStatus({
    required String requestId,
    required double amount,
    required String paymentStatus,
    required String paymentId,
    required String paymentMethod,
  }) async {
    final uri = Uri.parse('$baseUrl/rescueRequests/$requestId/payment');

    final response = await http
        .put(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'amount': amount,
            'paymentStatus': paymentStatus,
            'paymentId': paymentId,
            'paymentMethod': paymentMethod,
          }),
        )
        .timeout(_timeout);

    if (response.statusCode == 200) {
      return _decodeResponse(response);
    }

    throw _error('Update payment failed', response);
  }

  // ================= TOKENS (Admin) =================

  static Future<List<dynamic>> getAdminTokens() async {
    final uri = Uri.parse('$baseUrl/admin/tokens');
    final response = await http.get(uri).timeout(_timeout);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw _error('Admin fetch tokens failed', response);
  }

  static Future<Map<String, dynamic>> createToken({
    required String vehicleId,
    required String userId,
    String? jobId,
    String? hubId,
  }) async {
    final uri = Uri.parse('$baseUrl/admin/tokens');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'vehicleId': vehicleId,
            'userId': userId,
            'jobId': jobId ?? '',
            'hubId': hubId ?? '',
          }),
        )
        .timeout(_timeout);
    if (response.statusCode == 200 || response.statusCode == 201) {
      return _decodeResponse(response);
    }
    throw _error('Create token failed', response);
  }

  static Future<Map<String, dynamic>> updateTokenStatus({
    required String tokenId,
    required String status,
  }) async {
    final uri = Uri.parse('$baseUrl/admin/tokens/$tokenId/status');
    final response = await http
        .put(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'status': status}),
        )
        .timeout(_timeout);
    if (response.statusCode == 200) {
      return _decodeResponse(response);
    }
    throw _error('Update token failed', response);
  }

  static Future<Map<String, dynamic>> releaseToken({
    required String tokenId,
    String? releasedBy,
  }) async {
    final uri = Uri.parse('$baseUrl/admin/tokens/$tokenId/release');
    final response = await http
        .put(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'releasedBy': releasedBy ?? ''}),
        )
        .timeout(_timeout);
    if (response.statusCode == 200) {
      return _decodeResponse(response);
    }
    throw _error('Release token failed', response);
  }

  // ================= ZONES (Admin) =================

  static Future<List<dynamic>> getAdminZones() async {
    final uri = Uri.parse('$baseUrl/admin/zones');
    final response = await http.get(uri).timeout(_timeout);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw _error('Admin fetch zones failed', response);
  }

  static Future<Map<String, dynamic>> createZone({
    required String name,
    required double latMin,
    required double latMax,
    required double lngMin,
    required double lngMax,
  }) async {
    final uri = Uri.parse('$baseUrl/admin/zones');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'name': name,
            'latMin': latMin,
            'latMax': latMax,
            'lngMin': lngMin,
            'lngMax': lngMax,
          }),
        )
        .timeout(_timeout);
    if (response.statusCode == 200 || response.statusCode == 201) {
      return _decodeResponse(response);
    }
    throw _error('Create zone failed', response);
  }

  static Future<Map<String, dynamic>> deleteZone(String zoneId) async {
    final uri = Uri.parse('$baseUrl/admin/zones/$zoneId');
    final response = await http.delete(uri).timeout(_timeout);
    if (response.statusCode == 200) {
      return _decodeResponse(response);
    }
    throw _error('Delete zone failed', response);
  }

  // ================= USERS (Admin) =================

  static Future<List<dynamic>> getAdminUsers() async {
    final uri = Uri.parse('$baseUrl/admin/users');
    final response = await http.get(uri).timeout(_timeout);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw _error('Admin fetch users failed', response);
  }

  // ================= ADMIN =================

  static Future<List<dynamic>> getAdminRescueRequests() async {
    final uri = Uri.parse('$baseUrl/admin/requests');

    final response = await http.get(uri).timeout(_timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }

    throw _error('Admin fetch requests failed', response);
  }

  static Future<List<dynamic>> getAdminMechanics() async {
    final uri = Uri.parse('$baseUrl/admin/mechanics');

    final response = await http.get(uri).timeout(_timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }

    throw _error('Admin fetch mechanics failed', response);
  }

  static Future<List<dynamic>> getAdminHubs() async {
    final uri = Uri.parse('$baseUrl/admin/hubs');

    final response = await http.get(uri).timeout(_timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }

    throw _error('Admin fetch hubs failed', response);
  }

  static Future<List<dynamic>> fetchAdminRequests() async {
    return getAdminRescueRequests();
  }

  static Future<List<dynamic>> fetchAdminMechanics() async {
    return getAdminMechanics();
  }

  static Future<List<dynamic>> fetchAdminHubs() async {
    return getAdminHubs();
  }

  static Future<Map<String, dynamic>> adminAssignMechanic({
    required String requestId,
    required String mechanicId,
  }) async {
    final uri = Uri.parse('$baseUrl/admin/assign-mechanic');

    final response = await http
        .put(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'requestId': requestId, 'mechanicId': mechanicId}),
        )
        .timeout(_timeout);

    if (response.statusCode == 200) {
      final data = _decodeResponse(response);
      return (data['request'] as Map<String, dynamic>?) ?? data;
    }

    throw _error('Admin assign mechanic failed', response);
  }

  // ================= ADMIN - DELETE USER =================
  static Future<Map<String, dynamic>> deleteUser(String userId) async {
    final uri = Uri.parse('$baseUrl/admin/users/$userId');
    final response = await http.delete(uri).timeout(_timeout);
    if (response.statusCode == 200) {
      return _decodeResponse(response);
    }
    throw _error('Admin delete user failed', response);
  }

  // ================= ADMIN - DELETE TOKEN =================
  static Future<Map<String, dynamic>> deleteToken(String tokenId) async {
    final uri = Uri.parse('$baseUrl/admin/tokens/$tokenId');
    final response = await http.delete(uri).timeout(_timeout);
    if (response.statusCode == 200) {
      return _decodeResponse(response);
    }
    throw _error('Admin delete token failed', response);
  }
}

