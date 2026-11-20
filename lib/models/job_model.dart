import 'package:cloud_firestore/cloud_firestore.dart';

/// Job Model for Crew (Mechanic or Assistant)
/// Tracks individual crew job lifecycle for a rescue request
class JobModel {
  final String id;
  final String requestId;
  final String crewId;
  final String crewName;
  final String crewRole; // 'mechanic' or 'assistant'
  final String userId;
  final String userName;
  final String userPhone;
  final GeoPoint pickupLocation;
  final String address;
  final String vehicleType;
  final String issueType;
  final String
      status; // pending, accepted, on_the_way, reached, completed, cancelled
  final double distanceKm;
  final double etaMinutes;
  final double earnings;
  final String? cancelledBy;
  final String? cancellationReason;
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final DateTime? startedAt;
  final DateTime? reachedAt;
  final DateTime? completedAt;

  JobModel({
    required this.id,
    required this.requestId,
    required this.crewId,
    this.crewName = '',
    required this.crewRole,
    this.userId = '',
    this.userName = '',
    this.userPhone = '',
    required this.pickupLocation,
    this.address = '',
    this.vehicleType = '',
    this.issueType = '',
    this.status = 'pending',
    this.distanceKm = 0.0,
    this.etaMinutes = 0.0,
    this.earnings = 0.0,
    this.cancelledBy,
    this.cancellationReason,
    DateTime? createdAt,
    this.acceptedAt,
    this.startedAt,
    this.reachedAt,
    this.completedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory JobModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return JobModel(
      id: doc.id,
      requestId: data['requestId'] ?? '',
      crewId: data['crewId'] ?? '',
      crewName: data['crewName'] ?? '',
      crewRole: data['crewRole'] ?? '',
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? '',
      userPhone: data['userPhone'] ?? '',
      pickupLocation:
          data['pickupLocation'] as GeoPoint? ?? const GeoPoint(0, 0),
      address: data['address'] ?? '',
      vehicleType: data['vehicleType'] ?? '',
      issueType: data['issueType'] ?? '',
      status: data['status'] ?? 'pending',
      distanceKm: (data['distanceKm'] ?? 0.0).toDouble(),
      etaMinutes: (data['etaMinutes'] ?? 0.0).toDouble(),
      earnings: (data['earnings'] ?? 0.0).toDouble(),
      cancelledBy: data['cancelledBy'],
      cancellationReason: data['cancellationReason'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      acceptedAt: (data['acceptedAt'] as Timestamp?)?.toDate(),
      startedAt: (data['startedAt'] as Timestamp?)?.toDate(),
      reachedAt: (data['reachedAt'] as Timestamp?)?.toDate(),
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'requestId': requestId,
      'crewId': crewId,
      'crewName': crewName,
      'crewRole': crewRole,
      'userId': userId,
      'userName': userName,
      'userPhone': userPhone,
      'pickupLocation': pickupLocation,
      'address': address,
      'vehicleType': vehicleType,
      'issueType': issueType,
      'status': status,
      'distanceKm': distanceKm,
      'etaMinutes': etaMinutes,
      'earnings': earnings,
      'cancelledBy': cancelledBy,
      'cancellationReason': cancellationReason,
      'createdAt': Timestamp.fromDate(createdAt),
      'acceptedAt': acceptedAt != null ? Timestamp.fromDate(acceptedAt!) : null,
      'startedAt': startedAt != null ? Timestamp.fromDate(startedAt!) : null,
      'reachedAt': reachedAt != null ? Timestamp.fromDate(reachedAt!) : null,
      'completedAt':
          completedAt != null ? Timestamp.fromDate(completedAt!) : null,
    };
  }

  JobModel copyWith(
      {String? status,
      DateTime? acceptedAt,
      DateTime? startedAt,
      DateTime? reachedAt,
      DateTime? completedAt}) {
    return JobModel(
      id: id,
      requestId: requestId,
      crewId: crewId,
      crewName: crewName,
      crewRole: crewRole,
      userId: userId,
      userName: userName,
      userPhone: userPhone,
      pickupLocation: pickupLocation,
      address: address,
      vehicleType: vehicleType,
      issueType: issueType,
      status: status ?? this.status,
      distanceKm: distanceKm,
      etaMinutes: etaMinutes,
      earnings: earnings,
      cancelledBy: cancelledBy,
      cancellationReason: cancellationReason,
      createdAt: createdAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      startedAt: startedAt ?? this.startedAt,
      reachedAt: reachedAt ?? this.reachedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  bool get isActive =>
      status == 'accepted' || status == 'on_the_way' || status == 'reached';
  String get statusDisplay {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'accepted':
        return 'Accepted';
      case 'on_the_way':
        return 'On The Way';
      case 'reached':
        return 'Reached';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }
}
