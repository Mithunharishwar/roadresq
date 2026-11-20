/// Community Safety Mesh — Helper Model (novel module).
///
/// A verified community helper acts as a fallback rescue layer (safety-vouched
/// bystanders) that can respond to an emergency beacon before / alongside crew.
class CommunityHelper {
  final String id;
  final String name;
  final String phone;
  final String? photoUrl;
  final double lat;
  final double lng;
  final bool isAvailable;
  final bool isVerified;
  final int vouchesReceived;
  final double responseScore; // 0-100
  final List<String> skills; // first_aid, vehicle_basic, escort
  final DateTime updatedAt;

  CommunityHelper({
    this.id = '',
    this.name = '',
    this.phone = '',
    this.photoUrl,
    this.lat = 0,
    this.lng = 0,
    this.isAvailable = false,
    this.isVerified = false,
    this.vouchesReceived = 0,
    this.responseScore = 0,
    this.skills = const [],
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  factory CommunityHelper.fromJson(Map<String, dynamic> json) =>
      CommunityHelper(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        phone: json['phone']?.toString() ?? '',
        photoUrl: json['photoUrl']?.toString(),
        lat: (json['lat'] as num?)?.toDouble() ?? 0,
        lng: (json['lng'] as num?)?.toDouble() ?? 0,
        isAvailable: json['isAvailable'] == true,
        isVerified: json['isVerified'] == true,
        vouchesReceived: (json['vouchesReceived'] as num?)?.toInt() ?? 0,
        responseScore: (json['responseScore'] as num?)?.toDouble() ?? 0,
        skills: (json['skills'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'photoUrl': photoUrl,
        'lat': lat,
        'lng': lng,
        'isAvailable': isAvailable,
        'isVerified': isVerified,
        'vouchesReceived': vouchesReceived,
        'responseScore': responseScore,
        'skills': skills,
        'updatedAt': updatedAt.toIso8601String(),
      };
}

/// A broadcast emergency beacon.
class EmergencyBeacon {
  final String beaconId;
  final String userId;
  final String userName;
  final String userPhone;
  final double lat;
  final double lng;
  final String message;
  final String status; // active, responded, resolved
  final DateTime createdAt;
  final List<String> notifiedHelperIds;
  final List<String> notifiedFamilyIds;

  EmergencyBeacon({
    this.beaconId = '',
    this.userId = '',
    this.userName = '',
    this.userPhone = '',
    this.lat = 0,
    this.lng = 0,
    this.message = '',
    this.status = 'active',
    DateTime? createdAt,
    this.notifiedHelperIds = const [],
    this.notifiedFamilyIds = const [],
  }) : createdAt = createdAt ?? DateTime.now();

  factory EmergencyBeacon.fromJson(Map<String, dynamic> json) =>
      EmergencyBeacon(
        beaconId: json['beaconId']?.toString() ?? '',
        userId: json['userId']?.toString() ?? '',
        userName: json['userName']?.toString() ?? '',
        userPhone: json['userPhone']?.toString() ?? '',
        lat: (json['lat'] as num?)?.toDouble() ?? 0,
        lng: (json['lng'] as num?)?.toDouble() ?? 0,
        message: json['message']?.toString() ?? '',
        status: json['status']?.toString() ?? 'active',
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
            : DateTime.now(),
        notifiedHelperIds: (json['notifiedHelperIds'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        notifiedFamilyIds: (json['notifiedFamilyIds'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );
}
