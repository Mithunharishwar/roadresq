import 'package:cloud_firestore/cloud_firestore.dart';

/// GarageModel — Represents a partner garage where towed vehicles are serviced.
/// Used in conjunction with the Digital Vehicle Token System patent.
class GarageModel {
  final String id;
  final String name;
  final String phone;
  final String email;
  final String address;
  final GeoPoint location;
  final List<String> serviceTypes; // ['towing', 'repair', 'painting', ...]
  final double rating;
  final int ratingCount;
  final bool isActive;
  final String? photoUrl;
  final String? licenseNumber;
  final String? ownerName;
  final DateTime createdAt;
  final DateTime updatedAt;

  GarageModel({
    required this.id,
    required this.name,
    required this.phone,
    this.email = '',
    required this.address,
    required this.location,
    this.serviceTypes = const [],
    this.rating = 0.0,
    this.ratingCount = 0,
    this.isActive = true,
    this.photoUrl,
    this.licenseNumber,
    this.ownerName,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory GarageModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return GarageModel(
      id: doc.id,
      name: data['name'] ?? '',
      phone: data['phone'] ?? '',
      email: data['email'] ?? '',
      address: data['address'] ?? '',
      location: data['location'] as GeoPoint? ?? const GeoPoint(0, 0),
      serviceTypes: List<String>.from(data['serviceTypes'] ?? []),
      rating: (data['rating'] ?? 0.0).toDouble(),
      ratingCount: data['ratingCount'] ?? 0,
      isActive: data['isActive'] ?? true,
      photoUrl: data['photoUrl'],
      licenseNumber: data['licenseNumber'],
      ownerName: data['ownerName'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'phone': phone,
      'email': email,
      'address': address,
      'location': location,
      'serviceTypes': serviceTypes,
      'rating': rating,
      'ratingCount': ratingCount,
      'isActive': isActive,
      'photoUrl': photoUrl,
      'licenseNumber': licenseNumber,
      'ownerName': ownerName,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  GarageModel copyWith({bool? isActive, double? rating, int? ratingCount}) {
    return GarageModel(
      id: id,
      name: name,
      phone: phone,
      email: email,
      address: address,
      location: location,
      serviceTypes: serviceTypes,
      rating: rating ?? this.rating,
      ratingCount: ratingCount ?? this.ratingCount,
      isActive: isActive ?? this.isActive,
      photoUrl: photoUrl,
      licenseNumber: licenseNumber,
      ownerName: ownerName,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
