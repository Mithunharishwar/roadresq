// FILE: lib/core/services/auth_service.dart
/// AuthService — Rapido-style Phone OTP Authentication wrapper.
///
/// Handles:
///   - sendOTP   : send OTP to a +91 phone number via Firebase Phone Auth
///   - verifyOTP : confirm the OTP code entered by the user
///   - getUserRole: read the user's role from Firestore `users/{uid}.role`
///   - logout    : sign the current user out
///
/// Uses Firebase Auth + Cloud Firestore. All methods throw on failure so
/// callers (Riverpod providers / screens) can surface the error to the UI.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  AuthService._internal();
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Stream of auth state changes (used by Riverpod to react to login/logout).
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// The currently signed-in Firebase user (null when logged out).
  User? get currentUser => _auth.currentUser;

  /// The raw phone number the user logged in with (session helper).
  static const String countryCode = '+91';

  // ─────────────────────────────────────────────
  // OTP Sending
  // ─────────────────────────────────────────────

  /// Sends an OTP to the given 10-digit [phoneNumber] (auto-prefixes +91).
  ///
  /// Returns a [ConfirmationResult] which must be passed to [verifyOtp].
  /// On mobile, [kIsWeb] false, plain `signInWithPhoneNumber` is sufficient.
  Future<ConfirmationResult> sendOTP({
    required String phoneNumber,
  }) async {
    assert(phoneNumber.length == 10, 'Phone number must be 10 digits');

    final fullNumber = '$countryCode${phoneNumber.trim()}';

    try {
      return await _auth.signInWithPhoneNumber(fullNumber);
    } catch (e) {
      debugPrint('AuthService.sendOTP error: $e');
      rethrow;
    }
  }

  // ─────────────────────────────────────────────
  // OTP Verification
  // ─────────────────────────────────────────────

  /// Verifies the OTP [code] using the [confirmationResult] from [sendOTP].
  ///
  /// On success it returns the signed-in [User] and saves the user doc to
  /// Firestore under `users/{uid}` (defaulting name/role from the phone).
  Future<User> verifyOTP({
    required ConfirmationResult confirmationResult,
    required String code,
    String name = '',
    String role = 'user',
    String email = '',
  }) async {
    try {
      final credential = await confirmationResult.confirm(code.trim());
      final user = credential.user!;

      // Idempotently create/update the user profile in Firestore.
      await _firestore.collection('users').doc(user.uid).set(
        {
          'uid': user.uid,
          'name': name.isEmpty ? 'User' : name,
          'phone': user.phoneNumber ?? '',
          'email': email,
          'role': role,
          'isOnline': false,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      return user;
    } catch (e) {
      debugPrint('AuthService.verifyOTP error: $e');
      rethrow;
    }
  }

// ─────────────────────────────────────────────
  // Single-Login OTP Verification (saves role + returns role)
  // ─────────────────────────────────────────────

  /// Verifies the OTP [code] and, on success, writes the user's [role] to
  /// Firestore `users/{uid}.role` and returns that role.
  ///
  /// This is the Rapido-style flow: pick a role first, verify OTP, then route
  /// straight to the matching dashboard. Returns one of `user`, `mechanic`,
  /// `assistant`, `garage`, `admin`.
  Future<String> verifyOtpWithRole({
    required ConfirmationResult confirmationResult,
    required String code,
    required String role,
    String name = '',
    String email = '',
  }) async {
    try {
      final user = await verifyOTP(
        confirmationResult: confirmationResult,
        code: code,
        role: role,
        name: name,
        email: email,
      );

      // Persist/resolve the role explicitly so the router can route correctly.
      final savedRole = await saveRole(uid: user.uid, role: role);
      return savedRole;
    } catch (e) {
      debugPrint('AuthService.verifyOtpWithRole error: $e');
      rethrow;
    }
  }

  /// Writes the given [role] to `users/{uid}.role` and returns it.
  ///
  /// Safe to call multiple times (idempotent). Does not overwrite an existing
  /// role unless [force] is true, but the single-login flow always sets the
  /// role the user selected, so it writes by default.
  Future<String> saveRole({
    required String uid,
    required String role,
    bool force = true,
  }) async {
    try {
      final docRef = _firestore.collection('users').doc(uid);
      final existing = await docRef.get();

      if (existing.exists && !force) {
        final data = existing.data() as Map<String, dynamic>;
        final currentRole = (data['role'] ?? 'user').toString();
        return currentRole;
      }

      await docRef.set(
        {
          'role': role,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return role;
    } catch (e) {
      debugPrint('AuthService.saveRole error: $e');
      return role;
    }
  }

  /// Returns the role stored in Firestore for [uid], defaulting to `user`.
  ///
  /// This is provided for callers that need a one-shot read (e.g. route guards).
  Future<String> fetchRole(String uid) async {
    return getUserRole(uid);
  }

  // ─────────────────────────────────────────────
  // Role Resolution
  // ─────────────────────────────────────────────

  /// Reads the role of [uid] from Firestore `users/{uid}.role`.
  ///
  /// Returns one of: `user`, `mechanic`, `assistant`, `garage`, `admin`.
  /// Defaults to `user` when the document is missing.
  Future<String> getUserRole(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final role = (data['role'] ?? 'user').toString();
        return role;
      }
      return 'user';
    } catch (e) {
      debugPrint('AuthService.getUserRole error: $e');
      return 'user';
    }
  }

  /// Reads the full user profile document for [uid].
  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (!doc.exists) return null;
      return doc.data() as Map<String, dynamic>;
    } catch (e) {
      debugPrint('AuthService.getUserProfile error: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────
  // Session
  // ─────────────────────────────────────────────

  /// Signs the current user out. Safe to call even when not signed in.
  Future<void> logout() async {
    try {
      await _auth.signOut();
    } catch (e) {
      debugPrint('AuthService.logout error: $e');
      rethrow;
    }
  }
}
