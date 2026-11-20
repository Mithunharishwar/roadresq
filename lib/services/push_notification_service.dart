// FILE: lib/services/push_notification_service.dart
/// PushNotificationService — FCM + SMS Module
///
/// Implements the spec functions:
///   - initFCM()                  → get device FCM token
///   - sendNotificationToCrew(crewId, title, body)
///   - sendNotificationToUser(userId, title, body)
///   - sendEmergencySMS(phone, message) → zone security SMS
///
/// Uses FirebaseMessaging on-device for token + foreground handling, and
/// delegates server-side sends to Cloud Functions (sendPushNotification /
/// sendEmergencySms) so the FCM tokens are resolved server-side.
library;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Result of a notification send.
class NotificationSendResult {
  final bool success;
  final String message;

  const NotificationSendResult({this.success = false, this.message = ''});
}

/// Push notification + SMS service.
class PushNotificationService {
  PushNotificationService._internal();
  static final PushNotificationService _instance =
      PushNotificationService._internal();
  factory PushNotificationService() => _instance;

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// initFCM() — request permission + retrieve device token.
  Future<String?> initFCM() async {
    try {
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus.name.contains('denied')) {
        debugPrint('PushNotificationService: permission denied');
        return null;
      }
      final token = await _messaging.getToken();
      debugPrint('PushNotificationService FCM token: $token');
      return token;
    } catch (e) {
      debugPrint('PushNotificationService.initFCM error: $e');
      return null;
    }
  }

  /// Listen for foreground messages (e.g., queued jobs).
  void listenForMessages(void Function(Map<String, dynamic> data) onMessage) {
    FirebaseMessaging.onMessage.listen((msg) {
      onMessage(msg.data);
    });
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      onMessage(msg.data);
    });
  }

  /// sendNotificationToCrew(crewId, title, body) — via Cloud Function.
  Future<NotificationSendResult> sendNotificationToCrew({
    required String crewId,
    required String title,
    required String body,
  }) async {
    return _send('sendPushNotification', {
      'crewId': crewId,
      'title': title,
      'body': body,
    });
  }

  /// sendNotificationToUser(userId, title, body) — via Cloud Function.
  Future<NotificationSendResult> sendNotificationToUser({
    required String userId,
    required String title,
    required String body,
  }) async {
    return _send('sendPushNotification', {
      'userId': userId,
      'title': title,
      'body': body,
    });
  }

  /// sendEmergencySMS(phone, message) — zone security SMS.
  Future<NotificationSendResult> sendEmergencySMS({
    required String phone,
    required String message,
    String userId = '',
    String requestId = '',
  }) async {
    try {
      final result = await _functions.httpsCallable('sendEmergencySms').call({
        'userId': userId,
        'userPhone': phone,
        'requestId': requestId,
        'message': message,
      });
      final data = result.data as Map<String, dynamic>;
      return NotificationSendResult(
        success: data['success'] == true,
        message: data['message'] ?? '',
      );
    } catch (e) {
      debugPrint('PushNotificationService.sendEmergencySMS error: $e');
      return NotificationSendResult(message: 'Failed to send SMS');
    }
  }

  Future<NotificationSendResult> _send(
      String fnName, Map<String, dynamic> payload) async {
    try {
      final result = await _functions.httpsCallable(fnName).call(payload);
      final data = result.data as Map<String, dynamic>;
      return NotificationSendResult(
        success: data['success'] == true,
        message: data['message'] ?? '',
      );
    } catch (e) {
      debugPrint('PushNotificationService._send($fnName) error: $e');
      return NotificationSendResult(message: 'Failed to send notification');
    }
  }
}
