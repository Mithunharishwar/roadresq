import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen> {
  static const LatLng _fallbackLocation = LatLng(13.0827, 80.2707);
  static const Color _rescueRed = Color(0xFFD32F2F);

  GoogleMapController? _mapController;
  LatLng? _currentLocation;
  String? _locationError;
  bool _isLocating = false;
  bool _isRequesting = false;

  @override
  void initState() {
    super.initState();
    _refreshLocation();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  String get _locationLabel {
    final location = _currentLocation;
    if (_isLocating) {
      return 'Finding your current location…';
    }
    if (location == null) {
      return _locationError ?? 'Location is required to request rescue.';
    }
    return '${location.latitude.toStringAsFixed(5)}, '
        '${location.longitude.toStringAsFixed(5)}';
  }

  Future<LatLng?> _refreshLocation() async {
    if (_isLocating) {
      return _currentLocation;
    }

    if (mounted) {
      setState(() {
        _isLocating = true;
        _locationError = null;
      });
    }

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _setLocationError('Turn on location services to continue.');
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        _setLocationError('Location permission was denied.');
        return null;
      }
      if (permission == LocationPermission.deniedForever) {
        _setLocationError(
          'Location permission is permanently denied in settings.',
        );
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final location = LatLng(position.latitude, position.longitude);
      if (!mounted) {
        return location;
      }

      setState(() {
        _currentLocation = location;
        _locationError = null;
      });
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: location, zoom: 16),
        ),
      );
      return location;
    } catch (_) {
      _setLocationError('Unable to get your current location.');
      return null;
    } finally {
      if (mounted) {
        setState(() => _isLocating = false);
      }
    }
  }

  void _setLocationError(String message) {
    if (mounted) {
      setState(() => _locationError = message);
    }
  }

  Future<void> _requestRescue() async {
    if (_isRequesting) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showMessage('Please sign in before requesting rescue.');
      return;
    }

    setState(() => _isRequesting = true);
    try {
      final location = _currentLocation ?? await _refreshLocation();
      if (location == null) {
        _showMessage('Current location is needed to request rescue.');
        return;
      }

      final job = await FirebaseFirestore.instance.collection('jobs').add({
        'userId': user.uid,
        'mechanicId': null,
        'lat': location.latitude,
        'lng': location.longitude,
        'status': 'pending',
        'token': null,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) {
        return;
      }
      context.go('/track-rescue/${job.id}');
    } on FirebaseException catch (error) {
      _showMessage(error.message ?? 'Could not create the rescue request.');
    } catch (_) {
      _showMessage('Could not create the rescue request. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isRequesting = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _rescueRed,
        content: Text(
          message,
          style: const TextStyle(inherit: true, color: Colors.white),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentLocation = _currentLocation;
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: _fallbackLocation,
              zoom: 13,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
              if (_currentLocation != null) {
                controller.animateCamera(
                  CameraUpdate.newLatLngZoom(_currentLocation!, 16),
                );
              }
            },
            myLocationEnabled: currentLocation != null,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            markers: currentLocation == null
                ? const <Marker>{}
                : {
                    Marker(
                      markerId: const MarkerId('user-location'),
                      position: currentLocation,
                      infoWindow: const InfoWindow(
                        title: 'Your current location',
                      ),
                    ),
                  },
          ),
          Align(
            alignment: Alignment.topCenter,
            child: _buildLocationBanner(),
          ),
          _buildRescueSheet(),
        ],
      ),
    );
  }

  Widget _buildLocationBanner() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: _rescueRed,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 14,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.location_on, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'RoadResQ Rescue',
                      style: TextStyle(
                        inherit: true,
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _locationLabel,
                      style: const TextStyle(
                        inherit: true,
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _isLocating ? null : _refreshLocation,
                tooltip: 'Refresh location',
                icon: const Icon(Icons.refresh, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRescueSheet() {
    return DraggableScrollableSheet(
      initialChildSize: 0.27,
      minChildSize: 0.20,
      maxChildSize: 0.50,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 18,
                offset: Offset(0, -3),
              ),
            ],
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.fromLTRB(
              24,
              12,
              24,
              MediaQuery.of(context).padding.bottom + 24,
            ),
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Need roadside assistance?',
                style: TextStyle(
                  inherit: true,
                  color: Color(0xFF1D1D1D),
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'We’ll connect you with the nearest available mechanic.',
                style: TextStyle(
                  inherit: true,
                  color: Color(0xFF616161),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  onPressed:
                      _isRequesting || _isLocating ? null : _requestRescue,
                  icon: _isRequesting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.emergency),
                  label: Text(
                    _isRequesting ? 'Creating request…' : 'Request Rescue',
                    style: const TextStyle(
                      inherit: true,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _rescueRed,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFEF9A9A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
