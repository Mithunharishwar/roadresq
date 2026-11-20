// FILE: lib/features/crew/token_generator.dart
/// Token Generator — Mechanic generates a 6-digit digital vehicle token
/// On tap "Generate Token": Calls Cloud Function, shows QR + 6-digit code
/// Token lifecycle: generated → handed_to_garage → repair_started → ready_for_pickup → closed
/// QR code links: User, Crew, Garage, Vehicle
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_constants.dart';
import '../../models/token_model.dart';
import '../../providers/token_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';

class TokenGenerator extends ConsumerStatefulWidget {
  final String requestId;
  final String vehicleNumber;
  final String vehicleType;
  final String garageId;

  const TokenGenerator({
    super.key,
    required this.requestId,
    required this.vehicleNumber,
    this.vehicleType = '',
    this.garageId = '',
  });

  @override
  ConsumerState<TokenGenerator> createState() => _TokenGeneratorState();
}

class _TokenGeneratorState extends ConsumerState<TokenGenerator> {
  TokenModel? _generatedToken;
  bool _isGenerating = false;
  String? _errorMessage;
  bool _showQr = false;

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _generateToken() async {
    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });

    try {
      final userId = ref.read(authProvider).firebaseUser?.uid ?? 'unknown_user';
      final crewId = ref.read(authProvider).userProfile?.id ?? 'unknown_crew';
      final garageId =
          widget.garageId.isNotEmpty ? widget.garageId : 'default_garage';

      // Call token provider to generate
      final token = await ref.read(tokenProvider.notifier).generateToken(
            userId: userId,
            crewId: crewId,
            garageId: garageId,
            vehicleNumber: widget.vehicleNumber,
            vehicleType: widget.vehicleType,
            garageName: 'Garage',
            garagePhone: '',
          );

      if (token != null) {
        // If no garage, create a default garage assignment
        if (widget.garageId.isEmpty) {
          await FirestoreService().createDocument(
            collection: AppConstants.collectionGarages,
            data: {
              'name': 'Default Garage',
              'phone': '',
              'address': '',
              'location': const GeoPoint(0, 0),
              'isActive': true,
              'createdAt': Timestamp.fromDate(DateTime.now()),
              'updatedAt': Timestamp.fromDate(DateTime.now()),
            },
          );
        }

        setState(() {
          _generatedToken = token;
          _showQr = true;
          _isGenerating = false;
        });

        // Show success
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Token generated: ${token.tokenCode}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        setState(() {
          _errorMessage = 'Failed to generate token';
          _isGenerating = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: ${e.toString()}';
        _isGenerating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        title: const Text('Generate Vehicle Token'),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        actions: [
          if (_generatedToken != null)
            IconButton(
              icon: Icon(_showQr ? Icons.confirmation_number : Icons.qr_code),
              onPressed: () => setState(() => _showQr = !_showQr),
              tooltip: _showQr ? 'Show Code' : 'Show QR',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Header card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.confirmation_number,
                      color: Colors.white, size: 40),
                  SizedBox(height: 12),
                  Text(
                    'Digital Vehicle Token',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Generate a unique 6-character token for garage handover',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Vehicle info card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(13),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Vehicle Details',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _detailRow('Vehicle Number', widget.vehicleNumber),
                  const SizedBox(height: 8),
                  _detailRow(
                    'Vehicle Type',
                    widget.vehicleType.isEmpty ? 'Car' : widget.vehicleType,
                  ),
                  const SizedBox(height: 8),
                  _detailRow(
                      'Garage ID',
                      widget.garageId.isEmpty
                          ? 'Auto-assign'
                          : widget.garageId),
                  const SizedBox(height: 8),
                  _detailRow('Request ID', widget.requestId),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Generate button
            if (_generatedToken == null)
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _isGenerating ? null : _generateToken,
                  icon: _isGenerating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.generating_tokens, size: 20),
                  label: Text(
                    _isGenerating ? 'Generating...' : 'Generate Vehicle Token',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _isGenerating ? Colors.grey : const Color(0xFF0D47A1),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),

            // Error message
            if (_errorMessage != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(top: 16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        color: Colors.red.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style:
                            TextStyle(color: Colors.red.shade700, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

            // Generated token display
            if (_generatedToken != null) ...[
              const SizedBox(height: 24),

              // Token code display
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
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
                  children: [
                    const Text(
                      'Token Generated Successfully',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 6-digit token code
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 20,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F4FF),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF0D47A1).withAlpha(50),
                        ),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'TOKEN CODE',
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            _generatedToken!.tokenCode,
                            style: const TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0D47A1),
                              letterSpacing: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Share this code with the garage',
                      style: TextStyle(color: Colors.black54, fontSize: 12),
                    ),

                    const SizedBox(height: 24),

                    // QR Code
                    if (_showQr) ...[
                      const Text(
                        'QR Code',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.grey.shade200,
                          ),
                        ),
                        child: QrImageView(
                          data: _generatedToken!.tokenCode,
                          version: QrVersions.auto,
                          size: 200,
                          backgroundColor: Colors.white,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: Color(0xFF0D47A1),
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: Color(0xFFD32F2F),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Scan with Garage Scanner',
                        style: TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Token details
                    const Divider(),
                    const SizedBox(height: 12),
                    _detailRow(
                        'Token ID', _generatedToken!.id.substring(0, 12)),
                    const SizedBox(height: 6),
                    _detailRow('Vehicle No', _generatedToken!.vehicleNumber),
                    const SizedBox(height: 6),
                    _detailRow('Status', _generatedToken!.statusDisplay),
                    const SizedBox(height: 6),
                    _detailRow('Created',
                        '${_generatedToken!.createdAt.hour}:${_generatedToken!.createdAt.minute.toString().padLeft(2, '0')}'),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // View Token Tracking
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pushNamed(
                      context,
                      '/token-tracking',
                      arguments: {
                        'tokenId': _generatedToken!.id,
                        'userRole': 'mechanic',
                      },
                    );
                  },
                  icon: const Icon(Icons.timeline),
                  label: const Text(
                    'View Token Timeline',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D47A1),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),

              // Generate another
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  setState(() {
                    _generatedToken = null;
                    _errorMessage = null;
                    _showQr = false;
                  });
                },
                child: const Text('Generate Another Token'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}
