/// EcoRide — Green Rescue & Carbon Intelligence Service (novel module).
///
/// Computes per-rescue CO2 impact, aggregates an EcoScore, derives a
/// Green Tier, and tracks an offset "trees equivalent" counter. All logic
/// is additive and self-contained — no changes to existing rescue flow.
library;

import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../models/novel/eco_score_model.dart';

class EcoScoreService {
  EcoScoreService._internal();
  static final EcoScoreService _instance = EcoScoreService._internal();
  factory EcoScoreService() => _instance;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  double _co2Factor(String fuelType) {
    switch (fuelType) {
      case 'diesel':
        return 0.171;
      case 'ev':
        return 0.0;
      case 'manual':
        return 0.0;
      case 'petrol':
      default:
        return 0.192;
    }
  }

  /// ─── Compute the CO2 impact + green score of a single rescue ───
  EcoImpact computeRescueImpact({
    required String serviceType,
    required double distanceKm,
    String fuelType = 'petrol',
  }) {
    // Onsite repair (flat tyre/battery/lockout) avoids a tow-truck trip.
    // Onsite service emits only the crew's vehicle travel; a tow emits more.
    final baselineTow = distanceKm * 0.45; // what a tow-truck would emit
    final actual = distanceKm * _co2Factor(fuelType);

    // For EV / manual (no combustion), emissions are ~0 → maximum saving.
    final co2Saved = max(0.0, baselineTow - actual);
    final co2Kg = actual;

    // EcoScore: reward low emissions + short distance + high savings.
    final emissionScore = (1 - (co2Kg / max(1.0, baselineTow))).clamp(0.0, 1.0);
    final distanceEfficiency = (1 - (distanceKm / 20)).clamp(0.0, 1.0);
    final fuelGrade = fuelType == 'ev' || fuelType == 'manual'
        ? 1.0
        : (fuelType == 'petrol' ? 0.7 : 0.5);
    final raw =
        (emissionScore * 60) + (distanceEfficiency * 20) + (fuelGrade * 20);
    final ecoScore = raw.clamp(0.0, 100.0);

    return EcoImpact(
      serviceType: serviceType,
      distanceKm: distanceKm,
      fuelType: fuelType,
      co2Kg: co2Kg,
      co2SavedKg: co2Saved,
      ecoScore: ecoScore,
    );
  }

  /// ─── Aggregate a full EcoScore from a list of rescue impacts ───
  EcoScore aggregateScore({
    required String name,
    required List<EcoImpact> impacts,
  }) {
    final rescues = impacts.length;
    final totalCo2 = impacts.fold(0.0, (s, i) => s + i.co2Kg);
    final totalSaved = impacts.fold(0.0, (s, i) => s + i.co2SavedKg);
    final avgScore = rescues == 0
        ? 50.0
        : impacts.fold(0.0, (s, i) => s + i.ecoScore) / rescues;

    // Composite: average score weighted by consistency (rescues).
    final consistencyBoost = (1 - 1 / max(1, rescues)).clamp(0.0, 1.0);
    final ecoScore = (avgScore * 0.8 + consistencyBoost * 20).clamp(0.0, 100.0);

    // 1 mature tree offsets ~21 kg CO2/year → equivalent trees counter.
    final trees = (totalSaved / 21).floor();

    return EcoScore(
      name: name,
      rescues: rescues,
      totalCo2Kg: totalCo2,
      totalCo2SavedKg: totalSaved,
      ecoScore: ecoScore,
      greenTier: _deriveGreenTier(ecoScore, rescues),
      treesEquivalent: trees,
      recentImpacts: impacts,
    );
  }

  String _deriveGreenTier(double score, int rescues) {
    if (score >= 85 || rescues >= 50) return 'eco_elite';
    if (score >= 70 || rescues >= 20) return 'eco_guardian';
    if (score >= 55 || rescues >= 8) return 'eco_saver';
    return 'eco_beginner';
  }

  /// ─── Persist an EcoScore profile ───
  Future<bool> persistEcoScore(EcoScore score) async {
    try {
      await _firestore
          .collection('eco_scores')
          .doc(score.id.isEmpty ? 'default' : score.id)
          .set(score.toJson(), SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('EcoScoreService.persistEcoScore error: $e');
      return false;
    }
  }

  /// ─── Fetch an EcoScore profile ───
  Future<EcoScore?> fetchEcoScore(String id) async {
    try {
      final doc = await _firestore.collection('eco_scores').doc(id).get();
      if (!doc.exists) return null;
      return EcoScore.fromJson(Map<String, dynamic>.from(doc.data() as Map));
    } catch (e) {
      debugPrint('EcoScoreService.fetchEcoScore error: $e');
      return null;
    }
  }

  /// ─── Demo dataset for self-contained screen demo ───
  List<EcoImpact> sampleImpacts() => [
        computeRescueImpact(
            serviceType: 'flat_tyre', distanceKm: 3.2, fuelType: 'petrol'),
        computeRescueImpact(
            serviceType: 'battery', distanceKm: 4.1, fuelType: 'ev'),
        computeRescueImpact(
            serviceType: 'fuel', distanceKm: 6.5, fuelType: 'diesel'),
        computeRescueImpact(
            serviceType: 'lockout', distanceKm: 2.0, fuelType: 'manual'),
        computeRescueImpact(
            serviceType: 'towing', distanceKm: 8.0, fuelType: 'petrol'),
        computeRescueImpact(
            serviceType: 'battery', distanceKm: 1.4, fuelType: 'ev'),
      ];
}
