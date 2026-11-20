import 'package:cloud_firestore/cloud_firestore.dart';

/// Rescue Request Model
/// Tracks a user's SOS request through its full lifecycle
class RequestModel {
  final String id;
  final String userId;
  final String userName;
  final String userPhone;
  final GeoPoint location;
  final String address;
  final String vehicleType;
  final String issueType;
  final String? issuePhotoUrl;
  final String
      status; // pending, searching, assigned, active, completed, cancelled, escalated
  final String? assignedMechanicId;
  final String? assignedAssistantId;
  final double? mechanicEtaMinutes;
  final double? assistantEtaMinutes;
  final double amount;
  final String? paymentId;
  final String paymentStatus; // pending, success, failed, refunded
  final String? invoiceUrl;
  final String? cancellationReason;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? assignedAt;
  final DateTime? completedAt;

  RequestModel({
    required this.id,
    required this.userId,
    this.userName = '',
    this.userPhone = '',
    required this.location,
    this.address = '',
    this.vehicleType = '',
    this.issueType = '',
    this.issuePhotoUrl,
    this.status = 'pending',
    this.assignedMechanicId,
    this.assignedAssistantId,
    this.mechanicEtaMinutes,
    this.assistantEtaMinutes,
    this.amount = 0.0,
    this.paymentId,
    this.paymentStatus = 'pending',
    this.invoiceUrl,
    this.cancellationReason,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.assignedAt,
    this.completedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory RequestModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return RequestModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? '',
      userPhone: data['userPhone'] ?? '',
      location: data['location'] as GeoPoint? ?? const GeoPoint(0, 0),
      address: data['address'] ?? '',
      vehicleType: data['vehicleType'] ?? '',
      issueType: data['issueType'] ?? '',
      issuePhotoUrl: data['issuePhotoUrl'],
      status: data['status'] ?? 'pending',
      assignedMechanicId: data['assignedMechanicId'],
      assignedAssistantId: data['assignedAssistantId'],
      mechanicEtaMinutes: (data['mechanicEtaMinutes'] as num?)?.toDouble(),
      assistantEtaMinutes: (data['assistantEtaMinutes'] as num?)?.toDouble(),
      amount: (data['amount'] ?? 0.0).toDouble(),
      paymentId: data['paymentId'],
      paymentStatus: data['paymentStatus'] ?? 'pending',
      invoiceUrl: data['invoiceUrl'],
      cancellationReason: data['cancellationReason'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      assignedAt: (data['assignedAt'] as Timestamp?)?.toDate(),
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'userName': userName,
      'userPhone': userPhone,
      'location': location,
      'address': address,
      'vehicleType': vehicleType,
      'issueType': issueType,
      'issuePhotoUrl': issuePhotoUrl,
      'status': status,
      'assignedMechanicId': assignedMechanicId,
      'assignedAssistantId': assignedAssistantId,
      'mechanicEtaMinutes': mechanicEtaMinutes,
      'assistantEtaMinutes': assistantEtaMinutes,
      'amount': amount,
      'paymentId': paymentId,
      'paymentStatus': paymentStatus,
      'invoiceUrl': invoiceUrl,
      'cancellationReason': cancellationReason,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'assignedAt': assignedAt != null ? Timestamp.fromDate(assignedAt!) : null,
      'completedAt':
          completedAt != null ? Timestamp.fromDate(completedAt!) : null,
    };
  }

  RequestModel copyWith({
    String? userId,
    String? userName,
    String? userPhone,
    GeoPoint? location,
    String? address,
    String? vehicleType,
    String? issueType,
    String? issuePhotoUrl,
    String? status,
    String? assignedMechanicId,
    String? assignedAssistantId,
    double? mechanicEtaMinutes,
    double? assistantEtaMinutes,
    double? amount,
    String? paymentId,
    String? paymentStatus,
    String? invoiceUrl,
    String? cancellationReason,
    DateTime? assignedAt,
    DateTime? completedAt,
  }) {
    return RequestModel(
      id: id,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userPhone: userPhone ?? this.userPhone,
      location: location ?? this.location,
      address: address ?? this.address,
      vehicleType: vehicleType ?? this.vehicleType,
      issueType: issueType ?? this.issueType,
      issuePhotoUrl: issuePhotoUrl ?? this.issuePhotoUrl,
      status: status ?? this.status,
      assignedMechanicId: assignedMechanicId ?? this.assignedMechanicId,
      assignedAssistantId: assignedAssistantId ?? this.assignedAssistantId,
      mechanicEtaMinutes: mechanicEtaMinutes ?? this.mechanicEtaMinutes,
      assistantEtaMinutes: assistantEtaMinutes ?? this.assistantEtaMinutes,
      amount: amount ?? this.amount,
      paymentId: paymentId ?? this.paymentId,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      invoiceUrl: invoiceUrl ?? this.invoiceUrl,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      assignedAt: assignedAt ?? this.assignedAt,
      completedAt: completedAt ?? this.completedAt,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  bool get isActive => status == 'assigned' || status == 'active';
  bool get isCompleted => status == 'completed';
  bool get isPending => status == 'pending' || status == 'searching';
  bool get isPaid => paymentStatus == 'success';
}
