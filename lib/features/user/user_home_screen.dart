// FILE: lib/features/user/user_home_screen.dart
/// UserHomeScreen — The user's main dashboard (Image1 reference).
///
/// Layout:
///   - Full-screen GoogleMap showing the user's live location.
///   - Top Red banner (#D32F2F) with user name + lat/lng coordinates.
///   - DraggableScrollableSheet at the bottom with a "Request Rescue" button.
///
/// Uses StreamBuilder on `users/{uid}` (Firestore) to display the name (no
/// manual timers → no timeout errors).
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen> {
  GoogleMapController? _mapController;
  LatLng? _currentLatLng;
  bool _locating = false;

  /// Initial camera position (falls back to Chennai on web where geolocation
  /// may be denied, so the map still renders instead of timing out).
  static const CameraPosition _initialCamera = CameraPosition(
    target: LatLng(13.0827, 80.2707),
    zoom: 13,
  );

  @override
  void initState() {
    super.initState();
    _locateUser();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  /// Attempt to fetch the device's current location. Never throws to the UI —
  /// it updates state so the map/coords either reflect live data or fall back.
  Future<void> _locateUser() async {
    setState(() => _locating = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // Location unavailable — keep the initial camera; show fallback banner.
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (!mounted) return;

      final latLng = LatLng(position.latitude, position.longitude);
      setState(() => _currentLatLng = latLng);
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
            CameraPosition(target: latLng, zoom: 15)),
      );
    } catch (_) {
      // Ignore — user can still use the app; no timeout crash.
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// Creates a rescue job and navigates to the tracking screen.
  Future<void> _requestRescue() async {
    final loc = _currentLatLng ?? const LatLng(13.0827, 80.2707);
    if (_locating) return;
    final user = FirebaseAuth.instance.currentUser;
    final eventId = DateTime.now().millisecondsSinceEpoch.toString();

    try {
      final jobRef = FirebaseFirestore.instance.collection('jobs').doc(eventId);
      await jobRef.set({
        'requestId': eventId,
        'userId': user?.uid ?? '',
        'userName': user?.displayName ?? 'User',
        'userPhone': user?.phoneNumber ?? '',
        'pickupLocation': GeoPoint(loc.latitude, loc.longitude),
        'issueType': 'Roadside Assistance',
        'vehicleType': '',
        'status': 'pending',
        'cancelledBy': null,
        'cancellationReason': null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      // Route to the live tracker (StreamBuilder based → no timeout).
      context.go('/track-rescue/$eventId');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create rescue request: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ─── Full-screen Google Map background ───
          GoogleMap(
            initialCameraPosition: _initialCamera,
            onMapCreated: (controller) => _mapController = controller,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            markers: {
              if (_currentLatLng != null)
                Marker(
                  markerId: const MarkerId('user'),
                  position: _currentLatLng!,
                  infoWindow: const InfoWindow(title: 'You are here'),
                ),
            },
          ),

          // ─── Top Red Banner (Image1) ───
          SafeArea(
            child: Column(
              children: [
                // Red banner with name + lat/lng.
                StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(FirebaseAuth.instance.currentUser?.uid ?? 'unknown')
                      .snapshots(),
                  builder: (context, snapshot) {
                    String name = 'User';
                    if (snapshot.hasData && snapshot.data!.exists) {
                      final data =
                          snapshot.data!.data() as Map<String, dynamic>;
                      name = data['name']?.toString() ??
                          data['phone']?.toString() ??
                          'User';
                    }
                    return _buildTopBanner(name);
                  },
                ),
                const Spacer(),
              ],
            ),
          ),

          // ─── Bottom DraggableScrollableSheet with Request Rescue ───
          DraggableScrollableSheet(
            initialChildSize: 0.24,
            minChildSize: 0.14,
            maxChildSize: 0.45,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 18)],
                ),
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Need help on the road?',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _currentLatLng != null
                          ? 'Lat: ${_currentLatLng!.latitude.toStringAsFixed(5)}  •  Lng: ${_currentLatLng!.longitude.toStringAsFixed(5)}'
                          : 'Fetching your location…',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Request Rescue button (Red).
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: _locating ? null : _requestRescue,
                        icon: const Icon(Icons.emergency),
                        label: const Text('Request Rescue'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD32F2F),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTopBanner(String userName) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFD32F2F), Color(0xFFFF7043)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
              color: Colors.black26, blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 22,
            backgroundColor: Colors.white,
            child: Icon(Icons.person, color: Color(0xFFD32F2F)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hi, $userName',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  _currentLatLng != null
                      ? '${_currentLatLng!.latitude.toStringAsFixed(5)}, ${_currentLatLng!.longitude.toStringAsFixed(5)}'
                      : 'Getting Live Coordinates…',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
