// FILE: lib/services/allocation_service.dart
/// Client for the RoadResQ v2 API: authentication, the regional allocation
/// engine, the mechanic lifecycle, payments, ratings and admin analytics.
///
/// This sits alongside the older `ApiService` (which still serves the legacy
/// rescue-request endpoints) rather than replacing it, so nothing that already
/// works is disturbed.
///
/// Every method attaches the signed bearer token from [SessionService] to
/// guarded endpoints, and surfaces the backend's own error envelope
/// (`{success, message, code}`) as an [ApiException] instead of a raw HTTP
/// failure.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config/app_config.dart';
import '../models/allocation_model.dart';
import 'session_service.dart';

/// A failure reported by the backend, carrying its own message and code.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final String? code;

  @override
  String toString() =>
      message +
      (code != null ? ' ($code)' : '') +
      (statusCode != null ? ' [HTTP $statusCode]' : '');
}

class AllocationService {
  AllocationService._();

  static const Duration _timeout = AppConfig.requestTimeout;

  // ── Plumbing ─────────────────────────────────────────────────────────
  static Map<String, String> _headers({bool auth = false}) {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (auth && SessionService.token != null) {
      headers['Authorization'] = 'Bearer ${SessionService.token}';
    }
    return headers;
  }

  static Map<String, dynamic> _decode(http.Response response) {
    if (response.body.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      return <String, dynamic>{'success': false, 'raw': response.body};
    } catch (_) {
      return <String, dynamic>{
        'success': false,
        'message': 'The server returned a response that could not be read.',
        'raw': response.body,
      };
    }
  }

  static dynamic _decodeDynamic(http.Response response) {
    try {
      return jsonDecode(response.body);
    } catch (_) {
      return null;
    }
  }

  /// Convert a non-2xx response into an [ApiException] using the backend's
  /// error envelope.
  static ApiException _error(http.Response response) {
    final body = _decode(response);
    final message = (body['message'] ?? response.body).toString();
    return ApiException(
      message.isEmpty ? 'Request failed' : message,
      statusCode: response.statusCode,
      code: body['code']?.toString(),
    );
  }

  static Future<Map<String, dynamic>> _get(
    String path, {
    bool auth = false,
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}$path')
        .replace(queryParameters: query);
    final response =
        await http.get(uri, headers: _headers(auth: auth)).timeout(_timeout);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _decode(response);
    }
    throw _error(response);
  }

  static Future<Map<String, dynamic>> _post(
    String path, {
    Map<String, dynamic>? body,
    bool auth = false,
  }) async {
    final response = await http
        .post(
          Uri.parse('${AppConfig.apiBaseUrl}$path'),
          headers: _headers(auth: auth),
          body: jsonEncode(body ?? const <String, dynamic>{}),
        )
        .timeout(_timeout);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _decode(response);
    }
    throw _error(response);
  }

  static Future<Map<String, dynamic>> _put(
    String path, {
    Map<String, dynamic>? body,
    bool auth = false,
  }) async {
    final response = await http
        .put(
          Uri.parse('${AppConfig.apiBaseUrl}$path'),
          headers: _headers(auth: auth),
          body: jsonEncode(body ?? const <String, dynamic>{}),
        )
        .timeout(_timeout);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _decode(response);
    }
    throw _error(response);
  }

  // ── Configuration (§11, §12, §42) ────────────────────────────────────
  /// Public, non-secret configuration: categories, dev-mode flag, allocation
  /// weights and whether real payments are configured.
  static Future<Map<String, dynamic>> publicConfig() => _get('/config/public');

  /// Rule-based fault classifier. Labelled by the backend as a prototype.
  static Future<Map<String, dynamic>> classifyFault(String description) =>
      _post('/fault/classify', body: {'description': description});

  // ── Authentication (§7, §8) ──────────────────────────────────────────
  /// Unified login for `user` or `mechanic`. Stores the session on success.
  static Future<Map<String, dynamic>> login({
    required String role,
    String? email,
    String? phone,
    required String password,
  }) async {
    final body = <String, dynamic>{'role': role, 'password': password};
    if (email != null && email.isNotEmpty) body['email'] = email;
    if (phone != null && phone.isNotEmpty) body['phone'] = phone;

    final response = await _post('/auth/login', body: body);
    await SessionService.saveFromLoginResponse(response);
    return response;
  }

  /// Request an OTP. In development the response carries a `devOtp` field and
  /// a `devNotice` explaining that it is not a real SMS delivery.
  static Future<Map<String, dynamic>> sendOtp({
    required String phone,
    String role = 'user',
  }) =>
      _post('/auth/otp/send', body: {'phone': phone, 'role': role});

  /// Verify an OTP and start a session.
  static Future<Map<String, dynamic>> verifyOtp({
    required String phone,
    required String otp,
    String role = 'user',
    String? name,
  }) async {
    final body = <String, dynamic>{'phone': phone, 'otp': otp, 'role': role};
    if (name != null && name.isNotEmpty) body['name'] = name;

    final response = await _post('/auth/otp/verify', body: body);
    await SessionService.saveFromLoginResponse(response);
    return response;
  }

  /// Register a user or mechanic. Passwords are hashed server-side; a new
  /// mechanic always starts unverified.
  static Future<Map<String, dynamic>> register({
    required String role,
    required String name,
    required String email,
    required String password,
    String phone = '',
  }) =>
      _post('/auth/register', body: {
        'role': role,
        'name': name,
        'email': email,
        'password': password,
        'phone': phone,
      });

  /// Resolve the caller from their token.
  static Future<Map<String, dynamic>> me() => _get('/auth/me', auth: true);

  // ── Allocation engine (§15–§19) ──────────────────────────────────────
  /// Run the regional allocation pipeline for a rescue request.
  ///
  /// Returns the chosen mechanic plus the full evidence set: every candidate,
  /// its eligibility verdict, rejection reasons and score breakdown.
  static Future<AllocationDecision> findMechanic({
    required String requestId,
    List<String> excludeMechanicIds = const [],
  }) async {
    final response = await _post('/allocation/find', body: {
      'requestId': requestId,
      if (excludeMechanicIds.isNotEmpty)
        'excludeMechanicIds': excludeMechanicIds,
    });
    return AllocationDecision.fromJson(response);
  }

  /// Dry-run the engine without persisting anything — useful for experiments
  /// and for showing what *would* happen for a given GPS point.
  static Future<AllocationDecision> dryRun({
    required double lat,
    required double lng,
    required String issue,
    required String vehicle,
    List<String> excludeMechanicIds = const [],
    double? radiusKm,
  }) async {
    final response = await _post('/allocation/find', body: {
      'lat': lat,
      'lng': lng,
      'issue': issue,
      'vehicle': vehicle,
      'dryRun': true,
      if (excludeMechanicIds.isNotEmpty)
        'excludeMechanicIds': excludeMechanicIds,
      if (radiusKm != null) 'radiusKm': radiusKm,
    });
    return AllocationDecision.fromJson(response);
  }

  /// The stored allocation record(s) for a request.
  static Future<Map<String, dynamic>> allocationLog(String requestId) =>
      _get('/allocation/$requestId');

  // ── Mechanic roster & profile (§32, §33) ─────────────────────────────
  static Future<List<Map<String, dynamic>>> listMechanics({
    String? regionId,
    String? service,
    bool? online,
    bool? verified,
    int limit = 100,
  }) async {
    final query = <String, String>{'limit': '$limit'};
    if (regionId != null) query['regionId'] = regionId;
    if (service != null) query['service'] = service;
    if (online != null) query['online'] = '$online';
    if (verified != null) query['verified'] = '$verified';

    final response = await _get('/mechanics', query: query);
    return ((response['mechanics'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList(growable: false);
  }

  /// Update the signed-in mechanic's own profile (region, hub, capabilities).
  static Future<Map<String, dynamic>> updateMechanicProfile(
    String mechanicId,
    Map<String, dynamic> patch,
  ) =>
      _patch('/mechanics/$mechanicId', body: patch);

  static Future<Map<String, dynamic>> _patch(
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
  }) async {
    final response = await http
        .patch(
          Uri.parse('${AppConfig.apiBaseUrl}$path'),
          headers: _headers(auth: auth),
          body: jsonEncode(body ?? const <String, dynamic>{}),
        )
        .timeout(_timeout);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _decode(response);
    }
    throw _error(response);
  }

  /// Toggle online / available state. Availability drives eligibility.
  static Future<Map<String, dynamic>> setAvailability(
    String mechanicId, {
    bool? online,
    bool? available,
  }) =>
      _put(
        '/mechanics/$mechanicId/availability',
        auth: true,
        body: {
          if (online != null) 'online': online,
          if (available != null) 'available': available,
        },
      );

  /// Publish the mechanic's current location. Returns once stored and
  /// broadcast to tracking clients.
  static Future<Map<String, dynamic>> publishLocation(
    String mechanicId,
    double lat,
    double lng, {
    String requestId = '',
  }) =>
      _put(
        '/mechanics/$mechanicId/location',
        auth: true,
        body: {'lat': lat, 'lng': lng, 'requestId': requestId},
      );

  /// Admin verification decision for a mechanic.
  static Future<Map<String, dynamic>> verifyMechanic(
    String mechanicId,
    String decision, // approve | reject | suspend
  ) =>
      _post(
        '/admin/mechanics/$mechanicId/verify',
        auth: true,
        body: {'decision': decision},
      );

  // ── Mechanic lifecycle (§14, §33) ────────────────────────────────────
  static Future<Map<String, dynamic>> accept(
          String mechanicId, String requestId) =>
      _post('/mechanic/$mechanicId/accept',
          auth: true, body: {'requestId': requestId});

  static Future<Map<String, dynamic>> decline(
    String mechanicId,
    String requestId, {
    String reason = '',
    bool autoReallocate = true,
  }) =>
      _post('/mechanic/$mechanicId/decline', auth: true, body: {
        'requestId': requestId,
        'reason': reason,
        'autoReallocate': autoReallocate,
      });

  static Future<Map<String, dynamic>> startTravel(
          String mechanicId, String requestId) =>
      _post('/mechanic/$mechanicId/start',
          auth: true, body: {'requestId': requestId});

  static Future<Map<String, dynamic>> arrive(
          String mechanicId, String requestId) =>
      _post('/mechanic/$mechanicId/arrive',
          auth: true, body: {'requestId': requestId});

  static Future<Map<String, dynamic>> complete(
          String mechanicId, String requestId) =>
      _post('/mechanic/$mechanicId/complete',
          auth: true, body: {'requestId': requestId});

  static Future<Map<String, dynamic>> cancelRequest(
    String requestId, {
    String reason = '',
  }) =>
      _post('/rescueRequests/$requestId/cancel',
          auth: true, body: {'reason': reason});

  // ── Pricing & payment (§29, §30) ─────────────────────────────────────
  /// Itemised quote for a request (or for an issue + distance).
  static Future<PriceQuote> quote({
    String? requestId,
    String? issue,
    double? distanceKm,
  }) async {
    final query = <String, String>{};
    if (requestId != null) query['requestId'] = requestId;
    if (issue != null) query['issue'] = issue;
    if (distanceKm != null) query['distanceKm'] = '$distanceKm';

    final response = await _get('/payments/quote', query: query);
    return PriceQuote.fromJson(
      (response['quote'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  /// Create a payment order. The response reports its `mode`
  /// (`live` / `test` / `simulated`) and never claims a real order when the
  /// gateway is not configured.
  static Future<Map<String, dynamic>> createPaymentOrder(String requestId) =>
      _post('/payments/create', body: {'requestId': requestId});

  /// Verify a payment. Pass the three Razorpay fields for a real check, or
  /// `simulate: true` in development mode for an explicitly-flagged
  /// simulation.
  static Future<Map<String, dynamic>> verifyPayment({
    required String requestId,
    String? razorpayOrderId,
    String? razorpayPaymentId,
    String? razorpaySignature,
    bool simulate = false,
  }) =>
      _post('/payments/verify', body: {
        'requestId': requestId,
        if (razorpayOrderId != null) 'razorpayOrderId': razorpayOrderId,
        if (razorpayPaymentId != null) 'razorpayPaymentId': razorpayPaymentId,
        if (razorpaySignature != null) 'razorpaySignature': razorpaySignature,
        'simulate': simulate,
      });

  // ── Ratings (§31) ────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> rate({
    required String requestId,
    required double rating,
    String review = '',
  }) =>
      _post('/ratings', body: {
        'requestId': requestId,
        'rating': rating,
        'review': review,
      });

  static Future<Map<String, dynamic>> mechanicRatings(String mechanicId) =>
      _get('/mechanics/$mechanicId/ratings');

  // ── Admin & research (§34, §45, §46) ─────────────────────────────────
  /// Dashboard metrics, every one aggregated from the live database.
  static Future<Map<String, dynamic>> adminDashboard() =>
      _get('/admin/dashboard');

  /// Per-scenario aggregate metrics computed from stored allocation logs.
  static Future<Map<String, dynamic>> experimentsSummary() =>
      _get('/admin/experiments/summary');

  static Future<Map<String, dynamic>> allocationLogs({
    String? requestId,
    int limit = 50,
    bool includeCandidates = false,
  }) {
    final query = <String, String>{
      'limit': '$limit',
      'includeCandidates': '$includeCandidates',
    };
    if (requestId != null) query['requestId'] = requestId;
    return _get('/admin/allocation-logs', query: query);
  }

  static Future<Map<String, dynamic>> regions() => _get('/admin/regions');

  static Future<Map<String, dynamic>> systemHealth() =>
      _get('/admin/system/health');

  /// Download the anonymised allocation dataset as CSV text.
  ///
  /// Personal identifiers are replaced with stable hashes server-side, so the
  /// result can be shared for research.
  static Future<String> exportAllocationCsv() async {
    final response = await http
        .get(Uri.parse('${AppConfig.apiBaseUrl}/admin/export/allocation'))
        .timeout(const Duration(seconds: 60));
    if (response.statusCode == 200) {
      return response.body;
    }
    throw _error(response);
  }

  /// Convenience: the raw JSON of an endpoint, for diagnostics screens.
  static Future<dynamic> debugGet(String path) async {
    final response = await http
        .get(Uri.parse('${AppConfig.apiBaseUrl}$path'))
        .timeout(_timeout);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _decodeDynamic(response);
    }
    throw _error(response);
  }

  /// Human-readable form of the resolved backend host, for the profile screen
  /// and support tickets.
  static String get hostDescription => AppConfig.describe();
}
