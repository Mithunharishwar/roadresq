// FILE: lib/features/garage/garage_scanner.dart
/// Garage Scanner — Scans QR code, verifies 6-digit token, and updates status
/// Used by garage staff to accept vehicles via digital token
/// Token flow: scanned → validates → updates to "handed_to_garage"
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_constants.dart';
import '../../models/token_model.dart';
import '../../providers/token_provider.dart';
import '../../services/firestore_service.dart';

class GarageScanner extends ConsumerStatefulWidget {
  final String garageId;
  final String garageName;

  const GarageScanner({
    super.key,
    required this.garageId,
    this.garageName = 'Garage',
  });

  @override
  ConsumerState<GarageScanner> createState() => _GarageScannerState();
}

class _GarageScannerState extends ConsumerState<GarageScanner> {
  bool _isScanning = true;
  bool _isProcessing = false;
  TokenModel? _verifiedToken;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
  }

  void _onDetect(BarcodeCapture capture) {
    if (!_isScanning || _isProcessing) return;

    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue == null) return;

    final code = barcode!.rawValue!;
    setState(() {
      _isScanning = false;
    });

    _verifyAndProcessToken(code);
  }

  Future<void> _verifyAndProcessToken(String code) async {
    setState(() => _isProcessing = true);

    try {
      // Validate token via provider
      final isValid =
          await ref.read(tokenProvider.notifier).validateTokenCode(code);

      if (!isValid) {
        setState(() {
          _statusMessage = '❌ Invalid token code';
          _isProcessing = false;
        });
        return;
      }

      final token = ref.read(tokenProvider).currentToken;
      if (token == null) {
        setState(() {
          _statusMessage = '❌ Token not found';
          _isProcessing = false;
        });
        return;
      }

// After successful Cloud-Function verification the token is marked
      // "consumed" (one-time use enforced server-side). We now transition it
      // to the garage lifecycle start state.
      if (token.status != 'consumed' && token.status != 'generated') {
        setState(() {
          _statusMessage =
              '⚠️ Token is already in "${token.statusDisplay}". Cannot re-use.';
          _isProcessing = false;
        });
        return;
      }

      // Update token status to "handed_to_garage"
      await ref.read(tokenProvider.notifier).updateTokenStatus(
            tokenId: token.id,
            status: 'handed_to_garage',
            notes: 'Vehicle received at ${widget.garageName}',
          );

      // Also update the garage assignment
      await FirestoreService().updateDocument(
        collection: AppConstants.collectionTokens,
        documentId: token.id,
        updates: {
          'garageId': widget.garageId,
          'garageName': widget.garageName,
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        },
      );

      setState(() {
        _verifiedToken = ref.read(tokenProvider).currentToken;
        _statusMessage =
            '✅ Token validated! Vehicle handed to ${widget.garageName}';
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _statusMessage = '❌ Error: ${e.toString()}';
        _isProcessing = false;
      });
    }
  }

  Future<void> _updateTokenStatus(String status) async {
    if (_verifiedToken == null) return;

    setState(() => _isProcessing = true);

    try {
      await ref.read(tokenProvider.notifier).updateTokenStatus(
            tokenId: _verifiedToken!.id,
            status: status,
            notes: 'Status updated by ${widget.garageName}',
          );

      setState(() {
        _verifiedToken = ref.read(tokenProvider).currentToken;
        _isProcessing = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Status updated to: ${_verifiedToken?.statusDisplay}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _statusMessage = '❌ Update failed: ${e.toString()}';
        _isProcessing = false;
      });
    }
  }

  void _resetScanner() {
    setState(() {
      _isScanning = true;
      _isProcessing = false;
      _verifiedToken = null;
      _statusMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        title: Text(widget.garageName),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        actions: [
          if (!_isScanning)
            IconButton(
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: _resetScanner,
              tooltip: 'Scan Another',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Scanner section
            if (_isScanning)
              Container(
                height: 300,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF2E7D32),
                    width: 3,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: MobileScanner(
                  onDetect: _onDetect,
                  controller: MobileScannerController(
                    detectionSpeed: DetectionSpeed.normal,
                    facing: CameraFacing.back,
                  ),
                ),
              ),

            if (_isScanning) ...[
              const SizedBox(height: 16),
              const Text(
                'Scan the vehicle token QR code',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Hold the QR code in front of the camera',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],

            // Processing indicator
            if (_isProcessing)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Verifying token...',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

            // Status message
            if (_statusMessage != null && !_isProcessing)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(top: 16),
                decoration: BoxDecoration(
                  color: _statusMessage!.startsWith('✅')
                      ? Colors.green.shade50
                      : _statusMessage!.startsWith('⚠️')
                          ? Colors.orange.shade50
                          : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _statusMessage!.startsWith('✅')
                        ? Colors.green
                        : _statusMessage!.startsWith('⚠️')
                            ? Colors.orange
                            : Colors.red,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _statusMessage!.startsWith('✅')
                          ? Icons.check_circle
                          : _statusMessage!.startsWith('⚠️')
                              ? Icons.warning
                              : Icons.error,
                      color: _statusMessage!.startsWith('✅')
                          ? Colors.green
                          : _statusMessage!.startsWith('⚠️')
                              ? Colors.orange
                              : Colors.red,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _statusMessage!,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: _statusMessage!.startsWith('✅')
                              ? Colors.green.shade800
                              : _statusMessage!.startsWith('⚠️')
                                  ? Colors.orange.shade800
                                  : Colors.red.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Verified token details
            if (_verifiedToken != null && !_isProcessing) ...[
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(13),
                      blurRadius: 14,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle,
                            color: Colors.green, size: 24),
                        const SizedBox(width: 8),
                        const Text(
                          'Verified Token',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    _detailRow('Token Code', _verifiedToken!.tokenCode),
                    _detailRow('Vehicle No', _verifiedToken!.vehicleNumber),
                    _detailRow('Vehicle Type', _verifiedToken!.vehicleType),
                    _detailRow('Status', _verifiedToken!.statusDisplay),
                    if (_verifiedToken!.garageName != null)
                      _detailRow('Garage', _verifiedToken!.garageName!),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Status update buttons (for garage)
              const Text(
                'Update Token Status',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              // Next statuses in the token lifecycle
              if (_verifiedToken!.status == 'handed_to_garage')
                _buildStatusButton(
                  label: 'Start Repair',
                  icon: Icons.build,
                  status: 'repair_started',
                  color: Colors.orange,
                ),

              if (_verifiedToken!.status == 'repair_started')
                _buildStatusButton(
                  label: 'Ready for Pickup',
                  icon: Icons.check_circle_outline,
                  status: 'ready_for_pickup',
                  color: Colors.blue,
                ),

              if (_verifiedToken!.status == 'ready_for_pickup')
                _buildStatusButton(
                  label: 'Close Token',
                  icon: Icons.check_circle,
                  status: 'closed',
                  color: Colors.green,
                ),

              if (_verifiedToken!.status == 'closed')
                Container(
                  width: double.infinity,
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
                      Text(
                        'Token lifecycle completed',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 16),

              // Scan another button
              OutlinedButton.icon(
                onPressed: _resetScanner,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan Another Token'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2E7D32),
                  side: const BorderSide(color: Color(0xFF2E7D32)),
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],

            // Manual entry section
            if (!_isScanning && _verifiedToken == null && !_isProcessing)
              Column(
                children: [
                  const SizedBox(height: 20),
                  const Text(
                    'Or enter token code manually',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  _buildManualEntry(),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualEntry() {
    final controller = TextEditingController();
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: 'Enter 6-digit token code',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
            textCapitalization: TextCapitalization.characters,
            maxLength: 6,
          ),
        ),
        const SizedBox(width: 12),
        ElevatedButton(
          onPressed: () {
            final code = controller.text.trim().toUpperCase();
            if (code.length == 6) {
              _verifyAndProcessToken(code);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2E7D32),
            foregroundColor: Colors.white,
            minimumSize: const Size(60, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: const Icon(Icons.search),
        ),
      ],
    );
  }

  Widget _buildStatusButton({
    required String label,
    required IconData icon,
    required String status,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _isProcessing ? null : () => _updateTokenStatus(status),
          icon: _isProcessing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(icon),
          label: Text(label),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
