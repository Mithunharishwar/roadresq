import 'package:flutter/material.dart';

class MechanicCommunityScreen extends StatelessWidget {
  const MechanicCommunityScreen({super.key});

  Widget buildCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha((0.05 * 255).round()),
              blurRadius: 12),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: color.withAlpha((0.12 * 255).round()),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text(subtitle, style: const TextStyle(color: Colors.black54)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildTopBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.groups, color: Colors.white, size: 34),
          SizedBox(height: 12),
          Text(
            'Partner Community',
            style: TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Connect with local partners, see announcements, and stay updated with the RoadResQ partner network.',
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        title: const Text('Partner Community'),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            buildTopBanner(),
            const SizedBox(height: 16),
            buildCard(
              icon: Icons.groups,
              title: 'Join Mechanic Community',
              subtitle:
                  'Connect with nearby mechanics, partners, and local rescue network members.',
              color: Colors.blue,
            ),
            buildCard(
              icon: Icons.campaign_outlined,
              title: 'Announcements',
              subtitle:
                  'Get updates about app features, service zones, and partner growth opportunities.',
              color: Colors.orange,
            ),
            buildCard(
              icon: Icons.emoji_events_outlined,
              title: 'Top Partner Highlights',
              subtitle:
                  'See active partners, top performers, and community recognition.',
              color: Colors.green,
            ),
            buildCard(
              icon: Icons.forum_outlined,
              title: 'Partner Discussion',
              subtitle:
                  'Share mechanic tips, customer handling ideas, and rescue experiences.',
              color: Colors.purple,
            ),
          ],
        ),
      ),
    );
  }
}
