/// RoadResQ Token Tracking Screen
/// Core Patent UI: Digital Vehicle Token System
///
/// Displays the full token lifecycle timeline for all 3 parties:
/// - User: Track vehicle status from tow to garage to repair to pickup
/// - Crew (Mechanic): Generate and scan tokens for handover
/// - Garage: Accept/release tokens and update repair status
///
/// Features:
/// - QR Code display + Scanner for token handover
/// - 5-step status timeline (generated → handed_to_garage → repair_started → ready_for_pickup → closed)
/// - All 3 parties can view and update token status
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/token_model.dart';
import '../providers/token_provider.dart';

/// ─── Token Tracking Screen ───
class TokenTrackingScreen extends ConsumerStatefulWidget {
  final String? tokenId;
  final String? tokenCode;
  final String userRole; // 'user', 'mechanic', 'assistant', 'garage'
  final String? userId;

  const TokenTrackingScreen({
    super.key,
    this.tokenId,
    this.tokenCode,
    required this.userRole,
    this.userId,
  });

  @override
  ConsumerState<TokenTrackingScreen> createState() =>
      _TokenTrackingScreenState();
}

class _TokenTrackingScreenState extends ConsumerState<TokenTrackingScreen> {
  bool _showScanner = false;
  bool _showQrCode = false;
  String? _scannedCode;
  bool _isUpdating = false;

  final TextEditingController _noteController = TextEditingController();

  // Status flow for the Digital Vehicle Token System (Patent)
  static const List<Map<String, dynamic>> _tokenStatuses = [
    {
      'key': 'generated',
      'label': 'Token Generated',
      'icon': Icons.confirmation_number,
      'description': 'Vehicle token created and assigned',
    },
    {
      'key': 'handed_to_garage',
      'label': 'Handed to Garage',
      'icon': Icons.local_car_wash,
      'description': 'Vehicle handed over to service garage',
    },
    {
      'key': 'repair_started',
      'label': 'Repair Started',
      'icon': Icons.build,
      'description': 'Garage has started repair work',
    },
    {
      'key': 'ready_for_pickup',
      'label': 'Ready for Pickup',
      'icon': Icons.check_circle_outline,
      'description': 'Vehicle is ready for customer pickup',
    },
    {
      'key': 'closed',
      'label': 'Closed',
      'icon': Icons.check_circle,
      'description': 'Token lifecycle completed',
    },
  ];

  @override
  void initState() {
    super.initState();

    // Load token if ID provided
    if (widget.tokenId != null) {
      Future.microtask(() {
        ref.read(tokenProvider.notifier).fetchToken(widget.tokenId!);
      });
    }

    // Validate token code if provided
    if (widget.tokenCode != null) {
      Future.microtask(() {
        ref.read(tokenProvider.notifier).validateTokenCode(widget.tokenCode!);
      });
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  /// ─── Handle QR Code detection ───
  void _onDetect(String code) {
    setState(() {
      _scannedCode = code;
      _showScanner = false;
    });

    // Validate the scanned code
    ref.read(tokenProvider.notifier).validateTokenCode(code);
  }

  /// ─── Update token status ───
  Future<void> _updateTokenStatus(String tokenId, String status) async {
    setState(() => _isUpdating = true);

    await ref.read(tokenProvider.notifier).updateTokenStatus(
          tokenId: tokenId,
          status: status,
          notes: _noteController.text.trim().isNotEmpty
              ? _noteController.text.trim()
              : null,
        );

    setState(() {
      _isUpdating = false;
    });
    _noteController.clear();
  }

  /// ─── Get current token state ───
  TokenModel? get _token => ref.watch(tokenProvider).currentToken;
  bool get _isLoading => ref.watch(tokenProvider).isLoading;
  String? get _error => ref.watch(tokenProvider).errorMessage;
  bool get _isValidating => ref.watch(tokenProvider).isValidating;

  /// ─── Check if user can update to this status ───
  bool _canUpdateTo(String statusKey) {
    if (_token == null) return false;

    final currentIndex = _token!.statusIndex;
    final targetIndex = _tokenStatuses.indexWhere((s) => s['key'] == statusKey);

    // Can only move forward in flow
    if (targetIndex <= currentIndex) return false;

    // Only mechanic/garage can update status
    if (widget.userRole == 'user') return false;

    // Must be exactly one step ahead (sequential flow)
    return targetIndex == currentIndex + 1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        title: const Text('Vehicle Token Tracking'),
        backgroundColor: const Color(0xFFD32F2F),
        foregroundColor: Colors.white,
        actions: [
          // Scan QR button
          if (widget.userRole != 'user')
            IconButton(
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: () => setState(() => _showScanner = !_showScanner),
              tooltip: 'Scan QR Code',
            ),
          // Show QR button
          IconButton(
            icon: const Icon(Icons.qr_code),
            onPressed: () => setState(() => _showQrCode = !_showQrCode),
            tooltip: 'Show QR Code',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading || _isValidating) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _token == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: Colors.red),
              ),
              const SizedBox(height: 20),
              if (_scannedCode != null)
                Text('Scanned Code: $_scannedCode',
                    style: const TextStyle(color: Colors.black54)),
            ],
          ),
        ),
      );
    }

    if (_token == null) {
      return _buildScanPrompt();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // QR Code display
          if (_showQrCode) _buildQrSection(),
          if (_showScanner) _buildScannerSection(),

          // Token Header
          _buildTokenHeader(),

          const SizedBox(height: 20),

          // Status Timeline
          _buildTimeline(),

          const SizedBox(height: 20),

          // Status Update Controls
          if (widget.userRole != 'user') _buildStatusControls(),

          const SizedBox(height: 20),

          // Token Details
          _buildTokenDetails(),
        ],
      ),
    );
  }

  Widget _buildScanPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.qr_code_scanner,
                size: 80, color: Color(0xFF0D47A1)),
            const SizedBox(height: 20),
            const Text(
              'Scan Token QR Code',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Scan the QR code on the token to view vehicle status.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, fontSize: 15),
            ),
            const SizedBox(height: 24),
            if (_showScanner) _buildScannerSection(),
            if (!_showScanner)
              ElevatedButton.icon(
                onPressed: () => setState(() => _showScanner = true),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan QR Code'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D47A1),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(200, 48),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildScannerSection() {
    return Container(
      height: 250,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF0D47A1), width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: MobileScanner(
        onDetect: (capture) {
          final barcode = capture.barcodes.firstOrNull;
          if (barcode != null && barcode.rawValue != null) {
            _onDetect(barcode.rawValue!);
          }
        },
      ),
    );
  }

  Widget _buildQrSection() {
    if (_token == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 10),
        ],
      ),
      child: Column(
        children: [
          const Text('Vehicle Token QR Code',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          QrImageView(
            data: _token!.tokenCode,
            version: QrVersions.auto,
            size: 180,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: Color(0xFFD32F2F),
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Color(0xFF0D47A1),
            ),
          ),
          const SizedBox(height: 12),
          SelectableText(
            _token!.tokenCode,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: 4,
              color: Color(0xFFD32F2F),
            ),
          ),
          const SizedBox(height: 4),
          const Text('Share this code with the garage',
              style: TextStyle(color: Colors.black54, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildTokenHeader() {
    if (_token == null) return const SizedBox.shrink();

    final currentStatus = _tokenStatuses.firstWhere(
      (s) => s['key'] == _token!.status,
      orElse: () => _tokenStatuses.first,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFD32F2F), Color(0xFFFF7043)],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(currentStatus['icon'] as IconData,
                  color: Colors.white, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  currentStatus['label'] as String,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Token: ${_token!.tokenCode}',
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 18,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Vehicle: ${_token!.vehicleNumber}',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    if (_token == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Token Status Timeline',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 18),
          ..._tokenStatuses.asMap().entries.map((entry) {
            final index = entry.key;
            final status = entry.value;
            final label = status['label'] as String;
            final icon = status['icon'] as IconData;
            final description = status['description'] as String;

            final isDone = _token!.statusIndex > index;
            final isActive = _token!.statusIndex == index;

            return _buildTimelineStep(
              index: index,
              icon: icon,
              label: label,
              description: description,
              isDone: isDone,
              isActive: isActive,
              isLast: index == _tokenStatuses.length - 1,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTimelineStep({
    required int index,
    required IconData icon,
    required String label,
    required String description,
    required bool isDone,
    required bool isActive,
    required bool isLast,
  }) {
    final color =
        isDone || isActive ? const Color(0xFFD32F2F) : Colors.grey.shade400;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Timeline indicator
        SizedBox(
          width: 40,
          child: Column(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isDone || isActive ? color : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: color.withAlpha(80),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: isDone
                    ? const Icon(Icons.check, color: Colors.white, size: 18)
                    : Icon(icon, color: color, size: 16),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 40,
                  color: isDone ? color : Colors.grey.shade300,
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Content
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight:
                        isActive || isDone ? FontWeight.bold : FontWeight.w500,
                    fontSize: 15,
                    color: isActive || isDone ? Colors.black87 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 13,
                  ),
                ),
                // Show timestamp if available
                if (isActive || isDone)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _getStatusTimestamp(_token!.status),
                      style: const TextStyle(
                        color: Colors.black38,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _getStatusTimestamp(String status) {
    if (_token == null) return '';

    DateTime? ts;
    switch (status) {
      case 'generated':
        ts = _token!.createdAt;
        break;
      case 'handed_to_garage':
        ts = _token!.handedOverAt;
        break;
      case 'repair_started':
        ts = _token!.repairStartedAt;
        break;
      case 'ready_for_pickup':
        ts = _token!.readyForPickupAt;
        break;
      case 'closed':
        ts = _token!.closedAt;
        break;
    }

    if (ts == null) return '';
    return '${ts.day}/${ts.month}/${ts.year} ${ts.hour}:${ts.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildStatusControls() {
    if (_token == null) return const SizedBox.shrink();

    // Find which status we can update to
    final nextStatuses =
        _tokenStatuses.where((s) => _canUpdateTo(s['key'] as String)).toList();

    if (nextStatuses.isEmpty) {
      if (_token!.status == 'closed') {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.green),
          ),
          child: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 12),
              Text('Token lifecycle completed.',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.green)),
            ],
          ),
        );
      }
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Update Token Status',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteController,
            decoration: const InputDecoration(
              labelText: 'Status Note (optional)',
              hintText: 'Add notes about this status update',
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 14),
          ...nextStatuses.map((status) {
            final key = status['key'] as String;
            final label = status['label'] as String;
            final icon = status['icon'] as IconData;

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isUpdating
                      ? null
                      : () => _updateTokenStatus(_token!.id, key),
                  icon: _isUpdating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(icon),
                  label: Text(label),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D47A1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTokenDetails() {
    if (_token == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Token Details',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _detailRow('Token Code', _token!.tokenCode),
          _detailRow('Vehicle Number', _token!.vehicleNumber),
          _detailRow('Vehicle Type', _token!.vehicleType),
          _detailRow('Status', _token!.statusDisplay),
          if (_token!.garageName != null && _token!.garageName!.isNotEmpty)
            _detailRow('Garage', _token!.garageName!),
          if (_token!.garagePhone != null && _token!.garagePhone!.isNotEmpty)
            _detailRow('Garage Phone', _token!.garagePhone!),
          if (_token!.notes != null && _token!.notes!.isNotEmpty)
            _detailRow('Notes', _token!.notes!),
          _detailRow('Created', _formatDate(_token!.createdAt)),
          if (_token!.closedAt != null)
            _detailRow('Closed', _formatDate(_token!.closedAt!)),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: const TextStyle(
                    color: Colors.black54, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
