import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_database/firebase_database.dart';

/// HubMapScreen
/// - Shows RoadResQ hubs from Firebase and allows tapping markers for details
class HubMapScreen extends StatefulWidget {
  const HubMapScreen({super.key});

  @override
  State<HubMapScreen> createState() => _HubMapScreenState();
}

class _HubMapScreenState extends State<HubMapScreen> {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  final Map<String, Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _db.child('hubs').onValue.listen((ev) {
      final m = <String, Marker>{};
      if (ev.snapshot.exists) {
        final val = Map<String, dynamic>.from(ev.snapshot.value as Map);
        val.forEach((key, v) {
          final hub = Map<String, dynamic>.from(v as Map);
          final loc = hub['location'] as Map<dynamic, dynamic>?;
          if (loc == null) return;
          final lat = (loc['lat'] as num).toDouble();
          final lng = (loc['lng'] as num).toDouble();
          m[key] = Marker(
            markerId: MarkerId(key),
            position: LatLng(lat, lng),
            infoWindow: InfoWindow(
                title: hub['name'] ?? key,
                snippet: 'Bays: ${hub['availableBays'] ?? '-'}'),
          );
        });
      }
      if (mounted) {
        setState(() {
          _markers
            ..clear()
            ..addAll(m);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final initial = LatLng(13.0827, 80.2707);
    return Scaffold(
      appBar: AppBar(title: const Text('Hubs Map')),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(target: initial, zoom: 12),
        markers: _markers.values.toSet(),
      ),
    );
  }
}
