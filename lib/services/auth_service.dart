// IMPORTANT: Set Firestore Rules to allow read/write for testing
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';

/// AuthService — Firebase Authentication wrapper
/// Handles phone OTP, email/password, and session management.
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ─── Streams ───

  /// Stream of auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Current Firebase user
  User? get currentUser => _auth.currentUser;

  // ─── Phone OTP Auth ───

  /// Send OTP to phone number
  Future<ConfirmationResult> signInWithPhone({
    required String phoneNumber,
    required RecaptchaVerifier recaptchaVerifier,
  }) async {
    try {
      final result = await _auth.signInWithPhoneNumber(
        phoneNumber,
        recaptchaVerifier,
      );
      return result;
    } catch (e) {
      debugPrint('AuthService.signInWithPhone error: $e');
      rethrow;
    }
  }

  /// Verify OTP code
  Future<UserCredential> verifyOtp({
    required ConfirmationResult confirmationResult,
    required String otp,
  }) async {
    try {
      final credential = await confirmationResult.confirm(otp);
      return credential;
    } catch (e) {
      debugPrint('AuthService.verifyOtp error: $e');
      rethrow;
    }
  }

  // ─── Email/Password Auth ───

  /// Register with email and password
  Future<UserCredential> registerWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return credential;
    } catch (e) {
      debugPrint('AuthService.registerWithEmail error: $e');
      rethrow;
    }
  }

  /// Login with email and password
  Future<UserCredential> loginWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return credential;
    } catch (e) {
      debugPrint('AuthService.loginWithEmail error: $e');
      rethrow;
    }
  }

  // ─── Session Management ───

  /// Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Create/Update user profile in Firestore
  Future<void> updateUserProfile(UserModel user) async {
    try {
      await _firestore
          .collection('users')
          .doc(user.id)
          .set(user.toFirestore(), SetOptions(merge: true));
    } on FirebaseException catch (e) {
      debugPrint(
          'AuthService.updateUserProfile FirebaseException: ${e.code} - ${e.message}');
      if (e.code == 'permission-denied') {
        debugPrint('PERMISSION_DENIED: Check Firestore Rules');
      }
      rethrow;
    } catch (e) {
      debugPrint('AuthService.updateUserProfile error: $e');
      rethrow;
    }
  }

  /// Get user profile from Firestore
  Future<UserModel?> getUserProfile(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (doc.exists) {
        return UserModel.fromFirestore(doc);
      }
      return null;
    } on FirebaseException catch (e) {
      debugPrint(
          'AuthService.getUserProfile FirebaseException: ${e.code} - ${e.message}');
      if (e.code == 'permission-denied') {
        debugPrint('PERMISSION_DENIED: Check Firestore Rules');
      }
      return null;
    } catch (e) {
      debugPrint('AuthService.getUserProfile error: $e');
      return null;
    }
  }

  /// Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }
}
