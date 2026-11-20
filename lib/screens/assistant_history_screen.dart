import 'package:flutter/material.dart';
import '../services/assistant_service.dart';

/// AssistantHistoryScreen
///
/// Shows the job history for an assistant (rider) crew member.
/// Displays completed jobs with details like customer name, issue,
/// location, and completion time.
class AssistantHistoryScreen extends StatefulWidget {
  final String assistantId;

  const AssistantHistoryScreen({super.key, required this.assistantId});

  @override
  State<AssistantHistoryScreen> createState() => _AssistantHistoryScreenState();
}

class _AssistantHistoryScreenState extends State<AssistantHistoryScreen> {
  final AssistantService _service = AssistantService();
  List jobs = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadHistory();
  }

  Future<void> loadHistory() async {
    try {
      setState(() => loading = true);
      final allJobs = await _service.fetchAssignedJobs(
        assistantId: widget.assistantId,
      );

      // Filter to show only completed jobs
      final completed = allJobs.where((j) {
        final status = (j['status'] ?? '').toString().toLowerCase();
        return status == 'completed';
      }).toList();

      if (!mounted) return;
      setState(() {
        jobs = completed;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : jobs.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Container(
                      padding: const EdgeInsets.all(22),
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
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history, size: 46, color: Colors.green),
                          SizedBox(height: 14),
                          Text(
                            'No Completed Rides',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Your completed pickup jobs will appear here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: loadHistory,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: jobs.length,
                    itemBuilder: (_, index) {
                      final job = jobs[index] as Map;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  Colors.black.withAlpha((0.05 * 255).round()),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const CircleAvatar(
                                  radius: 20,
                                  backgroundColor: Color(0xFFE8F5E9),
                                  child: Icon(Icons.person,
                                      color: Color(0xFF2E7D32)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    job['name'] ?? 'Customer',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'Completed',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _infoRow(Icons.build_circle_outlined, 'Issue',
                                '${job['issue'] ?? ''}'),
                            _infoRow(Icons.directions_car_outlined, 'Vehicle',
                                '${job['vehicle'] ?? ''}'),
                            _infoRow(Icons.location_on_outlined, 'Location',
                                '${job['locationText'] ?? ''}'),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _infoRow(IconData icon, String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.black54),
          const SizedBox(width: 8),
          Text('$title: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Expanded(
              child:
                  Text(value, style: const TextStyle(color: Colors.black54))),
        ],
      ),
    );
  }
}
