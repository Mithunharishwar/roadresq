// IMPORTANT: Set Firestore Rules to allow read/write for testing
// FILE: lib/features/crew/mechanic_dashboard.dart
/// MechanicDashboard — Blue-themed dashboard for mechanics.
///
/// Features:
///   - Online/Offline toggle (persisted to Firestore `crews/{uid}.isOnline`).
///   - "Available Jobs" list streamed from `jobs` where status == 'pending'
///     via StreamBuilder (real-time, no timeout).
///   - Accept button to claim a job → updates job status to 'assigned' and
///     writes crew info.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/firestore_failure.dart';

class MechanicDashboard extends StatefulWidget {
  const MechanicDashboard({super.key});

  @override
  State<MechanicDashboard> createState() => _MechanicDashboardState();
}

class _MechanicDashboardState extends State<MechanicDashboard> {
  static const Color _blue = Color(0xFF1976D2);
  final User? _user = FirebaseAuth.instance.currentUser;

  // Not yet wired to a dashboard availability toggle.
  // ignore: unused_element
  Future<void> _setOnline(bool online) async {
    final uid = _user?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('crews')
          .doc(uid)
          .set({'isOnline': online}, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(firestoreFailureSummary(e, what: 'online status')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (_) {
      // Show a gentle message instead of crashing.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not update status. Check your connection.'),
            backgroundColor: _blue,
          ),
        );
      }
    }
  }

  /// Stream of this mechanic's offered (pending) jobs. StreamBuilder → live updates.
  ///
  /// Dispatch creates a job already linked to a specific crew member via
  /// `crewId` with status 'pending', so "available" here means "offered to me",
  /// not a public pool. Scoping to `crewId == uid` is also what the jobs read
  /// rule requires: an unfiltered query cannot be proven safe and Firestore
  /// denies it before looking at any data.
  Stream<QuerySnapshot<Map<String, dynamic>>> _availableJobsStream() {
    final uid = _user?.uid ?? 'none';
    return FirebaseFirestore.instance
        .collection('jobs')
        .where('crewId', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> _acceptJob(DocumentSnapshot<Map<String, dynamic>> job) async {
    final uid = _user?.uid;
    if (uid == null) return;
    try {
      await job.reference.update({
        'status': 'assigned',
        'assignedMechanicId': uid,
        'assignedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Job accepted! Head to the customer.'),
            backgroundColor: _blue,
          ),
        );
      }
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(firestoreFailureSummary(e, what: 'this job')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to accept job: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _blue,
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
                  stream: _availableJobsStream(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      final err = snapshot.error;
                      // Always log the real cause — a silent generic message is
                      // what made this failure so hard to trace.
                      debugPrint(
                        'MechanicDashboard jobs stream error: $err',
                      );
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Could not load your jobs.\n\n$err',
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
                          'No available jobs right now',
                          style: TextStyle(fontSize: 16, color: Colors.black54),
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: jobs.length,
                      itemBuilder: (context, index) {
                        final job = jobs[index];
                        final data = job.data();
                        return _buildJobCard(job, data);
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
            child: const Icon(Icons.build, color: Colors.white),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mechanic Dashboard',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Accept nearby rescue jobs',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          FloatingActionButton.small(
            heroTag: 'home',
            backgroundColor: Colors.white,
            onPressed: () => context.go('/role-select'),
            child: const Icon(Icons.logout, color: _blue),
          ),
        ],
      ),
    );
  }

  Widget _buildJobCard(
    DocumentSnapshot<Map<String, dynamic>> job,
    Map<String, dynamic> data,
  ) {
    final address = data['address']?.toString() ?? 'Location shared in app';
    final issue = data['issueType']?.toString() ?? 'Roadside Assistance';
    final vehicle = data['vehicleType']?.toString() ?? 'Vehicle';
    final distanceKm = (data['distanceKm'] as num?)?.toDouble();
    final eta = (data['etaMinutes'] as num?)?.toDouble();

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
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _blue.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  issue,
                  style: const TextStyle(
                    color: _blue,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              const Spacer(),
              Icon(Icons.place, color: Colors.grey.shade500, size: 16),
              const SizedBox(width: 4),
              Text(
                distanceKm != null
                    ? '${distanceKm.toStringAsFixed(1)} km'
                    : '-- km',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            address,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            '$vehicle • $issue',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          if (eta != null) ...[
            const SizedBox(height: 6),
            Text('ETA: ${eta.round()} min',
                style: const TextStyle(color: _blue)),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: () => _acceptJob(job),
              style: ElevatedButton.styleFrom(
                backgroundColor: _blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Accept Job',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
