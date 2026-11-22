// FILE: lib/features/auth/role_selection_screen.dart
/// RoleSelectionScreen — Entry point after splash.
///
/// Presents 3 role cards (User / Mechanic / Assistant) plus a Garage entry.
/// Tapping a card routes to `/login/:role` via go_router.
library;

import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              _buildHeader(),
              const SizedBox(height: 24),
              const Text(
                'Choose your role',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Continue as a customer requesting support or as a mechanic handling nearby jobs.',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 15),
              ),
              const SizedBox(height: 22),
              _buildRoleCard(
                context: context,
                title: 'User',
                badge: 'LIVE TRACKING',
                subtitle:
                    'Request instant rescue, share location, and track mechanic arrival in real time.',
                icon: Icons.person,
                gradient: const [Color(0xFFD32F2F), Color(0xFFFF7043)],
                role: 'user',
              ),
              const SizedBox(height: 18),
              _buildRoleCard(
                context: context,
                title: 'Mechanic',
                badge: 'PARTNER PANEL',
                subtitle:
                    'Accept jobs, update service status, and share live route progress with customers.',
                icon: Icons.build,
                gradient: const [Color(0xFF0D47A1), Color(0xFF1976D2)],
                role: 'mechanic',
              ),
              const SizedBox(height: 18),
              _buildRoleCard(
                context: context,
                title: 'Assistant',
                badge: 'FIRST RESPONDER',
                subtitle:
                    'Quick response on 2-wheeler. Pickup customer, assess situation, and coordinate with mechanic.',
                icon: Icons.two_wheeler,
                gradient: const [Color(0xFF2E7D32), Color(0xFF4CAF50)],
                role: 'assistant',
              ),
              const SizedBox(height: 18),
              _buildRoleCard(
                context: context,
                title: 'Garage',
                badge: 'REPAIR SHOP',
                subtitle:
                    'Scan tokens, verify rescue jobs, and manage garage operations.',
                icon: Icons.garage,
                gradient: const [Color(0xFF4527A0), Color(0xFF7E57C2)],
                role: 'garage',
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: const [
                  _FeatureChip(
                    icon: Icons.verified_user_outlined,
                    text: 'Verified mechanics',
                  ),
                  _FeatureChip(
                    icon: Icons.location_on_outlined,
                    text: 'Live location',
                  ),
                  _FeatureChip(
                      icon: Icons.route_outlined, text: 'Route updates'),
                  _FeatureChip(
                    icon: Icons.support_agent_outlined,
                    text: 'Fast support',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFD32F2F), Color(0xFFFF7043)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.all(Radius.circular(30)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white,
            child: Icon(
              Icons.car_repair,
              color: Color(0xFFD32F2F),
              size: 30,
            ),
          ),
          SizedBox(height: 18),
          Text(
            'RoadResQ',
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Real-time roadside rescue with live tracking,\nverified mechanics and quick emergency support.',
            style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required String badge,
    required IconData icon,
    required List<Color> gradient,
    required String role,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(26),
      onTap: () => context.go('/login/$role'),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: gradient.first.withAlpha(56),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              height: 64,
              width: 64,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(46),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 30),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(46),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      badge,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _FeatureChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: const Color(0xFFD32F2F)),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
