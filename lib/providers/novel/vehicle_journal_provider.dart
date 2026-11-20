/// Digital Garage — Vehicle Service Journal Provider (novel module).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/novel/vehicle_journal_model.dart';
import '../../services/novel/vehicle_journal_service.dart';

/// ─── State ───
class VehicleJournalState {
  final bool isLoading;
  final String? errorMessage;
  final VehicleJournal? journal;
  final bool isPersisted;

  const VehicleJournalState({
    this.isLoading = false,
    this.errorMessage,
    this.journal,
    this.isPersisted = false,
  });

  VehicleJournalState copyWith({
    bool? isLoading,
    String? errorMessage,
    VehicleJournal? journal,
    bool? isPersisted,
  }) {
    return VehicleJournalState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      journal: journal ?? this.journal,
      isPersisted: isPersisted ?? this.isPersisted,
    );
  }
}

/// ─── Notifier ───
class VehicleJournalNotifier extends StateNotifier<VehicleJournalState> {
  final VehicleJournalService _service;

  VehicleJournalNotifier(this._service) : super(const VehicleJournalState());

  /// Build / refresh the journal from completed services.
  void buildJournal({
    required String vehicleId,
    required String vehicleNumber,
    required String vehicleType,
    required String ownerId,
    String ownerName = '',
    List<Map<String, dynamic>>? completedServices,
  }) {
    state = state.copyWith(isLoading: true, errorMessage: null);
    final journal = _service.buildJournal(
      vehicleId: vehicleId,
      vehicleNumber: vehicleNumber,
      vehicleType: vehicleType,
      ownerId: ownerId,
      ownerName: ownerName,
      completedServices: completedServices,
    );
    state = state.copyWith(isLoading: false, journal: journal);
  }

  /// Persist the current journal.
  Future<void> persist() async {
    final journal = state.journal;
    if (journal == null) return;
    final ok = await _service.persistJournal(journal);
    state = state.copyWith(isPersisted: ok);
  }

  /// Load an existing journal for a vehicle.
  Future<void> loadJournal(String vehicleId) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    final journal = await _service.fetchJournal(vehicleId);
    state = state.copyWith(isLoading: false, journal: journal);
  }

  void reset() => state = const VehicleJournalState();
}

/// ─── Provider ───
final vehicleJournalProvider =
    StateNotifierProvider<VehicleJournalNotifier, VehicleJournalState>((ref) {
  return VehicleJournalNotifier(VehicleJournalService());
});
