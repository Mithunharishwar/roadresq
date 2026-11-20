// IMPORTANT: Set Firestore Rules to allow read/write for testing
// FILE: lib/services/rating_service.dart
/// RatingService — User ratings for crew.
///
/// Implements: rateCrew(jobId, rating, review)
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../core/constants/app_constants.dart';

class RatingService {
  RatingService._internal();
  static final RatingService _instance = RatingService._internal();
  factory RatingService() => _instance;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// rateCrew(jobId, rating, review) — store rating + review after job complete.
  /// Updates the crew's aggregate rating and stores per-job rating.
  Future<bool> rateCrew({
    required String jobId,
    required double rating,
    required String review,
    String? mechanicCrewId,
    String? assistantCrewId,
    String? userId,
  }) async {
    try {
      await _firestore.collection('ratings').add({
        'jobId': jobId,
        'userId': userId ?? '',
        'rating': rating,
        'review': review,
        'mechanicCrewId': mechanicCrewId ?? '',
        'assistantCrewId': assistantCrewId ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Update aggregate rating for mechanic crew if provided.
      if (mechanicCrewId != null && mechanicCrewId.isNotEmpty) {
        await _updateCrewRating(mechanicCrewId, rating);
      }
      if (assistantCrewId != null && assistantCrewId.isNotEmpty) {
        await _updateCrewRating(assistantCrewId, rating);
      }
      return true;
    } on FirebaseException catch (e) {
      debugPrint(
          'RatingService.rateCrew FirebaseException: ${e.code} - ${e.message}');
      if (e.code == 'permission-denied') {
        debugPrint('PERMISSION_DENIED: Check Firestore Rules');
      }
      return false;
    } catch (e) {
      debugPrint('RatingService.rateCrew error: $e');
      return false;
    }
  }

  Future<void> _updateCrewRating(String crewId, double rating) async {
    try {
      final crewRef =
          _firestore.collection(AppConstants.collectionCrews).doc(crewId);
      final doc = await crewRef.get();
      if (!doc.exists) return;
      final data = doc.data() as Map<String, dynamic>;
      final totalRatings = (data['totalRatings'] ?? 0) as num;
      final ratingSum = ((data['ratingSum'] ?? 0) as num).toDouble();
      final newCount = totalRatings.toInt() + 1;
      final newSum = ratingSum + rating;
      await crewRef.update({
        'totalRatings': newCount,
        'ratingSum': newSum,
        'rating': (newSum / newCount),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      debugPrint(
          'RatingService._updateCrewRating FirebaseException: ${e.code} - ${e.message}');
      if (e.code == 'permission-denied') {
        debugPrint('PERMISSION_DENIED: Check Firestore Rules');
      }
    } catch (e) {
      debugPrint('RatingService._updateCrewRating error: $e');
    }
  }
}
