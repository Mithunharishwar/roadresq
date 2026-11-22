// FILE: lib/screens/nearby_mechanics_screen.dart
/// §16 — mechanics near the user, with real distance, rating and ETA.
///
/// Distance is computed from the device position and each mechanic's last
/// reported position (haversine). ETA uses the same assumed average speed the
/// backend uses for allocation, so the two numbers agree. Neither is presented
/// as a measured travel time.
library;

import 'package:material_ui/material_ui.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/role_colors.dart';
import '../services/module_api.dart';
import '../widgets/rq_async.dart';

class NearbyMechanicsScreen extends StatefulWidget {
  const NearbyMechanicsScreen({super.key});

  @override
  State<NearbyMechanicsScreen> createState() => _NearbyMechanicsScreenState();
}

class _NearbyMechanicsScreenState extends State<NearbyMechanicsScreen> {
  /// Same assumption the backend allocation uses (§22).
  static const double _assumedSpeedKmh = 30.0;

  List<Map<String, dynamic>> _mechanics = const [];
  Position? _position;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    Position? position;
    try {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (serviceOn && permission != LocationPermission.denied &&
          permission != LocationPermission.deniedForever) {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
        ).timeout(const Duration(seconds: 10));
      }
    } catch (_) {
      // A missing fix must not block the list: mechanics are still shown,
      // sorted by rating, with distance marked unavailable.
      position = null;
    }

    try {
      var rows = await ModuleApi.mechanics(online: true);
      if (rows.isEmpty) {
        // No one online: show the full roster rather than an empty screen, and
        // say so on the card.
        rows = await ModuleApi.mechanics();
      }

      rows.sort((a, b) {
        if (position == null) {
          return _rating(b).compareTo(_rating(a));
        }
        return _distanceKm(a, position)!.compareTo(_distanceKm(b, position)!);
      });

      if (!mounted) return;
      setState(() {
        _mechanics = rows;
        _position = position;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = rqMessage(e);
      });
    }
  }

  double _rating(Map<String, dynamic> m) =>
      (m['rating'] as num?)?.toDouble() ?? 0.0;

  double? _distanceKm(Map<String, dynamic> m, Position from) {
    final location = m['location'];
    if (location is! Map) return null;
    final lat = (location['lat'] as num?)?.toDouble();
    final lng = (location['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;

    final metres = Geolocator.distanceBetween(from.latitude, from.longitude,
        lat, lng);
    return metres / 1000.0;
  }

  String _etaLabel(double? km) {
    if (km == null) return 'Distance unavailable';
    final minutes = (km / _assumedSpeedKmh * 60).round();
    return '${km.toStringAsFixed(1)} km · ~$minutes min';
  }

  Future<void> _call(String phone) async {
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This mechanic has no phone number on file.',
              style: TextStyle(inherit: true)),
        ),
      );
      return;
    }
    final uri = Uri.parse('tel:$phone');
    if (!await launchUrl(uri)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not start a call to $phone.',
              style: const TextStyle(inherit: true)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby mechanics',
            style: TextStyle(inherit: true)),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const RqLoading(label: 'Finding mechanics near you…')
          : _error != null
              ? RqError(message: _error!, onRetry: _load)
              : _mechanics.isEmpty
                  ? RqEmpty(
                      icon: Icons.car_repair,
                      title: 'No mechanics registered yet',
                      message: 'Mechanics appear here once they sign up and '
                          'set themselves online.',
                      actionLabel: 'Refresh',
                      onAction: _load,
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _mechanics.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) =>
                            _mechanicCard(_mechanics[index]),
                      ),
                    ),
    );
  }

  Widget _mechanicCard(Map<String, dynamic> mechanic) {
    final name = (mechanic['name'] ?? 'Mechanic').toString();
    final phone = (mechanic['phone'] ?? '').toString();
    final online = mechanic['online'] == true || mechanic['isOnline'] == true;
    final verified = mechanic['verified'] == true;
    final rating = _rating(mechanic);
    final ratingCount = (mechanic['ratingCount'] as num?)?.toInt() ?? 0;
    final completed =
        (mechanic['completedRescues'] as num?)?.toInt() ?? 0;
    final servicesRaw = mechanic['services'];
    final services = servicesRaw is List
        ? servicesRaw.map((s) => s.toString()).where((s) => s.isNotEmpty).toList()
        : <String>[];
    final km = _position == null ? null : _distanceKm(mechanic, _position!);

    return RqCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: RoleColors.tint(RoleColors.mechanic, opacity: 0.15),
                backgroundImage: (mechanic['photoUrl'] ?? '').toString().isNotEmpty
                    ? NetworkImage(mechanic['photoUrl'].toString())
                    : null,
                child: (mechanic['photoUrl'] ?? '').toString().isEmpty
                    ? const Icon(Icons.person, color: RoleColors.mechanic)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: const TextStyle(
                                inherit: true,
                                fontSize: 15,
                                fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (verified) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.verified,
                              size: 15, color: RoleColors.assistant),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _etaLabel(km),
                      style: const TextStyle(
                          inherit: true,
                          fontSize: 12,
                          color: RoleColors.neutral),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: RoleColors.tint(
                      online ? RoleColors.assistant : RoleColors.neutral,
                      opacity: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  online ? 'Online' : 'Offline',
                  style: TextStyle(
                    inherit: true,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: online ? RoleColors.assistant : RoleColors.neutral,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.star_rounded,
                  size: 16, color: Color(0xFFF9A825)),
              const SizedBox(width: 4),
              Text(
                ratingCount == 0
                    ? 'No ratings yet'
                    : '${rating.toStringAsFixed(1)} ($ratingCount)',
                style: const TextStyle(inherit: true, fontSize: 12),
              ),
              const SizedBox(width: 14),
              const Icon(Icons.task_alt,
                  size: 15, color: RoleColors.neutral),
              const SizedBox(width: 4),
              Text('$completed jobs done',
                  style: const TextStyle(
                      inherit: true, fontSize: 12, color: RoleColors.neutral)),
            ],
          ),
          if (services.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: services
                  .take(4)
                  .map((s) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: RoleColors.tint(RoleColors.mechanic,
                              opacity: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(s,
                            style: const TextStyle(
                                inherit: true,
                                fontSize: 10,
                                color: RoleColors.mechanic)),
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _call(phone),
                  icon: const Icon(Icons.call, size: 17),
                  label: const Text('Call',
                      style: TextStyle(inherit: true, fontSize: 13)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: RoleColors.user),
                  onPressed: () {
                    // The rescue flow is where a job is created; this screen is
                    // for choosing who to call, not for forging a job.
                    Navigator.of(context).maybePop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Request a rescue from Home and RoadResQ will '
                          'dispatch the best-placed crew (nearest first).',
                          style: const TextStyle(inherit: true),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.bolt, size: 17),
                  label: const Text('Request',
                      style: TextStyle(inherit: true, fontSize: 13)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

