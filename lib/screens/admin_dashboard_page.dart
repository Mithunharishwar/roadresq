import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List requests = [];
  List mechanics = [];
  List hubs = [];
  List users = [];
  List tokens = [];
  List zones = [];
  bool loading = true;

  GoogleMapController? mapController;
  Set<Marker> markers = {};

  final SocketService socket = SocketService();

  final Map<String, String?> selectedMechanicByRequest = {};
  final Set<String> assigningRequests = {};

  /// Handles for this screen's socket listeners, cancelled in dispose().
  final List<SocketSubscription> _socketSubs = <SocketSubscription>[];

  // Token & Zone form controllers
  final TextEditingController tokenVehicleCtrl = TextEditingController();
  final TextEditingController tokenUserCtrl = TextEditingController();
  final TextEditingController tokenJobCtrl = TextEditingController();
  final TextEditingController tokenHubCtrl = TextEditingController();

  final TextEditingController zoneNameCtrl = TextEditingController();
  final TextEditingController zoneLatMinCtrl = TextEditingController();
  final TextEditingController zoneLatMaxCtrl = TextEditingController();
  final TextEditingController zoneLngMinCtrl = TextEditingController();
  final TextEditingController zoneLngMaxCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    socket.connect();

    // Show a SnackBar if the backend has been unreachable for 15s.
    _socketSubs.add(socket.addOfflineListener(() {
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

    setupSocketListeners();
    loadAdminData();
  }

  void setupSocketListeners() {
    // Every event simply refreshes the dashboard. Each registration is kept as
    // its own handle so dispose() can cancel exactly these — the previous
    // app-wide clearAllListeners() also unsubscribed every other open screen.
    void refresh(dynamic _) => loadAdminData(showLoader: false);

    _socketSubs
      ..add(socket.onNewRequest(refresh))
      ..add(socket.onRequestAssigned(refresh))
      ..add(socket.onStatusUpdated(refresh))
      ..add(socket.onMechanicLocationUpdated(refresh))
      ..add(socket.onMechanicOnlineUpdated(refresh))
      ..add(socket.onMechanicLocationGlobalUpdated(refresh))
      ..add(socket.onAssistantAssigned(refresh))
      ..add(socket.onAssistantOnlineUpdated(refresh))
      ..add(socket.onPaymentUpdated(refresh));
  }

  Future<void> loadAdminData({bool showLoader = true}) async {
    try {
      if (showLoader && mounted) setState(() => loading = true);

      final results = await Future.wait([
        ApiService.fetchAdminRequests(),
        ApiService.fetchAdminHubs(),
        ApiService.fetchAdminMechanics(),
        ApiService.getAdminUsers(),
        ApiService.getAdminTokens(),
        ApiService.getAdminZones(),
      ]);

      final reqs = results[0];
      final fetchedHubs = results[1];
      final fetchedMechanics = results[2];
      final fetchedUsers = results[3];
      final fetchedTokens = results[4];
      final fetchedZones = results[5];

      final Set<Marker> newMarkers = {};

      for (final req in reqs) {
        final request = req as Map;
        final location = request['location'];

        if (location != null &&
            location['lat'] != null &&
            location['lng'] != null) {
          final double lat = (location['lat'] as num).toDouble();
          final double lng = (location['lng'] as num).toDouble();
          final status = (request['status'] ?? 'pending').toString();

          newMarkers.add(
            Marker(
              markerId: MarkerId('req_${request['_id'] ?? request['id']}'),
              position: LatLng(lat, lng),
              infoWindow: InfoWindow(
                title: request['name'] ?? 'Customer',
                snippet: '${request['issue'] ?? ''} • $status',
              ),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                _getRequestMarkerHue(status),
              ),
            ),
          );
        }
      }

      if (!mounted) return;

      setState(() {
        requests = reqs;
        hubs = fetchedHubs;
        mechanics = fetchedMechanics;
        users = fetchedUsers;
        tokens = fetchedTokens;
        zones = fetchedZones;
        markers = newMarkers;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Admin load failed: $e')));
    }
  }

  double _getRequestMarkerHue(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return BitmapDescriptor.hueRed;
      case 'assigned':
        return BitmapDescriptor.hueOrange;
      case 'accepted':
        return BitmapDescriptor.hueAzure;
      case 'on_the_way':
      case 'on the way':
        return BitmapDescriptor.hueBlue;
      case 'reached':
        return BitmapDescriptor.hueViolet;
      case 'completed':
        return BitmapDescriptor.hueGreen;
      default:
        return BitmapDescriptor.hueRed;
    }
  }

  Color getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.red;
      case 'assigned':
        return Colors.orange;
      case 'accepted':
        return Colors.blue;
      case 'on_the_way':
      case 'on the way':
        return Colors.deepPurple;
      case 'reached':
        return Colors.teal;
      case 'completed':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  int get totalRequests => requests.length;
  int get pendingRequests => requests
      .where((r) =>
          ((r as Map)['status'] ?? '').toString().toLowerCase() == 'pending')
      .length;
  int get completedRequests => requests
      .where((r) =>
          ((r as Map)['status'] ?? '').toString().toLowerCase() == 'completed')
      .length;
  int get onlineMechanics =>
      mechanics.where((m) => (m as Map)['online'] == true).length;

  List<Map> getAvailableMechanicsForAssignment() {
    return mechanics
        .where((m) => (m as Map)['online'] == true)
        .map((m) => Map<String, dynamic>.from(m as Map))
        .toList();
  }

  Future<void> assignMechanic(Map req) async {
    final requestId = (req['_id'] ?? req['id'] ?? '').toString();
    final mechanicId = selectedMechanicByRequest[requestId];

    if (requestId.isEmpty || mechanicId == null || mechanicId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a mechanic first')));
      return;
    }

    try {
      setState(() => assigningRequests.add(requestId));
      await ApiService.adminAssignMechanic(
          requestId: requestId, mechanicId: mechanicId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mechanic assigned successfully')));
      await loadAdminData(showLoader: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Assignment failed: $e')));
    } finally {
      if (mounted) setState(() => assigningRequests.remove(requestId));
    }
  }

  // ==================== TOKEN ACTIONS ====================
  Future<void> handleCreateToken() async {
    try {
      await ApiService.createToken(
        vehicleId: tokenVehicleCtrl.text.trim(),
        userId: tokenUserCtrl.text.trim(),
        jobId:
            tokenJobCtrl.text.trim().isEmpty ? null : tokenJobCtrl.text.trim(),
        hubId:
            tokenHubCtrl.text.trim().isEmpty ? null : tokenHubCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Token created successfully')));
      tokenVehicleCtrl.clear();
      tokenUserCtrl.clear();
      tokenJobCtrl.clear();
      tokenHubCtrl.clear();
      await loadAdminData(showLoader: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Create token failed: $e')));
    }
  }

  Future<void> handleReleaseToken(String tokenId) async {
    try {
      await ApiService.releaseToken(tokenId: tokenId, releasedBy: 'admin');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Token released')));
      await loadAdminData(showLoader: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Release failed: $e')));
    }
  }

  Future<void> handleDeleteToken(String tokenId) async {
    try {
      await ApiService.deleteToken(tokenId);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Token deleted')));
      await loadAdminData(showLoader: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  // ==================== ZONE ACTIONS ====================
  Future<void> handleCreateZone() async {
    try {
      await ApiService.createZone(
        name: zoneNameCtrl.text.trim(),
        latMin: double.parse(zoneLatMinCtrl.text.trim()),
        latMax: double.parse(zoneLatMaxCtrl.text.trim()),
        lngMin: double.parse(zoneLngMinCtrl.text.trim()),
        lngMax: double.parse(zoneLngMaxCtrl.text.trim()),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Zone created')));
      zoneNameCtrl.clear();
      zoneLatMinCtrl.clear();
      zoneLatMaxCtrl.clear();
      zoneLngMinCtrl.clear();
      zoneLngMaxCtrl.clear();
      await loadAdminData(showLoader: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Create zone failed: $e')));
    }
  }

  Future<void> handleDeleteZone(String zoneId) async {
    try {
      await ApiService.deleteZone(zoneId);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Zone deleted')));
      await loadAdminData(showLoader: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  // ==================== USER ACTIONS ====================
  Future<void> handleDeleteUser(String userId) async {
    try {
      await ApiService.deleteUser(userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('User deleted')));
      await loadAdminData(showLoader: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    // Remove only THIS screen's listeners, not every screen's.
    for (final sub in _socketSubs) {
      sub.cancel();
    }
    _socketSubs.clear();
    mapController?.dispose();
    tokenVehicleCtrl.dispose();
    tokenUserCtrl.dispose();
    tokenJobCtrl.dispose();
    tokenHubCtrl.dispose();
    zoneNameCtrl.dispose();
    zoneLatMinCtrl.dispose();
    zoneLatMaxCtrl.dispose();
    zoneLngMinCtrl.dispose();
    zoneLngMaxCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        flexibleSpace: FlexibleSpaceBar(
          background: Stack(
            children: [
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
              // Firework glow blobs
              Positioned(
                top: -30,
                right: -20,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha((0.10 * 255).round()),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Positioned(
                bottom: -40,
                left: -10,
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    color:
                        const Color(0xFF1976D2).withAlpha((0.25 * 255).round()),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard), text: 'Overview'),
            Tab(icon: Icon(Icons.people), text: 'Users'),
            Tab(icon: Icon(Icons.build), text: 'Mechanics'),
            Tab(icon: Icon(Icons.confirmation_number), text: 'Tokens'),
            Tab(icon: Icon(Icons.map), text: 'Zones'),
          ],
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(),
                _buildUsersTab(),
                _buildMechanicsTab(),
                _buildTokensTab(),
                _buildZonesTab(),
              ],
            ),
    );
  }

  // ==================== OVERVIEW TAB ====================
  Widget _buildOverviewTab() {
    return RefreshIndicator(
      onRefresh: () => loadAdminData(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              _summaryCard('Total', totalRequests.toString(), Colors.blue,
                  Icons.list_alt),
              const SizedBox(width: 10),
              _summaryCard('Pending', pendingRequests.toString(), Colors.red,
                  Icons.pending_actions),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _summaryCard('Completed', completedRequests.toString(),
                  Colors.green, Icons.check_circle),
              const SizedBox(width: 10),
              _summaryCard('Online Mech', onlineMechanics.toString(),
                  Colors.teal, Icons.build_circle),
            ],
          ),
          const SizedBox(height: 20),
          const Text('Live Operations Map',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Container(
            height: 300,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 8)
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: GoogleMap(
              initialCameraPosition: const CameraPosition(
                target: LatLng(13.0827, 80.2707),
                zoom: 11,
              ),
              onMapCreated: (c) => mapController = c,
              markers: markers,
            ),
          ),
          const SizedBox(height: 20),
          const Text('Live Requests',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (requests.isEmpty)
            const Text('No requests found')
          else
            ...requests.map((e) => _buildRequestCard(e as Map)),
          const SizedBox(height: 20),
          const Text('Rescue Hubs',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (hubs.isEmpty)
            const Text('No hubs found')
          else
            ...hubs.map((e) => _buildHubCard(e as Map)),
        ],
      ),
    );
  }

  Widget _summaryCard(String title, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(value,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
            const SizedBox(height: 4),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestCard(Map req) {
    final status = (req['status'] ?? '').toString();
    final requestId = (req['_id'] ?? req['id'] ?? '').toString();
    final mechanicId = req['mechanicId']?.toString();
    final isPending = status.toLowerCase() == 'pending';
    final assignableMechanics = getAvailableMechanicsForAssignment();
    final isAssigning = assigningRequests.contains(requestId);

    selectedMechanicByRequest.putIfAbsent(requestId, () => mechanicId);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(req['name'] ?? 'Customer',
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          Text('Issue: ${req['issue'] ?? ''}'),
          Text('Vehicle: ${req['vehicle'] ?? ''}'),
          Text('Location: ${req['locationText'] ?? ''}'),
          Text('Phone: ${req['phone'] ?? ''}'),
          const SizedBox(height: 10),
          Row(children: [
            const Text('Status: ',
                style: TextStyle(fontWeight: FontWeight.bold)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: getStatusColor(status),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(status,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 10),
          Text(
              'Mechanic: ${mechanicId == null || mechanicId.isEmpty ? 'Not assigned' : mechanicId}'),
          if (isPending) ...[
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: selectedMechanicByRequest[requestId],
              decoration: InputDecoration(
                labelText: 'Assign Mechanic',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: assignableMechanics.map((mech) {
                final id = (mech['_id'] ?? mech['id'] ?? '').toString();
                final name = (mech['name'] ?? 'Mechanic').toString();
                return DropdownMenuItem<String>(
                  value: id,
                  child: Text(name),
                );
              }).toList(),
              onChanged: (value) =>
                  setState(() => selectedMechanicByRequest[requestId] = value),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isAssigning ? null : () => assignMechanic(req),
                icon: isAssigning
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.assignment_ind),
                label: Text(isAssigning ? 'Assigning...' : 'Assign Mechanic'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D47A1),
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHubCard(Map hub) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(hub['name'] ?? 'Hub',
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          Text('Address: ${hub['address'] ?? ''}'),
          Text('Zone: ${hub['zone'] ?? ''}'),
        ],
      ),
    );
  }

  // ==================== USERS TAB ====================
  Widget _buildUsersTab() {
    return RefreshIndicator(
      onRefresh: () => loadAdminData(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Total Users: ${users.length}',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (users.isEmpty)
            const Text('No users found')
          else
            ...users.map((e) {
              final user = e as Map;
              final userId = (user['_id'] ?? user['id'] ?? '').toString();
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFD32F2F),
                    child: Icon(Icons.person, color: Colors.white),
                  ),
                  title: Text(user['name'] ?? 'User'),
                  subtitle:
                      Text('${user['email'] ?? ''} • ${user['phone'] ?? ''}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => handleDeleteUser(userId),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  // ==================== MECHANICS TAB ====================
  Widget _buildMechanicsTab() {
    return RefreshIndicator(
      onRefresh: () => loadAdminData(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Total Mechanics: ${mechanics.length}',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (mechanics.isEmpty)
            const Text('No mechanics found')
          else
            ...mechanics.map((e) {
              final mech = e as Map;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 8)
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const CircleAvatar(
                        backgroundColor: Color(0xFF0D47A1),
                        child: Icon(Icons.build, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(mech['name'] ?? 'Mechanic',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: mech['online'] == true
                              ? Colors.green
                              : Colors.grey,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          mech['online'] == true ? 'Online' : 'Offline',
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Text('Phone: ${mech['phone'] ?? ''}'),
                    Text('Email: ${mech['email'] ?? ''}'),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // ==================== TOKENS TAB ====================
  Widget _buildTokensTab() {
    return RefreshIndicator(
      onRefresh: () => loadAdminData(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Create Token',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                TextField(
                    controller: tokenVehicleCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Vehicle ID', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(
                    controller: tokenUserCtrl,
                    decoration: const InputDecoration(
                        labelText: 'User ID', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(
                    controller: tokenJobCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Job ID (optional)',
                        border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(
                    controller: tokenHubCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Hub ID (optional)',
                        border: OutlineInputBorder())),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: handleCreateToken,
                  child: const Text('Create Token'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Tokens (${tokens.length})',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (tokens.isEmpty)
            const Text('No tokens found')
          else
            ...tokens.map((e) {
              final token = e as Map;
              final tokenId = (token['_id'] ?? token['id'] ?? '').toString();
              final status = (token['status'] ?? 'created').toString();
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(
                    Icons.confirmation_number,
                    color: status == 'released' ? Colors.green : Colors.orange,
                  ),
                  title: Text('Token: ${tokenId.substring(0, 8)}...'),
                  subtitle: Text(
                      'Vehicle: ${token['vehicleId'] ?? ''} • Status: $status'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (status != 'released')
                        IconButton(
                          icon: const Icon(Icons.check_circle,
                              color: Colors.green),
                          onPressed: () => handleReleaseToken(tokenId),
                        ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => handleDeleteToken(tokenId),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  // ==================== ZONES TAB ====================
  Widget _buildZonesTab() {
    return RefreshIndicator(
      onRefresh: () => loadAdminData(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Create Zone',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                TextField(
                    controller: zoneNameCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Zone Name', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: zoneLatMinCtrl,
                          decoration: const InputDecoration(
                              labelText: 'Lat Min',
                              border: OutlineInputBorder()),
                          keyboardType: TextInputType.number)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: TextField(
                          controller: zoneLatMaxCtrl,
                          decoration: const InputDecoration(
                              labelText: 'Lat Max',
                              border: OutlineInputBorder()),
                          keyboardType: TextInputType.number)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: zoneLngMinCtrl,
                          decoration: const InputDecoration(
                              labelText: 'Lng Min',
                              border: OutlineInputBorder()),
                          keyboardType: TextInputType.number)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: TextField(
                          controller: zoneLngMaxCtrl,
                          decoration: const InputDecoration(
                              labelText: 'Lng Max',
                              border: OutlineInputBorder()),
                          keyboardType: TextInputType.number)),
                ]),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: handleCreateZone,
                  child: const Text('Create Zone'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Zones (${zones.length})',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (zones.isEmpty)
            const Text('No zones found')
          else
            ...zones.map((e) {
              final zone = e as Map;
              final zoneId = (zone['_id'] ?? zone['id'] ?? '').toString();
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.map, color: Color(0xFF0D47A1)),
                  title: Text(zone['name'] ?? 'Zone'),
                  subtitle: Text(
                    'Lat: ${zone['latMin'] ?? ''}-${zone['latMax'] ?? ''}, Lng: ${zone['lngMin'] ?? ''}-${zone['lngMax'] ?? ''}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => handleDeleteZone(zoneId),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
