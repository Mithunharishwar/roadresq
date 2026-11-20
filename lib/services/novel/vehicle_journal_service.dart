/// Digital Garage — Persistent Vehicle Service Journal Service (novel module).
///
/// Maintains a per-vehicle digital profile that accumulates a service history
/// timeline (fed from completed tokens/jobs), computes a health score, and
/// proactively generates maintenance reminders.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../models/novel/vehicle_journal_model.dart';

class VehicleJournalService {
  VehicleJournalService._internal();
  static final VehicleJournalService _instance =
      VehicleJournalService._internal();
  factory VehicleJournalService() => _instance;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// ─── Build / refresh a vehicle journal from completed service events ───
  VehicleJournal buildJournal({
    required String vehicleId,
    required String vehicleNumber,
    required String vehicleType,
    required String ownerId,
    String ownerName = '',
    List<Map<String, dynamic>>? completedServices,
  }) {
    final services = (completedServices ?? []).map((s) {
      return ServiceEntry(
        jobId: s['jobId']?.toString() ?? '',
        serviceType: s['serviceType']?.toString() ?? '',
        garageName: s['garageName']?.toString() ?? '',
        servicedAt: s['servicedAt'] is Timestamp
            ? (s['servicedAt'] as Timestamp).toDate()
            : DateTime.tryParse(s['servicedAt']?.toString() ?? '') ??
                DateTime.now(),
        cost: (s['cost'] as num?)?.toDouble() ?? 0,
        notes: s['notes']?.toString() ?? '',
      );
    }).toList()
      ..sort((a, b) => b.servicedAt.compareTo(a.servicedAt));

    final now = DateTime.now();
    final lastService = services.isNotEmpty ? services.first.servicedAt : null;

    // Health score: base 50, +10 per regular service (cap 100), decay if old.
    var health = 50.0;
    if (services.isNotEmpty) {
      health = minOf(100, 50 + services.length * 8);
      final daysSinceLast =
          lastService != null ? now.difference(lastService).inDays : 999;
      if (daysSinceLast > 180) health -= 20;
    }

    final reminders = _buildReminders(services, now);

    return VehicleJournal(
      vehicleId: vehicleId,
      vehicleNumber: vehicleNumber,
      vehicleType: vehicleType,
      ownerId: ownerId,
      ownerName: ownerName,
      healthScore: health.clamp(0, 100),
      lastServiceDate: lastService,
      totalServices: services.length,
      history: services,
      reminders: reminders,
    );
  }

  /// ─── Generate proactive maintenance reminders ───
  List<MaintenanceReminder> _buildReminders(
      List<ServiceEntry> services, DateTime now) {
    final reminders = <MaintenanceReminder>[];
    final last = services.isNotEmpty ? services.first.servicedAt : null;

    // Engine oil change reminder (~every 6 months).
    if (last != null) {
      final due = last.add(const Duration(days: 180));
      final overdue = now.isAfter(due);
      reminders.add(MaintenanceReminder(
        type: 'oil_change',
        title: 'Engine Oil Change',
        description: 'Recommended every 6 months or 5000 km.',
        dueDate: due,
        isOverdue: overdue,
      ));
    }

    // Battery check reminder (~every 2 years).
    if (last != null) {
      final due = last.add(const Duration(days: 730));
      reminders.add(MaintenanceReminder(
        type: 'battery',
        title: 'Battery Health Check',
        description: 'Recommended every 2 years.',
        dueDate: due,
        isOverdue: now.isAfter(due),
      ));
    }

    // General service reminder.
    reminders.add(MaintenanceReminder(
      type: 'general',
      title: 'General Servicing',
      description: 'Periodic full vehicle inspection.',
      dueDate: now.add(const Duration(days: 30)),
      isOverdue: false,
    ));

    return reminders;
  }

  double minOf(double a, double b) => a < b ? a : b;

  /// ─── Persist the vehicle journal ───
  Future<bool> persistJournal(VehicleJournal journal) async {
    try {
      await _firestore
          .collection('vehicle_journals')
          .doc(journal.vehicleId)
          .set({
        'vehicleId': journal.vehicleId,
        'vehicleNumber': journal.vehicleNumber,
        'vehicleType': journal.vehicleType,
        'ownerId': journal.ownerId,
        'ownerName': journal.ownerName,
        'healthScore': journal.healthScore,
        'lastServiceDate': journal.lastServiceDate?.toIso8601String(),
        'totalServices': journal.totalServices,
        'totalDistanceKm': journal.totalDistanceKm,
        'history': journal.history
            .map((e) => {
                  'jobId': e.jobId,
                  'serviceType': e.serviceType,
                  'garageName': e.garageName,
                  'servicedAt': e.servicedAt.toIso8601String(),
                  'cost': e.cost,
                  'notes': e.notes,
                })
            .toList(),
        'reminders': journal.reminders
            .map((e) => {
                  'type': e.type,
                  'title': e.title,
                  'description': e.description,
                  'dueDate': e.dueDate.toIso8601String(),
                  'isOverdue': e.isOverdue,
                })
            .toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('VehicleJournalService.persistJournal error: $e');
      return false;
    }
  }

  /// ─── Fetch the vehicle journal for a vehicle ───
  Future<VehicleJournal?> fetchJournal(String vehicleId) async {
    try {
      final doc =
          await _firestore.collection('vehicle_journals').doc(vehicleId).get();
      if (!doc.exists) return null;
      final data = Map<String, dynamic>.from(doc.data() as Map);
      return VehicleJournal.fromJson(data);
    } catch (e) {
      debugPrint('VehicleJournalService.fetchJournal error: $e');
      return null;
    }
  }
}
