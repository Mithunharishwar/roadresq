import 'package:cloud_firestore/cloud_firestore.dart';

/// CrewModel — Core patent entity for 2-Man Crew Dispatch System.
/// Represents either a Mechanic or Assistant crew member.
/// Used by the weighted matching algorithm for intelligent dispatch.
class CrewModel {
  final String id;
  final String name;
  final String phone;
  final String email;
  final String role; // 'mechanic' | 'assistant'
  final String? photoUrl;
  final double rating;
  final int ratingCount;
  final bool isOnline;
  final bool isKycVerified;
  final String? kycDocUrl;
  final String? vehicleType; // For mechanics: bike, car, towing
  final String? specialization;
  final GeoPoint? currentLocation;
  final String? geohash; // Spatial index for 2-man matching (geohash prefix)
  final String? serviceZone;
  final double totalEarnings;
  final int jobsCompleted;
  final String? fcmToken;
  final DateTime createdAt;
  final DateTime updatedAt;

  CrewModel({
    required this.id,
    required this.name,
    required this.phone,
    this.email = '',
    required this.role,
    this.photoUrl,
    this.rating = 0.0,
    this.ratingCount = 0,
    this.isOnline = false,
    this.isKycVerified = false,
    this.kycDocUrl,
    this.vehicleType,
    this.specialization,
    this.currentLocation,
    this.geohash,
    this.serviceZone,
    this.totalEarnings = 0.0,
    this.jobsCompleted = 0,
    this.fcmToken,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory CrewModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CrewModel(
      id: doc.id,
      name: data['name'] ?? '',
      phone: data['phone'] ?? '',
      email: data['email'] ?? '',
      role: data['role'] ?? '',
      photoUrl: data['photoUrl'],
      rating: (data['rating'] ?? 0.0).toDouble(),
      ratingCount: data['ratingCount'] ?? 0,
      isOnline: data['isOnline'] ?? false,
      isKycVerified: data['isKycVerified'] ?? false,
      kycDocUrl: data['kycDocUrl'],
      vehicleType: data['vehicleType'],
      specialization: data['specialization'],
      currentLocation: data['currentLocation'] as GeoPoint?,
      geohash: data['geohash'],
      serviceZone: data['serviceZone'],
      totalEarnings: (data['totalEarnings'] ?? 0.0).toDouble(),
      jobsCompleted: data['jobsCompleted'] ?? 0,
      fcmToken: data['fcmToken'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'phone': phone,
      'email': email,
      'role': role,
      'photoUrl': photoUrl,
      'rating': rating,
      'ratingCount': ratingCount,
      'isOnline': isOnline,
      'isKycVerified': isKycVerified,
      'kycDocUrl': kycDocUrl,
      'vehicleType': vehicleType,
      'specialization': specialization,
      'currentLocation': currentLocation,
      'geohash': geohash,
      'serviceZone': serviceZone,
      'totalEarnings': totalEarnings,
      'jobsCompleted': jobsCompleted,
      'fcmToken': fcmToken,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  CrewModel copyWith({
    String? name,
    String? phone,
    String? email,
    String? photoUrl,
    double? rating,
    int? ratingCount,
    bool? isOnline,
    bool? isKycVerified,
    String? kycDocUrl,
    String? vehicleType,
    String? specialization,
    GeoPoint? currentLocation,
    String? geohash,
    String? serviceZone,
    double? totalEarnings,
    int? jobsCompleted,
    String? fcmToken,
  }) {
    return CrewModel(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      role: role,
      photoUrl: photoUrl ?? this.photoUrl,
      rating: rating ?? this.rating,
      ratingCount: ratingCount ?? this.ratingCount,
      isOnline: isOnline ?? this.isOnline,
      isKycVerified: isKycVerified ?? this.isKycVerified,
      kycDocUrl: kycDocUrl ?? this.kycDocUrl,
      vehicleType: vehicleType ?? this.vehicleType,
      specialization: specialization ?? this.specialization,
      currentLocation: currentLocation ?? this.currentLocation,
      geohash: geohash ?? this.geohash,
      serviceZone: serviceZone ?? this.serviceZone,
      totalEarnings: totalEarnings ?? this.totalEarnings,
      jobsCompleted: jobsCompleted ?? this.jobsCompleted,
      fcmToken: fcmToken ?? this.fcmToken,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  bool get isAvailable => isOnline && isKycVerified;

  String get roleDisplay => role == 'mechanic' ? 'Mechanic' : 'Assistant';

  /// Compute dispatch score for patent matching algorithm
  double computeDispatchScore({
    required double distanceKm,
    required double maxDistance,
    required bool isInPreferredZone,
  }) {
    // Weights from AppConstants
    const double wDistance = 0.40;
    const double wRating = 0.25;
    const double wActive = 0.20;
    const double wZone = 0.15;

    // Normalize distance score (closer = higher)
    final distanceScore = maxDistance > 0
        ? (1.0 - (distanceKm / maxDistance)).clamp(0.0, 1.0)
        : 1.0;

    // Rating score (0-5 normalized to 0-1)
    final ratingScore = rating / 5.0;

    // Active status score
    final activeScore = isOnline ? 1.0 : 0.0;

    // Zone preference score
    final zoneScore = isInPreferredZone ? 1.0 : 0.3;

    // Weighted composite score
    return (wDistance * distanceScore) +
        (wRating * ratingScore) +
        (wActive * activeScore) +
        (wZone * zoneScore);
  }
}
