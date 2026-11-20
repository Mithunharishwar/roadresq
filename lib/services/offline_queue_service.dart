import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// OfflineQueueService (FEATURE 5)
///
/// Handles the offline-crew scenario:
///  - When no crew is available, the app queues pending jobs via
///    `queueOfflineJob` → stored in `crew_offline_queue` (status "queued").
///  - When a crew comes back online, `deliverQueuedJobs` is called to push
///    queued jobs to that crew via FCM (`type: queued_job`).
///  - The FCM listener (`onQueuedJobMessage`) lets the crew accept the
///    delivered job.
class OfflineQueueService {
  OfflineQueueService._internal();
  static final OfflineQueueService _instance = OfflineQueueService._internal();
  factory OfflineQueueService() => _instance;

  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  /// Queue a pending job when no crew of [role] is available.
  Future<Map<String, dynamic>> queueOfflineJob({
    required String requestId,
    required String role,
    double? lat,
    double? lng,
    String zone = '',
  }) async {
    try {
      final result = await _functions.httpsCallable('queueOfflineJob').call({
        'requestId': requestId,
        'role': role,
        'lat': lat,
        'lng': lng,
        'zone': zone,
      });
      final data = result.data as Map<String, dynamic>;
      return {
        'success': data['success'] == true,
        'queueId': data['queueId'] ?? '',
      };
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
          'OfflineQueueService.queueOfflineJob error: ${e.code} ${e.message}');
      return {'success': false, 'message': e.message ?? 'Failed to queue job'};
    } catch (e) {
      debugPrint('OfflineQueueService.queueOfflineJob error: $e');
      return {'success': false, 'message': 'Failed to queue job'};
    }
  }

  /// Deliver queued jobs to a crew member when they come online.
  Future<Map<String, dynamic>> deliverQueuedJobs({
    required String crewId,
    double? lat,
    double? lng,
  }) async {
    try {
      final result = await _functions.httpsCallable('deliverQueuedJobs').call({
        'crewId': crewId,
        'lat': lat,
        'lng': lng,
      });
      final data = result.data as Map<String, dynamic>;
      return {
        'success': data['success'] == true,
        'delivered': data['delivered'] ?? [],
        'message': data['message'] ?? '',
      };
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
          'OfflineQueueService.deliverQueuedJobs error: ${e.code} ${e.message}');
      return {'success': false, 'message': e.message ?? 'Failed to deliver'};
    } catch (e) {
      debugPrint('OfflineQueueService.deliverQueuedJobs error: $e');
      return {'success': false, 'message': 'Failed to deliver'};
    }
  }

  /// Register an FCM listener that handles delivered queued-job messages.
  /// Returns an unsubscribe function.
  Future<void> onQueuedJobMessage(
    void Function(Map<String, dynamic> data) handler,
  ) async {
    // Foreground message stream.
    FirebaseMessaging.onMessage.listen((message) {
      final data = message.data;
      if (data['type'] == 'queued_job') {
        handler(data);
      }
    });

    // Background/terminated message (when tapped).
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final data = message.data;
      if (data['type'] == 'queued_job') {
        handler(data);
      }
    });

    // Initial message if the app was launched from a notification.
    final initial = await _messaging.getInitialMessage();
    if (initial != null && initial.data['type'] == 'queued_job') {
      handler(initial.data);
    }
  }
}
