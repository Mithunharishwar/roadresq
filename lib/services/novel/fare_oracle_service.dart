/// FareOracle — Smart Dynamic Pricing Engine Service (novel module).
///
/// Predicts a transparent surge multiplier from fused signals (demand,
/// weather, time-of-day, traffic, availability) and produces a full fare
/// estimate with a price breakdown. Additive & self-contained.
library;

import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../models/novel/fare_oracle_model.dart';

// Base fare per service type (INR).
const Map<String, double> _baseFares = {
  'flat_tyre': 299,
  'battery': 349,
  'fuel': 199,
  'towing': 799,
  'lockout': 249,
  'general': 299,
};

class FareOracleService {
  FareOracleService._internal();
  static final FareOracleService _instance = FareOracleService._internal();
  factory FareOracleService() => _instance;

  double _baseFareFor(String serviceType) =>
      _baseFares[serviceType] ?? _baseFares['general']!;

  /// ─── Compute a live fare estimate ───
  FareEstimate estimateFare({
    required String serviceType,
    required double distanceKm,
    double demandIndex = 0.5, // 0-1
    String weather = 'clear', // clear, rain, storm, fog, hot
    int hour = 12,
    double trafficFactor = 1.0,
    int availableCrews = 10,
    String? estimateId,
  }) {
    final baseFare = _baseFareFor(serviceType) + distanceKm * 12;

    // ── Surge factors ──
    // 1. Demand-supply ratio.
    final demandWeight = (demandIndex * 0.5).clamp(0.0, 0.5);
    // 2. Weather.
    final weatherWeight = _weatherWeight(weather);
    // 3. Time-of-day (night 22:00-06:00 and rush 08-10/17-20).
    final timeWeight = _timeWeight(hour);
    // 4. Traffic (congestion multiplier).
    final trafficWeight = ((trafficFactor - 1.0) * 0.3).clamp(0.0, 0.3);
    // 5. Availability (scarcity raises price).
    final availabilityWeight = (1 - (availableCrews / 20)).clamp(0.0, 0.4);

    final surge = 1.0 +
        demandWeight +
        weatherWeight +
        timeWeight +
        trafficWeight +
        availabilityWeight;

    final fare = baseFare * surge;
    final gst = fare * 0.18;
    final total = fare + gst;

    final tier = _tierFor(surge);
    final etaMinutes =
        (distanceKm / 0.4).round() + (trafficFactor > 1.2 ? 8 : 0);

    return FareEstimate(
      estimateId: estimateId ?? 'est_${DateTime.now().millisecondsSinceEpoch}',
      serviceType: serviceType,
      distanceKm: distanceKm,
      etaMinutes: etaMinutes,
      baseFare: baseFare,
      surgeMultiplier: surge,
      fare: fare,
      gst: gst,
      total: total,
      fareTier: tier,
      expectedAvailableCrews: max(0, availableCrews),
      factors: [
        PriceFactor(
            name: 'Demand-Supply',
            weight: demandWeight,
            detail: 'Demand index ${(demandIndex * 100).toStringAsFixed(0)}%'),
        PriceFactor(
            name: 'Weather',
            weight: weatherWeight,
            detail: _weatherLabel(weather)),
        PriceFactor(
            name: 'Time of Day',
            weight: timeWeight,
            detail: '${hour.toString().padLeft(2, '0')}:00'),
        PriceFactor(
            name: 'Traffic',
            weight: trafficWeight,
            detail: 'Congestion ${(trafficFactor * 100).toStringAsFixed(0)}%'),
        PriceFactor(
            name: 'Crew Availability',
            weight: availabilityWeight,
            detail: '$availableCrews crews online'),
      ],
    );
  }

  double _weatherWeight(String weather) {
    switch (weather) {
      case 'storm':
        return 0.35;
      case 'rain':
        return 0.22;
      case 'fog':
        return 0.18;
      case 'hot':
        return 0.08;
      case 'clear':
      default:
        return 0.0;
    }
  }

  String _weatherLabel(String weather) {
    switch (weather) {
      case 'storm':
        return 'Storm';
      case 'rain':
        return 'Rain';
      case 'fog':
        return 'Fog';
      case 'hot':
        return 'Heat';
      default:
        return 'Clear';
    }
  }

  double _timeWeight(int hour) {
    if (hour >= 22 || hour < 6) return 0.15; // night
    if ((hour >= 8 && hour <= 10) || (hour >= 17 && hour <= 20)) {
      return 0.10; // rush
    }
    return 0.0;
  }

  String _tierFor(double surge) {
    if (surge >= 1.7) return 'high_surge';
    if (surge >= 1.35) return 'surge';
    if (surge >= 1.1) return 'normal';
    return 'low';
  }

  /// ─── Persist an estimate (historical fare log) ───
  Future<bool> persistEstimate(FareEstimate estimate) async {
    try {
      // No Firestore dependency needed for the demo; kept as a no-op hook.
      debugPrint('FareOracleService.persistEstimate: '
          '${estimate.estimateId} total ${estimate.total.toStringAsFixed(2)}');
      return true;
    } catch (e) {
      debugPrint('FareOracleService.persistEstimate error: $e');
      return false;
    }
  }

  /// ─── Demo estimate for self-contained screen demo ───
  FareEstimate sampleEstimate() => estimateFare(
        serviceType: 'flat_tyre',
        distanceKm: 4.5,
        demandIndex: 0.72,
        weather: 'rain',
        hour: DateTime.now().hour,
        trafficFactor: 1.3,
        availableCrews: 6,
      );
}
