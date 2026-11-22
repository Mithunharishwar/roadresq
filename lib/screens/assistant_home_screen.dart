import 'dart:async';
import 'package:material_ui/material_ui.dart';

import '../core/theme/app_theme.dart';
import 'package:geolocator/geolocator.dart';
import '../core/theme/rq_widgets.dart';
import '../services/assistant_service.dart';
import '../core/request_status.dart';
import '../services/offline_queue_service.dart';
import '../services/socket_service.dart';
import '../services/notification_service.dart';
import 'notification_history_screen.dart';
import 'request_location_screen.dart';

/// AssistantHomeScreen
///
/// Dashboard for the assistant (rider) crew member.
/// Shows:
/// - Online/offline toggle
/// - Available jobs nearby
/// - Accepted/active jobs
/// - Job status update flow: pending -> accepted -> on_the_way -> reached -> completed
class AssistantHomeScreen extends StatefulWidget {
  final String assistantId;
  final String assistantName;

  const AssistantHomeScreen({
    super.key,
    required this.assistantId,
    required this.assistantName,
  });

  @override
  State<AssistantHomeScreen> createState() => _AssistantHomeScreenState();
}

class _AssistantHomeScreenState extends State<AssistantHomeScreen> {
  final AssistantService _service = AssistantService();
  final SocketService _socket = SocketService();

  List assignedJobs = [];
  List availableJobs = [];
  bool loading = true;
  bool isOnline = true;
  bool isUpdatingOnline = false;

  Timer? locationTimer;
  int unreadCount = 0;

  /// Handles for this screen's socket listeners, cancelled in dispose().
  final List<SocketSubscription> _socketSubs = <SocketSubscription>[];

  @override
  void initState() {
    super.initState();
    loadUnreadCount();
    loadAllJobs();

    _socket.connect();

    // Show a SnackBar if the backend has been unreachable for 15s.
    _socketSubs.add(_socket.addOfflineListener(() {
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

    _socketSubs.add(_socket.onNewRequest((data) async {
      if (!mounted) return;
      await NotificationService.push(
        title: 'New Job',
        message: 'A new customer pickup job is available.',
      );
      if (!mounted) return;
      NotificationService.show(context, '🛵 New job available!');
      await loadUnreadCount();
      if (!mounted) return;
      loadAllJobs(showLoader: false);
    }));

    _socketSubs.add(_socket.onRequestAssigned((data) async {
      if (!mounted) return;
      await NotificationService.push(
        title: 'Job Assigned',
        message: 'A pickup job has been assigned to you.',
      );
      if (!mounted) return;
      NotificationService.show(context, '📍 Job assigned!');
      await loadUnreadCount();
      if (!mounted) return;
      loadAllJobs(showLoader: false);
    }));

    // The customer, the mechanic and the garage all move the same request.
    // Without this listener the assistant's list went stale whenever somebody
    // else advanced or cancelled the job it was carrying.
    _socketSubs.add(_socket.onStatusUpdated((data) async {
      if (!mounted) return;
      await loadAllJobs(showLoader: false);
      if (!mounted) return;
      final label = RequestStatusInfo.label('${data['status'] ?? ''}');
      if (label.isNotEmpty) {
        NotificationService.show(context, 'Job update: $label');
      }
    }));

    // Keep the online toggle in sync when the backend broadcasts a change.
    _socketSubs.add(_socket.onAssistantOnlineUpdated((data) {
      if (!mounted) return;
      final id = data['assistantId'] == widget.assistantId ||
          data['customId'] == widget.assistantId ||
          data['mongoId'] == widget.assistantId;
      if (id) {
        setState(() => isOnline = data['online'] == true);
      }
    }));
  }

  Future<void> loadUnreadCount() async {
    final count = await NotificationService.getUnreadCount();
    if (!mounted) return;
    setState(() => unreadCount = count);
  }

  Future<void> loadAllJobs({bool showLoader = true}) async {
    try {
      if (showLoader && mounted) {
        setState(() => loading = true);
      }

      final assignedRaw = await _service.fetchAssignedJobs(
        assistantId: widget.assistantId,
      );
      final available = await _service.fetchAvailableJobs();

      if (!mounted) return;

      setState(() {
        assignedJobs = assignedRaw;
        availableJobs = available;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load jobs: $e')),
      );
    }
  }

  Future<void> refreshPage() async {
    await loadAllJobs(showLoader: true);
    await loadUnreadCount();
  }

  Future<void> toggleOnlineStatus(bool value) async {
    if (isUpdatingOnline) return;

    try {
      setState(() => isUpdatingOnline = true);

      await _service.updateOnlineStatus(
        assistantId: widget.assistantId,
        online: value,
      );

      if (!mounted) return;
      setState(() => isOnline = value);

      if (value) {
        await startLiveLocation();

        // FEATURE 5: Deliver any queued jobs to this assistant now that they
        // are back online (FCM push of pending jobs queued while offline).
        await OfflineQueueService().deliverQueuedJobs(
          crewId: widget.assistantId,
        );
      } else {
        stopLiveLocation();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value ? 'You are now online' : 'You are now offline'),
        ),
      );

      await loadAllJobs(showLoader: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update status: $e')),
      );
    } finally {
      if (mounted) setState(() => isUpdatingOnline = false);
    }
  }

  Future<void> startLiveLocation() async {
    if (!isOnline) return;

    locationTimer?.cancel();

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enable location services')),
      );
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

    locationTimer = Timer.periodic(const Duration(seconds: 8), (timer) async {
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        for (final job in assignedJobs) {
          final status = job['status']?.toString().toLowerCase() ?? '';
          if (status == 'accepted' ||
              status == 'on_the_way' ||
              status == 'reached') {
            final requestId = (job['_id'] ?? job['id'] ?? '').toString();
            if (requestId.isNotEmpty) {
              await _service.updateLocation(
                requestId: requestId,
                assistantId: widget.assistantId,
                lat: position.latitude,
                lng: position.longitude,
              );
            }
          }
        }
      } catch (e) {
        // Silently retry
      }
    });
  }

  void stopLiveLocation() {
    locationTimer?.cancel();
    locationTimer = null;
  }

  /// Lifecycle helpers — see lib/core/request_status.dart. Assistant jobs use
  /// the same state machine as mechanic jobs, so "Reached" must pass through
  /// "In Progress" before "Completed" (ARRIVED -> SERVICE_STARTED -> ...).
  String _displayStatus(String status) => RequestStatusInfo.label(status);

  String _backendStatus(String uiStatus) => RequestStatusInfo.apiValue(uiStatus);

  String? _nextStatus(String status) {
    final next = RequestStatusInfo.next(status);
    return next?.label;
  }

  String _nextButtonText(String status) =>
      RequestStatusInfo.nextActionLabel(status, audience: 'assistant');

  Color _statusColor(String status) => RequestStatusInfo.color(status);

  Future<void> acceptJob(Map job) async {
    try {
      final requestId = (job['_id'] ?? job['id'] ?? '').toString();
      if (requestId.isEmpty) {
        throw Exception('Invalid job id');
      }

      await _service.acceptJob(
        requestId: requestId,
        assistantId: widget.assistantId,
        assistantName: widget.assistantName,
      );

      await startLiveLocation();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Job accepted successfully')),
      );
      await loadAllJobs(showLoader: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to accept job: $e')),
      );
    }
  }

  Future<void> updateJobStatus({
    required String requestId,
    required String customerName,
    required String status,
  }) async {
    try {
      await _service.updateJobStatus(
        requestId: requestId,
        status: _backendStatus(status),
      );

      final parsed = RequestStatusInfo.parse(status);
      if (parsed == RequestStatus.completed ||
          parsed == RequestStatus.cancelled ||
          parsed == RequestStatus.closed) {
        stopLiveLocation();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${RequestStatusInfo.label(status)} — $customerName'),
        ),
      );
      await loadAllJobs(showLoader: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating status: $e')),
      );
    }
  }

  void openLocation(Map job) {
    final dynamic location = job['location'];
    final lat = location is Map && location['lat'] != null
        ? (location['lat'] as num).toDouble()
        : ((job['lat'] ?? 0) as num).toDouble();
    final lng = location is Map && location['lng'] != null
        ? (location['lng'] as num).toDouble()
        : ((job['lng'] ?? 0) as num).toDouble();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RequestLocationScreen(
          requestId: (job['_id'] ?? job['id'] ?? '').toString(),
          customerName: job['name'] ?? 'Customer',
          customerPhone: job['phone'] ?? '',
          lat: lat,
          lng: lng,
          issue: job['issue'] ?? '',
          locationText: job['locationText'] ?? '',
          currentStatus: _displayStatus(job['status'] ?? 'Assigned'),
        ),
      ),
    );
  }

  // ================= Widget Builders =================

  Widget _buildHeader() {
    return RQ.moduleHeader(
      title: 'Rider Dashboard',
      subtitle: isOnline
          ? 'You are available for customer pickup jobs'
          : 'You are offline. Turn on availability to receive jobs',
      icon: Icons.two_wheeler,
      colors: const [Color(0xFF1B5E20), Color(0xFF4CAF50)],
      glow: const Color(0xFF2E7D32),
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
                icon: const Icon(Icons.notifications_none, color: Colors.white),
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
            Expanded(
              child: Text(
                isOnline
                    ? 'Active zone: Chennai - First Responder'
                    : 'Go online to receive pickup jobs',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({
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
            Text(value,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppTheme.mutedOf(context))),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF2E7D32)),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildAssignedJobCard(Map job) {
    final status = _displayStatus(job['status'] ?? 'Assigned');
    final nextStatus = _nextStatus(status);

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
                child: Icon(Icons.person, color: Color(0xFF2E7D32)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  job['name'] ?? 'Customer',
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.bold),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _statusColor(status),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(status,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _infoRow(
              Icons.build_circle_outlined, 'Issue', '${job['issue'] ?? ''}'),
          _infoRow(Icons.directions_car_outlined, 'Vehicle',
              '${job['vehicle'] ?? ''}'),
          _infoRow(Icons.phone_outlined, 'Phone', '${job['phone'] ?? ''}'),
          _infoRow(Icons.location_on_outlined, 'Location',
              '${job['locationText'] ?? ''}'),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => openLocation(job),
              icon: const Icon(Icons.map_outlined),
              label: const Text('Open Live Map'),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
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
                      await updateJobStatus(
                        requestId: (job['_id'] ?? job['id'] ?? '').toString(),
                        customerName: job['name'] ?? 'Customer',
                        status: nextStatus,
                      );
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              // No legal next step is not the same as "Completed"; saying so
              // made an untouched job look finished.
              child: Text(
                nextStatus == null ? 'No action needed' : _nextButtonText(status),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvailableJobCard(Map job) {
    final distanceKm = job['distanceKm'];

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
                  job['name'] ?? 'Customer',
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.bold),
                ),
              ),
              if (distanceKm != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$distanceKm km',
                    style: const TextStyle(
                        color: Colors.green, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _infoRow(
              Icons.build_circle_outlined, 'Issue', '${job['issue'] ?? ''}'),
          _infoRow(Icons.directions_car_outlined, 'Vehicle',
              '${job['vehicle'] ?? ''}'),
          _infoRow(Icons.phone_outlined, 'Phone', '${job['phone'] ?? ''}'),
          _infoRow(Icons.location_on_outlined, 'Location',
              '${job['locationText'] ?? ''}'),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: !isOnline ? null : () => acceptJob(job),
              icon: const Icon(Icons.check_circle_outline),
              label: Text(isOnline ? 'Accept Pickup' : 'Go Online to Accept'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
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
              child:
                  Text(value, style: TextStyle(color: AppTheme.textOf(context)))),
        ],
      ),
    );
  }

  Widget _buildEmptyCard(String message) {
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
    // Remove only THIS screen's listeners, not every screen's.
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
            _buildHeader(),
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
                            Row(
                              children: [
                                _buildStatCard(
                                  title: 'Assigned',
                                  value: assignedJobs.length.toString(),
                                  color: Colors.orange,
                                  icon: Icons.assignment_ind_outlined,
                                ),
                                const SizedBox(width: 12),
                                _buildStatCard(
                                  title: 'Active',
                                  value: assignedJobs
                                      .where((r) => [
                                            'Accepted',
                                            'On The Way',
                                            'Reached'
                                          ].contains(_displayStatus(
                                              r['status'] ?? '')))
                                      .length
                                      .toString(),
                                  color: Colors.blue,
                                  icon: Icons.route,
                                ),
                                const SizedBox(width: 12),
                                _buildStatCard(
                                  title: 'Done',
                                  value: assignedJobs
                                      .where((r) =>
                                          _displayStatus(r['status'] ?? '') ==
                                          'Completed')
                                      .length
                                      .toString(),
                                  color: Colors.green,
                                  icon: Icons.check_circle_outline,
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            _buildSectionTitle(
                                'Active Pickups', Icons.assignment_outlined),
                            const SizedBox(height: 12),
                            if (assignedJobs.isEmpty)
                              _buildEmptyCard('No active pickup jobs')
                            else
                              ...assignedJobs.map(
                                  (req) => _buildAssignedJobCard(req as Map)),
                            const SizedBox(height: 20),
                            _buildSectionTitle(
                                'Available Nearby', Icons.location_searching),
                            const SizedBox(height: 12),
                            if (availableJobs.isEmpty)
                              _buildEmptyCard('No jobs available right now')
                            else
                              ...availableJobs.map(
                                  (req) => _buildAvailableJobCard(req as Map)),
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
