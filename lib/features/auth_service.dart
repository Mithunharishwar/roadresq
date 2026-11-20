import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final authServiceProvider = Provider<AuthService>((_) => AuthService());

/// Firebase Phone Auth backed by the `users/{uid}` Firestore profile.
class AuthService {
  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  String? _verificationId;
  String? _pendingPhone;
  ConfirmationResult? _webConfirmation;
  User? _automaticallyVerifiedUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  /// Sends an SMS OTP. Ten-digit Indian numbers are normalized to E.164.
  Future<void> sendOTP(String phone) async {
    final normalizedPhone = _normalizePhone(phone);

    _pendingPhone = normalizedPhone;
    _verificationId = null;
    _webConfirmation = null;
    _automaticallyVerifiedUser = null;

    if (kIsWeb) {
      _webConfirmation = await _auth.signInWithPhoneNumber(normalizedPhone);
      return;
    }

    final codeSent = Completer<void>();
    await _auth.verifyPhoneNumber(
      phoneNumber: normalizedPhone,
      verificationCompleted: (credential) async {
        try {
          final result = await _auth.signInWithCredential(credential);
          _automaticallyVerifiedUser = result.user;
          if (_automaticallyVerifiedUser == null) {
            throw StateError('Firebase did not return a verified user.');
          }
          if (!codeSent.isCompleted) {
            codeSent.complete();
          }
        } catch (error, stackTrace) {
          if (!codeSent.isCompleted) {
            codeSent.completeError(error, stackTrace);
          }
        }
      },
      verificationFailed: (error) {
        if (!codeSent.isCompleted) {
          codeSent.completeError(error);
        }
      },
      codeSent: (verificationId, forceResendingToken) {
        _verificationId = verificationId;
        if (!codeSent.isCompleted) {
          codeSent.complete();
        }
      },
      codeAutoRetrievalTimeout: (verificationId) {
        _verificationId ??= verificationId;
      },
    );

    await codeSent.future;
  }

  /// Verifies [sms], saves the selected [role], then returns that role.
  Future<String> verifyOTP(String sms, String role) async {
    final selectedRole = role.trim();
    if (selectedRole.isEmpty) {
      throw ArgumentError.value(role, 'role', 'A role is required.');
    }

    final smsCode = sms.trim();
    User? user = _automaticallyVerifiedUser;

    if (user == null) {
      if (smsCode.isEmpty) {
        throw ArgumentError.value(
            sms, 'sms', 'Enter the SMS verification code.');
      }

      if (kIsWeb) {
        final confirmation = _webConfirmation;
        if (confirmation == null) {
          throw StateError('Call sendOTP before verifyOTP.');
        }
        user = (await confirmation.confirm(smsCode)).user;
      } else {
        final verificationId = _verificationId;
        if (verificationId == null) {
          throw StateError('Call sendOTP before verifyOTP.');
        }
        final credential = PhoneAuthProvider.credential(
          verificationId: verificationId,
          smsCode: smsCode,
        );
        user = (await _auth.signInWithCredential(credential)).user;
      }
    }

    if (user == null) {
      throw StateError('Firebase did not return a signed-in user.');
    }

    await _firestore.collection('users').doc(user.uid).set(
      {
        'phone': user.phoneNumber ?? _pendingPhone ?? '',
        'role': selectedRole,
        'isOnline': false,
      },
      SetOptions(merge: true),
    );

    _verificationId = null;
    _pendingPhone = null;
    _webConfirmation = null;
    _automaticallyVerifiedUser = null;

    return selectedRole;
  }

  Future<void> signOut() => _auth.signOut();

  String _normalizePhone(String value) {
    final compact = value.trim().replaceAll(RegExp(r'[\s()-]'), '');
    final phone = compact.startsWith('+')
        ? compact
        : compact.length == 10
            ? '+91$compact'
            : '+$compact';

    if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(phone)) {
      throw ArgumentError.value(
        value,
        'phone',
        'Enter a valid phone number in E.164 format.',
      );
    }

    return phone;
  }
}
