// FILE: lib/services/demo_access.dart
//
// One-tap access to the four seeded accounts, for showing the product.
//
// WHY THIS EXISTS
// ---------------
// A reviewer opens the app, lands in whichever module last signed in, and has
// no way to see the other three without knowing a phone number, waiting for a
// code and typing it. That makes a four-sided product impossible to demo.
//
// Each method performs the normal server login — the same endpoints the forms
// use — with the seeded development accounts. Nothing here bypasses auth: if
// the server is not in development mode it does not return the code, and the
// call fails so the caller can fall back to the real OTP screen.
//
// These accounts exist in the development database (see seed_demo_data.py).

import 'package:shared_preferences/shared_preferences.dart';

import '../core/session/app_session.dart';
import 'api_service.dart';
import 'assistant_service.dart';

class DemoSignInResult {
  const DemoSignInResult({required this.ok, this.message = ''});

  final bool ok;
  final String message;
}

class DemoAccess {
  static const String userPhone = '9000000778';
  static const String mechanicPhone = '9876543210';
  static const String assistantPhone = '9111111111';
  static const String garageId = 'DEMO-GARAGE';
  static const String garagePassword = 'demo1234';

  /// Customer: phone OTP through the normal endpoints.
  static Future<DemoSignInResult> signInUser() async {
    try {
      final sent = await ApiService.sendOtp(phone: userPhone);
      final code = sent['devOtp']?.toString();
      if (code == null) {
        return const DemoSignInResult(
          ok: false,
          message: 'Server is not in dev mode, so no code was returned.',
        );
      }

      final res = await ApiService.verifyOtp(phone: userPhone, otp: code);
      final user = (res['user'] as Map<String, dynamic>?) ?? const {};
      await AppSession.save(
        role: 'user',
        id: (user['id'] ?? user['_id'] ?? userPhone).toString(),
        name: (user['name'] as String?)?.isNotEmpty == true
            ? user['name'] as String
            : 'Demo Customer',
        phone: userPhone,
        email: (user['email'] as String?) ?? '',
      );
      return const DemoSignInResult(ok: true);
    } catch (e) {
      return DemoSignInResult(ok: false, message: '$e');
    }
  }

  /// Mechanic: same pattern, mechanic endpoints.
  static Future<DemoSignInResult> signInMechanic() async {
    try {
      final sent = await ApiService.mechanicLoginOtp(phone: mechanicPhone);
      final code = sent['devOtp']?.toString();
      if (code == null) {
        return const DemoSignInResult(
          ok: false,
          message: 'Server is not in dev mode, so no code was returned.',
        );
      }

      final res = await ApiService.verifyOtp(
        phone: mechanicPhone,
        otp: code,
        isMechanic: true,
      );
      final mechanic = (res['mechanic'] as Map<String, dynamic>?) ?? const {};
      final prefs = await SharedPreferences.getInstance();
      final mechanicId =
          (mechanic['mechanicId'] ?? mechanic['_id'] ?? mechanicPhone).toString();
      await prefs.setString('mechanicId', mechanicId);
      await prefs.setString(
        'mechanicName',
        (mechanic['name'] as String?)?.isNotEmpty == true
            ? mechanic['name'] as String
            : 'Demo Mechanic',
      );
      await prefs.setString('mechanicPhone', mechanicPhone);
      await AppSession.save(
        role: 'mechanic',
        id: mechanicId,
        name: (mechanic['name'] as String?) ?? 'Demo Mechanic',
        phone: mechanicPhone,
        email: (mechanic['email'] as String?) ?? '',
      );
      return const DemoSignInResult(ok: true);
    } catch (e) {
      return DemoSignInResult(ok: false, message: '$e');
    }
  }

  /// Assistant rider: the page's own service, so the stored keys match what the
  /// dashboard reads.
  static Future<DemoSignInResult> signInAssistant() async {
    try {
      final service = AssistantService();
      final sent = await service.loginOtp(phone: assistantPhone);
      final code = (sent['devOtp'] ?? sent['otp'] ?? sent['code'])?.toString();
      if (code == null) {
        return const DemoSignInResult(
          ok: false,
          message: 'Server is not in dev mode, so no code was returned.',
        );
      }

      final res = await service.verifyOtp(phone: assistantPhone, otp: code);
      final assistant = (res['assistant'] as Map<String, dynamic>?) ??
          (res['rider'] as Map<String, dynamic>?) ??
          const <String, dynamic>{};
      final assistantId =
          (assistant['assistantId'] ?? assistant['_id'] ?? assistantPhone)
              .toString();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('assistantId', assistantId);
      await prefs.setString(
        'assistantName',
        (assistant['name'] as String?)?.isNotEmpty == true
            ? assistant['name'] as String
            : 'Demo Rider',
      );
      await prefs.setString('assistantPhone', assistantPhone);
      await AppSession.save(
        role: 'assistant',
        id: assistantId,
        name: (assistant['name'] as String?) ?? 'Demo Rider',
        phone: assistantPhone,
        email: (assistant['email'] as String?) ?? '',
      );
      return const DemoSignInResult(ok: true);
    } catch (e) {
      return DemoSignInResult(ok: false, message: '$e');
    }
  }

  /// Garage: id + password, no OTP.
  static Future<DemoSignInResult> signInGarage() async {
    try {
      final res = await ApiService.garageLogin(
        garageId: garageId,
        password: garagePassword,
      );
      final garage = (res['garage'] as Map<String, dynamic>?) ?? const {};

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('garageId', garageId);
      await prefs.setString(
        'garageName',
        (garage['name'] as String?)?.isNotEmpty == true
            ? garage['name'] as String
            : 'Demo Garage',
      );
      await prefs.setString(
        'garagePhone',
        (garage['phone'] as String?) ?? '',
      );
      await AppSession.save(
        role: 'garage',
        id: garageId,
        name: (garage['name'] as String?) ?? 'Demo Garage',
        phone: (garage['phone'] as String?) ?? '',
        email: (garage['email'] as String?) ?? '',
      );
      return const DemoSignInResult(ok: true);
    } catch (e) {
      return DemoSignInResult(ok: false, message: '$e');
    }
  }
}
