/// Digital Garage — Vehicle Service Journal Model (novel module).
///
/// A persistent per-vehicle digital profile that accumulates a service
/// history timeline from completed tokens/jobs and computes a health score
/// plus proactive maintenance reminders.
class VehicleJournal {
  final String vehicleId;
  final String vehicleNumber;
  final String vehicleType;
  final String ownerId;
  final String ownerName;
  final double healthScore; // 0-100
  final DateTime? lastServiceDate;
  final int totalServices;
  final int totalDistanceKm;
  final List<ServiceEntry> history;
  final List<MaintenanceReminder> reminders;

  VehicleJournal({
    this.vehicleId = '',
    this.vehicleNumber = '',
    this.vehicleType = '',
    this.ownerId = '',
    this.ownerName = '',
    this.healthScore = 0,
    this.lastServiceDate,
    this.totalServices = 0,
    this.totalDistanceKm = 0,
    this.history = const [],
    this.reminders = const [],
  });

  factory VehicleJournal.fromJson(Map<String, dynamic> json) => VehicleJournal(
        vehicleId: json['vehicleId']?.toString() ?? '',
        vehicleNumber: json['vehicleNumber']?.toString() ?? '',
        vehicleType: json['vehicleType']?.toString() ?? '',
        ownerId: json['ownerId']?.toString() ?? '',
        ownerName: json['ownerName']?.toString() ?? '',
        healthScore: (json['healthScore'] as num?)?.toDouble() ?? 0,
        lastServiceDate: json['lastServiceDate'] != null
            ? DateTime.tryParse(json['lastServiceDate'].toString())
            : null,
        totalServices: (json['totalServices'] as num?)?.toInt() ?? 0,
        totalDistanceKm: (json['totalDistanceKm'] as num?)?.toInt() ?? 0,
        history: (json['history'] as List?)
                ?.map((e) => ServiceEntry.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        reminders: (json['reminders'] as List?)
                ?.map((e) =>
                    MaintenanceReminder.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}

/// A single service event in the vehicle's history.
class ServiceEntry {
  final String jobId;
  final String serviceType;
  final String garageName;
  final DateTime servicedAt;
  final double cost;
  final String notes;

  ServiceEntry({
    this.jobId = '',
    this.serviceType = '',
    this.garageName = '',
    DateTime? servicedAt,
    this.cost = 0,
    this.notes = '',
  }) : servicedAt = servicedAt ?? DateTime.now();

  factory ServiceEntry.fromJson(Map<String, dynamic> json) => ServiceEntry(
        jobId: json['jobId']?.toString() ?? '',
        serviceType: json['serviceType']?.toString() ?? '',
        garageName: json['garageName']?.toString() ?? '',
        servicedAt: json['servicedAt'] != null
            ? DateTime.tryParse(json['servicedAt'].toString()) ?? DateTime.now()
            : DateTime.now(),
        cost: (json['cost'] as num?)?.toDouble() ?? 0,
        notes: json['notes']?.toString() ?? '',
      );
}

/// A proactive maintenance reminder.
class MaintenanceReminder {
  final String type; // oil_change, battery, tyre, general
  final String title;
  final String description;
  final DateTime dueDate;
  final bool isOverdue;

  MaintenanceReminder({
    this.type = 'general',
    this.title = '',
    this.description = '',
    DateTime? dueDate,
    this.isOverdue = false,
  }) : dueDate = dueDate ?? DateTime.now();

  factory MaintenanceReminder.fromJson(Map<String, dynamic> json) =>
      MaintenanceReminder(
        type: json['type']?.toString() ?? 'general',
        title: json['title']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        dueDate: json['dueDate'] != null
            ? DateTime.tryParse(json['dueDate'].toString()) ?? DateTime.now()
            : DateTime.now(),
        isOverdue: json['isOverdue'] == true,
      );
}
