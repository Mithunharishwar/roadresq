import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/router/app_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'recent_activity_screen.dart';
import 'rescue_request_screen.dart';
import 'my_requests_screen.dart';

/// UserHomeScreen — Rapido-inspired home for the customer.
///
/// Displays a live map with a location bar, quick service-type chips,
/// a bottom action bar (Request Rescue / SOS / Track / History),
/// and a full resizable SOS panel. All original rescue logic is preserved.
class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen> {
  bool _isRequestingHelp = false;
  GoogleMapController? _mapController;

  /// §11 — the address shown under the search bar. Reverse-geocoded from the
  /// device position instead of the hardcoded Chennai Central string.
  String _locationLabel = 'Locating your position…';
  final TextEditingController _searchController = TextEditingController();
  bool _searching = false;
  double? _lat;
  double? _lng;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _locateMe());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Initial camera position, e.g., Chennai
  static const CameraPosition _initialCameraPosition = CameraPosition(
    target: LatLng(13.0827, 80.2707),
    zoom: 12,
  );

  // ── §11 Location, search and reverse geocoding ───────────────────────
  /// Move the camera to the device position and label it with a real address.
  Future<void> _locateMe() async {
    try {
      final position = await _determinePosition();
      _lat = position.latitude;
      _lng = position.longitude;
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(position.latitude, position.longitude),
            zoom: 16,
          ),
        ),
      );
      final label = await _reverseGeocode(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() => _locationLabel = label);
    } catch (e) {
      if (!mounted) return;
      setState(() => _locationLabel = 'Location unavailable — tap to retry');
    }
  }

  /// Reverse geocode through OpenStreetMap's Nominatim endpoint — no API key,
  /// and the result is a real place name rather than a fixed string.
  Future<String> _reverseGeocode(double lat, double lng) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?format=jsonv2&lat=$lat&lon=$lng&zoom=16',
      );
      final response = await http.get(
        uri,
        headers: const {'User-Agent': 'RoadResQ/2.0 (support@roadresq.com)'},
      ).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        return '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
      }
      final body = jsonDecode(response.body);
      final address = body is Map ? body['address'] : null;
      if (address is Map) {
        final parts = <String>[
          (address['road'] ?? address['suburb'] ?? address['neighbourhood'] ?? '')
              .toString(),
          (address['city'] ?? address['town'] ?? address['state_district'] ?? '')
              .toString(),
          (address['state'] ?? '').toString(),
        ].where((p) => p.isNotEmpty).toList();
        if (parts.isNotEmpty) return parts.join(', ');
      }
      final display = (body is Map ? body['display_name'] : null)?.toString();
      if (display != null && display.isNotEmpty) {
        return display.split(',').take(3).join(',').trim();
      }
    } catch (e) {
      debugPrint('[user_home] reverse geocode failed: $e');
    }
    return '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
  }

  /// §11 — search bar: forward-geocode a typed place and move the map there.
  Future<void> _searchAddress() async {
    final query = _searchController.text.trim();
    if (query.isEmpty || _searching) return;

    setState(() => _searching = true);
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?format=jsonv2&limit=1&q=${Uri.encodeComponent(query)}',
      );
      final response = await http.get(
        uri,
        headers: const {'User-Agent': 'RoadResQ/2.0 (support@roadresq.com)'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('Search failed (HTTP ${response.statusCode})');
      }
      final results = jsonDecode(response.body);
      if (results is! List || results.isEmpty) {
        throw Exception('No place matched "$query"');
      }
      final first = results.first as Map;
      final lat = double.tryParse('${first['lat']}');
      final lng = double.tryParse('${first['lon']}');
      if (lat == null || lng == null) {
        throw Exception('That place has no coordinates');
      }

      _lat = lat;
      _lng = lng;
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: LatLng(lat, lng), zoom: 16),
        ),
      );
      if (!mounted) return;
      setState(() {
        _locationLabel = (first['display_name'] ?? query)
            .toString()
            .split(',')
            .take(2)
            .join(',')
            .trim();
      });
      FocusScope.of(context).unfocus();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
            style: const TextStyle(inherit: true),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  /// §21 / §53 — emergency sheet: dial 112, call a saved contact, or share the
  /// live position. Previously "SOS" only created a rescue request, which is
  /// not what someone in danger needs first.
  Future<void> _openEmergencySheet() async {
    final prefs = await SharedPreferences.getInstance();
    final contactName = prefs.getString('emergency_contact_name') ?? '';
    final contactPhone = prefs.getString('emergency_contact_phone') ?? '';
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Emergency',
              style: TextStyle(
                  inherit: true, fontSize: 16, fontWeight: FontWeight.w700),
            ),
            ListTile(
              leading: const Icon(Icons.local_police, color: Color(0xFFD32F2F)),
              title: const Text('Call 112',
                  style: TextStyle(inherit: true)),
              subtitle: const Text('Police · Fire · Ambulance',
                  style: TextStyle(inherit: true, fontSize: 11)),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await launchUrl(Uri.parse('tel:112'));
              },
            ),
            ListTile(
              leading: const Icon(Icons.contact_phone_outlined),
              title: Text(
                contactPhone.isEmpty
                    ? 'Add an emergency contact'
                    : 'Call $contactName',
                style: const TextStyle(inherit: true),
              ),
              subtitle: contactPhone.isEmpty
                  ? const Text('Saved on this device',
                      style: TextStyle(inherit: true, fontSize: 11))
                  : Text(contactPhone,
                      style:
                          const TextStyle(inherit: true, fontSize: 11)),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                if (contactPhone.isEmpty) {
                  await _editEmergencyContact();
                } else {
                  await launchUrl(Uri.parse('tel:$contactPhone'));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_location),
              title: const Text('Share my live location',
                  style: TextStyle(inherit: true)),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await _shareLiveLocation();
              },
            ),
            ListTile(
              leading: const Icon(Icons.sos),
              title: const Text('Request a rescue crew',
                  style: TextStyle(inherit: true)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _initiateRescue();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _editEmergencyContact() async {
    final prefs = await SharedPreferences.getInstance();
    final nameController =
        TextEditingController(text: prefs.getString('emergency_contact_name'));
    final phoneController = TextEditingController(
        text: prefs.getString('emergency_contact_phone'));

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Emergency contact',
            style: TextStyle(inherit: true)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: const TextStyle(inherit: true),
              decoration: const InputDecoration(
                  labelText: 'Name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              style: const TextStyle(inherit: true),
              decoration: const InputDecoration(
                  labelText: 'Phone', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(inherit: true)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save', style: TextStyle(inherit: true)),
          ),
        ],
      ),
    );

    if (saved == true) {
      await prefs.setString('emergency_contact_name', nameController.text.trim());
      await prefs.setString(
          'emergency_contact_phone', phoneController.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Emergency contact saved',
              style: TextStyle(inherit: true)),
        ),
      );
    }
    nameController.dispose();
    phoneController.dispose();
  }

  Future<void> _shareLiveLocation() async {
    try {
      final position = await _determinePosition();
      final link =
          'https://maps.google.com/?q=${position.latitude},${position.longitude}';
      await SharePlus.instance.share(
        ShareParams(
          subject: 'My RoadResQ location',
          text: 'I need help on the road. My live location: $link',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not share location: $e',
              style: const TextStyle(inherit: true)),
        ),
      );
    }
  }

  /// Handles the logic when the SOS button is pressed.
  Future<void> _initiateRescue() async {
    if (_isRequestingHelp) return;

    setState(() {
      _isRequestingHelp = true;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Getting your location...')),
    );

    try {
      // 1. Get user's current location
      final Position position = await _determinePosition();
      final userLocation = LatLng(position.latitude, position.longitude);

      // Animate camera to user's location
      _mapController?.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(target: userLocation, zoom: 16),
      ));

      if (!mounted) return;
      // 2. Navigate to the request screen to confirm details
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RescueRequestScreen(
            currentLocationText: _locationLabel,
            latitude: userLocation.latitude,
            longitude: userLocation.longitude,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to request help: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isRequestingHelp = false);
      }
    }
  }

  /// Handles quick-action tap for a specific service type.
  Future<void> _quickRescue(String service) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Requesting $service assistance…'),
        backgroundColor: const Color(0xFF0D47A1),
      ),
    );
    await _initiateRescue();
  }

  /// Determines the current position of the device.
  Future<Position> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
          'Location permissions are permanently denied, we cannot request permissions.');
    }

    return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return Scaffold(
      backgroundColor: const Color(0xFF0D47A1),
      body: Stack(
        children: [
          // ─── Live map (full-bleed) ───
          GoogleMap(
            initialCameraPosition: _initialCameraPosition,
            onMapCreated: (controller) {
              _mapController = controller;
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
          ),

// ─── Top location bar ───
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFD32F2F), Color(0xFFFF7043)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFD32F2F).withAlpha(90),
                          blurRadius: 22,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha((0.22 * 255).round()),
                            shape: BoxShape.circle,
                          ),
                          child: const CircleAvatar(
                            radius: 15,
                            backgroundColor: Colors.white,
                            child: Icon(
                              Icons.location_on,
                              color: Color(0xFFD32F2F),
                              size: 18,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Where are you stranded?',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.my_location,
                                    size: 12,
                                    color: Colors.white70,
                                  ),
                                  const SizedBox(width: 4),
                                   Expanded(
                                     child: GestureDetector(
                                       onTap: _locateMe,
                                       child: Text(
                                         _locationLabel,
                                         maxLines: 1,
                                         overflow: TextOverflow.ellipsis,
                                         style: TextStyle(
                                           inherit: true,
                                           fontSize: 12,
                                           color: Colors.white.withAlpha(200),
                                         ),
                                       ),
                                     ),
                                   ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha((0.22 * 255).round()),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: IconButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const RecentActivityScreen(),
                                ),
                              );
                            },
                            icon:
                                const Icon(Icons.history, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),                // ─── Search bar (§11) ───
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha((0.95 * 255).round()),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(24),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _searchAddress(),
                      style: const TextStyle(inherit: true, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search a landmark, road or area',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _searching
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : IconButton(
                                tooltip: 'Search',
                                onPressed: _searchAddress,
                                icon: const Icon(Icons.arrow_forward, size: 18),
                              ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ),

                // ─── Service type quick chips ───
                const SizedBox(height: 12),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _serviceChip(
                        Icons.car_repair_outlined,
                        'Flat Tyre',
                        const Color(0xFFD32F2F),
                        () => _quickRescue('Flat Tyre'),
                      ),
                      _serviceChip(
                        Icons.battery_charging_full_outlined,
                        'Battery',
                        const Color(0xFF2E7D32),
                        () => _quickRescue('Battery Jump'),
                      ),
                      _serviceChip(
                        Icons.local_gas_station_outlined,
                        'Fuel',
                        const Color(0xFFFF8F00),
                        () => _quickRescue('Fuel Delivery'),
                      ),
                      _serviceChip(
                        Icons.local_shipping_outlined,
                        'Towing',
                        const Color(0xFF0D47A1),
                        () => _quickRescue('Towing'),
                      ),
                      _serviceChip(
                        Icons.lock_open_outlined,
                        'Lockout',
                        const Color(0xFF7B1FA2),
                        () => _quickRescue('Lockout Help'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ─── Bottom action bar ───
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: _buildBottomActionBar(surface),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _serviceChip(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha((0.92 * 255).round()),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: color.withAlpha((0.25 * 255).round())),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(18),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomActionBar(Color surface) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subColor = isDark ? Colors.white70 : Colors.black54;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(40),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Primary rescue action
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _isRequestingHelp ? null : _initiateRescue,
              icon: const Icon(Icons.sos),
              label: Text(
                _isRequestingHelp ? 'Locating…' : 'Request Rescue Help',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD32F2F),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                elevation: 4,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Quick action row
          Row(
            children: [
              Expanded(
                 child: _miniAction(
                   icon: Icons.sos,
                   label: 'SOS',
                   color: Colors.red,
                   onTap: _openEmergencySheet,
                 ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _miniAction(
                  icon: Icons.two_wheeler,
                  label: 'Rider',
                  color: const Color(0xFF2E7D32),
                  onTap: () => _quickRescue('Rider Assistance'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                 child: _miniAction(
                   icon: Icons.route,
                   label: 'Track',
                   color: const Color(0xFF0D47A1),
                   onTap: () => Navigator.of(context).push(
                     MaterialPageRoute(
                       builder: (_) => const MyRequestsScreen(),
                     ),
                   ),
                 ),
               ),
               const SizedBox(width: 10),
               Expanded(
                 child: _miniAction(
                   icon: Icons.engineering_outlined,
                   label: 'Nearby',
                   color: const Color(0xFFFF8F00),
                   onTap: () => context.push(AppRoutes.nearbyMechanics),
                 ),
               ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.verified_user_outlined,
                  size: 14, color: const Color(0xFF2E7D32)),
              const SizedBox(width: 6),
              Text(
                'Live tracking • Verified crew • 24×7',
                style: TextStyle(fontSize: 11.5, color: subColor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withAlpha((0.1 * 255).round()),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}





