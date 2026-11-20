import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

/// MechanicDashboardScreen
/// - Shows grouped jobs (mechanic + assistant pair)
/// - Allows viewing token status and updating job statuses
class MechanicDashboardScreen extends StatefulWidget {
  const MechanicDashboardScreen({super.key});

  @override
  State<MechanicDashboardScreen> createState() =>
      _MechanicDashboardScreenState();
}

class _MechanicDashboardScreenState extends State<MechanicDashboardScreen> {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  StreamSubscription<DatabaseEvent>? _sub;
  Map<String, dynamic> groups = {};

  @override
  void initState() {
    super.initState();
    _sub = _db.child('jobs/group').onValue.listen((ev) {
      final map = <String, dynamic>{};
      if (ev.snapshot.exists) {
        final val = Map<String, dynamic>.from(ev.snapshot.value as Map);
        val.forEach((k, v) => map[k] = v);
      }
      if (mounted) setState(() => groups = map);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mechanic Dashboard')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: groups.keys.map((groupId) {
          final data = groups[groupId] as Map<dynamic, dynamic>;
          final mechanic = data['mechanic'] ?? {};
          final assistant = data['assistant'] ?? {};
          return Card(
            child: ListTile(
              title: Text('Group: $groupId'),
              subtitle: Text(
                  'Mech job: ${mechanic['jobId'] ?? '-'}\nAsst job: ${assistant['jobId'] ?? '-'}'),
              isThreeLine: true,
              trailing: IconButton(
                icon: const Icon(Icons.open_in_new),
                onPressed: () async {
                  // Open group details: for now show a dialog with basic info
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Group Details'),
                      content: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Group ID: $groupId'),
                            const SizedBox(height: 8),
                            Text('Mechanic Job: ${mechanic['jobId'] ?? '-'}'),
                            Text('Assistant Job: ${assistant['jobId'] ?? '-'}'),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close')),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
