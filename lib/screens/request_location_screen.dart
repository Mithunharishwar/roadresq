import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';

import '../services/api_service.dart';
import '../core/config/api_keys.dart';
import '../core/request_status.dart';
import '../services/activity_service.dart';
import '../services/socket_service.dart';

class RequestLocationScreen extends StatefulWidget {
  final String requestId;
  final String customerName;
  final String customerPhone;
  final double lat;
  final double lng;
  final String issue;
  final String locationText;
  final String currentStatus;

  const RequestLocationScreen({
    super.key,
    required this.requestId,
    required this.customerName,
    required this.customerPhone,
    required this.lat,
    required this.lng,
    required this.issue,
    required this.locationText,
    required this.currentStatus,
  });

  @override
  State<RequestLocationScreen> createState() => _RequestLocationScreenState();
}

class _RequestLocationScreenState extends State<RequestLocationScreen> {
  GoogleMapController? mapController;
  LatLng? mechanicLocation;
  LatLng? previousLocation;

  StreamSubscription<Position>? positionStream;
  final SocketService socketService = SocketService();

  double distanceKm = 0;
  int etaMinutes = 0;

  bool isUpdatingStatus = false;
  bool isMapReady = false;
  late String currentStatus;

  Set<Polyline> polylines = {};
  List<LatLng> routePoints = [];

  /// Injected at build time — see core/config/api_keys.dart. Empty when the
  /// build supplied no key, in which case routing falls back to a straight line.
  final String googleApiKey = ApiKeys.googleMaps;

  @override
  void initState() {
    super.initState();
    currentStatus = normalizeStatus(widget.currentStatus);
    socketService.connect();
    startLiveTracking();
  }

  String normalizeStatus(String status) {
    return status
        .toLowerCase()
        .replaceAll('_', ' ')
        .split(' ')
        .map((e) => e.isEmpty ? e : e[0].toUpperCase() + e.substring(1))
        .join(' ');
  }

  /// Lifecycle helpers — see lib/core/request_status.dart.
  String backendStatus(String status) => RequestStatusInfo.apiValue(status);

  String? getNextStatus(String status) {
    final next = RequestStatusInfo.next(status);
    return next?.label;
  }

  String getNextButtonText(String status) =>
      RequestStatusInfo.nextActionLabel(status);

  Color getStatusColor(String status) => RequestStatusInfo.color(status);

  String getStatusSubtitle(String status) => RequestStatusInfo.description(status);

  Future<void> fetchRoute(LatLng origin, LatLng destination) async {
    try {
      if (googleApiKey.isEmpty) {
        if (!mounted) return;
        setState(() {
          polylines = {
            Polyline(
              polylineId: const PolylineId('route_fallback'),
              color: Colors.blue,
              width: 5,
              points: [origin, destination],
            ),
          };
        });
        return;
      }

      final polylinePoints = PolylinePoints();

      final result = await polylinePoints.getRouteBetweenCoordinates(
        googleApiKey: googleApiKey,
        request: PolylineRequest(
          origin: PointLatLng(origin.latitude, origin.longitude),
          destination: PointLatLng(destination.latitude, destination.longitude),
          mode: TravelMode.driving,
        ),
      );

      if (result.points.isNotEmpty) {
        routePoints.clear();

        for (final p in result.points) {
          routePoints.add(LatLng(p.latitude, p.longitude));
        }

        if (!mounted) return;

        setState(() {
          polylines = {
            Polyline(
              polylineId: const PolylineId('route'),
              color: Colors.blue,
              width: 6,
              points: routePoints,
            ),
          };
        });
      } else {
        if (!mounted) return;

        setState(() {
          polylines = {
            Polyline(
              polylineId: const PolylineId('route_fallback'),
              color: Colors.blue,
              width: 5,
              points: [origin, destination],
            ),
          };
        });
      }
    } catch (_) {
      if (!mounted) return;

      setState(() {
        polylines = {
          Polyline(
            polylineId: const PolylineId('route_fallback'),
            color: Colors.blue,
            width: 5,
            points: [origin, destination],
          ),
        };
      });
    }
  }

  Future<void> animateMarker(LatLng newLocation) async {
    if (mechanicLocation == null) {
      if (!mounted) return;
      setState(() {
        mechanicLocation = newLocation;
      });
      return;
    }

    const int steps = 10;
    final double startLat = mechanicLocation!.latitude;
    final double startLng = mechanicLocation!.longitude;
    final double latStep = (newLocation.latitude - startLat) / steps;
    final double lngStep = (newLocation.longitude - startLng) / steps;

    for (int i = 1; i <= steps; i++) {
      await Future.delayed(const Duration(milliseconds: 50));

      if (!mounted) return;

      setState(() {
        mechanicLocation = LatLng(
          startLat + (latStep * i),
          startLng + (lngStep * i),
        );
      });
    }
  }

  Future<void> updateCamera(LatLng newLoc) async {
    if (mapController == null || !isMapReady) return;

    final bearing = previousLocation != null
        ? Geolocator.bearingBetween(
            previousLocation!.latitude,
            previousLocation!.longitude,
            newLoc.latitude,
            newLoc.longitude,
          )
        : 0.0;

    await mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: newLoc, zoom: 16, tilt: 45, bearing: bearing),
      ),
    );
  }

  Future<void> startLiveTracking() async {
    final prefs = await SharedPreferences.getInstance();
    final mechanicId = prefs.getString('mechanicId') ?? '';

    if (mechanicId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Mechanic ID not found')));
      return;
    }

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enable location services')),
      );
      await Geolocator.openLocationSettings();
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location permission denied')),
      );
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keep GPS ON for live tracking')),
      );
    }

    positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 3,
        timeLimit: Duration(minutes: 2), // Add a timeout
      ),
    ).listen((Position position) async {
      try {
        final newLoc = LatLng(position.latitude, position.longitude);

        final meters = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          widget.lat,
          widget.lng,
        );

        final km = meters / 1000;
        final min = ((km / 30) * 60).ceil();

        previousLocation = mechanicLocation;

        await animateMarker(newLoc);

        if (!mounted) return;
        setState(() {
          distanceKm = km;
          etaMinutes = min;
        });

        await fetchRoute(newLoc, LatLng(widget.lat, widget.lng));

        await ApiService.updateMechanicLocation(
          mechanicId: mechanicId,
          lat: position.latitude,
          lng: position.longitude,
          requestId: widget.requestId,
        );

        await ApiService.updateRequestMechanicLocation(
          requestId: widget.requestId,
          mechanicId: mechanicId,
          lat: position.latitude,
          lng: position.longitude,
        );

        socketService.emit('mechanic_location_update', {
          'mechanicId': mechanicId,
          'requestId': widget.requestId,
          'lat': position.latitude,
          'lng': position.longitude,
        });

        await updateCamera(newLoc);
      } catch (e) {
        debugPrint('Tracking error: $e');
      }
    });
  }

  Future<void> handleStatusUpdate() async {
    final next = getNextStatus(currentStatus);
    if (next == null) return;

    try {
      setState(() => isUpdatingStatus = true);

      await ApiService.updateRequestStatus(
        requestId: widget.requestId,
        status: backendStatus(next),
      );

      await ActivityService.addMechanicActivity(
        'Status Updated',
        '${widget.customerName} → $next',
      );

      if (!mounted) return;

      setState(() {
        currentStatus = next;
        isUpdatingStatus = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Status updated to $next')));
    } catch (e) {
      if (!mounted) return;

      setState(() => isUpdatingStatus = false);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update status: $e')));
    }
  }

  Future<void> callCustomer() async {
    final url = Uri.parse('tel:${widget.customerPhone}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  Future<void> openNavigation() async {
    final url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${widget.lat},${widget.lng}&travelmode=driving',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  Widget buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF0D47A1)),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 14, color: Colors.black87),
              children: [
                TextSpan(
                  text: label,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget statCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    positionStream?.cancel();
    // This screen only emits (`mechanic_location_update`) and registers no
    // listeners, so there is nothing to unsubscribe. It used to call the
    // app-wide clearAllListeners() here, which unsubscribed every OTHER open
    // screen — that is why live updates died when navigating away from here.
    mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customerLocation = LatLng(widget.lat, widget.lng);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: customerLocation,
              zoom: 14,
            ),
            onMapCreated: (c) {
              mapController = c;
              isMapReady = true;
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            markers: {
              Marker(
                markerId: const MarkerId('customer'),
                position: customerLocation,
                infoWindow: const InfoWindow(title: 'Customer Location'),
              ),
              if (mechanicLocation != null)
                Marker(
                  markerId: const MarkerId('mechanic'),
                  position: mechanicLocation!,
                  infoWindow: const InfoWindow(title: 'Your Live Location'),
                  rotation: previousLocation != null
                      ? Geolocator.bearingBetween(
                          previousLocation!.latitude,
                          previousLocation!.longitude,
                          mechanicLocation!.latitude,
                          mechanicLocation!.longitude,
                        )
                      : 0,
                  anchor: const Offset(0.5, 0.5),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueBlue,
                  ),
                ),
            },
            polylines: polylines,
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Row(
                    children: [
                      InkWell(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: const [
                              BoxShadow(color: Colors.black12, blurRadius: 10),
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
                            color: getStatusColor(currentStatus),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: const [
                              BoxShadow(color: Colors.black12, blurRadius: 10),
                            ],
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.route, color: Colors.white),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  currentStatus,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              Text(
                                etaMinutes > 0 ? '$etaMinutes min' : '--',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF7F9FC),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(30),
                    ),
                    boxShadow: [
                      BoxShadow(color: Colors.black12, blurRadius: 18),
                    ],
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 42,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
                            ),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.customerName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 23,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                getStatusSubtitle(currentStatus),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            statCard(
                              icon: Icons.access_time,
                              title: 'ETA',
                              value: '$etaMinutes min',
                              color: const Color(0xFF0D47A1),
                            ),
                            const SizedBox(width: 10),
                            statCard(
                              icon: Icons.route,
                              title: 'Distance',
                              value: '${distanceKm.toStringAsFixed(2)} km',
                              color: Colors.green,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black
                                    .withAlpha((0.05 * 255).round()),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Customer Details',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              buildInfoRow(
                                Icons.report_problem_outlined,
                                'Issue: ',
                                widget.issue,
                              ),
                              const SizedBox(height: 8),
                              buildInfoRow(
                                Icons.location_on_outlined,
                                'Location: ',
                                widget.locationText,
                              ),
                              const SizedBox(height: 8),
                              buildInfoRow(
                                Icons.phone_outlined,
                                'Phone: ',
                                widget.customerPhone,
                              ),
                              const SizedBox(height: 8),
                              buildInfoRow(
                                Icons.circle,
                                'Status: ',
                                currentStatus,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: callCustomer,
                                icon: const Icon(Icons.call),
                                label: const Text('Call'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: openNavigation,
                                icon: const Icon(Icons.navigation),
                                label: const Text('Navigate'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed:
                                isUpdatingStatus || currentStatus == 'Completed'
                                    ? null
                                    : handleStatusUpdate,
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 52),
                              backgroundColor: const Color(0xFF0D47A1),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: isUpdatingStatus
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(getNextButtonText(currentStatus)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
