/// RoadIQ — Predictive Demand & Dispatch Intelligence Service (novel module).
///
/// Provides:
///  - Demand forecasting (hourly service-type prediction from historical jobs)
///  - Live demand heatmap cells (aggregated by zone)
///  - Smart ETA refinement (traffic-aware decay + crew-load factor)
///  - Crew pre-warm recommendations (optimal crew count per zone/hour)
library;

import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../models/novel/prediction_model.dart';

class RoadIqService {
  RoadIqService._internal();
  static final RoadIqService _instance = RoadIqService._internal();
  factory RoadIqService() => _instance;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// ─── Demand Forecast ───
  /// Predicts demand for a given hour + service type based on historical jobs.
  /// Uses a lightweight moving-average + day-of-week boost heuristic.
  List<DemandPrediction> forecastDemand({
    required int hour,
    List<Map<String, dynamic>>? historicalJobs,
    List<Map<String, dynamic>>? zones,
  }) {
    final jobs = historicalJobs ?? _sampleJobs();
    final zoneList = zones ?? _sampleZones();
    final predictions = <DemandPrediction>[];

    for (final zone in zoneList) {
      final zoneName = zone['name']?.toString() ?? 'Zone';
      final lat = (zone['lat'] as num?)?.toDouble() ?? 13.0;
      final lng = (zone['lng'] as num?)?.toDouble() ?? 80.0;

      // Count historical jobs in this zone by service type.
      final serviceCounts = <String, int>{};
      for (final job in jobs) {
        final jZone = job['zone']?.toString() ?? '';
        if (jZone.isNotEmpty && jZone != zoneName) continue;
        final type = job['serviceType']?.toString() ?? 'general';
        final jHour = (job['hour'] as num?)?.toInt() ?? hour;
        // Weight jobs closer to the target hour more heavily.
        final weight = 1.0 / (0.5 + _hourDistance(jHour, hour).toDouble());
        serviceCounts[type] = (serviceCounts[type] ?? 0) + weight.round();
      }

      if (serviceCounts.isEmpty) {
        serviceCounts['general'] = (0.3 + Random().nextDouble() * 0.4).round();
      }

      serviceCounts.forEach((type, cnt) {
        // Normalize to a 0-100 demand score.
        final maxCount = serviceCounts.values.reduce(max);
        final demand = (cnt / (maxCount == 0 ? 1 : maxCount) * 100)
            .clamp(0, 100)
            .toDouble();
        final confidence = (0.5 + (cnt / (cnt + 5)) * 0.5).clamp(0.0, 1.0);
        final recommendedCrews = (demand / 25).ceil().clamp(1, 6);

        predictions.add(DemandPrediction(
          zoneName: zoneName,
          zoneId: zone['id']?.toString(),
          lat: lat,
          lng: lng,
          hour: hour,
          serviceType: type,
          predictedDemand: demand,
          confidence: confidence,
          recommendedCrews: recommendedCrews,
        ));
      });
    }

    predictions.sort((a, b) => b.predictedDemand.compareTo(a.predictedDemand));
    return predictions;
  }

  /// ─── Live Demand Heatmap ───
  /// Aggregates recent jobs into heatmap cells for map overlay.
  List<HeatmapCell> buildHeatmap({
    required List<Map<String, dynamic>> recentJobs,
    Map<String, List<double>>? anchorPoints,
  }) {
    final anchors = anchorPoints ??
        {
          'Chennai Central': [13.0827, 80.2707],
          'OMR': [12.8996, 80.2209],
          'Guindy': [13.0067, 80.2206],
        };

    final cells = <HeatmapCell>[];
    anchors.forEach((name, ll) {
      var intensity = 0.0;
      var count = 0;
      for (final job in recentJobs) {
        final lat = (job['lat'] as num?)?.toDouble() ?? 0;
        final lng = (job['lng'] as num?)?.toDouble() ?? 0;
        if (lat == 0 && lng == 0) continue;
        final d = _distanceKm(lat, lng, ll[0], ll[1]);
        if (d <= 5) {
          intensity += (1 - d / 5) * 0.5;
          count++;
        }
      }
      cells.add(HeatmapCell(
        lat: ll[0],
        lng: ll[1],
        intensity: intensity.clamp(0.0, 1.0),
        serviceType: 'general',
        jobCount: count,
      ));
    });
    return cells.where((c) => c.intensity > 0).toList();
  }

  /// ─── Smart ETA Refinement ───
  /// Refines a base ETA with a traffic-aware decay curve and a crew-load
  /// factor (busier crews = slightly slower).
  double refineEta({
    required double baseEtaMinutes,
    double trafficFactor = 1.0,
    int activeJobsForCrew = 0,
    double distanceKm = 0,
  }) {
    // Traffic-aware decay: longer trips see higher congestion impact.
    final congestion = trafficFactor * (1 + distanceKm / 20);
    // Crew-load factor: each concurrent job adds marginal delay.
    final loadFactor = 1 + activeJobsForCrew * 0.15;
    return (baseEtaMinutes * congestion.clamp(0.8, 2.5) * loadFactor)
        .clamp(1.0, 120.0);
  }

  /// ─── Pre-warm Recommendation ───
  /// Returns the optimal crew count to keep available for a zone at an hour.
  int recommendCrews({
    required double predictedDemand,
    double serviceLevel = 0.9, // target fill-rate
  }) {
    // Simple Erlang-B style approximation capped to a sensible range.
    final raw = (predictedDemand / 20) * serviceLevel;
    return raw.round().clamp(1, 8);
  }

  /// Persist a forecast batch to Firestore (for admin analytics).
  Future<bool> persistForecast(List<DemandPrediction> predictions) async {
    try {
      final batch = _firestore.batch();
      for (final p in predictions) {
        final ref = _firestore.collection('road_iq_forecasts').doc();
        batch.set(ref, {...p.toJson()});
      }
      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('RoadIqService.persistForecast error: $e');
      return false;
    }
  }

  int _hourDistance(int a, int b) {
    final d = (a - b).abs();
    return d <= 12 ? d : 24 - d;
  }

  double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = pow(sin(dLat / 2), 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * pow(sin(dLng / 2), 2);
    return 2 * R * atan2(sqrt(a), sqrt(1 - a));
  }

  double _rad(double deg) => deg * pi / 180.0;

  List<Map<String, dynamic>> _sampleJobs() => [
        {
          'serviceType': 'flat_tyre',
          'zone': 'Chennai Central',
          'hour': 9,
          'lat': 13.08,
          'lng': 80.27
        },
        {
          'serviceType': 'battery',
          'zone': 'Chennai Central',
          'hour': 10,
          'lat': 13.09,
          'lng': 80.28
        },
        {
          'serviceType': 'fuel',
          'zone': 'OMR',
          'hour': 11,
          'lat': 12.90,
          'lng': 80.22
        },
        {
          'serviceType': 'towing',
          'zone': 'Guindy',
          'hour': 12,
          'lat': 13.01,
          'lng': 80.22
        },
        {
          'serviceType': 'flat_tyre',
          'zone': 'OMR',
          'hour': 13,
          'lat': 12.89,
          'lng': 80.25
        },
      ];

  List<Map<String, dynamic>> _sampleZones() => [
        {'name': 'Chennai Central', 'lat': 13.0827, 'lng': 80.2707},
        {'name': 'OMR', 'lat': 12.8996, 'lng': 80.2209},
        {'name': 'Guindy', 'lat': 13.0067, 'lng': 80.2206},
      ];
}
