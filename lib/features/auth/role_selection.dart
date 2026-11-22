// FILE: lib/features/auth/role_selection.dart
/// Role Selection Screen — Entry point for the app
/// Users choose: User, Mechanic, or Assistant
/// Navigates to the appropriate login screen
library;

import 'package:material_ui/material_ui.dart';
import 'login_screen.dart';

class RoleSelection extends StatelessWidget {
  const RoleSelection({super.key});

  Widget _buildRoleCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required String badge,
    required IconData icon,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(26),
      onTap: onTap,
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
              // Header banner
              Container(
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
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Choose your role',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Continue as a customer requesting support or as a mechanic handling nearby jobs.',
                style: TextStyle(color: Colors.black54, fontSize: 15),
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
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LoginScreen(
                        role: 'user',
                      ),
                    ),
                  );
                },
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
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LoginScreen(
                        role: 'mechanic',
                      ),
                    ),
                  );
                },
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
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LoginScreen(
                        role: 'assistant',
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              // Feature chips
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _buildFeatureChip(
                      Icons.verified_user_outlined, 'Verified mechanics'),
                  _buildFeatureChip(
                      Icons.location_on_outlined, 'Live location'),
                  _buildFeatureChip(Icons.route_outlined, 'Route updates'),
                  _buildFeatureChip(
                      Icons.support_agent_outlined, 'Fast support'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureChip(IconData icon, String text) {
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
