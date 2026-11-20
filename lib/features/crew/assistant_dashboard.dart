// IMPORTANT: Set Firestore Rules to allow read/write for testing
// FILE: lib/features/crew/assistant_dashboard.dart
/// AssistantDashboard — Green-themed dashboard for assistants (first responders).
///
/// Features:
///   - "Assigned Jobs" list streamed from Firestore where the job is assigned
///     to this assistant and not completed/cancelled (StreamBuilder, no timeout).
///   - "Generate Token QR" button (opens a token generator bottom sheet).
///   - Online/Offline toggle persisted to Firestore.
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/utils/firestore_failure.dart';

class AssistantDashboard extends StatefulWidget {
  const AssistantDashboard({super.key});

  @override
  State<AssistantDashboard> createState() => _AssistantDashboardState();
}

class _AssistantDashboardState extends State<AssistantDashboard> {
  static const Color _green = Color(0xFF388E3C);
  final User? _user = FirebaseAuth.instance.currentUser;

  /// Assigned jobs for this assistant.
  Stream<QuerySnapshot<Map<String, dynamic>>> _assignedJobsStream() {
    final uid = _user?.uid ?? 'none';
    // `assignedAssistantId` is a field on `requests`, NOT on `jobs` — no code
    // path writes it to a job (dispatch links a job to its crew member via
    // `crewId`). Filtering on it meant this query could never match, and the
    // jobs read rule could not prove it safe, so it was denied outright.
    // `crewId == uid` is satisfied by the existing jobs read rule and the
    // existing jobs index (crewId, status, createdAt), so no new index or
    // rules clause is required.
    return FirebaseFirestore.instance
        .collection('jobs')
        .where('crewId', isEqualTo: uid)
        .where('status', whereIn: ['assigned', 'active', 'on_the_way'])
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  void _generateToken() {
    final jobId = DateTime.now().millisecondsSinceEpoch.toString();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Garage Token',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 20),
              // QR code for the job token.
              QrImageView(
                data: 'RoadResQ:TOKEN:$jobId',
                version: QrVersions.auto,
                size: 200,
              ),
              const SizedBox(height: 16),
              Text(
                'Job #$jobId',
                style: const TextStyle(
                  color: _green,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Show this QR at the verified garage after pickup.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _green,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xFFF7F9FC),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                ),
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _assignedJobsStream(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      final err = snapshot.error;
                      // Log the real cause. This screen used to print
                      // "Check Firebase Rules" for permission-denied, which was
                      // wrong: the rules are fine, the app simply has no
                      // Firebase Auth session. See firestore_failure.dart.
                      debugPrint(
                        'AssistantDashboard jobs stream error: $err',
                      );
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            describeFirestoreFailure(err, what: 'assigned jobs'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ),
                      );
                    }
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final jobs = snapshot.data?.docs ?? [];
                    if (jobs.isEmpty) {
                      return const Center(
                        child: Text(
                          'No assigned jobs yet',
                          style: TextStyle(fontSize: 16, color: Colors.black54),
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: jobs.length,
                      itemBuilder: (context, index) {
                        final data = jobs[index].data();
                        return _buildJobCard(data);
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.white.withAlpha(60),
            child: const Icon(Icons.two_wheeler, color: Colors.white),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Assistant Dashboard',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'First-responder assigned jobs',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          FloatingActionButton.small(
            heroTag: 'assistant_logout',
            backgroundColor: Colors.white,
            onPressed: () => context.go('/role-select'),
            child: const Icon(Icons.logout, color: _green),
          ),
        ],
      ),
    );
  }

  Widget _buildJobCard(Map<String, dynamic> data) {
    final address = data['address']?.toString() ?? 'Location shared in app';
    final userName = data['userName']?.toString() ?? 'Customer';
    final isAssigned = data['status'] == 'assigned';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
              color: Colors.black12, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 20,
                backgroundColor: Color(0xFF2E7D32),
                child: Icon(Icons.person, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  userName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _green.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isAssigned ? 'Assigned' : 'On The Way',
                  style: const TextStyle(
                    color: _green,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.place, color: Colors.grey.shade500, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  address,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _generateToken,
              icon: const Icon(Icons.qr_code_2),
              label: const Text('Generate Token QR'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
