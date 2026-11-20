// FILE: lib/features/garage/garage_dashboard.dart
/// GarageDashboard — the garage's working surface.
///
/// WHAT WAS WRONG BEFORE
/// This screen was decoration. It read `GET /api/garage/<id>/jobs`, which only
/// returns requests that already carry this garage's id — and nothing in the
/// backend ever wrote that field (verified in Mongo: 0 of 59 requests had a
/// garageId and `tokens` was empty). So the list was permanently empty, and the
/// single button on each card said "Verification portal coming soon".
///
/// A garage therefore had no way to acquire work, start it, finish it, or take
/// money for it. This version wires the real lifecycle that the backend already
/// enforces (backend/status_machine.py):
///
///   intake  -> `PUT /api/rescueRequests/<id>/garage`   (handover to this garage)
///   work    -> `PUT /api/rescueRequests/<id>/status`   (SERVICE_STARTED … CLOSED)
///   money   -> `PUT /api/rescueRequests/<id>/payment`  (amount + method)
///
/// The status buttons never guess: the backend validates every transition and
/// answers 409 with the states it WILL accept, and those are offered instead.
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/rq_widgets.dart';
import '../../core/utils/error_handler.dart';
import '../../core/session/app_session.dart';
import '../../services/api_service.dart';
import '../../services/session_service.dart';
import '../../services/socket_service.dart';
import '../../screens/map_screen.dart';
import '../../widgets/module_switcher.dart';
import '../../screens/role_selection_screen.dart';

class GarageDashboard extends StatefulWidget {
  const GarageDashboard({super.key});

  @override
  State<GarageDashboard> createState() => _GarageDashboardState();
}

class _GarageDashboardState extends State<GarageDashboard> {
  static const Color _purple = Color(0xFF7E57C2);

  String garageId = '';
  String garageName = 'Garage';
  String garagePhone = '';

  List<Map<String, dynamic>> jobs = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> inbox = <Map<String, dynamic>>[];

  bool loading = true;
  String? error;

  /// Id of the job with an action in flight — prevents double taps from firing
  /// two status transitions for the same request.
  String? busyJobId;

  /// Live updates. The garage used to fetch its lists once and then go stale:
  /// a request assigned or completed by the mechanic/assistant never appeared
  /// until the user pressed Refresh. It now follows the same realtime events as
  /// the other three roles, so one job is one shared record.
  final List<SocketSubscription> _socketSubs = <SocketSubscription>[];

  @override
  void initState() {
    super.initState();
    _bootstrap();
    final socket = SocketService();
    socket.connect();
    void refresh(dynamic _) {
      if (!mounted) return;
      _loadAll(showSpinner: false);
    }

    _socketSubs.add(socket.onNewRequest(refresh));
    _socketSubs.add(socket.onRequestAssigned(refresh));
    _socketSubs.add(socket.onStatusUpdated(refresh));
  }

  @override
  void dispose() {
    for (final sub in _socketSubs) {
      sub.cancel();
    }
    _socketSubs.clear();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      garageId = prefs.getString('garageId') ?? '';
      garageName = prefs.getString('garageName') ?? 'Garage';
      garagePhone = prefs.getString('garagePhone') ?? '';
    });
    await _loadAll();
  }

  Future<void> _loadAll({bool showSpinner = true}) async {
    if (!mounted) return;
    setState(() {
      if (showSpinner) loading = true;
      error = null;
    });

    if (garageId.isEmpty) {
      setState(() {
        loading = false;
        error = 'No garage is signed in on this device. '
            'Log in again from the role selection screen.';
      });
      return;
    }

    try {
      // Both lists in parallel: the queue is what the garage owns, the inbox is
      // what it could take on.
      final results = await Future.wait([
        ApiService.fetchGarageJobs(garageId),
        ApiService.fetchGarageInbox(garageId),
      ]);

      if (!mounted) return;
      setState(() {
        jobs = _asMaps(results[0]);
        inbox = _asMaps(results[1]);
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = ErrorHandler.getFriendlyMessage(e);
        loading = false;
      });
    }
  }

  List<Map<String, dynamic>> _asMaps(List<dynamic> raw) => raw
      .whereType<Map<dynamic, dynamic>>()
      .map(Map<String, dynamic>.from)
      .toList();

  // ── Actions ───────────────────────────────────────────────────────────────

  /// Takes a request in: writes this garage's id onto it, after which it shows
  /// up in the garage's own job list.
  Future<void> _claim(Map<String, dynamic> request) async {
    final id = _idOf(request);
    if (id.isEmpty) return;
    setState(() => busyJobId = id);

    try {
      await ApiService.linkRequestToGarage(requestId: id, garageId: garageId);
      if (!mounted) return;
      _toast('Request ${_short(id)} is now in your queue');
      await _loadAll(showSpinner: false);
    } catch (e) {
      if (!mounted) return;
      _toast(ErrorHandler.getFriendlyMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => busyJobId = null);
    }
  }

  /// Moves a job to its next lifecycle state.
  ///
  /// [target] is used when the user picked a specific state from the server's
  /// own `allowedNextStates`; otherwise the preferred next step is attempted.
  Future<void> _advance(Map<String, dynamic> job, {String? target}) async {
    final id = _idOf(job);
    if (id.isEmpty) return;

    final wanted = target ?? _preferredNext(_canonical(job));
    if (wanted == null) {
      _toast('This job has no further step in the current state.');
      return;
    }

    setState(() => busyJobId = id);
    try {
      final attempt =
          await ApiService.tryUpdateRequestStatus(requestId: id, status: wanted);

      if (!mounted) return;

      if (attempt.ok) {
        _toast('${_label(wanted)} recorded');
        await _loadAll(showSpinner: false);
        return;
      }

      // The state machine refused. It told us what it WOULD accept — offer that
      // rather than a dead end.
      if (attempt.allowedNext.isNotEmpty) {
        final chosen = await _pickAllowedState(attempt.allowedNext, attempt.message);
        if (chosen != null && mounted) {
          await _advance(job, target: chosen);
        }
        return;
      }

      _toast(attempt.message, isError: true);
    } finally {
      if (mounted) setState(() => busyJobId = null);
    }
  }

  Future<String?> _pickAllowedState(List<String> allowed, String reason) async {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        decoration: BoxDecoration(
          color: AppTheme.surfaceOf(context),
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Choose the next step', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(reason, style: TextStyle(color: AppTheme.mutedOf(context), fontSize: 13)),
            const SizedBox(height: 14),
            ...allowed.map(
              (state) => ListTile(
                leading: const Icon(Icons.arrow_forward, color: _purple),
                title: Text(_label(state)),
                subtitle: Text(state, style: const TextStyle(fontSize: 11)),
                onTap: () => Navigator.pop(sheetContext, state),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Records money against a job. The amount defaults to whatever the request
  /// already carries so the common case is one tap.
  Future<void> _collectPayment(Map<String, dynamic> job) async {
    final id = _idOf(job);
    if (id.isEmpty) return;

    final existing = _amountOf(job);
    final amountController =
        TextEditingController(text: existing > 0 ? existing.toStringAsFixed(0) : '');
    String method = 'cash';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Record payment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount (₹)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: method,
                decoration: const InputDecoration(
                  labelText: 'Method',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'upi', child: Text('UPI')),
                  DropdownMenuItem(value: 'card', child: Text('Card')),
                ],
                onChanged: (value) => setDialogState(() => method = value ?? 'cash'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    final amount = double.tryParse(amountController.text.trim()) ?? 0;
    amountController.dispose();
    if (confirmed != true || !mounted) return;

    if (amount <= 0) {
      _toast('Enter an amount greater than zero.', isError: true);
      return;
    }

    setState(() => busyJobId = id);
    try {
      await ApiService.updatePaymentStatus(
        requestId: id,
        amount: amount,
        paymentStatus: 'completed',
        paymentId: 'garage-$id-${DateTime.now().millisecondsSinceEpoch}',
        paymentMethod: method,
      );
      // Payment is recorded; move the lifecycle forward too, but a refusal here
      // must not undo the payment.
      final attempt = await ApiService.tryUpdateRequestStatus(
        requestId: id,
        status: 'PAYMENT_COMPLETED',
      );
      if (!mounted) return;
      _toast(
        attempt.ok
            ? 'Payment of ₹${amount.toStringAsFixed(0)} recorded'
            : 'Payment of ₹${amount.toStringAsFixed(0)} saved. ${attempt.message}',
      );
      await _loadAll(showSpinner: false);
    } catch (e) {
      if (!mounted) return;
      _toast(ErrorHandler.getFriendlyMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => busyJobId = null);
    }
  }

  Future<void> _callCustomer(Map<String, dynamic> job) async {
    final phone = (job['phone'] ?? '').toString().replaceAll(RegExp(r'[^0-9+]'), '');
    if (phone.isEmpty) {
      _toast('No phone number on this request.', isError: true);
      return;
    }
    final uri = Uri(scheme: 'tel', path: phone);
    if (!await launchUrl(uri)) {
      _toast('No dialer app available.', isError: true);
    }
  }

  Future<void> _navigate(Map<String, dynamic> job) async {
    final coords = _coordsOf(job);
    final query = coords ?? (job['locationText'] ?? '').toString();
    if (query.isEmpty) {
      _toast('This request has no location.', isError: true);
      return;
    }
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _toast('Could not open a map app.', isError: true);
    }
  }

  /// Looks up an arbitrary request by id — the garage-side equivalent of the
  /// mechanic's job search, and the fallback when a customer quotes an id.
  Future<void> _findJobById() async {
    final controller = TextEditingController();
    final id = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Find a job'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Request ID',
            hintText: 'Paste the id from the customer or admin',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Search'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (id == null || id.isEmpty || !mounted) return;

    try {
      final request = await ApiService.fetchRequestById(id);
      if (!mounted) return;
      await _showJobSheet(request, canClaim: (request['garageId'] ?? '') == '');
    } catch (e) {
      if (!mounted) return;
      _toast(ErrorHandler.getFriendlyMessage(e), isError: true);
    }
  }

  Future<void> _showJobSheet(Map<String, dynamic> job, {bool canClaim = false}) {
    final status = _canonical(job);
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        decoration: BoxDecoration(
          color: AppTheme.surfaceOf(context),
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Job ${_short(_idOf(job))}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              RQ.infoRow(Icons.person_outline, 'Customer',
                  (job['name'] ?? '—').toString()),
              RQ.infoRow(Icons.phone_outlined, 'Phone',
                  (job['phone'] ?? '—').toString()),
              RQ.infoRow(Icons.build_circle_outlined, 'Issue',
                  (job['issue'] ?? '—').toString()),
              RQ.infoRow(Icons.directions_car_outlined, 'Vehicle',
                  (job['vehicle'] ?? '—').toString()),
              RQ.infoRow(Icons.place_outlined, 'Location',
                  (job['locationText'] ?? '—').toString()),
              RQ.infoRow(Icons.flag_outlined, 'Status', _label(status)),
              if ((job['garageId'] ?? '') != '')
                RQ.infoRow(Icons.garage_outlined, 'Garage', job['garageId'].toString()),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _callCustomer(job),
                      icon: const Icon(Icons.call),
                      label: const Text('Call'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _navigate(job),
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Map'),
                    ),
                  ),
                ],
              ),
              if (canClaim) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      Navigator.pop(sheetContext);
                      await _claim(job);
                    },
                    icon: const Icon(Icons.add_task),
                    label: const Text('Take this job'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showInbox() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        decoration: BoxDecoration(
          color: AppTheme.surfaceOf(context),
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.inbox_outlined, color: _purple),
                const SizedBox(width: 8),
                Text('Open requests (${inbox.length})',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            Text('Requests not yet handed to any garage. Taking one links it to you.', style: TextStyle(fontSize: 12.5, color: AppTheme.mutedOf(context)),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: inbox.isEmpty
                  ? Center(
                      child: Text('Nothing waiting right now.',
                          style: TextStyle(color: AppTheme.mutedOf(context))),
                    )
                  : ListView.separated(
                      itemCount: inbox.length,
                      separatorBuilder: (_, __) => const Divider(height: 18),
                      itemBuilder: (context, index) {
                        final request = inbox[index];
                        final id = _idOf(request);
                        final busy = busyJobId == id;
                        return Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${request['issue'] ?? 'Request'} • ${request['vehicle'] ?? ''}',
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${request['name'] ?? 'Customer'} • ${request['locationText'] ?? ''}',
                                    style: TextStyle(fontSize: 12, color: AppTheme.mutedOf(context)),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: busy ? null : () => _claim(request),
                              style: FilledButton.styleFrom(backgroundColor: _purple),
                              child: busy
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Text('Take'),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSummary() async {
    final open = jobs.where((j) => !_isFinished(j)).length;
    final collected = jobs
        .where((j) => (j['paymentStatus'] ?? '').toString().toLowerCase() == 'success' ||
            (j['paymentStatus'] ?? '').toString().toLowerCase() == 'completed')
        .fold<double>(0, (sum, j) => sum + _amountOf(j));

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        decoration: BoxDecoration(
          color: AppTheme.surfaceOf(context),
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Today's board", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            RQ.infoRow(Icons.assignment_outlined, 'In queue', '${jobs.length}'),
            RQ.infoRow(Icons.pending_actions_outlined, 'Still open', '$open'),
            RQ.infoRow(Icons.inbox_outlined, 'Unclaimed nearby', '${inbox.length}'),
            RQ.infoRow(Icons.payments_outlined, 'Collected',
                '₹${collected.toStringAsFixed(0)}'),
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _idOf(Map<String, dynamic> job) =>
      (job['_id'] ?? job['id'] ?? '').toString();

  static String _short(String id) => id.length > 6 ? id.substring(0, 6) : id;

  static String _canonical(Map<String, dynamic> job) {
    final raw = (job['statusCanonical'] ?? job['status'] ?? '').toString().toUpperCase();
    // Legacy labels the collection still holds.
    if (raw == 'PENDING') return 'CREATED';
    if (raw == 'ASSIGNED') return 'MECHANIC_ASSIGNED';
    if (raw == 'COMPLETED') return 'SERVICE_COMPLETED';
    if (raw == 'CLOSED') return 'CLOSED';
    return raw;
  }

  static bool _isFinished(Map<String, dynamic> job) {
    const done = ['CLOSED', 'CANCELLED', 'PAYMENT_COMPLETED'];
    return done.contains(_canonical(job));
  }

  static double _amountOf(Map<String, dynamic> job) {
    final raw = job['amount'];
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? 0;
  }

  /// `"lat,lng"` for maps, or null when the request carries no coordinates.
  static String? _coordsOf(Map<String, dynamic> job) {
    final location = job['location'];
    if (location is Map && location['lat'] != null && location['lng'] != null) {
      return '${location['lat']},${location['lng']}';
    }
    if (job['lat'] != null && job['lng'] != null) {
      return '${job['lat']},${job['lng']}';
    }
    return null;
  }

  /// The lifecycle step a garage would normally take next. The backend has the
  /// final say; this is only the first attempt.
  /// The garage's legal next step.
  ///
  /// A garage takes over a vehicle that has already physically arrived, so it
  /// starts at ARRIVED. The previous version jumped from CREATED/SEARCHING
  /// straight to SERVICE_STARTED, which the state machine rejects (CREATED may
  /// only become SEARCHING or CANCELLED) — the same "illegal transition" class
  /// of bug the mechanic screen had. States before ARRIVED belong to the field
  /// crew, and the garage now waits for them instead of fighting the server for
  /// them.
  static String? _preferredNext(String canonical) {
    switch (canonical) {
      case 'ARRIVED':
        return 'SERVICE_STARTED';
      case 'SERVICE_STARTED':
        return 'SERVICE_COMPLETED';
      case 'SERVICE_COMPLETED':
        return 'PAYMENT_PENDING';
      case 'PAYMENT_PENDING':
        return 'PAYMENT_COMPLETED';
      default:
        return null;
    }
  }

  /// True while the field crew still owns the job — the garage's action button
  /// is disabled with this explanation instead of firing a transition the
  /// backend will refuse.
  static bool _awaitingCrew(String canonical) {
    const fieldStates = {
      'CREATED',
      'SEARCHING',
      'MECHANIC_ASSIGNED',
      'MECHANIC_ACCEPTED',
      'MECHANIC_EN_ROUTE',
    };
    return fieldStates.contains(canonical);
  }

  /// Action label for a lifecycle state.
  static String _label(String state) {
    switch (state.toUpperCase()) {
      case 'CREATED':
      case 'SEARCHING':
        return 'Received';
      case 'MECHANIC_ASSIGNED':
      case 'MECHANIC_ACCEPTED':
      case 'MECHANIC_EN_ROUTE':
        return 'Crew on the way';
      case 'ARRIVED':
        return 'Vehicle arrived';
      case 'SERVICE_STARTED':
        return 'Service started';
      case 'SERVICE_COMPLETED':
        return 'Service ready';
      case 'PAYMENT_PENDING':
        return 'Payment pending';
      case 'PAYMENT_COMPLETED':
        return 'Paid';
      case 'CLOSED':
        return 'Closed';
      case 'CANCELLED':
        return 'Cancelled';
      default:
        return state;
    }
  }

  /// Primary button label for the next step.
  static String _nextLabel(Map<String, dynamic> job) {
    switch (_canonical(job)) {
      case 'CREATED':
      case 'SEARCHING':
      case 'MECHANIC_ASSIGNED':
      case 'MECHANIC_ACCEPTED':
      case 'MECHANIC_EN_ROUTE':
        return 'Waiting for the crew';
      case 'ARRIVED':
        return 'Start service';
      case 'SERVICE_STARTED':
        return 'Mark service done';
      case 'SERVICE_COMPLETED':
        return 'Ready for pickup';
      case 'PAYMENT_PENDING':
        return 'Record payment';
      default:
        return 'Advance';
    }
  }

  /// "Ravi (mechanic) • Rider Asha" — empty when nobody is assigned yet.
  static String _crewLine(Map<String, dynamic> job) {
    final parts = <String>[];
    final mechanic = (job['mechanicName'] ?? '').toString().trim();
    final assistant = (job['assistantName'] ?? '').toString().trim();
    if (mechanic.isNotEmpty) parts.add('$mechanic (mechanic)');
    if (assistant.isNotEmpty) parts.add('$assistant (rider)');
    return parts.join(' • ');
  }

  /// Latest crew position, if the job carries one.
  static (double, double)? _crewPosition(Map<String, dynamic> job) {
    for (final key in <String>['mechanicLocation', 'assistantLocation']) {
      final raw = job[key];
      if (raw is Map) {
        final lat = raw['lat'];
        final lng = raw['lng'];
        if (lat is num && lng is num && (lat != 0 || lng != 0)) {
          return (lat.toDouble(), lng.toDouble());
        }
      }
    }
    return null;
  }

  /// End the garage session properly.
  ///
  /// This used to be `Navigator.pop`, which is wrong in two ways now that the
  /// dashboard lives inside a tab shell: popping it left an empty navigator (a
  /// black screen), and the garage identity stayed in SharedPreferences, so the
  /// next launch silently signed the same garage back in.
  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('garageId');
    await prefs.remove('garageName');
    await prefs.remove('garagePhone');

    // The garage keys are not what the splash screen checks — AppSession is —
    // so clearing them alone left the same garage signed in on next launch.
    await AppSession.clear();
    await SessionService.clear();
    SocketService().disconnect();

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
      (route) => false,
    );
  }

  static Color _statusColor(String canonical) {
    switch (canonical) {
      case 'SERVICE_STARTED':
        return Colors.orange;
      case 'SERVICE_COMPLETED':
        return Colors.blue;
      case 'PAYMENT_PENDING':
        return Colors.deepPurple;
      case 'PAYMENT_COMPLETED':
      case 'CLOSED':
        return Colors.green;
      case 'CANCELLED':
        return Colors.red;
      default:
        return _purple;
    }
  }

  void _toast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : null,
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundOf(context),
      body: SafeArea(
        child: Column(
          children: [
            RQ.moduleHeader(
              title: 'Garage Dashboard',
              subtitle: garageId.isEmpty
                  ? 'No garage signed in'
                  : '$garageName • ${jobs.length} job(s) in queue',
              icon: Icons.garage,
              colors: const [Color(0xFF4A148C), Color(0xFF7E57C2)],
              glow: _purple,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton.small(
                    heroTag: 'garage_modules',
                    backgroundColor: Colors.white,
                    onPressed: () => ModuleSwitcher.open(context),
                    child: const Icon(Icons.grid_view_rounded,
                        color: _purple, size: 20),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton.small(
                    heroTag: 'garage_home',
                    backgroundColor: Colors.white,
                    onPressed: _logout,
                    child: const Icon(Icons.logout, color: _purple),
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
                    const Icon(Icons.qr_code_scanner, color: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        garagePhone.isEmpty
                            ? garageName
                            : '$garageName • $garagePhone',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    if (inbox.isNotEmpty)
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.amber,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${inbox.length} open',
                          style: TextStyle(
                            color: AppTheme.textOf(context),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppTheme.backgroundOf(context),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(30)),
                ),
                child: RefreshIndicator(
                  onRefresh: () => _loadAll(showSpinner: false),
                  child: _buildBody(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (error != null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 60),
          const Icon(Icons.cloud_off, size: 48, color: Colors.black26),
          const SizedBox(height: 16),
          Text(error!, textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.mutedOf(context))),
          const SizedBox(height: 16),
          Center(
            child: ElevatedButton(
              onPressed: () => _loadAll(),
              style: ElevatedButton.styleFrom(backgroundColor: _purple),
              child: const Text('Retry'),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            RQ.statCard(
              title: 'Queue',
              value: jobs.where((j) => !_isFinished(j)).length.toString(),
              color: _purple,
              icon: Icons.pending_actions_outlined,
            ),
            const SizedBox(width: 10),
            RQ.statCard(
              title: 'In service',
              value: jobs
                  .where((j) => _canonical(j) == 'SERVICE_STARTED')
                  .length
                  .toString(),
              color: Colors.orange,
              icon: Icons.build_outlined,
            ),
            const SizedBox(width: 10),
            RQ.statCard(
              title: 'Ready',
              value: jobs
                  .where((j) => _canonical(j) == 'SERVICE_COMPLETED')
                  .length
                  .toString(),
              color: Colors.blue,
              icon: Icons.task_alt,
            ),
          ],
        ),
        const SizedBox(height: 18),
        RQ.sectionTitle('What do you want to do?', Icons.dashboard_customize_outlined,
            _purple),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: RQ.quickAction(
                icon: Icons.inbox_outlined,
                label: 'Claim work',
                color: _purple,
                onTap: _showInbox,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: RQ.quickAction(
                icon: Icons.search,
                label: 'Find job',
                color: Colors.blue,
                onTap: _findJobById,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: RQ.quickAction(
                icon: Icons.dashboard_outlined,
                label: 'Summary',
                color: Colors.green,
                onTap: _showSummary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: RQ.quickAction(
                icon: Icons.refresh,
                label: 'Refresh',
                color: Colors.orange,
                onTap: () => _loadAll(showSpinner: false),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        RQ.sectionTitle('Jobs in this garage', Icons.assignment_outlined, _purple),
        const SizedBox(height: 10),
        if (jobs.isEmpty)
          RQ.emptyCard(
            'No jobs yet. Take one from "Claim work" to start — the vehicle is '
            'then yours to service and bill.',
            icon: Icons.assignment_outlined,
          )
        else
          ...jobs.map(_buildJobCard),
      ],
    );
  }

  Widget _buildJobCard(Map<String, dynamic> job) {
    final id = _idOf(job);
    final canonical = _canonical(job);
    final busy = busyJobId == id;
    final payable = canonical == 'PAYMENT_PENDING' ||
        canonical == 'SERVICE_COMPLETED' ||
        canonical == 'SERVICE_STARTED';
    final finished = _isFinished(job);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RQ.statusPill(_label(canonical), _statusColor(canonical)),
              const Spacer(),
              Text('Job #${_short(id)}',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            (job['name'] ?? 'Customer').toString(),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            [
              if ((job['issue'] ?? '').toString().isNotEmpty) job['issue'].toString(),
              if ((job['vehicle'] ?? '').toString().isNotEmpty) job['vehicle'].toString(),
            ].join(' • '),
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            (job['locationText'] ?? 'Location shared in app').toString(),
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
          if (_amountOf(job) > 0) ...[
            const SizedBox(height: 6),
            Text(
              '₹${_amountOf(job).toStringAsFixed(0)} • ${(job['paymentStatus'] ?? 'unpaid')}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
          // Who is actually coming. The garage used to see only the customer
          // and a status, so it could not tell whether a crew had been assigned
          // or where that crew was.
          if (_crewLine(job).isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.engineering_outlined,
                    size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _crewLine(job),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ),
              ],
            ),
          ],
          if (_crewPosition(job) != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  final pos = _crewPosition(job)!;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MapScreen(
                        latitude: pos.$1,
                        longitude: pos.$2,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.near_me_outlined, size: 18),
                label: const Text('Track crew live'),
                style: TextButton.styleFrom(foregroundColor: _purple),
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (!finished)
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: busy || (_awaitingCrew(canonical) &&
                        canonical != 'PAYMENT_PENDING')
                    ? null
                    : () => canonical == 'PAYMENT_PENDING'
                        ? _collectPayment(job)
                        : _advance(job),
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(canonical == 'PAYMENT_PENDING'
                        ? Icons.payments_outlined
                        : Icons.arrow_forward),
                label: Text(_nextLabel(job)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _purple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          if (payable && canonical != 'PAYMENT_COMPLETED') ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: OutlinedButton.icon(
                onPressed: busy ? null : () => _collectPayment(job),
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: const Text('Collect payment'),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () => _callCustomer(job),
                  icon: const Icon(Icons.call, size: 18),
                  label: const Text('Call'),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: () => _navigate(job),
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('Map'),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: () => _showJobSheet(job),
                  icon: const Icon(Icons.info_outline, size: 18),
                  label: const Text('Details'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
