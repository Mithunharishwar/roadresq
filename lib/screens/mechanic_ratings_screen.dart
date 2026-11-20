// FILE: lib/screens/mechanic_ratings_screen.dart
/// §31 — a mechanic's average rating and the reviews behind it.
///
/// Reads `GET /api/mechanics/<id>/ratings`, which recomputes the aggregate from
/// stored ratings. An empty list means "no ratings yet", never a placeholder
/// score.
library;

import 'package:flutter/material.dart';

import '../core/session/app_session.dart';
import '../core/theme/role_colors.dart';
import '../services/module_api.dart';
import '../widgets/rq_async.dart';

class MechanicRatingsScreen extends StatefulWidget {
  const MechanicRatingsScreen({super.key, this.mechanicId});

  final String? mechanicId;

  @override
  State<MechanicRatingsScreen> createState() => _MechanicRatingsScreenState();
}

class _MechanicRatingsScreenState extends State<MechanicRatingsScreen> {
  Map<String, dynamic> _aggregate = const {};
  List<Map<String, dynamic>> _ratings = const [];
  bool _loading = true;
  String? _error;

  String get _id => widget.mechanicId ?? AppSession.id ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_id.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'No mechanic is signed in.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final body = await ModuleApi.ratings(_id);
      final aggregate = body['aggregate'];
      final rows = (body['ratings'] as List?) ?? const [];
      if (!mounted) return;
      setState(() {
        _aggregate =
            aggregate is Map ? aggregate.cast<String, dynamic>() : const {};
        _ratings = rows
            .whereType<Map>()
            .map((r) => r.cast<String, dynamic>())
            .toList();
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

  @override
  Widget build(BuildContext context) {
    final average = (_aggregate['rating'] as num?)?.toDouble() ?? 0.0;
    final count = (_aggregate['ratingCount'] as num?)?.toInt() ?? 0;

    // Count per star bucket, computed from the stored rows.
    final buckets = List<int>.filled(5, 0);
    for (final r in _ratings) {
      final value = (r['rating'] as num?)?.round() ?? 0;
      if (value >= 1 && value <= 5) buckets[value - 1]++;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ratings & reviews',
            style: TextStyle(inherit: true)),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const RqLoading(label: 'Loading ratings…')
          : _error != null
              ? RqError(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              average.toStringAsFixed(1),
                              style: const TextStyle(
                                  inherit: true,
                                  fontSize: 40,
                                  fontWeight: FontWeight.w700),
                            ),
                            Row(
                              children: List.generate(5, (i) {
                                return Icon(
                                  i < average.round()
                                      ? Icons.star_rounded
                                      : Icons.star_border_rounded,
                                  size: 16,
                                  color: const Color(0xFFF9A825),
                                );
                              }),
                            ),
                            Text(
                              count == 0 ? 'No ratings yet' : '$count ratings',
                              style: const TextStyle(
                                  inherit: true,
                                  fontSize: 11,
                                  color: RoleColors.neutral),
                            ),
                          ],
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: Column(
                            children: List.generate(5, (index) {
                              final star = 5 - index;
                              final value = buckets[star - 1];
                              final ratio = count == 0 ? 0.0 : value / count;
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  children: [
                                    Text('$star',
                                        style: const TextStyle(
                                            inherit: true, fontSize: 10)),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: ratio,
                                          minHeight: 6,
                                          backgroundColor: RoleColors.tint(
                                              RoleColors.neutral,
                                              opacity: 0.12),
                                          color: const Color(0xFFF9A825),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    SizedBox(
                                      width: 18,
                                      child: Text('$value',
                                          style: const TextStyle(
                                              inherit: true,
                                              fontSize: 10,
                                              color: RoleColors.neutral)),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Divider(),
                    if (_ratings.isEmpty)
                      const RqEmpty(
                        icon: Icons.star_border,
                        title: 'No reviews yet',
                        message:
                            'Customers can rate a rescue once payment is '
                            'completed. Reviews appear here after that.',
                      )
                    else
                      ..._ratings.map((rating) {
                        final stars = (rating['rating'] as num?)?.toInt() ?? 0;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  ...List.generate(
                                    5,
                                    (i) => Icon(
                                      i < stars
                                          ? Icons.star_rounded
                                          : Icons.star_border_rounded,
                                      size: 14,
                                      color: const Color(0xFFF9A825),
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    (rating['createdAt'] ?? '')
                                        .toString()
                                        .split('T')
                                        .first,
                                    style: const TextStyle(
                                        inherit: true,
                                        fontSize: 10,
                                        color: RoleColors.neutral),
                                  ),
                                ],
                              ),
                              if ((rating['review'] ?? '')
                                  .toString()
                                  .isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  rating['review'].toString(),
                                  style: const TextStyle(
                                      inherit: true, fontSize: 12),
                                ),
                              ],
                            ],
                          ),
                        );
                      }),
                  ],
                ),
    );
  }
}
