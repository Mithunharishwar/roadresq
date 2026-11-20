import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart';

/// LocationProvider — Riverpod state management for location
/// Tracks current position, zone info, and tracking state.

class LocationState {
  final Position? position;
  final bool isTracking;
  final bool hasPermission;
  final String? errorMessage;
  final bool isNightMode;

  const LocationState({
    this.position,
    this.isTracking = false,
    this.hasPermission = false,
    this.errorMessage,
    this.isNightMode = false,
  });

  LocationState copyWith({
    Position? position,
    bool? isTracking,
    bool? hasPermission,
    String? errorMessage,
    bool? isNightMode,
  }) {
    return LocationState(
      position: position ?? this.position,
      isTracking: isTracking ?? this.isTracking,
      hasPermission: hasPermission ?? this.hasPermission,
      errorMessage: errorMessage,
      isNightMode: isNightMode ?? this.isNightMode,
    );
  }
}

class LocationNotifier extends StateNotifier<LocationState> {
  final LocationService _locationService;

  LocationNotifier(this._locationService) : super(const LocationState());

  Future<void> requestPermission() async {
    final hasPermission = await _locationService.requestPermissions();
    state = state.copyWith(hasPermission: hasPermission);
  }

  Future<void> getCurrentPosition() async {
    final position = await _locationService.getCurrentPosition();
    if (position != null) {
      state = state.copyWith(
        position: position,
        isNightMode: LocationService.isNightMode(),
      );
    }
  }

  void startTracking() {
    _locationService.startTracking(
      onPositionUpdate: (position) {
        state = state.copyWith(
          position: position,
          isTracking: true,
          isNightMode: LocationService.isNightMode(),
        );
      },
      onError: (error) {
        state = state.copyWith(errorMessage: error);
      },
    );
  }

  void stopTracking() {
    _locationService.stopTracking();
    state = state.copyWith(isTracking: false);
  }

  @override
  void dispose() {
    _locationService.dispose();
    super.dispose();
  }
}

final locationProvider =
    StateNotifierProvider<LocationNotifier, LocationState>((ref) {
  return LocationNotifier(LocationService());
});
