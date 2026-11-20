/// AR Damage Recon — Evidence Model (novel module).
///
/// Pre/post-service damage documentation capture. Each capture is tagged with
/// location, timestamp, and job id to form a secure, tamper-evident evidence
/// chain useful for dispute-proofing.
class DamageCapture {
  final String captureId;
  final String jobId;
  final String userId;
  final String crewId;
  final String phase; // pre_service, post_service
  final String imageUrl;
  final double lat;
  final double lng;
  final String? caption;
  final DateTime capturedAt;
  final String hash; // lightweight integrity hash of the record

  DamageCapture({
    this.captureId = '',
    this.jobId = '',
    this.userId = '',
    this.crewId = '',
    this.phase = 'pre_service',
    this.imageUrl = '',
    this.lat = 0,
    this.lng = 0,
    this.caption,
    DateTime? capturedAt,
    this.hash = '',
  }) : capturedAt = capturedAt ?? DateTime.now();

  factory DamageCapture.fromJson(Map<String, dynamic> json) => DamageCapture(
        captureId: json['captureId']?.toString() ?? '',
        jobId: json['jobId']?.toString() ?? '',
        userId: json['userId']?.toString() ?? '',
        crewId: json['crewId']?.toString() ?? '',
        phase: json['phase']?.toString() ?? 'pre_service',
        imageUrl: json['imageUrl']?.toString() ?? '',
        lat: (json['lat'] as num?)?.toDouble() ?? 0,
        lng: (json['lng'] as num?)?.toDouble() ?? 0,
        caption: json['caption']?.toString(),
        capturedAt: json['capturedAt'] != null
            ? DateTime.tryParse(json['capturedAt'].toString()) ?? DateTime.now()
            : DateTime.now(),
        hash: json['hash']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
        'captureId': captureId,
        'jobId': jobId,
        'userId': userId,
        'crewId': crewId,
        'phase': phase,
        'imageUrl': imageUrl,
        'lat': lat,
        'lng': lng,
        'caption': caption,
        'capturedAt': capturedAt.toIso8601String(),
        'hash': hash,
      };
}
