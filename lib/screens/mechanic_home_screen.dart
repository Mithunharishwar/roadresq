import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../core/theme/rq_widgets.dart';
import '../core/theme/app_theme.dart';
import '../services/api_service.dart';
import '../core/request_status.dart';
import '../services/activity_service.dart';
import '../services/offline_queue_service.dart';
import '../services/socket_service.dart';
import 'request_location_screen.dart';
import 'mechanic_community_screen.dart';
import 'mechanic_safety_screen.dart';
import '../services/notification_service.dart';
import 'notification_history_screen.dart';

class MechanicHomeScreen extends StatefulWidget {
  final String mechanicId;
  final String mechanicName;

  const MechanicHomeScreen({
    super.key,
    required this.mechanicId,
    required this.mechanicName,
  });

  @override
  State<MechanicHomeScreen> createState() => _MechanicHomeScreenState();
}

class _MechanicHomeScreenState extends State<MechanicHomeScreen> {
  List assignedRequests = [];
  List availableRequests = [];
  bool loading = true;
  bool isOnline = true;
  bool isUpdatingOnline = false;

  final SocketService socketService = SocketService();
  Timer? locationTimer;
  int unreadCount = 0;

  /// Handles for this screen's socket listeners. Cancelled in dispose() so
  /// they are removed individually — the previous app-wide
  /// `clearAllListeners()` also unsubscribed every other open screen.
  final List<SocketSubscription> _socketSubs = <SocketSubscription>[];

  @override
  void initState() {
    super.initState();
    loadUnreadCount();
    loadAllRequests();

    socketService.connect();

    // Show a SnackBar if the backend has been unreachable for 15s.
    _socketSubs.add(socketService.addOfflineListener(() {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Backend offline. Start python backend/roadresq_backend.py',
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ),
      );
    }));

    _socketSubs.add(socketService.onNewRequest((data) async {
      if (!mounted) return;
      await NotificationService.push(
        title: 'New Request',
        message: 'A new rescue request is available nearby.',
      );
      if (!mounted) return;
      NotificationService.show(context, '🚨 New request nearby!');
      await loadUnreadCount();
      if (!mounted) return;
      loadAllRequests(showLoader: false);
    }));

    _socketSubs.add(socketService.onRequestAssigned((data) async {
      if (!mounted) return;
      await NotificationService.push(
        title: 'Request Assigned',
        message: 'A rescue request has been assigned.',
      );
      if (!mounted) return;
      NotificationService.show(context, '📍 Request assigned');
      await loadUnreadCount();
      if (!mounted) return;
      loadAllRequests(showLoader: false);
    }));

    _socketSubs.add(socketService.onStatusUpdated((data) async {
      if (!mounted) return;
      await NotificationService.push(
        title: 'Status Updated',
        message: 'A request status was updated.',
      );
      if (!mounted) return;
      NotificationService.show(context, '🔄 Status updated!');
      await loadUnreadCount();
      if (!mounted) return;
      loadAllRequests(showLoader: false);
    }));

    _socketSubs.add(socketService.onMechanicOnlineUpdated((data) {
      if (!mounted) return;
      if (data['mechanicId'] == widget.mechanicId ||
          data['customId'] == widget.mechanicId ||
          data['mongoId'] == widget.mechanicId) {
        setState(() {
          isOnline = data['online'] == true;
        });
      }
    }));
  }

  Future<void> loadUnreadCount() async {
    final count = await NotificationService.getUnreadCount();
    if (!mounted) return;
    setState(() {
      unreadCount = count;
    });
  }

  Future<void> loadAllRequests({bool showLoader = true}) async {
    try {
      if (showLoader && mounted) {
        setState(() {
          loading = true;
        });
      }

      final assignedRaw = await ApiService.fetchMechanicRequests(
        mechanicId: widget.mechanicId,
      );
      final available = await ApiService.fetchAvailableRequests(
        mechanicId: widget.mechanicId,
      );

      if (!mounted) return;

      setState(() {
        assignedRequests = assignedRaw;
        availableRequests = available;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load mechanic requests: $e')),
      );
    }
  }

  Future<void> refreshPage() async {
    await loadAllRequests(showLoader: true);
    await loadUnreadCount();
  }

  Future<void> toggleOnlineStatus(bool value) async {
    if (isUpdatingOnline) return;

    try {
      setState(() {
        isUpdatingOnline = true;
      });

      await ApiService.updateMechanicOnline(
        mechanicId: widget.mechanicId,
        online: value,
      );

      if (!mounted) return;

      setState(() {
        isOnline = value;
      });

      if (!value) {
        stopLiveLocation();
      } else {
        await startLiveLocation();

        // FEATURE 5: Deliver any queued jobs to this mechanic now that they
        // are back online (FCM push of pending jobs queued while offline).
        await OfflineQueueService().deliverQueuedJobs(
          crewId: widget.mechanicId,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value ? 'You are now online' : 'You are now offline'),
        ),
      );

      await loadAllRequests(showLoader: false);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update online status: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          isUpdatingOnline = false;
        });
      }
    }
  }

  Future<void> startLiveLocation() async {
    if (!isOnline) return;

    locationTimer?.cancel();

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enable location services')));
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

    locationTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        await ApiService.updateMechanicLocation(
          mechanicId: widget.mechanicId,
          lat: position.latitude,
          lng: position.longitude,
        );

        for (final req in assignedRequests) {
          final status = normalizeStatus(req['status'] ?? '');
          if (RequestStatusInfo.parse(status)?.isFieldActive ?? false) {
            final requestId = (req['_id'] ?? req['id'] ?? '').toString();
            if (requestId.isNotEmpty) {
              await ApiService.updateRequestMechanicLocation(
                requestId: requestId,
                mechanicId: widget.mechanicId,
                lat: position.latitude,
                lng: position.longitude,
              );
            }
          }
        }
      } catch (e) {
        debugPrint('Location error: $e');
      }
    });
  }

  void stopLiveLocation() {
    locationTimer?.cancel();
    locationTimer = null;
  }

  /// Lifecycle helpers — see lib/core/request_status.dart.
  ///
  /// These used to be hand-written switches per screen, and this one jumped
  /// `Reached` straight to `Completed`, which the backend rejects:
  /// "illegal transition ARRIVED -> SERVICE_COMPLETED". The shared module mirrors
  /// backend/status_machine.py, so the button can only offer a legal step.
  String normalizeStatus(String status) => RequestStatusInfo.label(status);

  String getBackendStatus(String uiStatus) => RequestStatusInfo.apiValue(uiStatus);

  String? getNextStatus(String status) {
    final next = RequestStatusInfo.next(status);
    return next?.label;
  }

  String getNextButtonText(String status) =>
      RequestStatusInfo.nextActionLabel(status);

  Color getStatusColor(String status) => RequestStatusInfo.color(status);

  bool _isActiveStatus(String status) =>
      RequestStatusInfo.parse(status)?.isFieldActive ?? false;

  int get assignedCount => assignedRequests.length;

  int get activeCount => assignedRequests
      .where((r) => _isActiveStatus('${r['status'] ?? ''}'))
      .length;

  int get completedCount => assignedRequests.where((r) {
        final s = RequestStatusInfo.parse('${r['status'] ?? ''}');
        return s != null && s.isFinished;
      }).length;

  Future<void> acceptAvailableJob(Map req) async {
    try {
      final requestId = (req['_id'] ?? req['id'] ?? '').toString();
      if (requestId.isEmpty) {
        throw Exception('Invalid request id');
      }

      await ApiService.assignMechanicToRequest(
        requestId: requestId,
        mechanicId: widget.mechanicId,
      );

      await ActivityService.addMechanicActivity(
        'Job Accepted',
        '${req['issue']} for ${req['name']}',
      );

      await startLiveLocation();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request accepted successfully')),
      );

      await loadAllRequests(showLoader: false);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to accept job: $e')));
    }
  }

  Future<void> updateStatus({
    required String requestId,
    required String customerName,
    required String status,
  }) async {
    try {
      await ApiService.updateRequestStatus(
        requestId: requestId,
        status: status,
      );

      await ActivityService.addMechanicActivity(
        'Status Updated',
        '$customerName → $status',
      );

      // Keep pushing position while the job is live, including while the
      // service itself is being performed (In Progress) — the customer's map
      // must not freeze between "Reached" and "Completed".
      final parsed = RequestStatusInfo.parse(status);
      if (parsed == RequestStatus.completed ||
          parsed == RequestStatus.cancelled ||
          parsed == RequestStatus.closed) {
        stopLiveLocation();
      } else if (parsed?.isFieldActive ?? false) {
        await startLiveLocation();
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${RequestStatusInfo.label(status)} — $customerName',
          ),
        ),
      );

      await loadAllRequests(showLoader: false);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error updating status: $e')));
    }
  }

  void openLocation(Map req) {
    final dynamic location = req['location'];

    final double lat = location is Map && location['lat'] != null
        ? (location['lat'] as num).toDouble()
        : ((req['lat'] ?? 0) as num).toDouble();

    final double lng = location is Map && location['lng'] != null
        ? (location['lng'] as num).toDouble()
        : ((req['lng'] ?? 0) as num).toDouble();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RequestLocationScreen(
          requestId: (req['_id'] ?? req['id'] ?? '').toString(),
          customerName: req['name'] ?? 'Customer',
          customerPhone: req['phone'] ?? '',
          lat: lat,
          lng: lng,
          issue: req['issue'] ?? '',
          locationText: req['locationText'] ?? '',
          currentStatus: normalizeStatus(req['status'] ?? 'Assigned'),
        ),
      ),
    );
  }

  Widget buildHeader() {
    return RQ.moduleHeader(
      title: 'Captain Dashboard',
      subtitle: isOnline
          ? 'You are available for new jobs and live rescue updates'
          : 'You are offline. Turn on availability to receive nearby jobs',
      icon: Icons.build,
      colors: const [Color(0xFF0D47A1), Color(0xFF1976D2)],
      glow: const Color(0xFF0D47A1),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              IconButton(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const NotificationHistoryScreen(),
                    ),
                  );
                  await loadUnreadCount();
                },
                icon: const Icon(
                  Icons.notifications_none,
                  color: Colors.white,
                ),
              ),
              if (unreadCount > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      unreadCount > 9 ? '9+' : unreadCount.toString(),
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
          const SizedBox(width: 4),
          Switch(
            value: isOnline,
            onChanged: isUpdatingOnline ? null : toggleOnlineStatus,
            activeThumbColor: Colors.green,
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha((0.14 * 255).round()),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(
              isOnline ? Icons.verified_user_outlined : Icons.location_off,
              color: Colors.white,
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Active service zone: Chennai Central',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildQuickActions() {
    // 4-tab quick action grid: Safety, Community, Help, Ratings.
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: RQ.quickAction(
                icon: Icons.shield,
                label: 'Safety',
                color: const Color(0xFFD32F2F),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MechanicSafetyScreen(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: RQ.quickAction(
                icon: Icons.groups,
                label: 'Community',
                color: const Color(0xFF0D47A1),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MechanicCommunityScreen(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: RQ.quickAction(
                icon: Icons.help_outline,
                label: 'Help',
                color: const Color(0xFF2E7D32),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Support center coming soon'),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: RQ.quickAction(
                icon: Icons.star_outline,
                label: 'My Rating',
                color: const Color(0xFFFF8F00),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Your rating: 4.8 ★ (excellent)'),
                      backgroundColor: Color(0xFF2E7D32),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Earnings + rating strip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              const Icon(Icons.currency_rupee, color: Colors.white),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Today Earnings',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '₹850',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha((0.2 * 255).round()),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.star, color: Colors.amber, size: 16),
                    SizedBox(width: 4),
                    Text(
                      '4.8',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget buildStatCard({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceOf(context),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha((0.05 * 255).round()),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.mutedOf(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildDashboardCards() {
    return Row(
      children: [
        buildStatCard(
          title: 'Assigned',
          value: assignedCount.toString(),
          color: Colors.orange,
          icon: Icons.assignment_ind_outlined,
        ),
        const SizedBox(width: 12),
        buildStatCard(
          title: 'In Progress',
          value: activeCount.toString(),
          color: Colors.blue,
          icon: Icons.route,
        ),
        const SizedBox(width: 12),
        buildStatCard(
          title: 'Completed',
          value: completedCount.toString(),
          color: Colors.green,
          icon: Icons.check_circle_outline,
        ),
      ],
    );
  }

  Widget buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF0D47A1)),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget buildAssignedRequestCard(Map req) {
    final status = normalizeStatus(req['status'] ?? 'Assigned');
    final nextStatus = getNextStatus(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha((0.05 * 255).round()),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                backgroundColor: Color(0xFFE3F2FD),
                child: Icon(Icons.person, color: Color(0xFF0D47A1)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  req['name'] ?? 'Customer',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: getStatusColor(status),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  status,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _infoRow(
            Icons.build_circle_outlined,
            'Issue',
            '${req['issue'] ?? ''}',
          ),
          _infoRow(
            Icons.directions_car_outlined,
            'Vehicle',
            '${req['vehicle'] ?? ''}',
          ),
          _infoRow(Icons.phone_outlined, 'Phone', '${req['phone'] ?? ''}'),
          _infoRow(
            Icons.location_on_outlined,
            'Location',
            '${req['locationText'] ?? ''}',
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => openLocation(req),
              icon: const Icon(Icons.map_outlined),
              label: const Text('Open Live Map'),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: nextStatus == null || !isOnline
                  ? null
                  : () async {
                      await updateStatus(
                        requestId: (req['_id'] ?? req['id'] ?? '').toString(),
                        customerName: req['name'] ?? 'Customer',
                        status: getBackendStatus(nextStatus),
                      );
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D47A1),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                nextStatus == null ? 'Completed' : getNextButtonText(status),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildAvailableRequestCard(Map req) {
    final distanceKm = req['distanceKm'];

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha((0.05 * 255).round()),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                backgroundColor: Color(0xFFE8F5E9),
                child: Icon(Icons.support_agent, color: Colors.green),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  req['name'] ?? 'Customer',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (distanceKm != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$distanceKm km',
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _infoRow(
            Icons.build_circle_outlined,
            'Issue',
            '${req['issue'] ?? ''}',
          ),
          _infoRow(
            Icons.directions_car_outlined,
            'Vehicle',
            '${req['vehicle'] ?? ''}',
          ),
          _infoRow(Icons.phone_outlined, 'Phone', '${req['phone'] ?? ''}'),
          _infoRow(
            Icons.location_on_outlined,
            'Location',
            '${req['locationText'] ?? ''}',
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: !isOnline ? null : () => acceptAvailableJob(req),
              icon: const Icon(Icons.check_circle_outline),
              label: Text(isOnline ? 'Accept This Job' : 'Go Online to Accept'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppTheme.mutedOf(context)),
          const SizedBox(width: 8),
          Text('$title: ', style: const TextStyle(fontWeight: FontWeight.w700)),
          Expanded(
            child: Text(value, style: TextStyle(color: AppTheme.textOf(context))),
          ),
        ],
      ),
    );
  }

  Widget buildEmptyCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(message, style: TextStyle(color: AppTheme.mutedOf(context))),
    );
  }

  @override
  void dispose() {
    stopLiveLocation();
    // Remove only THIS screen's listeners. Calling the app-wide
    // clearAllListeners() here used to unsubscribe every other open screen.
    for (final sub in _socketSubs) {
      sub.cancel();
    }
    _socketSubs.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundOf(context),
      body: SafeArea(
        child: Column(
          children: [
            buildHeader(),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: refreshPage,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          children: [
                            buildQuickActions(),
                            const SizedBox(height: 16),
                            buildDashboardCards(),
                            const SizedBox(height: 20),
                            buildSectionTitle(
                              'Assigned Requests',
                              Icons.assignment_outlined,
                            ),
                            const SizedBox(height: 12),
                            if (assignedRequests.isEmpty)
                              buildEmptyCard('No assigned requests available')
                            else
                              ...assignedRequests.map(
                                (req) => buildAssignedRequestCard(req as Map),
                              ),
                            const SizedBox(height: 20),
                            buildSectionTitle(
                              'Available Nearby Jobs',
                              Icons.location_searching,
                            ),
                            const SizedBox(height: 12),
                            if (availableRequests.isEmpty)
                              buildEmptyCard(
                                'No nearby jobs available right now',
                              )
                            else
                              ...availableRequests.map(
                                (req) => buildAvailableRequestCard(req as Map),
                              ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
