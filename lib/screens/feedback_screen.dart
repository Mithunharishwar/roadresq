// FILE: lib/screens/feedback_screen.dart
/// §48 — submit a complaint or feedback, then track its status.
///
/// Backed by `POST /api/feedback` and `GET /api/feedback?userId=…`. A ticket
/// keeps a status trail (`open → in_review → resolved/closed`) which is
/// rendered as a timeline, so "track status" means real stored state rather
/// than a static "submitted" message.
library;

import 'package:material_ui/material_ui.dart';

import '../core/session/app_session.dart';
import '../core/theme/role_colors.dart';
import '../services/module_api.dart';
import '../widgets/rq_async.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key, this.requestId = ''});

  /// Pre-fills the ticket with the job it relates to, when opened from a job.
  final String requestId;

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  static const List<String> _categories = <String>[
    'Payment',
    'Crew behaviour',
    'Late arrival',
    'App problem',
    'Safety',
    'Other',
  ];

  final TextEditingController _subject = TextEditingController();
  final TextEditingController _message = TextEditingController();

  String _category = _categories.first;
  List<Map<String, dynamic>> _tickets = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTickets();
  }

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _loadTickets() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await ModuleApi.feedbackFor(AppSession.id ?? '');
      if (!mounted) return;
      setState(() {
        _tickets = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = rqMessage(e);
      });
    }
  }

  Future<void> _submit() async {
    if (_message.text.trim().length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please describe the issue in at least a sentence.',
              style: TextStyle(inherit: true)),
        ),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      await ModuleApi.submitFeedback(
        userId: AppSession.id ?? '',
        role: AppSession.role ?? '',
        category: _category,
        subject: _subject.text.trim(),
        message: _message.text.trim(),
        requestId: widget.requestId,
      );
      _message.clear();
      _subject.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report submitted. Support can now see it.',
              style: TextStyle(inherit: true)),
        ),
      );
      await _loadTickets();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(rqMessage(e), style: const TextStyle(inherit: true))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'resolved':
      case 'closed':
        return RoleColors.assistant;
      case 'in_review':
        return RoleColors.mechanic;
      default:
        return RoleColors.garage;
    }
  }

  String _statusLabel(String status) => status
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Feedback & complaints',
            style: TextStyle(inherit: true)),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadTickets,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Report an issue',
              style: theme.textTheme.titleSmall
                  ?.copyWith(inherit: true, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(
              labelText: 'Category',
              border: OutlineInputBorder(),
            ),
            style: TextStyle(
                inherit: true, color: theme.colorScheme.onSurface),
            items: _categories
                .map((c) => DropdownMenuItem<String>(
                      value: c,
                      child: Text(c, style: const TextStyle(inherit: true)),
                    ))
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _category = value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _subject,
            maxLength: 120,
            style: const TextStyle(inherit: true),
            decoration: const InputDecoration(
              labelText: 'Subject (optional)',
              hintText: 'Short summary',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _message,
            minLines: 4,
            maxLines: 8,
            maxLength: 2000,
            style: const TextStyle(inherit: true),
            decoration: const InputDecoration(
              labelText: 'What happened?',
              hintText: 'Include the job id if this is about a rescue.',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 48,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: RoleColors.user),
              onPressed: _sending ? null : _submit,
              child: _sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Submit report',
                      style: TextStyle(
                          inherit: true, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 24),
          Text('Your reports',
              style: theme.textTheme.titleSmall
                  ?.copyWith(inherit: true, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (_loading)
            const RqLoading(label: 'Loading your reports…')
          else if (_error != null)
            RqError(message: _error!, onRetry: _loadTickets)
          else if (_tickets.isEmpty)
            const RqEmpty(
              icon: Icons.receipt_long_outlined,
              title: 'No reports yet',
              message: 'Anything you submit will appear here with its status.',
            )
          else
            ..._tickets.map(_ticketCard),
        ],
      ),
    );
  }

  Widget _ticketCard(Map<String, dynamic> ticket) {
    final status = (ticket['status'] ?? 'open').toString();
    final color = _statusColor(status);
    final updates = (ticket['updates'] as List?) ?? const [];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: RoleColors.tint(color, opacity: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  (ticket['subject'] ?? '').toString().isEmpty
                      ? (ticket['category'] ?? 'Report').toString()
                      : ticket['subject'].toString(),
                  style: const TextStyle(
                      inherit: true, fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: RoleColors.tint(color, opacity: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _statusLabel(status),
                  style: TextStyle(
                      inherit: true,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            (ticket['message'] ?? '').toString(),
            style: const TextStyle(inherit: true, fontSize: 12),
          ),
          if (updates.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...updates.take(3).map((u) {
              final map = u is Map ? u : const {};
              return Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Icon(Icons.circle,
                        size: 6, color: _statusColor('${map['status']}')),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${_statusLabel('${map['status']}')} · ${map['at'] ?? ''}',
                        style: const TextStyle(
                            inherit: true,
                            fontSize: 10,
                            color: RoleColors.neutral),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
