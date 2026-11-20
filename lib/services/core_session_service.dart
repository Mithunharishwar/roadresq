// IMPORTANT: Set Firestore Rules to allow read/write for testing
// FILE: lib/services/core_session_service.dart
/// CoreSessionService — wraps the Authentication Module.
///
/// Implements the spec functions:
///   - signUpWithPhone(phone)  → send OTP
///   - verifyOTP(phone, otp)   → login + create user doc
///   - selectRole(role)        → user / mechanic / assistant / garage / admin
///   - logout()                → clear session + set crew status offline
///   - getCurrentUserRole()    → returns role for routing
///   - resetPassword()         → email password reset for admins
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../core/constants/app_constants.dart';

/// Supported roles in the RoadResQ ecosystem.
class AppRoles {
  static const String user = 'user';
  static const String mechanic = 'mechanic';
  static const String assistant = 'assistant';
  static const String garage = 'garage';
  static const String admin = 'admin';
}

/// Result type for OTP flows.
class OtpResult {
  final bool success;
  final String message;
  final String code; // dev-visible OTP (demo)
  final ConfirmationResult? confirmation; // for Firebase phone auth
  final String? userId;

  const OtpResult({
    this.success = false,
    this.message = '',
    this.code = '',
    this.confirmation,
    this.userId,
  });
}

/// Core session + auth service.
class CoreSessionService {
  CoreSessionService._internal();
  static final CoreSessionService _instance = CoreSessionService._internal();
  factory CoreSessionService() => _instance;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// signUpWithPhone(phone) — send an OTP to the phone.
  /// Uses Firebase phone auth when a recaptcha verifier is available;
  /// otherwise falls back to a demo OTP (`999999`).
  Future<OtpResult> signUpWithPhone({
    required String phone,
    RecaptchaVerifier? recaptchaVerifier,
  }) async {
    try {
      if (recaptchaVerifier != null) {
        final confirmation = await _auth.signInWithPhoneNumber(
          phone,
          recaptchaVerifier,
        );
        return OtpResult(success: true, confirmation: confirmation);
      }
      // Demo path (no reCAPTCHA): return a fixed dev OTP.
      return const OtpResult(success: true, code: '999999');
    } catch (e) {
      return OtpResult(
        success: false,
        message: 'Failed to send OTP: ${e.toString()}',
      );
    }
  }

  /// verifyOTP(phone, otp) — verify OTP, log in, create user doc.
  Future<OtpResult> verifyOTP({
    required String phone,
    required String otp,
    ConfirmationResult? confirmation,
  }) async {
    try {
      if (confirmation != null) {
        final cred = await confirmation.confirm(otp);
        final uid = cred.user?.uid;
        if (uid != null) {
          await _createUserDoc(uid, phone);
        }
        return OtpResult(
            success: true, userId: uid, confirmation: confirmation);
      }

      // Demo path: accept dev code.
      if (otp.trim() == '999999') {
        await _auth.signInAnonymously();
        return OtpResult(success: true, userId: _auth.currentUser?.uid);
      }
      return const OtpResult(success: false, message: 'Invalid OTP');
    } catch (e) {
      return OtpResult(
        success: false,
        message: 'OTP verification failed: ${e.toString()}',
      );
    }
  }

  Future<void> _createUserDoc(String uid, String phone) async {
    try {
      await _firestore.collection(AppConstants.collectionUsers).doc(uid).set({
        'uid': uid,
        'phone': phone,
        'role': AppRoles.user,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      debugPrint(
          'CoreSessionService._createUserDoc FirebaseException: ${e.code} - ${e.message}');
      if (e.code == 'permission-denied') {
        debugPrint('PERMISSION_DENIED: Check Firestore Rules');
      }
      rethrow;
    } catch (e) {
      debugPrint('CoreSessionService._createUserDoc error: $e');
      rethrow;
    }
  }

  /// selectRole(role) — persist the chosen role on the user doc.
  Future<bool> selectRole(String role) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    try {
      await _firestore
          .collection(AppConstants.collectionUsers)
          .doc(uid)
          .update({
        'role': role,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } on FirebaseException catch (e) {
      debugPrint(
          'CoreSessionService.selectRole FirebaseException: ${e.code} - ${e.message}');
      if (e.code == 'permission-denied') {
        debugPrint('PERMISSION_DENIED: Check Firestore Rules');
      }
      return false;
    } catch (e) {
      debugPrint('CoreSessionService.selectRole error: $e');
      return false;
    }
  }

  /// logout() — clear session + set crew status offline.
  Future<void> logout({String? crewId}) async {
    if (crewId != null) {
      try {
        await _firestore
            .collection(AppConstants.collectionCrews)
            .doc(crewId)
            .update({
          'isOnline': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } on FirebaseException catch (e) {
        debugPrint(
            'CoreSessionService.logout FirebaseException: ${e.code} - ${e.message}');
        if (e.code == 'permission-denied') {
          debugPrint('PERMISSION_DENIED: Check Firestore Rules');
        }
      } catch (_) {}
    }
    await _auth.signOut();
  }

  /// getCurrentUserRole() — returns role for routing.
  Future<String?> getCurrentUserRole() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    try {
      final doc = await _firestore
          .collection(AppConstants.collectionUsers)
          .doc(uid)
          .get();
      final data = doc.data();
      return (data?['role'] ?? '').toString();
    } on FirebaseException catch (e) {
      debugPrint(
          'CoreSessionService.getCurrentUserRole FirebaseException: ${e.code} - ${e.message}');
      if (e.code == 'permission-denied') {
        debugPrint('PERMISSION_DENIED: Check Firestore Rules');
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// resetPassword() — send password reset email (admin accounts).
  Future<bool> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return true;
    } catch (_) {
      return false;
    }
  }
}
