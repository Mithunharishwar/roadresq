import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import '../core/constants/app_constants.dart';

/// LocationService — Dedicated location management service
/// Handles GPS permissions, continuous tracking, zone detection, and ETA calculation.
class LocationService {
  StreamSubscription<Position>? _positionStream;
  Position? _lastPosition;
  bool _isTracking = false;

  // ─── Singleton ───
  LocationService._internal();
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;

  // ─── Getters ───
  Position? get lastPosition => _lastPosition;
  bool get isTracking => _isTracking;

  // ─── Permissions ───

  /// Check and request location permissions
  Future<bool> requestPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('LocationService: Location services disabled');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('LocationService: Location permissions denied');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('LocationService: Location permissions permanently denied');
      return false;
    }

    return true;
  }

  /// Get current position (one-time)
  Future<Position?> getCurrentPosition({
    LocationAccuracy accuracy = LocationAccuracy.high,
  }) async {
    try {
      final hasPermission = await requestPermissions();
      if (!hasPermission) return null;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: accuracy,
      );
      _lastPosition = position;
      return position;
    } catch (e) {
      debugPrint('LocationService.getCurrentPosition error: $e');
      return null;
    }
  }

  // ─── Continuous Tracking ───

  /// Start continuous location tracking
  void startTracking({
    LocationAccuracy accuracy = LocationAccuracy.bestForNavigation,
    int distanceFilter = 5, // meters
    Function(Position)? onPositionUpdate,
    Function(String)? onError,
    bool isNightMode = false,
  }) {
    if (_isTracking) return;

    _isTracking = true;
    final interval = isNightMode
        ? AppConstants.ruralTrackingIntervalSec
        : AppConstants.normalLocationIntervalMs ~/ 1000;

    _positionStream = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        timeLimit: Duration(seconds: interval * 10),
      ),
    ).listen(
      (Position position) {
        _lastPosition = position;
        onPositionUpdate?.call(position);
      },
      onError: (error) {
        debugPrint('LocationService stream error: $error');
        onError?.call(error.toString());
      },
    );
  }

  /// Stop location tracking
  void stopTracking() {
    _positionStream?.cancel();
    _positionStream = null;
    _isTracking = false;
  }

  // ─── Utility Methods ───

  /// Calculate distance between two coordinates in meters
  static double distanceInMeters(
      double lat1, double lng1, double lat2, double lng2) {
    return Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
  }

  /// Calculate distance in kilometers
  static double distanceInKm(
      double lat1, double lng1, double lat2, double lng2) {
    return distanceInMeters(lat1, lng1, lat2, lng2) / 1000;
  }

  /// Estimate ETA in minutes based on distance and average speed
  static int estimateEtaMinutes(double distanceKm, {double avgSpeedKmph = 30}) {
    if (distanceKm <= 0) return 0;
    final minutes = (distanceKm / avgSpeedKmph) * 60;
    return minutes.ceil();
  }

  /// Get bearing between two points
  static double bearingBetween(
      double lat1, double lng1, double lat2, double lng2) {
    return Geolocator.bearingBetween(lat1, lng1, lat2, lng2);
  }

  /// Check if current time is night mode (10PM - 6AM)
  static bool isNightMode() {
    final hour = DateTime.now().hour;
    return hour >= AppConstants.nightStartHour ||
        hour < AppConstants.nightEndHour;
  }

  /// Dispose
  void dispose() {
    stopTracking();
  }
}
