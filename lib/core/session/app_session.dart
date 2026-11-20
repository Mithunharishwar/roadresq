// FILE: lib/core/session/app_session.dart
/// The signed-in identity, persisted across app restarts.
///
/// `SessionService` stores the signed bearer token issued by the v2 auth
/// endpoints. The four legacy login pages (`ApiService` v1) do not receive a
/// token, so they had no way to remember who signed in — which is why the
/// splash screen could not do a login-state check and every logout simply
/// pushed the role screen without clearing anything.
///
/// This class stores exactly what is needed to resume: role, id, display name
/// and contact details. No credential is stored here.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSession {
  AppSession._();

  static const String _kRole = 'roadresq_session_role';
  static const String _kId = 'roadresq_session_id';
  static const String _kName = 'roadresq_session_name';
  static const String _kPhone = 'roadresq_session_phone';
  static const String _kEmail = 'roadresq_session_email';
  static const String _kVehicle = 'roadresq_session_vehicle';
  static const String _kSavedAt = 'roadresq_session_saved_at';

  static String? _role;
  static String? _id;
  static String? _name;
  static String? _phone;
  static String? _email;
  static String? _vehicle;

  static String? get role => _role;
  static String? get id => _id;
  static String? get name => _name;
  static String? get phone => _phone;
  static String? get email => _email;

  /// §7 — the vehicle captured at signup, cached so the profile and the rescue
  /// form can pre-fill it without another request.
  static String? get vehicle => _vehicle;

  /// True when a role and an id were restored or saved.
  static bool get isSignedIn =>
      (_role ?? '').isNotEmpty && (_id ?? '').isNotEmpty;

  /// Load the stored identity. Safe to call before `runApp`.
  static Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _role = prefs.getString(_kRole);
      _id = prefs.getString(_kId);
      _name = prefs.getString(_kName);
      _phone = prefs.getString(_kPhone);
      _email = prefs.getString(_kEmail);
      _vehicle = prefs.getString(_kVehicle);
    } catch (e) {
      debugPrint('[AppSession] restore failed: $e');
    }
  }

  /// Persist the identity after a successful login.
  ///
  /// Any missing field is left as-is rather than being overwritten with an
  /// empty string, so a login that does not return a name cannot erase a name
  /// that was already stored.
  static Future<void> save({
    required String role,
    required String id,
    String? name,
    String? phone,
    String? email,
    String? vehicle,
  }) async {
    _role = role;
    _id = id;
    if (name != null && name.isNotEmpty) _name = name;
    if (phone != null && phone.isNotEmpty) _phone = phone;
    if (email != null && email.isNotEmpty) _email = email;
    if (vehicle != null && vehicle.isNotEmpty) _vehicle = vehicle;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kRole, role);
      await prefs.setString(_kId, id);
      if (_name != null) await prefs.setString(_kName, _name!);
      if (_phone != null) await prefs.setString(_kPhone, _phone!);
      if (_email != null) await prefs.setString(_kEmail, _email!);
      if (_vehicle != null) await prefs.setString(_kVehicle, _vehicle!);
      await prefs.setInt(
        _kSavedAt,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      debugPrint('[AppSession] save failed: $e');
    }
  }

  /// Update the stored display name without touching the rest of the session.
  static Future<void> updateName(String name) async {
    _name = name;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kName, name);
    } catch (e) {
      debugPrint('[AppSession] updateName failed: $e');
    }
  }

  /// Clear the identity. Call this from every logout path.
  static Future<void> clear() async {
    _role = null;
    _id = null;
    _name = null;
    _phone = null;
    _email = null;
    _vehicle = null;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kRole);
      await prefs.remove(_kId);
      await prefs.remove(_kName);
      await prefs.remove(_kPhone);
      await prefs.remove(_kEmail);
      await prefs.remove(_kVehicle);
      await prefs.remove(_kSavedAt);
      // The v1 flow also left these behind; clearing them stops a stale request
      // id from re-opening "Track" for a signed-out user.
      await prefs.remove('last_request_id');
      await prefs.remove('last_role');
    } catch (e) {
      debugPrint('[AppSession] clear failed: $e');
    }
  }

  /// Route the saved role should land on after a cold start.
  static String get homeRoute {
    switch ((_role ?? '').toLowerCase()) {
      case 'user':
        return '/user-home';
      case 'mechanic':
        return '/mechanic-home';
      case 'assistant':
        return '/assistant-home';
      case 'garage':
        return '/garage-home';
      case 'admin':
        return '/admin';
      default:
        return '/role-select';
    }
  }
}

