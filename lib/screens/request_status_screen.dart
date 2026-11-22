// IMPORTANT: Set Firestore Rules to allow read/write for testing
import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../core/session/app_session.dart';
import '../core/utils/firestore_failure.dart';
import '../services/api_service.dart';
import '../services/activity_service.dart';
import '../services/live_tracking_service.dart';
import '../services/notification_service.dart';
import '../services/socket_service.dart';
import 'notification_history_screen.dart';
import 'payment_screen.dart';
import 'rating_screen.dart';

class RequestStatusScreen extends StatefulWidget {
  final String requestId;
  final String issue;
  final String vehicle;
  final String location;

  const RequestStatusScreen({
    super.key,
    required this.requestId,
    required this.issue,
    required this.vehicle,
    required this.location,
  });

  @override
  State<RequestStatusScreen> createState() => _RequestStatusScreenState();
}

class _RequestStatusScreenState extends State<RequestStatusScreen> {
  Timer? _timer;
  GoogleMapController? mapController;
  final SocketService socketService = SocketService();
  final LiveTrackingService liveTracking = LiveTrackingService();
  StreamSubscription<LiveTrackingUpdate>? _trackingSub;

  /// Handles for this screen's socket listeners, cancelled in dispose().
  final List<SocketSubscription> _socketSubs = <SocketSubscription>[];

  bool isLoading = true;
  bool paymentDone = false;
  bool completedActivitySaved = false;

  /// True once the backend has answered 404 for this request id. Stops the
  /// 4-second poll: retrying a record that does not exist can never succeed.
  bool requestMissing = false;

  String status = 'Pending';
  String displayStatus = 'Pending';
  String errorMessage = '';

  Map<String, dynamic>? mechanic;
  Map<String, dynamic>? hub;
  Map<String, dynamic>? assistant;

  LatLng? userLatLng;
  LatLng? mechanicLatLng;
  LatLng? assistantLatLng;

  double? etaMinutes;
  double? distanceKm;

  double? assistantEtaMinutes;
  double? assistantDistanceKm;

  int unreadCount = 0;

  double serviceAmount = 499;

  @override
  void initState() {
    super.initState();

    _loadRequestStatus();

    ActivityService.saveLastRequestId(widget.requestId);
    ActivityService.addUserActivity(
      'Tracking Started',
      '${widget.issue} • ${widget.vehicle}',
    );

    loadUnreadCount();

    socketService.connect();

    _socketSubs.add(socketService.onStatusUpdated((data) async {
      final id = data['id'] ?? data['_id'] ?? data['requestId'];
      if (id == widget.requestId) {
        await _loadRequestStatus(showLoader: false);
      }
    }));

    _socketSubs.add(socketService.onRequestAssigned((data) async {
      final id = data['id'] ?? data['_id'] ?? data['requestId'];
      if (id == widget.requestId) {
        await NotificationService.push(
          title: 'Mechanic Assigned',
          message: 'A mechanic has been assigned to your request.',
        );
        await loadUnreadCount();
        await _loadRequestStatus(showLoader: false);
      }
    }));

    _socketSubs.add(socketService.onMechanicLocationUpdated((data) {
      if (data['requestId'] == widget.requestId &&
          data['lat'] != null &&
          data['lng'] != null) {
        setState(() {
          mechanicLatLng = LatLng(
            (data['lat'] as num).toDouble(),
            (data['lng'] as num).toDouble(),
          );
        });
        _recalculateEtaAndDistance();
        _updateMapCamera();
      }
    }));

    _socketSubs.add(socketService.onAssistantAssigned((data) async {
      final id = data['id'] ?? data['_id'] ?? data['requestId'];
      if (id == widget.requestId) {
        // Assistants are rider pickup; we treat as first-mile stage.
        await _loadRequestStatus(showLoader: false);
      }
    }));

    _socketSubs.add(socketService.onAssistantLocationUpdated((data) {
      if (data['requestId'] == widget.requestId &&
          data['lat'] != null &&
          data['lng'] != null) {
        setState(() {
          assistantLatLng = LatLng(
            (data['lat'] as num).toDouble(),
            (data['lng'] as num).toDouble(),
          );
        });
        _recalculateAssistantEtaAndDistance();
        _updateMapCamera();
      }
    }));

    _socketSubs.add(socketService.onPaymentUpdated((data) {
      final reqId = (data['requestId'] ?? '').toString();
      if (reqId != widget.requestId) return;
      final paymentStatus =
          (data['paymentStatus'] ?? '').toString().toLowerCase();
      if (!mounted) return;
      setState(() {
        paymentDone = paymentStatus == 'success';
      });
    }));

    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      // Stop once the backend has said this request does not exist — retrying
      // a missing record every 4 seconds cannot ever succeed.
      if (requestMissing) return;
      _loadRequestStatus(showLoader: false);
    });

    // Feature 1: Battery-safe live tracking (socket + Firestore fallback).
    _setupLiveTracking();
  }

  /// Feature 1: Live 3-person tracking via LiveTrackingService.
  /// Socket primary + Firestore onSnapshot (5s) fallback. Only streams
  /// while the job is "active" — stops on pending/completed/cancelled.
  void _setupLiveTracking() {
    _trackingSub = liveTracking.updates.listen((update) {
      if (update.requestId != widget.requestId) return;
      if (!mounted) return;

      setState(() => status = update.status);

      if (update.mechanic != null) {
        mechanicLatLng = LatLng(update.mechanic!.lat, update.mechanic!.lng);
        _recalculateEtaAndDistance();
      }

      if (update.assistant != null) {
        assistantLatLng = LatLng(update.assistant!.lat, update.assistant!.lng);
        _recalculateAssistantEtaAndDistance();
      }

      _updateMapCamera();
    });

    liveTracking.startTracking(requestId: widget.requestId);
  }

  Future<void> loadUnreadCount() async {
    final count = await NotificationService.getUnreadCount();
    if (!mounted) return;
    setState(() {
      unreadCount = count;
    });
  }

  String normalizeStatus(String value) {
    switch (value.toLowerCase()) {
      case 'pending':
        return 'Pending';
      case 'assigned':
      case 'accepted':
      case 'on_the_way':
      case 'on the way':
      case 'reached':
        return 'Active';
      case 'completed':
        return 'Completed';
      default:
        return 'Pending';
    }
  }

  String rawStatusLabel(String value) {
    switch (value.toLowerCase()) {
      case 'pending':
        return 'Pending';
      case 'assigned':
        return 'Assigned';
      case 'accepted':
        return 'Accepted';
      case 'on_the_way':
      case 'on the way':
        return 'On The Way';
      case 'reached':
        return 'Reached';
      case 'completed':
        return 'Completed';
      default:
        return 'Pending';
    }
  }

  Future<void> _loadRequestStatus({bool showLoader = true}) async {
    try {
      if (showLoader && mounted) {
        setState(() {
          isLoading = true;
          errorMessage = '';
        });
      }

      // Read the request from the RoadResQ backend.
      //
      // This used to read the Firestore `requests` collection FIRST and only
      // fall back to HTTP when the document did not exist. That Firestore read
      // never succeeds — the app holds no Firebase Auth session, so the get()
      // throws permission-denied, the fallback never runs, and the screen shows
      // a permission error instead of the request it was asked to display. See
      // core/utils/firestore_failure.dart. The backend is the system of record
      // for requests anyway, and the timer below polls it every 4 seconds.
      final data = await ApiService.fetchRequestById(widget.requestId);
      _applyRequestData(data);
    } catch (e) {
      if (!mounted) return;

      // A request that no longer exists is not a transient failure. Stop the
      // poll and say so plainly; otherwise the 4-second timer hits 404 forever
      // and the screen shows a bare error with no explanation and no way
      // forward. This is easy to hit in practice: a stale request id survives
      // in storage after the record is gone.
      if (e is ApiNotFoundException) {
        _timer?.cancel();
        setState(() {
          isLoading = false;
          requestMissing = true;
          errorMessage =
              'This rescue request is no longer on the server, so it cannot be '
              'tracked any further.\n\nStart a new request to continue.';
        });
        return;
      }

      setState(() {
        isLoading = false;
        errorMessage = 'Failed to load request status: $e';
      });

      // Report the real cause of a denial. This used to say
      // "Check Firebase Rules", which was wrong: the rules are fine, the app
      // simply holds no Firebase Auth session. See firestore_failure.dart.
      if (e is FirebaseException && e.code == 'permission-denied') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              firestoreFailureSummary(e, what: 'this request'),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Applies request data from either Firestore or HTTP API.
  void _applyRequestData(Map<String, dynamic> data) {
    final requestLocation = data['location'] ?? {};
    final requestLat = requestLocation['lat'];
    final requestLng = requestLocation['lng'];

    final mechanicName = data['mechanicName']?.toString() ?? 'Mechanic';
    final mechanicPhone = data['mechanicPhone']?.toString() ?? '';
    final mechanicId = data['mechanicId']?.toString() ?? '';
    final hubData = data['hub'];
    final mechLoc = data['mechanicLocation'] as Map<String, dynamic>? ?? {};

    final mechLat = mechLoc['lat'];
    final mechLng = mechLoc['lng'];

    final assistantName =
        data['assistantName']?.toString() ?? 'Assistant/Rider';
    final assistantId = data['assistantId']?.toString() ?? '';
    final assistantLocationMap =
        data['assistantLocation'] as Map<String, dynamic>? ?? {};
    final assistantCurrentLat = assistantLocationMap['lat'];
    final assistantCurrentLng = assistantLocationMap['lng'];

    final rawStatus = rawStatusLabel(data['status'] ?? 'pending');
    final newStatus = normalizeStatus(data['status'] ?? 'pending');

    double? newEta;
    double? newDistance;

    if (requestLat != null &&
        requestLng != null &&
        mechLat != null &&
        mechLng != null) {
      final meters = _distanceInMeters(
        (requestLat as num).toDouble(),
        (requestLng as num).toDouble(),
        (mechLat as num).toDouble(),
        (mechLng as num).toDouble(),
      );

      final km = meters / 1000;
      newDistance = km;
      newEta = ((km / 30) * 60).ceilToDouble();
    }

    if (newStatus == 'Completed' && !completedActivitySaved) {
      completedActivitySaved = true;
      ActivityService.addUserActivity(
        'Rescue Completed',
        '${widget.issue} • ${widget.vehicle}',
      );
    }

    if (!mounted) return;

    setState(() {
      status = newStatus;
      displayStatus = rawStatus;
      mechanic = {
        'name': mechanicName,
        'phone': mechanicPhone,
        'id': mechanicId,
      };
      hub = hubData != null ? Map<String, dynamic>.from(hubData as Map) : null;
      assistant = {
        'name': assistantName,
        'id': assistantId,
      };

      etaMinutes = newEta;
      distanceKm = newDistance;

      userLatLng = (requestLat != null && requestLng != null)
          ? LatLng(
              (requestLat as num).toDouble(),
              (requestLng as num).toDouble(),
            )
          : null;

      mechanicLatLng = (mechLat != null && mechLng != null)
          ? LatLng((mechLat as num).toDouble(), (mechLng as num).toDouble())
          : null;

      assistantLatLng =
          (assistantCurrentLat != null && assistantCurrentLng != null)
              ? LatLng(
                  (assistantCurrentLat as num).toDouble(),
                  (assistantCurrentLng as num).toDouble(),
                )
              : null;

      paymentDone =
          (data['paymentStatus']?.toString().toLowerCase() == 'success');

      // Compute assistant ETA/dist from user -> assistant when possible.
      if (userLatLng != null && assistantLatLng != null) {
        final meters = _distanceInMeters(
          userLatLng!.latitude,
          userLatLng!.longitude,
          assistantLatLng!.latitude,
          assistantLatLng!.longitude,
        );
        final km = meters / 1000;
        assistantDistanceKm = km;
        assistantEtaMinutes = ((km / 50) * 60).ceilToDouble();
      }

      isLoading = false;
      errorMessage = '';
    });

    if (displayStatus == 'Completed') {
      _timer?.cancel();
    }

    _updateMapCamera();
  }

  void _recalculateEtaAndDistance() {
    if (userLatLng == null || mechanicLatLng == null) return;

    final meters = _distanceInMeters(
      userLatLng!.latitude,
      userLatLng!.longitude,
      mechanicLatLng!.latitude,
      mechanicLatLng!.longitude,
    );

    final km = meters / 1000;
    final eta = ((km / 30) * 60).ceilToDouble();

    setState(() {
      distanceKm = km;
      etaMinutes = eta;
    });
  }

  void _recalculateAssistantEtaAndDistance() {
    if (userLatLng == null || assistantLatLng == null) return;

    final meters = _distanceInMeters(
      userLatLng!.latitude,
      userLatLng!.longitude,
      assistantLatLng!.latitude,
      assistantLatLng!.longitude,
    );

    final km = meters / 1000;
    // Assistant/Rider is typically faster than tow vehicle.
    // Simple model: use higher speed factor (50 km/h) instead of 30.
    final eta = ((km / 50) * 60).ceilToDouble();

    setState(() {
      assistantDistanceKm = km;
      assistantEtaMinutes = eta;
    });
  }

  double _distanceInMeters(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000;

    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) *
            math.cos(_degreesToRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _degreesToRadians(double degree) {
    return degree * math.pi / 180;
  }

  void _updateMapCamera() {
    if (mapController == null || userLatLng == null) return;

    if (mechanicLatLng != null) {
      final southWest = LatLng(
        math.min(userLatLng!.latitude, mechanicLatLng!.latitude),
        math.min(userLatLng!.longitude, mechanicLatLng!.longitude),
      );

      final northEast = LatLng(
        math.max(userLatLng!.latitude, mechanicLatLng!.latitude),
        math.max(userLatLng!.longitude, mechanicLatLng!.longitude),
      );

      mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(southwest: southWest, northeast: northEast),
          80,
        ),
      );
    } else {
      mapController!.animateCamera(CameraUpdate.newLatLngZoom(userLatLng!, 14));
    }
  }

  Color getStatusColor(String currentStatus) {
    switch (currentStatus) {
      case 'Pending':
        return Colors.red;
      case 'Active':
        return Colors.orange;
      case 'In Progress':
        return Colors.indigo;
      case 'Completed':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String getStatusDescription() {
    switch (displayStatus) {
      case 'Pending':
        return 'We are searching for the nearest available mechanic.';
      case 'Assigned':
        return 'A mechanic has been assigned to your request.';
      case 'Accepted':
        return 'Your mechanic accepted the request and is preparing to start.';
      case 'On The Way':
        return 'Your mechanic is on the way to your location.';
      case 'Reached':
        return 'Your mechanic has reached your location.';
      case 'In Progress':
        return 'Your service is in progress.';
      case 'Payment Pending':
        return 'Service completed. Please complete the payment.';
      case 'Paid':
        return 'Payment received. Thank you!';
      case 'Completed':
        return 'Your rescue request has been completed successfully.';
      default:
        return 'Tracking your rescue request live.';
    }
  }

  Widget sectionCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha((0.05 * 255).round()),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
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

  Widget _timelineStep({
    required String title,
    required bool active,
    required bool done,
  }) {
    final color =
        done || active ? const Color(0xFFD32F2F) : Colors.grey.shade400;

    return Row(
      children: [
        Column(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: done || active ? color : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
              ),
              child: done
                  ? const Icon(Icons.check, size: 11, color: Colors.white)
                  : null,
            ),
            Container(width: 2, height: 28, color: Colors.grey.shade300),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Text(
              title,
              style: TextStyle(
                fontWeight: active || done ? FontWeight.w700 : FontWeight.w500,
                color: active || done ? Colors.black87 : Colors.black54,
              ),
            ),
          ),
        ),
      ],
    );
  }

  bool _isStepDone(String step) {
    const order = [
      'Pending',
      'Assigned',
      'Accepted',
      'On The Way',
      'Reached',
      'In Progress',
      'Completed',
    ];

    final currentIndex = order.indexOf(displayStatus);
    final stepIndex = order.indexOf(step);

    if (currentIndex == -1 || stepIndex == -1) return false;
    return currentIndex > stepIndex;
  }

  bool _isStepActive(String step) {
    return displayStatus == step;
  }

  Widget _priceRow(String label, double value, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: bold ? FontWeight.bold : FontWeight.w500,
          ),
        ),
        Text(
          '₹${value.toStringAsFixed(0)}',
          style: TextStyle(
            fontWeight: bold ? FontWeight.bold : FontWeight.w700,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _trackingSub?.cancel();
    liveTracking.stopTracking();
    mapController?.dispose();
    // Remove only THIS screen's listeners, not every screen's.
    for (final sub in _socketSubs) {
      sub.cancel();
    }
    _socketSubs.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initialTarget = userLatLng ?? const LatLng(13.0827, 80.2707);
    final double platformFee = 49;
    final double total = serviceAmount + platformFee;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      errorMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                )
              : Stack(
                  children: [
                    GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: initialTarget,
                        zoom: 14,
                      ),
                      onMapCreated: (controller) {
                        mapController = controller;
                        _updateMapCamera();
                      },
                      myLocationEnabled: true,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      markers: {
                        if (userLatLng != null)
                          Marker(
                            markerId: const MarkerId('user'),
                            position: userLatLng!,
                            infoWindow:
                                const InfoWindow(title: 'Your Location'),
                          ),
                        if (mechanicLatLng != null)
                          Marker(
                            markerId: const MarkerId('mechanic'),
                            position: mechanicLatLng!,
                            infoWindow: InfoWindow(
                              title: mechanic?['name'] ?? 'Mechanic',
                              snippet: 'Live location',
                            ),
                            icon: BitmapDescriptor.defaultMarkerWithHue(
                              BitmapDescriptor.hueBlue,
                            ),
                          ),
                        if (assistantLatLng != null)
                          Marker(
                            markerId: const MarkerId('assistant'),
                            position: assistantLatLng!,
                            infoWindow: InfoWindow(
                              title: assistant?['name'] ?? 'Assistant/Rider',
                              snippet: 'Pickup rider live location',
                            ),
                            icon: BitmapDescriptor.defaultMarkerWithHue(
                              BitmapDescriptor.hueGreen,
                            ),
                          ),
                      },
                      polylines: {
                        if (userLatLng != null && mechanicLatLng != null)
                          Polyline(
                            polylineId: const PolylineId('route'),
                            points: [mechanicLatLng!, userLatLng!],
                            color: Colors.blue,
                            width: 5,
                          ),
                      },
                    ),
                    SafeArea(
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
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
                                        BoxShadow(
                                          color: Colors.black12,
                                          blurRadius: 10,
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
                                      color: getStatusColor(status),
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
                                            displayStatus,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ),
                                        if (etaMinutes != null)
                                          Text(
                                            '${etaMinutes!.toInt()} min',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Stack(
                                  children: [
                                    InkWell(
                                      onTap: () async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const NotificationHistoryScreen(),
                                          ),
                                        );
                                        await loadUnreadCount();
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Colors.black12,
                                              blurRadius: 10,
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                            Icons.notifications_none),
                                      ),
                                    ),
                                    if (unreadCount > 0)
                                      Positioned(
                                        right: 0,
                                        top: 0,
                                        child: Container(
                                          padding: const EdgeInsets.all(5),
                                          decoration: const BoxDecoration(
                                            color: Colors.red,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Text(
                                            unreadCount > 9
                                                ? '9+'
                                                : unreadCount.toString(),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          Container(
                            width: double.infinity,
                            constraints: BoxConstraints(
                              maxHeight:
                                  MediaQuery.of(context).size.height * 0.75,
                            ),
                            padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF7F9FC),
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(30),
                              ),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black12, blurRadius: 18),
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
                                        colors: [
                                          Color(0xFFD32F2F),
                                          Color(0xFFFF7043),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Live Rescue Status',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 23,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Request ID: ${widget.requestId}',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          getStatusDescription(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      _statCard(
                                        'Mechanic ETA',
                                        etaMinutes != null
                                            ? '${etaMinutes!.toInt()} min'
                                            : '--',
                                        Icons.schedule,
                                        const Color(0xFFD32F2F),
                                      ),
                                      const SizedBox(width: 10),
                                      _statCard(
                                        'Mechanic Distance',
                                        distanceKm != null
                                            ? '${distanceKm!.toStringAsFixed(1)} km'
                                            : '--',
                                        Icons.route,
                                        const Color(0xFF0D47A1),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  if (assistantEtaMinutes != null ||
                                      assistantDistanceKm != null)
                                    Row(
                                      children: [
                                        _statCard(
                                          'Assistant ETA',
                                          assistantEtaMinutes != null
                                              ? '${assistantEtaMinutes!.toInt()} min'
                                              : '--',
                                          Icons.directions_bike,
                                          const Color(0xFF2E7D32),
                                        ),
                                        const SizedBox(width: 10),
                                        _statCard(
                                          'Assistant Distance',
                                          assistantDistanceKm != null
                                              ? '${assistantDistanceKm!.toStringAsFixed(1)} km'
                                              : '--',
                                          Icons.route,
                                          const Color(0xFF1B5E20),
                                        ),
                                      ],
                                    ),
                                  const SizedBox(height: 16),
                                  sectionCard(
                                    child: Row(
                                      children: [
                                        const CircleAvatar(
                                          radius: 28,
                                          backgroundColor: Color(0xFFD32F2F),
                                          child: Icon(
                                            Icons.person,
                                            color: Colors.white,
                                            size: 30,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                mechanic?['name'] ??
                                                    'Searching mechanic...',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                mechanic?['partnerType'] ??
                                                    'Verified Roadside Partner',
                                                style: const TextStyle(
                                                  color: Colors.black54,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                mechanic?['phone'] ??
                                                    'Phone: N/A',
                                                style: const TextStyle(
                                                  color: Colors.black87,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (mechanic?['phone'] != null)
                                          Container(
                                            decoration: BoxDecoration(
                                              color: Colors.green.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(
                                                14,
                                              ),
                                            ),
                                            child: const Padding(
                                              padding: EdgeInsets.all(12),
                                              child: Icon(
                                                Icons.call,
                                                color: Colors.green,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  sectionCard(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Rescue Progress',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18,
                                          ),
                                        ),
                                        const SizedBox(height: 14),
                                        _timelineStep(
                                          title: 'Request Created',
                                          active: _isStepActive('Pending'),
                                          done: _isStepDone('Pending'),
                                        ),
                                        _timelineStep(
                                          title: 'Mechanic Assigned',
                                          active: _isStepActive('Assigned'),
                                          done: _isStepDone('Assigned'),
                                        ),
                                        _timelineStep(
                                          title: 'Request Accepted',
                                          active: _isStepActive('Accepted'),
                                          done: _isStepDone('Accepted'),
                                        ),
                                        _timelineStep(
                                          title: 'Mechanic On The Way',
                                          active: _isStepActive('On The Way'),
                                          done: _isStepDone('On The Way'),
                                        ),
                                        _timelineStep(
                                          title: 'Mechanic Reached',
                                          active: _isStepActive('Reached'),
                                          done: _isStepDone('Reached'),
                                        ),
                                        _timelineStep(
                                          title: 'Service Started',
                                          active: _isStepActive('In Progress'),
                                          done: _isStepDone('In Progress'),
                                        ),
                                        Row(
                                          children: [
                                            Container(
                                              width: 18,
                                              height: 18,
                                              decoration: BoxDecoration(
                                                color: _isStepDone(
                                                            'Completed') ||
                                                        _isStepActive(
                                                            'Completed')
                                                    ? const Color(0xFFD32F2F)
                                                    : Colors.white,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: _isStepDone(
                                                              'Completed') ||
                                                          _isStepActive(
                                                              'Completed')
                                                      ? const Color(0xFFD32F2F)
                                                      : Colors.grey.shade400,
                                                  width: 2,
                                                ),
                                              ),
                                              child: _isStepDone('Completed')
                                                  ? const Icon(
                                                      Icons.check,
                                                      size: 11,
                                                      color: Colors.white,
                                                    )
                                                  : null,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                'Completed',
                                                style: TextStyle(
                                                  fontWeight: _isStepActive(
                                                              'Completed') ||
                                                          _isStepDone(
                                                              'Completed')
                                                      ? FontWeight.w700
                                                      : FontWeight.w500,
                                                  color: _isStepActive(
                                                              'Completed') ||
                                                          _isStepDone(
                                                              'Completed')
                                                      ? Colors.black87
                                                      : Colors.black54,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (hub != null) ...[
                                    const SizedBox(height: 16),
                                    sectionCard(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Connected Rescue Hub',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Text('Hub: ${hub!['name'] ?? 'N/A'}'),
                                          const SizedBox(height: 6),
                                          Text(
                                            'Address: ${hub!['address'] ?? 'N/A'}',
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            'Distance: ${hub!['distanceKm'] ?? '--'} km',
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 16),
                                  sectionCard(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Payment',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        _priceRow(
                                            'Service Charge', serviceAmount),
                                        const SizedBox(height: 8),
                                        _priceRow('Platform Fee', platformFee),
                                        const Divider(height: 24),
                                        _priceRow('Total', total, bold: true),
                                        const SizedBox(height: 14),
                                        SizedBox(
                                          width: double.infinity,
                                          height: 50,
                                          child: ElevatedButton(
                                            onPressed: paymentDone
                                                ? null
                                                : () async {
                                                    final result =
                                                        await Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (_) =>
                                                            PaymentScreen(
                                                          requestId:
                                                              widget.requestId,
                                                          userName: (AppSession
                                                                      .name ??
                                                                  '')
                                                              .isEmpty
                                                              ? 'RoadResQ customer'
                                                              : AppSession.name!,
                                                          userPhone: AppSession
                                                                  .phone ??
                                                              '',
                                                          userEmail: AppSession
                                                                  .email ??
                                                              '',
                                                          amount: total.toInt(),
                                                        ),
                                                      ),
                                                    );

                                                    if (result != null &&
                                                        result["status"] ==
                                                            "success" &&
                                                        mounted) {
                                                      setState(() {
                                                        paymentDone = true;
                                                      });
                                                    }
                                                  },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: paymentDone
                                                  ? Colors.grey
                                                  : const Color(0xFF0D47A1),
                                              foregroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(
                                                  14,
                                                ),
                                              ),
                                            ),
                                            child: Text(
                                              paymentDone
                                                  ? 'Payment Done'
                                                  : 'Pay Now',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                        // Closing step of the workflow: the
                                        // customer can rate once paid, which
                                        // also closes the request.
                                        if (paymentDone) ...[
                                          const SizedBox(height: 12),
                                          SizedBox(
                                            width: double.infinity,
                                            height: 46,
                                            child: OutlinedButton.icon(
                                              onPressed: () => Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) => RatingScreen(
                                                    requestId:
                                                        widget.requestId,
                                                  ),
                                                ),
                                              ),
                                              icon: const Icon(Icons.star_border),
                                              label:
                                                  const Text('Rate your mechanic'),
                                            ),
                                          ),
                                        ],
                                      ],
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
