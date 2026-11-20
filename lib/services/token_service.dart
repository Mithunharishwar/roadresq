import 'package:firebase_database/firebase_database.dart';
import 'package:uuid/uuid.dart';

/// TokenService
/// - Generates unique digital tokens for vehicles dropped at hubs
/// - Stores tokens under `tokens/{tokenId}` in Firebase Realtime Database
/// - Exposes methods to generate, stream and release tokens
class TokenService {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  final Uuid _uuid = const Uuid();

  /// Create a new token and store it in Firebase.
  /// Returns the tokenId.
  Future<String> generateToken({
    required String vehicleId,
    required String userId,
    String? jobId,
    String? hubId,
  }) async {
    final tokenId = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();

    final tokenData = {
      'tokenId': tokenId,
      'vehicleId': vehicleId,
      'userId': userId,
      'jobId': jobId ?? '',
      'hubId': hubId ?? '',
      'status': 'created', // created -> in_transit -> at_hub -> released
      'createdAt': now,
      'updatedAt': now,
    };

    await _db.child('tokens/$tokenId').set(tokenData);
    return tokenId;
  }

  /// Returns a stream of token changes (useful for UI tracking).
  Stream<DatabaseEvent> streamToken(String tokenId) {
    return _db.child('tokens/$tokenId').onValue;
  }

  /// Read the latest snapshot for a token (one-time).
  Future<DataSnapshot> getTokenSnapshot(String tokenId) {
    return _db.child('tokens/$tokenId').get();
  }

  /// Update token status and timestamp.
  Future<void> updateTokenStatus(String tokenId, String status,
      {Map<String, dynamic>? extra}) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final update = <String, dynamic>{
      'status': status,
      'updatedAt': now,
    };
    if (extra != null) update.addAll(extra);
    await _db.child('tokens/$tokenId').update(update);
  }

  /// Release a token when vehicle & job are complete and customer acknowledged.
  Future<void> releaseToken(String tokenId, {String? releasedBy}) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.child('tokens/$tokenId').update({
      'status': 'released',
      'releasedBy': releasedBy ?? '',
      'releasedAt': now,
      'updatedAt': now,
    });
  }
}
