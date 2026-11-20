import 'package:flutter/material.dart';

class MechanicSafetyScreen extends StatelessWidget {
  const MechanicSafetyScreen({super.key});

  Widget buildTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
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
      child: ListTile(
        contentPadding: const EdgeInsets.all(14),
        leading: CircleAvatar(
          backgroundColor: color.withAlpha((0.12 * 255).round()),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(subtitle),
      ),
    );
  }

  Widget buildSafetyBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFD32F2F), Color(0xFFFF7043)],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield, color: Colors.white, size: 34),
          SizedBox(height: 12),
          Text(
            'Safety & Security',
            style: TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Quick safety tools and secure partner support for active rescue jobs.',
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
        title: const Text('Safety & Security'),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            buildSafetyBanner(),
            const SizedBox(height: 16),
            buildTile(
              icon: Icons.shield,
              title: 'Partner Safety',
              subtitle:
                  'Safety support tools for active rescue trips and partner work.',
              color: Colors.blue,
            ),
            buildTile(
              icon: Icons.sos,
              title: 'Emergency Support',
              subtitle:
                  'Quick emergency support and issue escalation for mechanics.',
              color: Colors.red,
            ),
            buildTile(
              icon: Icons.verified_user_outlined,
              title: 'Verified Access',
              subtitle:
                  'Protected access for partner account, documents, and support.',
              color: Colors.green,
            ),
            buildTile(
              icon: Icons.call_outlined,
              title: 'Emergency Contacts',
              subtitle:
                  'Keep support, local police, and emergency contacts accessible.',
              color: Colors.orange,
            ),
          ],
        ),
      ),
    );
  }
}
