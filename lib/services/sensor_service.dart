import 'package:sensors_plus/sensors_plus.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';
import 'dart:math';

class SensorService {
  StreamSubscription? _accelSub;
  final List<double> _buffer = [];
  final dbRef = FirebaseDatabase.instance.ref();
  Function(double)? onScoreUpdate;

  double _calculateAnomaly(List<double> data) {
    if (data.length < 50) return 0.0;
    double mean = data.reduce((a, b) => a + b) / data.length;
    double variance =
        data.map((x) => pow(x - mean, 2)).reduce((a, b) => a + b) / data.length;
    double score = (variance / 8).clamp(0.0, 1.0);
    return score;
  }

  void startMonitoring(String userId) {
    _buffer.clear();
    _accelSub = accelerometerEventStream().listen((event) {
      double magnitude = sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );
      _buffer.add(magnitude);
      if (_buffer.length > 100) _buffer.removeAt(0);

      double score = _calculateAnomaly(_buffer);
      onScoreUpdate?.call(score);

      if (_buffer.length % 30 == 0) {
        // Firebase Realtime Database paths cannot include '.' '#' '$' '[' ']'
        final safeUserId = userId
            .replaceAll('.', '_')
            .replaceAll('#', '_')
            .replaceAll(r'$', '_')
            .replaceAll('[', '_')
            .replaceAll(']', '_');

        dbRef.child('sensor_logs/$safeUserId').push().set({
          'timestamp': ServerValue.timestamp,
          'score': score,
          'magnitude': magnitude,
        });
      }
    });
  }

  void stopMonitoring() {
    _accelSub?.cancel();
    _accelSub = null;
  }
}
