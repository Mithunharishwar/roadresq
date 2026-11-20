// FILE: lib/screens/rating_screen.dart
/// §47 — 5-star rating with a written review.
///
/// Talks to `POST /api/ratings`, which only accepts a rating once the rescue
/// has been paid for. When the backend refuses (not yet paid, already rated),
/// its message is shown as-is: the screen never reports a rating as saved when
/// the server rejected it.
library;

import 'package:flutter/material.dart';

import '../core/theme/role_colors.dart';
import '../services/module_api.dart';
import '../widgets/rq_async.dart';

class RatingScreen extends StatefulWidget {
  const RatingScreen({
    super.key,
    required this.requestId,
    this.mechanicName = '',
    this.crewName = '',
  });

  final String requestId;
  final String mechanicName;
  final String crewName;

  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen> {
  static const List<String> _quickTags = <String>[
    'Arrived fast',
    'Clear explanation',
    'Fair price',
    'Friendly',
    'Fixed it properly',
    'Kept me updated',
  ];

  final TextEditingController _review = TextEditingController();
  final Set<String> _selectedTags = <String>{};
  int _stars = 0;
  bool _submitting = false;

  @override
  void dispose() {
    _review.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_stars == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pick a star rating first.',
              style: TextStyle(inherit: true)),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    final parts = <String>[
      if (_selectedTags.isNotEmpty) _selectedTags.join(', '),
      if (_review.text.trim().isNotEmpty) _review.text.trim(),
    ];

    try {
      await ModuleApi.rate(
        requestId: widget.requestId,
        rating: _stars.toDouble(),
        review: parts.join(' — '),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Thanks — your rating was saved.',
              style: TextStyle(inherit: true)),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Rating not saved',
              style: TextStyle(inherit: true)),
          content: Text(rqMessage(e), style: const TextStyle(inherit: true)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close', style: TextStyle(inherit: true)),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final who = widget.mechanicName.isNotEmpty
        ? widget.mechanicName
        : (widget.crewName.isNotEmpty ? widget.crewName : 'your crew');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rate your rescue', style: TextStyle(inherit: true)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'How was $who?',
            style: theme.textTheme.titleMedium
                ?.copyWith(inherit: true, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          const Text(
            'Your rating is public to other customers and affects dispatch '
            'priority.',
            style: TextStyle(
                inherit: true, fontSize: 12, color: RoleColors.neutral),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final value = index + 1;
              final active = value <= _stars;
              return IconButton(
                onPressed: () => setState(() => _stars = value),
                iconSize: 42,
                tooltip: '$value star${value == 1 ? '' : 's'}',
                icon: Icon(
                  active ? Icons.star_rounded : Icons.star_border_rounded,
                  color: active
                      ? const Color(0xFFF9A825)
                      : RoleColors.neutral,
                ),
              );
            }),
          ),
          Center(
            child: Text(
              _stars == 0
                  ? 'Tap a star'
                  : const [
                      '',
                      'Very poor',
                      'Poor',
                      'Okay',
                      'Good',
                      'Excellent',
                    ][_stars],
              style: const TextStyle(
                  inherit: true, fontSize: 13, color: RoleColors.neutral),
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _quickTags.map((tag) {
              final selected = _selectedTags.contains(tag);
              return FilterChip(
                label: Text(tag, style: const TextStyle(inherit: true, fontSize: 12)),
                selected: selected,
                onSelected: (on) => setState(() {
                  if (on) {
                    _selectedTags.add(tag);
                  } else {
                    _selectedTags.remove(tag);
                  }
                }),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _review,
            minLines: 3,
            maxLines: 6,
            maxLength: 500,
            style: const TextStyle(inherit: true),
            decoration: const InputDecoration(
              labelText: 'Review (optional)',
              hintText: 'What went well, or what should improve?',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 50,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: RoleColors.user),
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Submit rating',
                      style: TextStyle(
                          inherit: true,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Ratings can only be submitted after the payment is completed. '
            'If the backend reports that the job is not payable yet, finish '
            'the payment first.',
            style: TextStyle(
                inherit: true, fontSize: 11, color: RoleColors.neutral),
          ),
        ],
      ),
    );
  }
}
