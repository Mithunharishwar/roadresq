/// AR Damage Recon — Evidence Capture Screen (novel module).
///
/// Lets the crew capture pre/post-service damage evidence with a capturable
/// summary and verifies the integrity (hash) of each recorded capture.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/novel/damage_recon_model.dart';
import '../../providers/novel/damage_recon_provider.dart';
import '../../widgets/novel/novel_widgets.dart';

class DamageReconScreen extends ConsumerStatefulWidget {
  final String jobId;
  final String userId;
  final String crewId;

  const DamageReconScreen({
    super.key,
    this.jobId = 'job-1',
    this.userId = 'user1',
    this.crewId = 'Crew001',
  });

  @override
  ConsumerState<DamageReconScreen> createState() => _DamageReconScreenState();
}

class _DamageReconScreenState extends ConsumerState<DamageReconScreen> {
  bool _preCaptured = false;
  bool _postCaptured = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(damageReconProvider.notifier).loadForJob(widget.jobId);
    });
  }

  Future<void> _capture(String phase) async {
    await ref.read(damageReconProvider.notifier).capture(
          jobId: widget.jobId,
          userId: widget.userId,
          crewId: widget.crewId,
          phase: phase,
          imageUrl:
              'https://storage.example/captures/${widget.jobId}/$phase.jpg',
          lat: 13.0827,
          lng: 80.2707,
          caption: phase == 'pre_service'
              ? 'Vehicle condition before service'
              : 'Vehicle condition after service',
        );
    if (mounted) {
      setState(() {
        if (phase == 'pre_service') {
          _preCaptured = true;
        } else {
          _postCaptured = true;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(damageReconProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const NovelHero(
              title: 'Damage Recon',
              subtitle: 'Tamper-Evident Service Evidence Capture',
              icon: Icons.camera_alt_outlined,
              colors: [Color(0xFF4A148C), Color(0xFF9C27B0)],
            ),
            const SizedBox(height: 20),
            NovelSectionTitle(
              title: 'Capture Evidence',
              icon: Icons.add_a_photo,
              color: const Color(0xFF4A148C),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _captureButton(
                    icon: Icons.directions_car,
                    label: 'Pre-Service',
                    captured: _preCaptured,
                    onTap: () => _capture('pre_service'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _captureButton(
                    icon: Icons.check_circle_outline,
                    label: 'Post-Service',
                    captured: _postCaptured,
                    onTap: () => _capture('post_service'),
                  ),
                ),
              ],
            ),
            if (state.lastHash != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color:
                      const Color(0xFF4A148C).withAlpha((0.08 * 255).round()),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Latest capture hash:',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 12)),
                    const SizedBox(height: 4),
                    SelectableText(state.lastHash!,
                        style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF4A148C),
                            fontFamily: 'monospace')),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            NovelSectionTitle(
              title: 'Evidence Chain',
              icon: Icons.link,
              color: const Color(0xFF0D47A1),
            ),
            const SizedBox(height: 12),
            if (state.captures.isEmpty)
              const NovelEmptyCard(
                message: 'No damage captures recorded yet.',
                icon: Icons.camera_outlined,
              )
            else
              ...state.captures.map((c) => _evidenceTile(c)),
          ],
        ),
      ),
    );
  }

  Widget _captureButton({
    required IconData icon,
    required String label,
    required bool captured,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: captured ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: captured
              ? const Color(0xFF2E7D32).withAlpha((0.12 * 255).round())
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: captured
                ? const Color(0xFF2E7D32)
                : const Color(0xFF4A148C).withAlpha((0.3 * 255).round()),
          ),
        ),
        child: Column(
          children: [
            Icon(
              captured ? Icons.check_circle : icon,
              color:
                  captured ? const Color(0xFF2E7D32) : const Color(0xFF4A148C),
              size: 34,
            ),
            const SizedBox(height: 8),
            Text(
              captured ? '$label ✓' : label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: captured ? const Color(0xFF2E7D32) : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _evidenceTile(DamageCapture c) {
    final verified = ref.watch(damageReconProvider.notifier).verifyIntegrity(c);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF4A148C).withAlpha((0.1 * 255).round()),
              shape: BoxShape.circle,
            ),
            child: Icon(
              c.phase == 'pre_service'
                  ? Icons.directions_car
                  : Icons.fact_check,
              color: const Color(0xFF4A148C),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.phase == 'pre_service' ? 'Pre-Service' : 'Post-Service',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14),
                ),
                Text(c.caption ?? '',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black54)),
                Text(
                  '${c.capturedAt.toLocal().hour.toString().padLeft(2, '0')}:'
                  '${c.capturedAt.toLocal().minute.toString().padLeft(2, '0')} '
                  '${c.capturedAt.day}-${c.capturedAt.month}',
                  style: const TextStyle(fontSize: 11, color: Colors.black45),
                ),
              ],
            ),
          ),
          NovelStatusPill(
            text: verified ? 'Valid' : 'Tampered',
            color: verified ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F),
          ),
        ],
      ),
    );
  }
}
