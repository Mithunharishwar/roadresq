// FILE: lib/services/session_service.dart
/// Persists the signed session token issued by the backend.
///
/// The backend now returns a signed bearer token on login (`/api/auth/login`,
/// `/api/auth/otp/verify`) instead of trusting whatever identity the client
/// claims. Every guarded endpoint requires that token, so the app has to keep
/// it and attach it to those calls.
///
/// The token is an opaque signed string, not a password, and it expires on the
/// server. It is stored in SharedPreferences for simplicity; if the project
/// moves to `flutter_secure_storage` (already a dependency) only this file
/// changes.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SessionService {
  SessionService._();

  static const String _keyToken = 'roadresq_auth_token';
  static const String _keyRole = 'roadresq_role';
  static const String _keySubjectId = 'roadresq_subject_id';
  static const String _keyExpiresAt = 'roadresq_token_expires_at';
  static const String _keyProfile = 'roadresq_profile';

  static String? _token;
  static String? _role;
  static String? _subjectId;
  static int? _expiresAt;
  static Map<String, dynamic>? _profile;

  /// The current bearer token, or null when signed out.
  static String? get token => _token;
  static String? get role => _role;
  static String? get subjectId => _subjectId;
  static Map<String, dynamic>? get profile => _profile;

  static bool get isSignedIn => _token != null && _token!.isNotEmpty;

  /// True when the token has an expiry that has already passed.
  static bool get isExpired {
    if (_expiresAt == null) return false;
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return nowSeconds >= _expiresAt!;
  }

  /// Load a previously stored session. Safe to call at startup.
  static Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString(_keyToken);
      _role = prefs.getString(_keyRole);
      _subjectId = prefs.getString(_keySubjectId);
      _expiresAt = prefs.getInt(_keyExpiresAt);

      final rawProfile = prefs.getString(_keyProfile);
      if (rawProfile != null && rawProfile.isNotEmpty) {
        final decoded = jsonDecode(rawProfile);
        if (decoded is Map) {
          _profile = decoded.cast<String, dynamic>();
        }
      }

      if (isExpired) {
        debugPrint('[SessionService] stored token has expired; clearing');
        await clear();
      }
    } catch (e) {
      debugPrint('[SessionService] restore failed: $e');
    }
  }

  /// Persist the token and role returned by a login response.
  ///
  /// [response] is the raw JSON body from `/api/auth/login` or
  /// `/api/auth/otp/verify`. It also stores whichever profile object the
  /// response carried (`user` / `mechanic` / `assistant`).
  static Future<void> saveFromLoginResponse(
      Map<String, dynamic> response) async {
    _token = (response['token'] ?? '').toString();
    _role = response['role']?.toString();
    _subjectId = response['subjectId']?.toString();
    _expiresAt = (response['expiresAt'] as num?)?.toInt();

    final profile =
        response['user'] ?? response['mechanic'] ?? response['assistant'];
    if (profile is Map) {
      _profile = profile.cast<String, dynamic>();
      _subjectId ??= _profile!['id']?.toString();
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      if (_token != null && _token!.isNotEmpty) {
        await prefs.setString(_keyToken, _token!);
      }
      if (_role != null) await prefs.setString(_keyRole, _role!);
      if (_subjectId != null) await prefs.setString(_keySubjectId, _subjectId!);
      if (_expiresAt != null) await prefs.setInt(_keyExpiresAt, _expiresAt!);
      if (_profile != null) {
        await prefs.setString(_keyProfile, jsonEncode(_profile));
      }
    } catch (e) {
      debugPrint('[SessionService] persist failed: $e');
    }
  }

  /// Clear the in-memory and stored session.
  static Future<void> clear() async {
    _token = null;
    _role = null;
    _subjectId = null;
    _expiresAt = null;
    _profile = null;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyToken);
      await prefs.remove(_keyRole);
      await prefs.remove(_keySubjectId);
      await prefs.remove(_keyExpiresAt);
      await prefs.remove(_keyProfile);
    } catch (e) {
      debugPrint('[SessionService] clear failed: $e');
    }
  }
}
