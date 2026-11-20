// IMPORTANT: Set Firestore Rules to allow read/write for testing
import 'package:flutter/material.dart';
import '../core/session/app_session.dart';
import '../services/api_service.dart';
import '../services/activity_service.dart';
import '../services/token_service.dart';
import '../services/crew_dispatch_service.dart';
import '../services/zone_security_service.dart';
import 'request_status_screen.dart';

class RescueRequestScreen extends StatefulWidget {
  final String currentLocationText;
  final double latitude;
  final double longitude;
  final String? predictedIssue;
  final double? predictedConfidence;

  const RescueRequestScreen({
    super.key,
    required this.currentLocationText,
    required this.latitude,
    required this.longitude,
    this.predictedIssue,
    this.predictedConfidence,
  });

  @override
  State<RescueRequestScreen> createState() => _RescueRequestScreenState();
}

class _RescueRequestScreenState extends State<RescueRequestScreen> {
  String? selectedIssue;
  String? selectedVehicle;
  bool isLoading = false;
  final TokenService _tokenService = TokenService();
  final CrewDispatchService _dispatchService = CrewDispatchService();
  final ZoneSecurityService _zoneService = ZoneSecurityService();

  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();

  /// §12 — free-text note plus the signed-in user id, so the job is linked to
  /// the account that created it and the mechanic gets the detail.
  final TextEditingController noteController = TextEditingController();

  static const Map<String, IconData> _issueIcons = <String, IconData>{
    'Flat Tyre': Icons.tire_repair,
    'Battery Problem': Icons.battery_alert,
    'Fuel Delivery': Icons.local_gas_station,
    'Engine Trouble': Icons.car_repair,
    'Towing': Icons.local_shipping,
    'General Service': Icons.build,
  };

  final List<String> issues = [
    'Flat Tyre',
    'Battery Problem',
    'Fuel Delivery',
    'Engine Trouble',
    'Towing',
    'General Service',
    'Coolant Leak', // FIXED: Capitalized
    'Engine Smoke', // FIXED: Capitalized
    'Battery Corrosion', // FIXED: Capitalized + space
  ];

  final List<String> vehicles = [
    'Bike',
    'Scooter',
    'Car',
    'SUV',
    'Van',
    'Truck',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.predictedIssue != null) {
      // Convert "battery_corrosion" -> "Battery Corrosion"
      String formatted = widget.predictedIssue!
          .replaceAll('_', ' ')
          .split(' ')
          .map((w) => w.isNotEmpty ? w[0].toUpperCase() + w.substring(1) : '')
          .join(' ');

      // Only set if it exists in our list
      if (issues.contains(formatted)) {
        selectedIssue = formatted;
      }
    }
  }

  Future<void> _submitRescueRequest() async {
    if (selectedIssue == null || selectedVehicle == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select issue and vehicle')),
      );
      return;
    }
    if (nameController.text.trim().isEmpty ||
        phoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter name and phone number')),
      );
      return;
    }
    if (phoneController.text.trim().length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid phone number')),
      );
      return;
    }

    setState(() => isLoading = true);
    try {
      // Create the request in the RoadResQ backend.
      //
      // This used to fall back to writing the request straight into the
      // Firestore `requests` collection when the backend was unreachable. That
      // fallback could never work — the app holds no Firebase Auth session, so
      // the write was denied — and it converted a clear "backend unreachable"
      // into an opaque permission-denied error. A rescue request also has to be
      // recorded server-side, or no crew can ever be dispatched to it.
      final response = await ApiService.createRescueRequest(
        name: nameController.text.trim(),
        phone: phoneController.text.trim(),
        issue: selectedIssue!,
        vehicle: selectedVehicle!,
        locationText: widget.currentLocationText,
        lat: widget.latitude,
        lng: widget.longitude,
        issueDescription: noteController.text,
        userId: AppSession.id ?? '',
      );
      final requestId =
          (response['id'] ?? response['_id'] ?? '').toString().trim();

      if (requestId.isEmpty) throw Exception('Request ID not received');

      // Determine zone (urban/rural) — reads from Firestore `zones`.
      final zoneInfo =
          await _zoneService.checkZone(widget.latitude, widget.longitude);

      // Create a token for this vehicle/request so the hub can accept the vehicle if towed
      final tokenId = await _tokenService.generateToken(
        vehicleId: '${selectedVehicle}_$requestId',
        userId: phoneController.text.trim(),
        jobId: requestId,
      );

      // Dispatch two-man crew and attach tokenId in meta
      final jobGroupId = await _dispatchService.dispatchTwoManCrew(
        userId: phoneController.text.trim(),
        lat: widget.latitude,
        lng: widget.longitude,
        requestId: requestId,
        meta: {
          'tokenId': tokenId,
          'vehicle': selectedVehicle,
          'zone': zoneInfo['zone'],
          'zoneName': zoneInfo['zoneName'],
        },
      );

      // Update token with assigned job group
      await _tokenService.updateTokenStatus(tokenId, 'in_transit', extra: {
        'jobGroupId': jobGroupId,
        'assignedAt': DateTime.now().toUtc().toIso8601String(),
      });

      await ActivityService.saveLastRequestId(requestId);
      await ActivityService.addUserActivity(
        'Rescue Request Created',
        '$selectedIssue • $selectedVehicle',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request created successfully')),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => RequestStatusScreen(
            requestId: requestId,
            issue: selectedIssue!,
            vehicle: selectedVehicle!,
            location: widget.currentLocationText,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  void dispose() {
    noteController.dispose();
    nameController.dispose();
    phoneController.dispose();
    super.dispose();
  }

  InputDecoration buildInputDecoration({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: Colors.grey.shade100,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget buildDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required void Function(String?) onChanged,
    required IconData icon,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: buildInputDecoration(label: label, icon: icon),
      items: items
          .map(
            (item) => DropdownMenuItem<String>(value: item, child: Text(item)),
          )
          .toList(),
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        title: const Text('Request Rescue'),
        backgroundColor: const Color(0xFFD32F2F),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFD32F2F), Color(0xFFFF7043)],
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.car_repair, color: Colors.white, size: 36),
                    const SizedBox(height: 10),
                    const Text(
                      'Confirm Rescue Request',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.currentLocationText.isEmpty
                          ? 'Current location unavailable'
                          : widget.currentLocationText,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Lat: ${widget.latitude}, Lng: ${widget.longitude}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (widget.predictedIssue != null)
                Container(
                  padding: EdgeInsets.all(14),
                  margin: EdgeInsets.only(bottom: 15),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.auto_fix_high, color: Colors.green),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "AI Detected: ${widget.predictedIssue} ${(widget.predictedConfidence! * 100).toStringAsFixed(0)}%",
                          style: TextStyle(
                            color: Colors.green.shade900,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha((0.05 * 255).round()),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // §12 — the five common issues as tap targets. A dropdown
                    // hides them behind a menu and needs two taps for the most
                    // frequent case.
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'What happened?',
                        style: Theme.of(context)
                            .textTheme
                            .labelLarge
                            ?.copyWith(
                                inherit: true,
                                fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: issues.take(6).map((issue) {
                        final selected = selectedIssue == issue;
                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setState(() => selectedIssue = issue),
                          child: Container(
                            width: 100,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: selected
                                  ? const Color(0xFFD32F2F)
                                      .withAlpha((0.10 * 255).round())
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selected
                                    ? const Color(0xFFD32F2F)
                                    : Colors.transparent,
                                width: 1.4,
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  _issueIcons[issue] ?? Icons.build_outlined,
                                  size: 22,
                                  color: selected
                                      ? const Color(0xFFD32F2F)
                                      : Colors.black54,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  issue,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    inherit: true,
                                    fontSize: 11,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: selected
                                        ? const Color(0xFFD32F2F)
                                        : Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    if (selectedIssue == null)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          'Pick the closest match — you can add detail below.',
                          style: TextStyle(
                              inherit: true,
                              fontSize: 11,
                              color: Colors.black45),
                        ),
                      ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: nameController,
                      decoration: buildInputDecoration(
                        label: 'Your Name',
                        hint: 'Enter your full name',
                        icon: Icons.person_outline,
                      ),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: buildInputDecoration(
                        label: 'Phone Number',
                        hint: 'Enter your phone number',
                        icon: Icons.phone_outlined,
                      ),
                    ),
                    const SizedBox(height: 15),
                    buildDropdown(
                      label: 'Select Vehicle',
                      value: selectedVehicle,
                      items: vehicles,
                      icon: Icons.directions_car_outlined,
                      onChanged: (value) =>
                          setState(() => selectedVehicle = value),
                    ),
                    const SizedBox(height: 15),
                    // §12 — the note the mechanic reads on the way.
                    TextField(
                      controller: noteController,
                      minLines: 2,
                      maxLines: 4,
                      maxLength: 300,
                      decoration: buildInputDecoration(
                        label: 'Add a note (optional)',
                        hint: 'Landmark, what you noticed, gate number…',
                        icon: Icons.notes_outlined,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: isLoading ? null : _submitRescueRequest,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD32F2F),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: isLoading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Confirm Rescue Request',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


