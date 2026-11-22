/// Community Safety Mesh — Crowd-Sourced Rescue Layer Screen (novel module).
///
/// Lets the user broadcast an emergency beacon to nearby verified community
/// helpers + family, and lists the nearby verified helpers.
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/novel/community_helper_model.dart';
import '../../providers/novel/community_mesh_provider.dart';
import '../../widgets/novel/novel_widgets.dart';

class CommunityMeshScreen extends ConsumerStatefulWidget {
  final String userId;
  final String userName;
  final String userPhone;

  const CommunityMeshScreen({
    super.key,
    this.userId = 'user1',
    this.userName = 'Rahul Kumar',
    this.userPhone = '+919876543210',
  });

  @override
  ConsumerState<CommunityMeshScreen> createState() =>
      _CommunityMeshScreenState();
}

class _CommunityMeshScreenState extends ConsumerState<CommunityMeshScreen> {
  bool _beaconSent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(communityMeshProvider.notifier).findNearbyHelpers(
            lat: 13.0827,
            lng: 80.2707,
          );
    });
  }

  Future<void> _sendBeacon() async {
    final notifier = ref.read(communityMeshProvider.notifier);
    await notifier.broadcastBeacon(
      userId: widget.userId,
      userName: widget.userName,
      userPhone: widget.userPhone,
      lat: 13.0827,
      lng: 80.2707,
      message: 'I am stranded on the roadside. Please assist!',
      familyIds: const ['family1', 'family2'],
    );
    setState(() => _beaconSent = true);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(communityMeshProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const NovelHero(
              title: 'Community Mesh',
              subtitle: 'Crowd-Sourced Rescue Layer',
              icon: Icons.people_outline,
              colors: [Color(0xFF00695C), Color(0xFF26A69A)],
            ),
            const SizedBox(height: 20),

            // Beacon broadcast
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFD32F2F), Color(0xFFFF5252)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  const Icon(Icons.sos, color: Colors.white, size: 40),
                  const SizedBox(height: 10),
                  const Text(
                    'Broadcast Emergency Beacon',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Alerts nearby verified helpers + your family instantly.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white.withAlpha(230), fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _beaconSent ? null : _sendBeacon,
                      icon: const Icon(Icons.notifications_active),
                      label:
                          Text(_beaconSent ? 'Beacon Active' : 'Send Beacon'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFFD32F2F),
                      ),
                    ),
                  ),
                  if (_beaconSent) ...[
                    const SizedBox(height: 8),
                    Text(
                      '✅ Beacon sent — ${state.helpersNotified} helpers notified',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 20),
            NovelSectionTitle(
              title: 'Nearby Verified Helpers',
              icon: Icons.verified_user,
              color: const Color(0xFF00695C),
            ),
            const SizedBox(height: 12),

            if (state.isLoading)
              const Center(child: CircularProgressIndicator())
            else if (state.nearbyHelpers.isEmpty)
              const NovelEmptyCard(
                message: 'No verified helpers nearby right now.',
                icon: Icons.people_outline,
              )
            else
              ...state.nearbyHelpers.map((h) => _helperTile(h)),
          ],
        ),
      ),
    );
  }

  Widget _helperTile(CommunityHelper h) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor:
                const Color(0xFF00695C).withAlpha((0.15 * 255).round()),
            child: const Icon(Icons.person, color: Color(0xFF00695C)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(h.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                Text(
                  'Response ${h.responseScore.toStringAsFixed(0)} • '
                  'Vouches ${h.vouchesReceived}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
          const NovelStatusPill(text: 'Verified', color: Color(0xFF00695C)),
        ],
      ),
    );
  }
}
