/// RoadIQ Prediction Model — novel module.
///
/// Represents a single demand-forecast + dispatch-intelligence entry.
/// Used to power predictive dispatch, live demand heatmaps and smart ETA.
class DemandPrediction {
  final String id;
  final String? zoneId;
  final String zoneName;
  final double lat;
  final double lng;
  final int hour; // 0-23
  final String serviceType; // flat_tyre, battery, fuel, towing, lockout
  final double predictedDemand; // 0-100 score
  final double confidence; // 0-1
  final int recommendedCrews; // optimal crew count to pre-warm
  final DateTime createdAt;

  DemandPrediction({
    this.id = '',
    this.zoneId,
    this.zoneName = '',
    this.lat = 0,
    this.lng = 0,
    this.hour = 0,
    this.serviceType = 'general',
    this.predictedDemand = 0,
    this.confidence = 0,
    this.recommendedCrews = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory DemandPrediction.fromJson(Map<String, dynamic> json) {
    return DemandPrediction(
      id: json['id']?.toString() ?? '',
      zoneId: json['zoneId']?.toString(),
      zoneName: json['zoneName']?.toString() ?? '',
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0,
      hour: (json['hour'] as num?)?.toInt() ?? 0,
      serviceType: json['serviceType']?.toString() ?? 'general',
      predictedDemand: (json['predictedDemand'] as num?)?.toDouble() ?? 0,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      recommendedCrews: (json['recommendedCrews'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'zoneId': zoneId,
        'zoneName': zoneName,
        'lat': lat,
        'lng': lng,
        'hour': hour,
        'serviceType': serviceType,
        'predictedDemand': predictedDemand,
        'confidence': confidence,
        'recommendedCrews': recommendedCrews,
        'createdAt': createdAt.toIso8601String(),
      };

  /// Severity tier for the heatmap coloring.
  String get demandTier {
    if (predictedDemand >= 75) return 'high';
    if (predictedDemand >= 40) return 'medium';
    return 'low';
  }
}

/// A single heatmap cell aggregated for display on the map.
class HeatmapCell {
  final double lat;
  final double lng;
  final double intensity; // 0-1
  final String serviceType;
  final int jobCount;

  const HeatmapCell({
    this.lat = 0,
    this.lng = 0,
    this.intensity = 0,
    this.serviceType = 'general',
    this.jobCount = 0,
  });

  factory HeatmapCell.fromJson(Map<String, dynamic> json) => HeatmapCell(
        lat: (json['lat'] as num?)?.toDouble() ?? 0,
        lng: (json['lng'] as num?)?.toDouble() ?? 0,
        intensity: (json['intensity'] as num?)?.toDouble() ?? 0,
        serviceType: json['serviceType']?.toString() ?? 'general',
        jobCount: (json['jobCount'] as num?)?.toInt() ?? 0,
      );
}
