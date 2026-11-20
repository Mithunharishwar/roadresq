/// Zone Model for Chennai Geofencing
/// Core patent: Urban/Rural security zones with dynamic rules
class ZoneModel {
  final String id;
  final String name;
  final String type; // 'urban' or 'rural'
  final double latMin;
  final double latMax;
  final double lngMin;
  final double lngMax;
  final String securityLevel; // 'low', 'medium', 'high'
  final bool requiresPhotoVerification;
  final bool requiresEmergencySms;
  final int verificationCount; // 1 for urban, 2 for rural
  final DateTime createdAt;

  ZoneModel({
    required this.id,
    required this.name,
    required this.type,
    required this.latMin,
    required this.latMax,
    required this.lngMin,
    required this.lngMax,
    this.securityLevel = 'medium',
    this.requiresPhotoVerification = false,
    this.requiresEmergencySms = false,
    this.verificationCount = 1,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory ZoneModel.fromMap(Map<String, dynamic> data, String id) {
    return ZoneModel(
      id: id,
      name: data['name'] ?? '',
      type: data['type'] ?? 'urban',
      latMin: (data['latMin'] ?? 0.0).toDouble(),
      latMax: (data['latMax'] ?? 0.0).toDouble(),
      lngMin: (data['lngMin'] ?? 0.0).toDouble(),
      lngMax: (data['lngMax'] ?? 0.0).toDouble(),
      securityLevel: data['securityLevel'] ?? 'medium',
      requiresPhotoVerification: data['requiresPhotoVerification'] ?? false,
      requiresEmergencySms: data['requiresEmergencySms'] ?? false,
      verificationCount: data['verificationCount'] ?? 1,
      createdAt: DateTime.tryParse(data['createdAt'] ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'type': type,
      'latMin': latMin,
      'latMax': latMax,
      'lngMin': lngMin,
      'lngMax': lngMax,
      'securityLevel': securityLevel,
      'requiresPhotoVerification': requiresPhotoVerification,
      'requiresEmergencySms': requiresEmergencySms,
      'verificationCount': verificationCount,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// Check if a point falls within this zone
  bool contains(double lat, double lng) {
    return lat >= latMin && lat <= latMax && lng >= lngMin && lng <= lngMax;
  }

  bool get isUrban => type == 'urban';
  bool get isRural => type == 'rural';
}
