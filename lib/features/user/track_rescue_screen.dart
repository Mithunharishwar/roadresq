// FILE: lib/features/user/track_rescue_screen.dart
/// TrackRescueScreen — Live rescue tracking for a user (Image2 fix).
///
/// Uses StreamBuilder on `jobs/{jobId}` to subscribe to real-time updates.
/// This eliminates the old manual timer + HTTP polling that caused the
/// "Track Rescue Timeout Error".
///
/// States handled:
///   - loading   → CircularProgressIndicator
///   - error     → "Check internet" message
///   - null doc  → "No active rescue" message
///   - data      → live status card + map marker
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class TrackRescueScreen extends StatefulWidget {
  final String jobId;
  const TrackRescueScreen({super.key, required this.jobId});

  @override
  State<TrackRescueScreen> createState() => _TrackRescueScreenState();
}

class _TrackRescueScreenState extends State<TrackRescueScreen> {
  static const Color _red = Color(0xFFD32F2F);

  /// Stream of the rescue job document. StreamBuilder subscribes live →
  /// no manual timers, no timeout errors.
  Stream<DocumentSnapshot<Map<String, dynamic>>> _jobStream() {
    return FirebaseFirestore.instance
        .collection('jobs')
        .doc(widget.jobId)
        .snapshots();
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'pending':
        return 'Searching for a mechanic…';
      case 'assigned':
        return 'Mechanic assigned — on the way!';
      case 'active':
      case 'on_the_way':
        return 'Mechanic is on the way to you';
      case 'reached':
        return 'Mechanic has reached your location';
      case 'completed':
        return 'Rescue completed successfully';
      case 'cancelled':
        return 'Rescue was cancelled';
      default:
        return 'Tracking your rescue…';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _jobStream(),
        builder: (context, snapshot) {
          // Loading state.
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // Error state → "Check internet".
          if (snapshot.hasError) {
            return _messageState(
              icon: Icons.wifi_off,
              title: 'Check internet',
              subtitle: 'We could not reach the server. Please retry.',
            );
          }

          // No active rescue (null or missing doc).
          final doc = snapshot.data;
          if (doc == null || !doc.exists) {
            return _messageState(
              icon: Icons.radar,
              title: 'No active rescue',
              subtitle: 'There is no rescue request with that ID.',
            );
          }

          // Live job data.
          final data = doc.data() ?? {};
          final status = data['status']?.toString();
          final pickup = data['pickupLocation'] as GeoPoint?;
          final mechanicName =
              data['assignedMechanicName']?.toString() ?? 'Mechanic';
          final eta = data['etaMinutes'] as num?;

          return Column(
            children: [
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      InkWell(
                        onTap: () => context.go('/user-home'),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.arrow_back),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: _red,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.car_repair,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _statusLabel(status),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              if (eta != null)
                                Text(
                                  '${eta.round()} min',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    // Map showing the pickup location.
                    if (pickup != null)
                      GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: LatLng(pickup.latitude, pickup.longitude),
                          zoom: 14,
                        ),
                        markers: {
                          Marker(
                            markerId: const MarkerId('pickup'),
                            position: LatLng(
                              pickup.latitude,
                              pickup.longitude,
                            ),
                            infoWindow: const InfoWindow(
                              title: 'Your Location',
                            ),
                          ),
                        },
                        myLocationEnabled: true,
                        zoomControlsEnabled: false,
                      )
                    else
                      const Center(
                        child: Text('Location not available'),
                      ),
                    // Live status card.
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 14,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            const CircleAvatar(
                              radius: 26,
                              backgroundColor: _red,
                              child: Icon(
                                Icons.person,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    mechanicName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    data['userName']?.toString() ?? 'Customer',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (status == 'completed')
                              const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                                size: 30,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _messageState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: _red),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => context.go('/user-home'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Go to Home'),
            ),
          ],
        ),
      ),
    );
  }
}
