import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';

import '../services/api_service.dart';
import '../services/live_tracking_service.dart';
import '../services/socket_service.dart';
import '../core/config/api_keys.dart';
import '../core/request_status.dart';
import '../core/session/app_session.dart';
import 'payment_screen.dart';
import 'rating_screen.dart';

class UserTrackingScreen extends StatefulWidget {
  final double userLat;
  final double userLng;
  final String requestId;

  const UserTrackingScreen({
    super.key,
    required this.userLat,
    required this.userLng,
    required this.requestId,
  });

  @override
  State<UserTrackingScreen> createState() => _UserTrackingScreenState();
}

class _UserTrackingScreenState extends State<UserTrackingScreen> {
  GoogleMapController? mapController;
  final SocketService socketService = SocketService();
  final LiveTrackingService liveTracking = LiveTrackingService();
  StreamSubscription<LiveTrackingUpdate>? _trackingSub;

  /// Handles for this screen's socket listeners, cancelled in dispose().
  final List<SocketSubscription> _socketSubs = <SocketSubscription>[];

  LatLng? mechanicLocation;
  LatLng? previousLocation;
  LatLng? assistantLocation;

  double? distanceKm;
  int? etaMinutes;
  double? assistantDistanceKm;
  int? assistantEtaMinutes;

  String status = 'Pending';

  /// Name of the mechanic who owns the job, for the rating screen. Read from
  /// the request record; empty until the job is assigned.
  String mechanicName = '';
  bool paymentDone = false;

  Set<Polyline> polylines = {};
  List<LatLng> routePoints = [];

  /// Injected at build time — see core/config/api_keys.dart. Empty when the
  /// build supplied no key, in which case routing falls back to a straight line.
  final String googleApiKey = ApiKeys.googleMaps;

  @override
  void initState() {
    super.initState();
    socketService.connect();
    _setupSocketListeners();
    _setupLiveTracking();
    _loadInitialRequestState();
  }

  /// Feature 1: Battery-safe live tracking via LiveTrackingService.
  /// Socket primary + Firestore onSnapshot (5s) fallback. Only streams
  /// while the job is "active" — stops on pending/completed/cancelled.
  void _setupLiveTracking() {
    _trackingSub = liveTracking.updates.listen((update) {
      if (update.requestId != widget.requestId) return;
      if (!mounted) return;

      setState(() {
        status = update.status;
      });

      if (update.mechanic != null) {
        final newLoc = LatLng(update.mechanic!.lat, update.mechanic!.lng);
        previousLocation = mechanicLocation;
        _animateMarker(newLoc);
        _updateDistanceEtaRoute(newLoc);
        _updateCamera(newLoc);
      }

      if (update.assistant != null) {
        assistantLocation =
            LatLng(update.assistant!.lat, update.assistant!.lng);
        _recalculateAssistantEta();
      }
    });

    // Start streaming (only when job is active).
    liveTracking.startTracking(requestId: widget.requestId);
  }

  Future<void> _loadInitialRequestState() async {
    try {
      final data = await ApiService.fetchRequestById(widget.requestId);
      if (!mounted) return;

      final rawStatus = (data['status'] ?? 'Pending').toString();
      final mech = data['mechanicLocation'];
      final asst = data['assistantLocation'];
      final paymentStatus =
          data['paymentStatus']?.toString().toLowerCase() ?? '';

      final assignedMechanic = (data['mechanicName'] ?? '').toString();

      setState(() {
        status = rawStatus;
        paymentDone = paymentStatus == 'success';
        if (assignedMechanic.isNotEmpty) mechanicName = assignedMechanic;
      });

      if (mech != null && mech['lat'] != null && mech['lng'] != null) {
        final newLoc = LatLng(
          (mech['lat'] as num).toDouble(),
          (mech['lng'] as num).toDouble(),
        );
        mechanicLocation = newLoc;
        await _updateDistanceEtaRoute(newLoc);
        _updateCamera(newLoc);
      }

      if (asst != null && asst['lat'] != null && asst['lng'] != null) {
        setState(() {
          assistantLocation = LatLng(
            (asst['lat'] as num).toDouble(),
            (asst['lng'] as num).toDouble(),
          );
        });
        _recalculateAssistantEta();
      }
    } catch (e) {
      debugPrint('Initial tracking load error: $e');
    }
  }

  void _setupSocketListeners() {
    _socketSubs.add(socketService.onRequestAssigned((data) async {
      final reqId = (data['requestId'] ?? '').toString();
      if (reqId != widget.requestId) return;
      if (!mounted) return;
      setState(() => status = (data['status'] ?? 'Assigned').toString());
    }));

    _socketSubs.add(socketService.onStatusUpdated((data) async {
      final reqId = (data['requestId'] ?? '').toString();
      if (reqId != widget.requestId) return;
      if (!mounted) return;
      setState(() => status = (data['status'] ?? 'Pending').toString());
    }));

    _socketSubs.add(socketService.onPaymentUpdated((data) async {
      final reqId = (data['requestId'] ?? '').toString();
      if (reqId != widget.requestId) return;
      if (!mounted) return;
      final ps = (data['paymentStatus'] ?? '').toString().toLowerCase();
      if (ps == 'success') setState(() => paymentDone = true);
    }));

    _socketSubs.add(socketService.onMechanicLocationUpdated((data) async {
      final reqId = (data['requestId'] ?? '').toString();
      if (reqId != widget.requestId) return;
      if (data['lat'] == null || data['lng'] == null) return;

      final newLoc = LatLng(
        (data['lat'] as num).toDouble(),
        (data['lng'] as num).toDouble(),
      );
      previousLocation = mechanicLocation;
      await _animateMarker(newLoc);
      await _updateDistanceEtaRoute(newLoc);
      _updateCamera(newLoc);
    }));

    _socketSubs.add(socketService.onAssistantLocationUpdated((data) {
      final reqId = (data['requestId'] ?? '').toString();
      if (reqId != widget.requestId) return;
      if (data['lat'] == null || data['lng'] == null) return;

      final newLoc = LatLng(
        (data['lat'] as num).toDouble(),
        (data['lng'] as num).toDouble(),
      );
      if (!mounted) return;
      setState(() => assistantLocation = newLoc);
      _recalculateAssistantEta();
    }));

    _socketSubs.add(socketService.onAssistantAssigned((data) {
      final reqId = (data['requestId'] ?? '').toString();
      if (reqId == widget.requestId && mounted) {
        _loadInitialRequestState();
      }
    }));
  }

  void _recalculateAssistantEta() {
    if (assistantLocation == null) return;
    final meters = Geolocator.distanceBetween(
      widget.userLat,
      widget.userLng,
      assistantLocation!.latitude,
      assistantLocation!.longitude,
    );
    final km = meters / 1000;
    final min = ((km / 50) * 60).ceil();
    if (!mounted) return;
    setState(() {
      assistantDistanceKm = km;
      assistantEtaMinutes = min;
    });
  }

  Future<void> _updateDistanceEtaRoute(LatLng newLoc) async {
    final meters = Geolocator.distanceBetween(
      widget.userLat,
      widget.userLng,
      newLoc.latitude,
      newLoc.longitude,
    );
    final km = meters / 1000;
    final min = ((km / 30) * 60).ceil();

    if (!mounted) return;
    setState(() {
      distanceKm = km;
      etaMinutes = min;
    });
    await _fetchRoute(newLoc, LatLng(widget.userLat, widget.userLng));
  }

  Future<void> _fetchRoute(LatLng origin, LatLng destination) async {
    if (googleApiKey.isEmpty) {
      // No key configured for this build: draw the direct line instead of
      // issuing a Directions request that would be rejected.
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

    try {
      final polylinePoints = PolylinePoints();
      final result = await polylinePoints.getRouteBetweenCoordinates(
        googleApiKey: googleApiKey,
        request: PolylineRequest(
          origin: PointLatLng(origin.latitude, origin.longitude),
          destination: PointLatLng(destination.latitude, destination.longitude),
          mode: TravelMode.driving,
        ),
      );
      if (!mounted) return;

      if (result.points.isNotEmpty) {
        routePoints.clear();
        for (final p in result.points) {
          routePoints.add(LatLng(p.latitude, p.longitude));
        }
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
    } catch (e) {
      debugPrint('Polyline error: $e');
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

  Future<void> _animateMarker(LatLng newLocation) async {
    if (mechanicLocation == null) {
      if (!mounted) return;
      setState(() => mechanicLocation = newLocation);
      return;
    }
    const int steps = 10;
    final startLat = mechanicLocation!.latitude;
    final startLng = mechanicLocation!.longitude;
    final latStep = (newLocation.latitude - startLat) / steps;
    final lngStep = (newLocation.longitude - startLng) / steps;

    for (int i = 1; i <= steps; i++) {
      await Future.delayed(const Duration(milliseconds: 50));
      if (!mounted) return;
      setState(() {
        mechanicLocation =
            LatLng(startLat + (latStep * i), startLng + (lngStep * i));
      });
    }
  }

  void _updateCamera(LatLng loc) {
    if (mapController == null) return;
    mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: loc,
          zoom: 16,
          tilt: 45,
          bearing: previousLocation != null
              ? Geolocator.bearingBetween(
                  previousLocation!.latitude,
                  previousLocation!.longitude,
                  loc.latitude,
                  loc.longitude,
                )
              : 0,
        ),
      ),
    );
  }

  String displayStatus() => RequestStatusInfo.label(status);

  Color getStatusColor() => RequestStatusInfo.color(status);

  Widget statCard(String title, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Text(value,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Text(title, style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _trackingSub?.cancel();
    liveTracking.stopTracking();
    // Remove only THIS screen's listeners, not every screen's.
    for (final sub in _socketSubs) {
      sub.cancel();
    }
    _socketSubs.clear();
    mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userLoc = LatLng(widget.userLat, widget.userLng);
    const int total = 499;

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: userLoc, zoom: 14),
            onMapCreated: (c) => mapController = c,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            markers: {
              Marker(
                markerId: const MarkerId('user'),
                position: userLoc,
                infoWindow: const InfoWindow(title: 'Your Location'),
              ),
              if (mechanicLocation != null)
                Marker(
                  markerId: const MarkerId('mechanic'),
                  position: mechanicLocation!,
                  infoWindow: const InfoWindow(title: 'Mechanic'),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueBlue),
                ),
              if (assistantLocation != null)
                Marker(
                  markerId: const MarkerId('assistant'),
                  position: assistantLocation!,
                  infoWindow: const InfoWindow(title: 'Assistant/Rider'),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueGreen),
                ),
            },
            polylines: polylines,
          ),
          Positioned(
            top: 50,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: getStatusColor(),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.car_repair, color: Colors.white),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(displayStatus(),
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  if (etaMinutes != null)
                    Text('$etaMinutes min',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          Positioned(
            top: 50,
            left: 16,
            child: SafeArea(
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.arrow_back, color: Colors.black),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 16)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const CircleAvatar(
                        radius: 24,
                        backgroundColor: Color(0xFFD32F2F),
                        child: Icon(Icons.person, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          mechanicLocation != null
                              ? 'Mechanic On The Way'
                              : 'Searching for mechanic...',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (assistantEtaMinutes != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('Rider: ${assistantEtaMinutes}min',
                              style: const TextStyle(
                                  color: Colors.green, fontSize: 12)),
                        ),
                    ],
                  ),
                  if (assistantLocation != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.directions_bike,
                            size: 16, color: Colors.green),
                        const SizedBox(width: 6),
                        Text(
                          'Assistant/Rider is also on the way — arrives in ${assistantEtaMinutes ?? "--"} min',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      statCard(
                          'ETA', etaMinutes != null ? '$etaMinutes min' : '--'),
                      const SizedBox(width: 10),
                      statCard(
                          'Distance',
                          distanceKm != null
                              ? '${distanceKm!.toStringAsFixed(1)} km'
                              : '--'),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: paymentDone
                          ? null
                          : () async {
                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PaymentScreen(
                                    requestId: widget.requestId,
                                    // The signed-in customer, not a demo name:
                                    // this is what the payment receipt carries.
                                    userName: (AppSession.name ?? '').isEmpty
                                        ? 'RoadResQ customer'
                                        : AppSession.name!,
                                    userPhone: AppSession.phone ?? '',
                                    userEmail: AppSession.email ?? '',
                                    amount: total,
                                  ),
                                ),
                              );
                              if (result != null &&
                                  result["status"] == "success" &&
                                  mounted) {
                                setState(() => paymentDone = true);
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            paymentDone ? Colors.grey : const Color(0xFF0D47A1),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        paymentDone ? 'Payment Completed' : 'Pay ₹$total',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  // The workflow used to stop at "paid": nothing in the app
                  // opened the rating screen, so the mechanic's rating could
                  // never be earned from a real job.
                  if (paymentDone) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final rated = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RatingScreen(
                                requestId: widget.requestId,
                                mechanicName: mechanicName,
                              ),
                            ),
                          );
                          if (rated == true && mounted) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Thanks for rating your mechanic.'),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.star_border),
                        label: const Text('Rate your mechanic'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
