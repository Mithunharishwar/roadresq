import 'package:flutter/material.dart';

/// A reusable card widget for displaying job information.
class JobCard extends StatelessWidget {
  final String customerName;
  final String issue;
  final String vehicle;
  final String location;
  final double distanceKm;
  final String status;
  final VoidCallback? onTrack;
  final VoidCallback? onAction;

  const JobCard({
    super.key,
    required this.customerName,
    required this.issue,
    required this.vehicle,
    required this.location,
    required this.distanceKm,
    required this.status,
    this.onTrack,
    this.onAction,
  });

  Color _statusColor(BuildContext context) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'accepted':
        return Colors.blue;
      case 'in_progress':
      case 'in progress':
        return Colors.amber.shade700;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _statusLabel() {
    switch (status.toLowerCase()) {
      case 'in_progress':
        return 'In Progress';
      case 'in progress':
        return 'In Progress';
      default:
        return status[0].toUpperCase() + status.substring(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Customer name + status badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      customerName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _statusColor(context).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _statusColor(context).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      _statusLabel(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _statusColor(context),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Detail rows
              _DetailRow(
                icon: Icons.build_outlined,
                label: 'Issue',
                value: issue,
              ),
              const SizedBox(height: 8),
              _DetailRow(
                icon: Icons.directions_car_outlined,
                label: 'Vehicle',
                value: vehicle,
              ),
              const SizedBox(height: 8),
              _DetailRow(
                icon: Icons.location_on_outlined,
                label: 'Location',
                value: location,
              ),
              const SizedBox(height: 8),
              _DetailRow(
                icon: Icons.speed_outlined,
                label: 'Distance',
                value: '${distanceKm.toStringAsFixed(1)} km',
              ),

              // Action buttons
              const SizedBox(height: 16),
              Row(
                children: [
                  if (onTrack != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onTrack,
                        icon: const Icon(Icons.navigation, size: 18),
                        label: const Text('Track'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).primaryColor,
                          side: BorderSide(
                            color: Theme.of(context).primaryColor,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  if (onTrack != null && onAction != null)
                    const SizedBox(width: 12),
                  if (onAction != null)
                    Expanded(
                      child: ElevatedButton(
                        onPressed: onAction,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'Action',
                          style: TextStyle(fontWeight: FontWeight.w600),
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
}

/// Internal helper widget for rendering a detail row with icon.
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade800,
                height: 1.3,
              ),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
