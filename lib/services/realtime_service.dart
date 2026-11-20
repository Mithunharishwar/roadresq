import 'package:firebase_database/firebase_database.dart';

class RealtimeService {
  static final DatabaseReference db = FirebaseDatabase.instance.ref();

  static Future<void> createOrUpdateRequest(
    String requestId,
    Map<String, dynamic> data,
  ) async {
    await db.child('requests/$requestId').update(data);
  }

  static Stream<DatabaseEvent> listenToRequest(String requestId) {
    return db.child('requests/$requestId').onValue;
  }

  static Stream<DatabaseEvent> listenToAllRequests() {
    return db.child('requests').onValue;
  }

  static Future<void> updateStatus(String requestId, String status) async {
    await db.child('requests/$requestId').update({'status': status});
  }

  static Future<void> updateMechanicLocation(
    String requestId,
    double lat,
    double lng,
  ) async {
    await db.child('requests/$requestId').update({
      'mechanicLat': lat,
      'mechanicLng': lng,
    });
  }

  static Future<void> updateRequestData(
    String requestId,
    Map<String, dynamic> data,
  ) async {
    await db.child('requests/$requestId').update(data);
  }
}
