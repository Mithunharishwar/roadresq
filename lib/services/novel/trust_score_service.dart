/// TrustScore — Layered Reputation & Gamified Badges Service (novel module).
///
/// Computes a multi-dimensional trust score for a crew member from
/// behavioral signals, awards badges, and derives a trust tier that unlocks
/// platform perks (priority dispatch, higher payout bracket).
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../models/novel/trust_profile_model.dart';

class TrustScoreService {
  TrustScoreService._internal();
  static final TrustScoreService _instance = TrustScoreService._internal();
  factory TrustScoreService() => _instance;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// ─── Compute the full trust profile for a crew member ───
  TrustProfile computeTrustProfile({
    required String crewId,
    required String role,
    double rating = 0,
    int ratingCount = 0,
    int jobsCompleted = 0,
    int onTime = 0,
    int lateCount = 0,
    int cancellations = 0,
    int respondedFast = 0,
    int zoneAdherent = 0,
    int safetyAdherent = 0,
  }) {
    // Reliability: share of on-time accepts vs total completed.
    final reliability = jobsCompleted == 0
        ? 0.0
        : ((jobsCompleted - cancellations) / jobsCompleted * 60)
            .clamp(0, 100)
            .toDouble();

    // Response: share of fast responses.
    final response = jobsCompleted == 0
        ? 0.0
        : (respondedFast / jobsCompleted * 100).clamp(0, 100).toDouble();

    // Rating: normalized 0-5 → 0-100.
    final ratingScore =
        ratingCount == 0 ? 50.0 : (rating / 5 * 100).clamp(0, 100).toDouble();

    // Zone consistency.
    final zoneConsistency = jobsCompleted == 0
        ? 50.0
        : (zoneAdherent / jobsCompleted * 100).clamp(0, 100).toDouble();

    // Safety adherence.
    final safety = jobsCompleted == 0
        ? 60.0
        : (safetyAdherent / jobsCompleted * 100).clamp(0, 100).toDouble();

    // Weighted composite trust score.
    final trustScore = (reliability * 0.30) +
        (response * 0.20) +
        (ratingScore * 0.25) +
        (zoneConsistency * 0.10) +
        (safety * 0.15);

    final badges = _awardBadges(
      jobsCompleted: jobsCompleted,
      onTimeCount: onTime,
      responseScore: response,
      zoneConsistencyScore: zoneConsistency,
      safetyScore: safety,
    );

    final tier = _deriveTier(trustScore, badges);

    return TrustProfile(
      crewId: crewId,
      role: role,
      trustScore: trustScore,
      reliabilityScore: reliability,
      responseScore: response,
      ratingScore: ratingScore,
      zoneConsistencyScore: zoneConsistency,
      safetyScore: safety,
      jobsCompletedTotal: jobsCompleted,
      onTimeCount: onTime,
      lateCount: lateCount,
      cancellations: cancellations,
      badges: badges,
      tier: tier,
    );
  }

  /// ─── Award gamified badges based on behaviour ───
  List<String> _awardBadges({
    required int jobsCompleted,
    required int onTimeCount,
    required double responseScore,
    required double zoneConsistencyScore,
    required double safetyScore,
  }) {
    final badges = <String>[];
    if (jobsCompleted >= 10) badges.add('experience_warrior');
    if (jobsCompleted >= 50) badges.add('road_veteran');
    if (onTimeCount >= 20) badges.add('punctual_pro');
    if (responseScore >= 80) badges.add('rapid_responder');
    if (zoneConsistencyScore >= 80) badges.add('zone_guardian');
    if (safetyScore >= 85) badges.add('safety_champion');
    if (badges.length >= 4) badges.add('trust_elite');
    if (badges.isEmpty) badges.add('rising_star');
    return badges;
  }

  /// ─── Derive trust tier ───
  String _deriveTier(double score, List<String> badges) {
    if (score >= 85 || badges.contains('trust_elite')) return 'platinum';
    if (score >= 70) return 'gold';
    if (score >= 55) return 'silver';
    return 'bronze';
  }

  /// ─── Priority dispatch weight bump for higher tiers ───
  double dispatchPriorityMultiplier(String tier) {
    switch (tier) {
      case 'platinum':
        return 1.15;
      case 'gold':
        return 1.08;
      case 'silver':
        return 1.03;
      default:
        return 1.0;
    }
  }

  /// ─── Persist the trust profile for a crew member ───
  Future<bool> persistTrustProfile(TrustProfile profile) async {
    try {
      await _firestore
          .collection('trust_profiles')
          .doc(profile.crewId)
          .set(profile.toJson(), SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('TrustScoreService.persistTrustProfile error: $e');
      return false;
    }
  }

  /// ─── Fetch the trust profile for a crew member ───
  Future<TrustProfile?> fetchTrustProfile(String crewId) async {
    try {
      final doc =
          await _firestore.collection('trust_profiles').doc(crewId).get();
      if (!doc.exists) return null;
      return TrustProfile.fromJson(
          Map<String, dynamic>.from(doc.data() as Map));
    } catch (e) {
      debugPrint('TrustScoreService.fetchTrustProfile error: $e');
      return null;
    }
  }
}
