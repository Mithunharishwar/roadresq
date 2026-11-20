// IMPORTANT: Set Firestore Rules to allow read/write for testing
// FILE: lib/services/garage_service.dart
/// GarageService — Garage App Module
///
/// Implements the spec functions:
///   - scanTokenQR(qrData)        → parse QR from crew
///   - verifyToken(token, jobId)  → Cloud Function validates + marks "scanned"
///   - completeJobAtGarage(jobId) → marks token as "scanned" / job handed over
///   - raiseInvoice(jobId, amount) → send bill to user
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../core/constants/app_constants.dart';

/// Garage service.
class GarageService {
  GarageService._internal();
  static final GarageService _instance = GarageService._internal();
  factory GarageService() => _instance;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// scanTokenQR(qrData) — parse a scanned QR payload into a token code.
  /// QR data is either the raw 6-char code or a URL containing it.
  String scanTokenQR(String qrData) {
    final trimmed = qrData.trim();
    if (trimmed.isEmpty) return '';
    // If it's a URL like https://roadresq.app/token/ABC123, extract the code.
    final idx = trimmed.lastIndexOf('/');
    if (idx >= 0 && idx < trimmed.length - 1) {
      final candidate = trimmed.substring(idx + 1).trim();
      if (candidate.length == 6) return candidate;
    }
    return trimmed;
  }

  /// verifyToken(token, jobId) — Cloud Function atomically validates the token
  /// and marks it consumed/scanned.
  Future<Map<String, dynamic>> verifyToken({
    required String tokenCode,
    String jobId = '',
  }) async {
    try {
      final result = await _functions.httpsCallable('verifyToken')(
          {'tokenCode': tokenCode, 'jobId': jobId});
      final data = result.data as Map<String, dynamic>;
      return {
        'success': data['success'] == true,
        'message': data['message'] ?? '',
        'token': data['token'],
      };
    } catch (e) {
      debugPrint('GarageService.verifyToken error: $e');
      return {'success': false, 'message': 'Token verification failed'};
    }
  }

  /// completeJobAtGarage(jobId) — marks token as "scanned" and job handed over.
  /// Finds the token linked to the job and advances it to `handed_to_garage`.
  Future<bool> completeJobAtGarage({
    required String jobId,
    String garageId = '',
  }) async {
    try {
      final tokenSnap = await _firestore
          .collection(AppConstants.collectionTokens)
          .where('jobId', isEqualTo: jobId)
          .limit(1)
          .get();

      if (tokenSnap.docs.isNotEmpty) {
        final tokenRef = tokenSnap.docs.first.reference;
        await tokenRef.update({
          'status': 'handed_to_garage',
          'handedOverAt': FieldValue.serverTimestamp(),
          'scannedByGarageId': garageId,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      await _firestore
          .collection(AppConstants.collectionJobs)
          .doc(jobId)
          .update({
        'status': 'at_garage',
        'garageId': garageId,
        'handedToGarageAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } on FirebaseException catch (e) {
      debugPrint(
          'GarageService.completeJobAtGarage FirebaseException: ${e.code} - ${e.message}');
      if (e.code == 'permission-denied') {
        debugPrint('PERMISSION_DENIED: Check Firestore Rules');
      }
      return false;
    } catch (e) {
      debugPrint('GarageService.completeJobAtGarage error: $e');
      return false;
    }
  }

  /// raiseInvoice(jobId, amount) — send bill to the user.
  Future<Map<String, dynamic>> raiseInvoice({
    required String jobId,
    required String userId,
    required double amount,
    String mechanicId = '',
    String assistantId = '',
  }) async {
    try {
      final result = await _functions.httpsCallable('generateInvoice').call({
        'requestId': jobId,
        'userId': userId,
        'serviceAmount': amount,
        'mechanicId': mechanicId,
        'assistantId': assistantId,
      });
      final data = result.data as Map<String, dynamic>;
      return {
        'success': data['success'] == true,
        'invoiceId': data['invoiceId'] ?? '',
        'receiptNumber': data['receiptNumber'] ?? '',
        'totalAmount': (data['totalAmount'] ?? 0).toDouble(),
        'gstAmount': (data['gstAmount'] ?? 0).toDouble(),
      };
    } catch (e) {
      debugPrint('GarageService.raiseInvoice error: $e');
      return {'success': false, 'message': 'Failed to raise invoice'};
    }
  }
}
