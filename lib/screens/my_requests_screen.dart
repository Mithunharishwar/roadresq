import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/session/app_session.dart';
import '../services/api_service.dart';
import 'request_status_screen.dart';

class MyRequestsScreen extends StatefulWidget {
  const MyRequestsScreen({super.key, this.embedded = false});

  /// True when this screen is one tab of a shell that already draws the title.
  /// A nested Scaffold with its own AppBar produced two stacked "My Requests"
  /// headers, which is what the customer saw on screen.
  final bool embedded;

  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends State<MyRequestsScreen> {
  List requests = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadRequests();
  }

  Future<void> loadRequests() async {
    try {
      // Only this customer's jobs. Falls back to an empty list rather than the
      // unscoped table when the session has no phone.
      final phone = AppSession.phone ?? '';
      final data = await ApiService.fetchUserRequests(phone);

      if (!mounted) return;
      setState(() {
        requests = data;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
      });
    }
  }

  Color getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.red;
      case 'assigned':
        return Colors.orange;
      case 'accepted':
        return Colors.blue;
      case 'on_the_way':
      case 'on the way':
        return Colors.deepPurple;
      case 'reached':
        return Colors.teal;
      case 'completed':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('My Requests'),
        backgroundColor: const Color(0xFFD32F2F),
        foregroundColor: Colors.white,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : requests.isEmpty
              ? const Center(child: Text('No requests found'))
              : RefreshIndicator(
                  onRefresh: loadRequests,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: requests.length,
                    itemBuilder: (context, index) {
                      final req = requests[index];
                      final status = (req['status'] ?? 'Pending').toString();

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceOf(context),
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
                            Text(
                              req['issue'] ?? 'Request',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text('Vehicle: ${req['vehicle'] ?? ''}'),
                            Text('Location: ${req['locationText'] ?? ''}'),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: getStatusColor(status),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                status,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => RequestStatusScreen(
                                        requestId: req['_id'],
                                        issue: req['issue'] ?? '',
                                        vehicle: req['vehicle'] ?? '',
                                        location: req['locationText'] ?? '',
                                      ),
                                    ),
                                  );
                                },
                                child: const Text('Track Rescue'),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
