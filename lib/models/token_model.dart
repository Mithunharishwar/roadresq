import 'package:cloud_firestore/cloud_firestore.dart';

/// Digital Vehicle Token Model
/// Core patent: tracks vehicle through garage lifecycle
/// Flow: generated → handed_to_garage → repair_started → ready_for_pickup → closed
class TokenModel {
  final String id;
  final String tokenCode; // 6-digit alphanumeric
  final String qrUrl;
  final String userId;
  final String crewId;
  final String garageId;
  final String vehicleNumber;
  final String vehicleType;
  final String
      status; // generated, handed_to_garage, repair_started, ready_for_pickup, closed
  final String? garageName;
  final String? garagePhone;
  final String? garageAddress;
  final String? notes;
  // ── Security (Feature 2) ──
  final DateTime? expiresAt; // 30-min expiry
  final DateTime? consumedAt; // when token was used (one-time use)
  final String? issuedFor; // e.g. 'garage_pickup' — who token is intended for
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? handedOverAt;
  final DateTime? repairStartedAt;
  final DateTime? readyForPickupAt;
  final DateTime? closedAt;

  TokenModel({
    required this.id,
    required this.tokenCode,
    this.qrUrl = '',
    required this.userId,
    required this.crewId,
    required this.garageId,
    required this.vehicleNumber,
    this.vehicleType = '',
    this.status = 'generated',
    this.garageName,
    this.garagePhone,
    this.garageAddress,
    this.notes,
    this.expiresAt,
    this.consumedAt,
    this.issuedFor,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.handedOverAt,
    this.repairStartedAt,
    this.readyForPickupAt,
    this.closedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory TokenModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TokenModel(
      id: doc.id,
      tokenCode: data['tokenCode'] ?? '',
      qrUrl: data['qrUrl'] ?? '',
      userId: data['userId'] ?? '',
      crewId: data['crewId'] ?? '',
      garageId: data['garageId'] ?? '',
      vehicleNumber: data['vehicleNumber'] ?? '',
      vehicleType: data['vehicleType'] ?? '',
      status: data['status'] ?? 'generated',
      garageName: data['garageName'],
      garagePhone: data['garagePhone'],
      garageAddress: data['garageAddress'],
      notes: data['notes'],
      expiresAt: (data['expiresAt'] as Timestamp?)?.toDate(),
      consumedAt: (data['consumedAt'] as Timestamp?)?.toDate(),
      issuedFor: data['issuedFor'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      handedOverAt: (data['handedOverAt'] as Timestamp?)?.toDate(),
      repairStartedAt: (data['repairStartedAt'] as Timestamp?)?.toDate(),
      readyForPickupAt: (data['readyForPickupAt'] as Timestamp?)?.toDate(),
      closedAt: (data['closedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'tokenCode': tokenCode,
      'qrUrl': qrUrl,
      'userId': userId,
      'crewId': crewId,
      'garageId': garageId,
      'vehicleNumber': vehicleNumber,
      'vehicleType': vehicleType,
      'status': status,
      'garageName': garageName,
      'garagePhone': garagePhone,
      'garageAddress': garageAddress,
      'notes': notes,
      'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
      'consumedAt': consumedAt != null ? Timestamp.fromDate(consumedAt!) : null,
      'issuedFor': issuedFor,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'handedOverAt':
          handedOverAt != null ? Timestamp.fromDate(handedOverAt!) : null,
      'repairStartedAt':
          repairStartedAt != null ? Timestamp.fromDate(repairStartedAt!) : null,
      'readyForPickupAt': readyForPickupAt != null
          ? Timestamp.fromDate(readyForPickupAt!)
          : null,
      'closedAt': closedAt != null ? Timestamp.fromDate(closedAt!) : null,
    };
  }

  TokenModel copyWith({
    String? status,
    DateTime? expiresAt,
    DateTime? consumedAt,
    String? issuedFor,
    DateTime? handedOverAt,
    DateTime? repairStartedAt,
    DateTime? readyForPickupAt,
    DateTime? closedAt,
    String? notes,
  }) {
    return TokenModel(
      id: id,
      tokenCode: tokenCode,
      qrUrl: qrUrl,
      userId: userId,
      crewId: crewId,
      garageId: garageId,
      vehicleNumber: vehicleNumber,
      vehicleType: vehicleType,
      status: status ?? this.status,
      garageName: garageName,
      garagePhone: garagePhone,
      garageAddress: garageAddress,
      notes: notes ?? this.notes,
      expiresAt: expiresAt ?? this.expiresAt,
      consumedAt: consumedAt ?? this.consumedAt,
      issuedFor: issuedFor ?? this.issuedFor,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      handedOverAt: handedOverAt ?? this.handedOverAt,
      repairStartedAt: repairStartedAt ?? this.repairStartedAt,
      readyForPickupAt: readyForPickupAt ?? this.readyForPickupAt,
      closedAt: closedAt ?? this.closedAt,
    );
  }

  /// ── Security helpers (Feature 2) ──
  /// Whether the token has passed its 30-minute expiry window.
  bool get isExpired {
    final exp = expiresAt;
    if (exp == null) return false;
    return DateTime.now().isAfter(exp);
  }

  /// Whether the token has already been used (one-time use enforcement).
  bool get isConsumed => consumedAt != null;

  /// Whether the token is currently valid (not expired, not consumed).
  bool get isValid {
    if (isConsumed) return false;
    if (isExpired) return false;
    return true;
  }

  String get statusDisplay {
    switch (status) {
      case 'generated':
        return 'Token Generated';
      case 'handed_to_garage':
        return 'Handed to Garage';
      case 'repair_started':
        return 'Repair Started';
      case 'ready_for_pickup':
        return 'Ready for Pickup';
      case 'closed':
        return 'Closed';
      default:
        return status;
    }
  }

  int get statusIndex {
    const statuses = [
      'generated',
      'handed_to_garage',
      'repair_started',
      'ready_for_pickup',
      'closed'
    ];
    return statuses.indexOf(status);
  }
}
