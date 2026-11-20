/// AR Damage Recon — Evidence Capture Service (novel module).
///
/// Stores pre/post-service damage captures tagged with location + timestamp
/// and a lightweight integrity hash to build a tamper-evident evidence chain
/// for dispute-proofing.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../models/novel/damage_recon_model.dart';

class DamageReconService {
  DamageReconService._internal();
  static final DamageReconService _instance = DamageReconService._internal();
  factory DamageReconService() => _instance;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// ─── Capture a damage record ───
  Future<Map<String, dynamic>> capture({
    required String jobId,
    required String userId,
    required String crewId,
    required String phase, // pre_service or post_service
    required String imageUrl,
    required double lat,
    required double lng,
    String caption = '',
  }) async {
    try {
      final captureId = _newId();
      final capturedAt = DateTime.now();
      // Lightweight integrity hash of the record.
      final hash = _hash('$jobId|$phase|$capturedAt|$imageUrl|$lat|$lng');

      final capture = DamageCapture(
        captureId: captureId,
        jobId: jobId,
        userId: userId,
        crewId: crewId,
        phase: phase,
        imageUrl: imageUrl,
        lat: lat,
        lng: lng,
        caption: caption,
        capturedAt: capturedAt,
        hash: hash,
      );

      await _firestore
          .collection('damage_captures')
          .doc(captureId)
          .set(capture.toJson());

      return {'success': true, 'captureId': captureId, 'hash': hash};
    } catch (e) {
      debugPrint('DamageReconService.capture error: $e');
      return {'success': false, 'captureId': '', 'hash': ''};
    }
  }

  /// ─── List damage captures for a job ───
  Future<List<DamageCapture>> listForJob(String jobId) async {
    try {
      final snap = await _firestore
          .collection('damage_captures')
          .where('jobId', isEqualTo: jobId)
          .orderBy('capturedAt', descending: false)
          .get();
      return snap.docs
          .map((d) => DamageCapture.fromJson(
              Map<String, dynamic>.from(d.data() as Map)))
          .toList();
    } catch (e) {
      debugPrint('DamageReconService.listForJob error: $e');
      return [];
    }
  }

  /// ─── Verify integrity of a capture record ───
  bool verifyIntegrity(DamageCapture capture) {
    return capture.hash ==
        _hash(
            '${capture.jobId}|${capture.phase}|${capture.capturedAt}|${capture.imageUrl}|${capture.lat}|${capture.lng}');
  }

  String _newId() => 'dc-${DateTime.now().millisecondsSinceEpoch}-'
      '${DateTime.now().microsecondsSinceEpoch % 1000}';

  /// Lightweight FNV-1a 32-bit hash from a string.
  String _hash(String input) {
    var h = 0x811c9dc5;
    for (final c in input.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }
}
