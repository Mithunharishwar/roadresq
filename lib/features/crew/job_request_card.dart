// FILE: lib/features/crew/job_request_card.dart
/// Job Request Card — Displays incoming job details for crew (Mechanic/Assistant)
/// Shows: Customer name, issue, vehicle, location, distance, ETA
/// Buttons: Accept (green) / Reject (red)
/// On accept: Updates job doc status to 'accepted', emits socket event
library;

import 'package:material_ui/material_ui.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_constants.dart';
import '../../services/firestore_service.dart';

/// Job data model for the card
class JobRequestData {
  final String jobId;
  final String requestId;
  final String customerName;
  final String customerPhone;
  final String issueType;
  final String vehicleType;
  final String address;
  final double distanceKm;
  final double etaMinutes;
  final String status;
  final double? lat;
  final double? lng;

  JobRequestData({
    required this.jobId,
    required this.requestId,
    this.customerName = '',
    this.customerPhone = '',
    this.issueType = '',
    this.vehicleType = '',
    this.address = '',
    this.distanceKm = 0.0,
    this.etaMinutes = 0.0,
    this.status = 'pending',
    this.lat,
    this.lng,
  });

  factory JobRequestData.fromMap(Map<String, dynamic> map, String id) {
    return JobRequestData(
      jobId: id,
      requestId: map['requestId'] ?? '',
      customerName: map['userName'] ?? map['name'] ?? 'Customer',
      customerPhone: map['userPhone'] ?? map['phone'] ?? '',
      issueType: map['issueType'] ?? map['issue'] ?? '',
      vehicleType: map['vehicleType'] ?? map['vehicle'] ?? '',
      address: map['address'] ?? map['locationText'] ?? '',
      distanceKm: (map['distanceKm'] ?? 0.0).toDouble(),
      etaMinutes: (map['etaMinutes'] ?? 0.0).toDouble(),
      status: map['status'] ?? 'pending',
      lat: (map['pickupLocation'] is GeoPoint)
          ? (map['pickupLocation'] as GeoPoint).latitude
          : (map['lat'] is num ? (map['lat'] as num).toDouble() : null),
      lng: (map['pickupLocation'] is GeoPoint)
          ? (map['pickupLocation'] as GeoPoint).longitude
          : (map['lng'] is num ? (map['lng'] as num).toDouble() : null),
    );
  }
}

/// Job Request Card Widget
class JobRequestCard extends StatefulWidget {
  final JobRequestData job;
  final String crewId;
  final String crewRole; // 'mechanic' or 'assistant'
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onViewMap;

  const JobRequestCard({
    super.key,
    required this.job,
    required this.crewId,
    required this.crewRole,
    this.onAccept,
    this.onReject,
    this.onViewMap,
  });

  @override
  State<JobRequestCard> createState() => _JobRequestCardState();
}

class _JobRequestCardState extends State<JobRequestCard> {
  bool _isAccepting = false;
  bool _isRejecting = false;

  final FirestoreService _firestore = FirestoreService();

  Color get _roleColor {
    return widget.crewRole == 'mechanic'
        ? const Color(0xFF0D47A1)
        : const Color(0xFF2E7D32);
  }

  IconData get _roleIcon {
    return widget.crewRole == 'mechanic' ? Icons.build : Icons.two_wheeler;
  }

  Future<void> _acceptJob() async {
    setState(() => _isAccepting = true);

    try {
      await _firestore.updateDocument(
        collection: AppConstants.collectionJobs,
        documentId: widget.job.jobId,
        updates: {
          'status': 'accepted',
          'acceptedAt': Timestamp.fromDate(DateTime.now()),
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        },
      );

      // Also update the request status
      if (widget.job.requestId.isNotEmpty) {
        final roleField = widget.crewRole == 'mechanic'
            ? 'assignedMechanicId'
            : 'assignedAssistantId';
        await _firestore.updateDocument(
          collection: AppConstants.collectionRequests,
          documentId: widget.job.requestId,
          updates: {
            roleField: widget.crewId,
            'status': 'accepted',
            'updatedAt': Timestamp.fromDate(DateTime.now()),
          },
        );
      }

      widget.onAccept?.call();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Job accepted! Navigate to customer location.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to accept job: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAccepting = false);
    }
  }

  Future<void> _rejectJob() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Job?'),
        content: const Text('Are you sure you want to reject this request?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isRejecting = true);

    try {
      await _firestore.updateDocument(
        collection: AppConstants.collectionJobs,
        documentId: widget.job.jobId,
        updates: {
          'status': 'cancelled',
          'cancelledBy': widget.crewId,
          'cancellationReason': 'Rejected by ${widget.crewRole}',
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        },
      );

      widget.onReject?.call();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Job rejected')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reject job: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isRejecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPending = widget.job.status == 'pending';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _roleColor.withAlpha(30),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(_roleIcon, color: _roleColor, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.job.customerName,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.crewRole == 'mechanic' ? 'Tow/Repair' : 'Customer Pickup'} Request',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Distance badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _roleColor.withAlpha(20),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${widget.job.distanceKm.toStringAsFixed(1)} km',
                      style: TextStyle(
                        color: _roleColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Details
              _detailRow(Icons.build_outlined, 'Issue', widget.job.issueType),
              const SizedBox(height: 6),
              _detailRow(
                Icons.directions_car_outlined,
                'Vehicle',
                widget.job.vehicleType,
              ),
              const SizedBox(height: 6),
              _detailRow(
                Icons.location_on_outlined,
                'Location',
                widget.job.address,
              ),
              const SizedBox(height: 6),
              _detailRow(
                Icons.schedule,
                'ETA',
                '${widget.job.etaMinutes.toStringAsFixed(0)} min',
              ),
              const SizedBox(height: 6),
              _detailRow(
                Icons.phone_outlined,
                'Phone',
                widget.job.customerPhone,
              ),

              const SizedBox(height: 16),

              // Action buttons
              Row(
                children: [
                  // View on Map
                  if (widget.onViewMap != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: widget.onViewMap,
                        icon: const Icon(Icons.map_outlined, size: 18),
                        label: const Text('Map'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _roleColor,
                          side: BorderSide(color: _roleColor.withAlpha(80)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  if (widget.onViewMap != null) const SizedBox(width: 8),

                  // Accept button
                  if (isPending)
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _isAccepting ? null : _acceptJob,
                        icon: _isAccepting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_circle_outline, size: 18),
                        label: Text(_isAccepting ? 'Accepting...' : 'Accept'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),

                  if (isPending) const SizedBox(width: 8),

                  // Reject button
                  if (isPending)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isRejecting ? null : _rejectJob,
                        icon: _isRejecting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.red,
                                ),
                              )
                            : const Icon(Icons.cancel_outlined, size: 18),
                        label: const Text('Reject'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade500),
        const SizedBox(width: 8),
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}
