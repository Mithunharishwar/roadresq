// FILE: lib/services/core_util_service.dart
/// CoreUtilService — Utility Module.
///
/// Implements the spec functions:
///   - calculateDistance(lat1, lng1, lat2, lng2) → Haversine (km)
///   - encodeGeohash(lat, lng)                 → for location queries
///   - uploadToStorage(file)                   → for photos, docs
///   - socketConnect() / socketEmitLocation() / socketDisconnect()
library;

import 'dart:math';
import '../core/utils/geohash.dart';
import 'socket_service.dart';
import 'storage_service.dart';

class CoreUtilService {
  CoreUtilService._internal();
  static final CoreUtilService _instance = CoreUtilService._internal();
  factory CoreUtilService() => _instance;

  final SocketService _socket = SocketService();
  final StorageService _storage = StorageService();

  /// calculateDistance — Haversine distance in km.
  static double calculateDistance(
      double lat1, double lng1, double lat2, double lng2) {
    const R = 6371.0; // Earth radius in km
    final dLat = _degToRad(lat2 - lat1);
    final dLng = _degToRad(lng2 - lng1);
    final a = pow(sin(dLat / 2), 2) +
        cos(_degToRad(lat1)) * cos(_degToRad(lat2)) * pow(sin(dLng / 2), 2);
    return 2 * R * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _degToRad(double deg) => deg * pi / 180.0;

  /// encodeGeohash — geohash string for location queries.
  static String encodeGeohash(double lat, double lng, {int precision = 7}) {
    return Geohash.encode(latitude: lat, longitude: lng, precision: precision);
  }

  /// uploadToStorage(file) — upload a file to Firebase Storage.
  Future<String?> uploadToStorage({
    required String filePath,
    String storagePath = 'uploads',
    String? fileName,
  }) {
    return _storage.uploadFile(
      filePath: filePath,
      storagePath: storagePath,
      fileName: fileName,
    );
  }

  /// socketConnect() — connect the realtime socket.
  void socketConnect() => _socket.connect();

  /// socketEmitLocation() — emit the crew's current GPS via socket.
  void socketEmitLocation({
    required String jobId,
    required double lat,
    required double lng,
    String crewId = '',
  }) {
    _socket.connect();
    _socket.emit('update_location', {
      'jobId': jobId,
      'crewId': crewId,
      'lat': lat,
      'lng': lng,
    });
  }

  /// socketDisconnect() — disconnect the realtime socket.
  void socketDisconnect() => _socket.disconnect();

  /// Check whether the socket is currently connected.
  bool get isSocketConnected => _socket.isConnected;
}
