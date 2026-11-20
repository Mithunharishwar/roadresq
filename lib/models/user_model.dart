import 'package:cloud_firestore/cloud_firestore.dart';

/// User model for RoadResQ platform
/// Represents both regular users and crew members (mechanic/assistant)
class UserModel {
  final String id;
  final String name;
  final String phone;
  final String email;
  final String? photoUrl;
  final String role; // 'user', 'mechanic', 'assistant', 'admin'
  final List<String> vehicleIds;
  final String? emergencyContact;
  final String? emergencyContactName;
  final double rating;
  final int ratingCount;
  final bool isKycVerified;
  final String? kycDocUrl;
  final String? fcmToken;
  final bool isOnline;
  final GeoPoint? currentLocation;
  final String? serviceZone;
  final DateTime createdAt;
  final DateTime updatedAt;

  UserModel({
    required this.id,
    required this.name,
    required this.phone,
    this.email = '',
    this.photoUrl,
    required this.role,
    this.vehicleIds = const [],
    this.emergencyContact,
    this.emergencyContactName,
    this.rating = 0.0,
    this.ratingCount = 0,
    this.isKycVerified = false,
    this.kycDocUrl,
    this.fcmToken,
    this.isOnline = false,
    this.currentLocation,
    this.serviceZone,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Create from Firestore document
  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel(
      id: doc.id,
      name: data['name'] ?? '',
      phone: data['phone'] ?? '',
      email: data['email'] ?? '',
      photoUrl: data['photoUrl'],
      role: data['role'] ?? 'user',
      vehicleIds: List<String>.from(data['vehicleIds'] ?? []),
      emergencyContact: data['emergencyContact'],
      emergencyContactName: data['emergencyContactName'],
      rating: (data['rating'] ?? 0.0).toDouble(),
      ratingCount: data['ratingCount'] ?? 0,
      isKycVerified: data['isKycVerified'] ?? false,
      kycDocUrl: data['kycDocUrl'],
      fcmToken: data['fcmToken'],
      isOnline: data['isOnline'] ?? false,
      currentLocation: data['currentLocation'] as GeoPoint?,
      serviceZone: data['serviceZone'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'phone': phone,
      'email': email,
      'photoUrl': photoUrl,
      'role': role,
      'vehicleIds': vehicleIds,
      'emergencyContact': emergencyContact,
      'emergencyContactName': emergencyContactName,
      'rating': rating,
      'ratingCount': ratingCount,
      'isKycVerified': isKycVerified,
      'kycDocUrl': kycDocUrl,
      'fcmToken': fcmToken,
      'isOnline': isOnline,
      'currentLocation': currentLocation,
      'serviceZone': serviceZone,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  /// Copy with updated fields
  UserModel copyWith({
    String? name,
    String? phone,
    String? email,
    String? photoUrl,
    String? role,
    List<String>? vehicleIds,
    String? emergencyContact,
    String? emergencyContactName,
    double? rating,
    int? ratingCount,
    bool? isKycVerified,
    String? kycDocUrl,
    String? fcmToken,
    bool? isOnline,
    GeoPoint? currentLocation,
    String? serviceZone,
  }) {
    return UserModel(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      role: role ?? this.role,
      vehicleIds: vehicleIds ?? this.vehicleIds,
      emergencyContact: emergencyContact ?? this.emergencyContact,
      emergencyContactName: emergencyContactName ?? this.emergencyContactName,
      rating: rating ?? this.rating,
      ratingCount: ratingCount ?? this.ratingCount,
      isKycVerified: isKycVerified ?? this.isKycVerified,
      kycDocUrl: kycDocUrl ?? this.kycDocUrl,
      fcmToken: fcmToken ?? this.fcmToken,
      isOnline: isOnline ?? this.isOnline,
      currentLocation: currentLocation ?? this.currentLocation,
      serviceZone: serviceZone ?? this.serviceZone,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  /// Check if crew is available for dispatch
  bool get isAvailable =>
      isOnline && isKycVerified && role != 'user' && role != 'admin';

  /// Get role display name
  String get roleDisplay {
    switch (role) {
      case 'mechanic':
        return 'Mechanic';
      case 'assistant':
        return 'Assistant';
      case 'admin':
        return 'Admin';
      default:
        return 'User';
    }
  }
}
