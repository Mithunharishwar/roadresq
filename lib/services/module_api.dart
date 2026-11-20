// FILE: lib/services/module_api.dart
/// Client for the endpoints added by `backend/modules_v3.py`.
///
/// Kept separate from `ApiService` (legacy v1 routes) and `AllocationService`
/// (v2 auth/allocation) so this file can be read on its own and neither of the
/// two existing clients has to change.
///
/// Every call:
///   * goes through [AppConfig.apiBaseUrl] (no hardcoded host),
///   * times out after [AppConfig.requestTimeout],
///   * returns a typed result instead of throwing for an expected failure.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/config/app_config.dart';

/// A failure the UI can render. [message] is always safe to show.
class ModuleFailure implements Exception {
  ModuleFailure(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final String? code;

  bool get notFound => statusCode == 404;

  @override
  String toString() => message;
}

class ModuleApi {
  ModuleApi._();

  static const Duration _timeout = AppConfig.requestTimeout;

  static Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${AppConfig.apiBaseUrl}$path')
          .replace(queryParameters: query?.isEmpty ?? true ? null : query);

  static Map<String, dynamic> _decode(http.Response response) {
    if (response.body.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      return <String, dynamic>{'success': false, 'raw': response.body};
    } catch (_) {
      return <String, dynamic>{
        'success': false,
        'message': 'The server sent a response that could not be read.',
        'raw': response.body,
      };
    }
  }

  static ModuleFailure _failure(http.Response r) {
    final body = _decode(r);
    final message = (body['message'] ?? '').toString().trim();
    return ModuleFailure(
      message.isEmpty
          ? 'Request failed (HTTP ${r.statusCode}).'
          : message,
      statusCode: r.statusCode,
      code: body['code']?.toString(),
    );
  }

  /// Turn a transport exception into an actionable message.
  ///
  /// The four real causes of a dead request are distinguished instead of
  /// surfacing "Failed host lookup" to a user.
  static ModuleFailure _transport(Object error) {
    if (error is ModuleFailure) return error;
    if (error is SocketException) {
      return ModuleFailure(
        'Cannot reach the RoadResQ server at ${AppConfig.host}. '
        'Check that the backend is running and that this device is on the '
        'same network.',
        statusCode: 0,
        code: 'NO_CONNECTION',
      );
    }
    if (error is HttpException) {
      return ModuleFailure(
        'The server closed the connection unexpectedly. Try again.',
        statusCode: 0,
        code: 'CONNECTION_CLOSED',
      );
    }
    final text = error.toString();
    if (text.contains('TimeoutException')) {
      return ModuleFailure(
        'The server did not answer within '
        '${_timeout.inSeconds} seconds. It may be busy or unreachable.',
        statusCode: 0,
        code: 'TIMEOUT',
      );
    }
    return ModuleFailure('Unexpected error: $text', statusCode: 0,
        code: 'UNKNOWN');
  }

  static Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String>? query,
  }) async {
    try {
      final response =
          await http.get(_uri(path, query)).timeout(_timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return _decode(response);
      }
      throw _failure(response);
    } catch (e) {
      throw _transport(e);
    }
  }

  static Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final request = http.Request(method, _uri(path))
        ..headers['Content-Type'] = 'application/json';
      if (body != null) request.body = jsonEncode(body);

      final streamed = await request.send().timeout(_timeout);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return _decode(response);
      }
      throw _failure(response);
    } catch (e) {
      throw _transport(e);
    }
  }

  // ── Uploads (§7, §28, §33) ─────────────────────────────────────────
  /// Upload one file. Returns the absolute URL to store on the document.
  static Future<String> upload({
    required String filePath,
    required String kind,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw ModuleFailure('That file no longer exists on this device.');
      }

      final request = http.MultipartRequest('POST', _uri('/uploads'))
        ..fields['kind'] = kind
        ..files.add(await http.MultipartFile.fromPath('file', filePath));

      final streamed = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _failure(response);
      }
      final body = _decode(response);
      final url = (body['url'] ?? '').toString();
      if (url.isEmpty) {
        throw ModuleFailure('The upload succeeded but no URL came back.');
      }
      return url;
    } catch (e) {
      throw _transport(e);
    }
  }

  // ── Chat (§18) ─────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> messages(String requestId) async {
    final body = await _get('/rescueRequests/$requestId/messages');
    final rows = (body['messages'] as List?) ?? const [];
    return rows.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
  }

  static Future<Map<String, dynamic>> sendMessage({
    required String requestId,
    required String senderId,
    required String senderRole,
    required String senderName,
    required String text,
  }) =>
      _send('POST', '/rescueRequests/$requestId/messages', body: {
        'senderId': senderId,
        'senderRole': senderRole,
        'senderName': senderName,
        'text': text,
      });

  // ── Arrival token (§38, §39) ───────────────────────────────────────
  static Future<Map<String, dynamic>> generateToken(
    String requestId, {
    String? mechanicId,
  }) =>
      _send('POST', '/tokens/generate', body: {
        'requestId': requestId,
        'mechanicId': mechanicId ?? '',
      });

  /// Returns true when the token matched. Throws [ModuleFailure] otherwise so
  /// the caller can show the server's own reason (expired / wrong / used).
  static Future<bool> verifyToken({
    required String requestId,
    required String token,
  }) async {
    final body = await _send('POST', '/tokens/verify', body: {
      'requestId': requestId,
      'token': token,
    });
    return body['verified'] == true;
  }

  // ── Attendance (§41) ───────────────────────────────────────────────
  static Future<Map<String, dynamic>> checkIn(String assistantId) =>
      _send('POST', '/attendance/checkin', body: {'assistantId': assistantId});

  static Future<Map<String, dynamic>> checkOut(String assistantId) =>
      _send('POST', '/attendance/checkout', body: {'assistantId': assistantId});

  static Future<Map<String, dynamic>> attendance(
    String assistantId, {
    int days = 14,
  }) =>
      _get('/assistant/$assistantId/attendance',
          query: {'days': '$days'});

  // ── Earnings (§30, §42) ────────────────────────────────────────────
  static Future<Map<String, dynamic>> mechanicEarnings(String mechanicId) =>
      _get('/mechanic/$mechanicId/earnings');

  static Future<Map<String, dynamic>> assistantEarnings(String assistantId) =>
      _get('/assistant/$assistantId/earnings');

  // ── Feedback (§48) ─────────────────────────────────────────────────
  static Future<Map<String, dynamic>> submitFeedback({
    required String userId,
    required String role,
    required String category,
    required String subject,
    required String message,
    String requestId = '',
  }) =>
      _send('POST', '/feedback', body: {
        'userId': userId,
        'role': role,
        'category': category,
        'subject': subject,
        'message': message,
        'requestId': requestId,
      });

  static Future<List<Map<String, dynamic>>> feedbackFor(String userId) async {
    final body = await _get('/feedback', query: {'userId': userId});
    final rows = (body['feedback'] as List?) ?? const [];
    return rows.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
  }

  // ── Profiles (§29, §37) ────────────────────────────────────────────
  /// §7 — save the customer's name, vehicle and photo.
  static Future<void> saveUserProfile({
    required String userId,
    String? name,
    String? phone,
    String? email,
    String? vehicle,
    String? photoUrl,
  }) async {
    await _send('PUT', '/user/$userId/profile', body: {
      if (name != null) 'name': name,
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email,
      if (vehicle != null) 'vehicle': vehicle,
      if (photoUrl != null && photoUrl.isNotEmpty) 'photoUrl': photoUrl,
    });
  }

  static Future<Map<String, dynamic>> mechanicProfile(String mechanicId) async {
    final body = await _get('/mechanic/$mechanicId/profile');
    final doc = body['mechanic'];
    return doc is Map ? doc.cast<String, dynamic>() : <String, dynamic>{};
  }

  static Future<void> saveMechanicProfile(
    String mechanicId,
    Map<String, dynamic> fields,
  ) async {
    await _send('PUT', '/mechanic/$mechanicId/profile', body: fields);
  }

  static Future<Map<String, dynamic>> assistantProfile(
      String assistantId) async {
    final body = await _get('/assistant/$assistantId/profile');
    final doc = body['assistant'];
    return doc is Map ? doc.cast<String, dynamic>() : <String, dynamic>{};
  }

  // ── Ratings (§31, §46) ─────────────────────────────────────────────
  /// Saves a rating. The backend rejects pre-payment states by design, so the
  /// UI shows its message instead of pretending the rating stuck.
  static Future<void> rate({
    required String requestId,
    required double rating,
    required String review,
  }) async {
    await _send('POST', '/ratings', body: {
      'requestId': requestId,
      'rating': rating,
      'review': review,
    });
  }

  static Future<Map<String, dynamic>> ratings(String mechanicId) =>
      _get('/mechanics/$mechanicId/ratings');

  // ── Nearby mechanics (§16) ─────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> mechanics({
    bool? online,
    int limit = 100,
  }) async {
    final body = await _get('/mechanics', query: {
      if (online != null) 'online': online ? 'true' : 'false',
      'limit': '$limit',
    });
    final rows = (body['mechanics'] as List?) ?? const [];
    return rows.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
  }

  // ── Admin (§51) ────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> adminLogin({
    required String username,
    required String password,
  }) =>
      _send('POST', '/admin/login', body: {
        'username': username,
        'password': password,
      });

  static Future<Map<String, dynamic>> adminRevenue() =>
      _get('/admin/revenue');

  /// Debug helper: log the resolved base URL once, so a "cannot reach server"
  /// report can be matched against the address actually used.
  static void describe() {
    debugPrint('[ModuleApi] base=${AppConfig.apiBaseUrl}');
  }
}
