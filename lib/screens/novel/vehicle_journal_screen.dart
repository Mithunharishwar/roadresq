/// Digital Garage — Vehicle Service Journal Screen (novel module).
///
/// Shows a vehicle's persistent service history, health score, and proactive
/// maintenance reminders.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/novel/vehicle_journal_model.dart';
import '../../providers/novel/vehicle_journal_provider.dart';
import '../../widgets/novel/novel_widgets.dart';

class VehicleJournalScreen extends ConsumerStatefulWidget {
  final String vehicleId;
  final String vehicleNumber;
  final String vehicleType;
  final String ownerId;
  final String ownerName;

  const VehicleJournalScreen({
    super.key,
    this.vehicleId = 'VEH-001',
    this.vehicleNumber = 'TN09 AB 1234',
    this.vehicleType = 'Sedan',
    this.ownerId = 'user1',
    this.ownerName = 'Rahul Kumar',
  });

  @override
  ConsumerState<VehicleJournalScreen> createState() =>
      _VehicleJournalScreenState();
}

class _VehicleJournalScreenState extends ConsumerState<VehicleJournalScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(vehicleJournalProvider.notifier).buildJournal(
            vehicleId: widget.vehicleId,
            vehicleNumber: widget.vehicleNumber,
            vehicleType: widget.vehicleType,
            ownerId: widget.ownerId,
            ownerName: widget.ownerName,
            completedServices: _sampleServices(),
          );
    });
  }

  List<Map<String, dynamic>> _sampleServices() {
    final now = DateTime.now();
    return [
      {
        'jobId': 'job-1',
        'serviceType': 'flat_tyre',
        'garageName': 'Central Tyres',
        'servicedAt': now.subtract(const Duration(days: 30)),
        'cost': 450,
        'notes': 'Rear left tyre replaced',
      },
      {
        'jobId': 'job-2',
        'serviceType': 'battery',
        'garageName': 'AutoZone',
        'servicedAt': now.subtract(const Duration(days: 90)),
        'cost': 5200,
        'notes': 'Battery jump-start & check',
      },
      {
        'jobId': 'job-3',
        'serviceType': 'towing',
        'garageName': 'Reliable Towing',
        'servicedAt': now.subtract(const Duration(days: 200)),
        'cost': 1500,
        'notes': 'Towed to garage after breakdown',
      },
    ];
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(vehicleJournalProvider);
    final journal = state.journal;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const NovelHero(
              title: 'Digital Garage',
              subtitle: 'Your Vehicle\'s Persistent Service Journal',
              icon: Icons.build_circle_outlined,
              colors: [Color(0xFFE65100), Color(0xFFFF9800)],
            ),
            const SizedBox(height: 20),
            if (journal == null)
              const NovelEmptyCard(
                message: 'No vehicle journal available yet.',
                icon: Icons.directions_car_outlined,
              )
            else ...[
              Row(
                children: [
                  NovelStatCard(
                    title: 'Health',
                    value: '${journal.healthScore.toStringAsFixed(0)}%',
                    color: _healthColor(journal.healthScore),
                    icon: Icons.favorite,
                  ),
                  const SizedBox(width: 10),
                  NovelStatCard(
                    title: 'Services',
                    value: '${journal.totalServices}',
                    color: const Color(0xFFE65100),
                    icon: Icons.build,
                  ),
                  const SizedBox(width: 10),
                  NovelStatCard(
                    title: 'Distance',
                    value: '${journal.totalDistanceKm} km',
                    color: const Color(0xFF0D47A1),
                    icon: Icons.route,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              NovelSectionTitle(
                title: 'Vehicle Info',
                icon: Icons.directions_car,
                color: const Color(0xFFE65100),
              ),
              const SizedBox(height: 12),
              _infoCard(journal),
              const SizedBox(height: 20),
              NovelSectionTitle(
                title: 'Service History',
                icon: Icons.history,
                color: const Color(0xFF0D47A1),
              ),
              const SizedBox(height: 12),
              if (journal.history.isEmpty)
                const NovelEmptyCard(
                  message: 'No service history recorded.',
                  icon: Icons.history_toggle_off,
                )
              else
                ...journal.history.map((e) => _serviceTile(e)),
              const SizedBox(height: 20),
              NovelSectionTitle(
                title: 'Maintenance Reminders',
                icon: Icons.notifications_active,
                color: const Color(0xFFD32F2F),
              ),
              const SizedBox(height: 12),
              if (journal.reminders.isEmpty)
                const NovelEmptyCard(message: 'No reminders.')
              else
                ...journal.reminders.map((r) => _reminderTile(r)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoCard(VehicleJournal journal) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha((0.05 * 255).round()),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _infoRow('Vehicle', journal.vehicleNumber),
          _infoRow('Type', journal.vehicleType),
          _infoRow('Owner', journal.ownerName),
          _infoRow(
            'Last Service',
            journal.lastServiceDate != null
                ? '${journal.lastServiceDate!.day}-${journal.lastServiceDate!.month}-${journal.lastServiceDate!.year}'
                : 'None',
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w700)),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.black87)),
          ),
        ],
      ),
    );
  }

  Widget _serviceTile(ServiceEntry e) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0D47A1).withAlpha((0.1 * 255).round()),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.build, color: Color(0xFF0D47A1)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_prettyType(e.serviceType),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
                Text(e.garageName,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black54)),
                Text(
                  '${e.servicedAt.day}-${e.servicedAt.month}-${e.servicedAt.year}',
                  style: const TextStyle(fontSize: 12, color: Colors.black45),
                ),
              ],
            ),
          ),
          Text('₹${e.cost.toStringAsFixed(0)}',
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFE65100),
                  fontSize: 15)),
        ],
      ),
    );
  }

  Widget _reminderTile(MaintenanceReminder r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: r.isOverdue
            ? Border.all(color: const Color(0xFFD32F2F), width: 1.5)
            : null,
      ),
      child: Row(
        children: [
          Icon(
            r.isOverdue ? Icons.warning_amber : Icons.check_circle_outline,
            color:
                r.isOverdue ? const Color(0xFFD32F2F) : const Color(0xFF2E7D32),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
                Text(r.description,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
          if (r.isOverdue)
            const NovelStatusPill(text: 'Overdue', color: Color(0xFFD32F2F)),
        ],
      ),
    );
  }

  String _prettyType(String type) {
    switch (type) {
      case 'flat_tyre':
        return 'Flat Tyre';
      case 'battery':
        return 'Battery';
      case 'fuel':
        return 'Fuel';
      case 'towing':
        return 'Towing';
      default:
        return type;
    }
  }

  Color _healthColor(double health) {
    if (health >= 70) return const Color(0xFF2E7D32);
    if (health >= 40) return const Color(0xFFFF8F00);
    return const Color(0xFFD32F2F);
  }
}
