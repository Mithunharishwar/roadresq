// FILE: lib/features/user/sos_screen.dart
/// SOS Screen — Big red SOS button
/// On tap: gets location, creates job doc, triggers matching engine dispatch
/// Shows live status of crew dispatch (searching → assigned → en route)
library;

import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dispatch_provider.dart';
import '../../providers/request_provider.dart';
import '../../providers/sos_security_provider.dart';

class SosScreen extends ConsumerStatefulWidget {
  const SosScreen({super.key});

  @override
  ConsumerState<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends ConsumerState<SosScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  bool _isActivated = false;
  bool _isLocating = false;
  bool _isSending = false;
  String? _errorMessage;

  // Location data
  double? _lat;
  double? _lng;
  String? _address;

  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _triggerSos() async {
    if (_isActivated) return;

    // ─── FEATURE 6: Fake-SOS prevention ───
    // OTP-verify the phone before an SOS can be dispatched. If the user is
    // not yet verified, prompt for OTP. The 3-SOS/day limit and penalty for
    // fake cancel are enforced server-side via Cloud Functions.
    final sosState = ref.read(sosSecurityProvider);
    if (!sosState.verified) {
      final phone = ref.read(authProvider).userProfile?.phone ?? '';
      final ok = await _verifySosOtp(phone);
      if (!ok || !mounted) return;
    }

    setState(() {
      _isActivated = true;
      _isLocating = true;
      _errorMessage = null;
    });

    // Vibrate/haptic feedback would go here in production

    try {
      // Step 1: Get current location
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled. Please enable GPS.');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permission denied');
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception(
          'Location permissions permanently denied. Please enable in Settings.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      setState(() {
        _lat = position.latitude;
        _lng = position.longitude;
        _isLocating = false;
        _isSending = true;
      });

      // Step 2: Create request in Firestore via provider
      final userId = ref.read(authProvider).firebaseUser?.uid ?? 'anonymous';
      final userName =
          ref.read(authProvider).userProfile?.name ?? 'Anonymous User';
      final userPhone = ref.read(authProvider).userProfile?.phone ?? '';

      final requestId = await ref.read(requestProvider.notifier).createRequest(
            userId: userId,
            userName: userName,
            userPhone: userPhone,
            latitude: _lat!,
            longitude: _lng!,
            address: _address ?? 'Current Location',
            vehicleType: 'Car', // User can change later
            issueType: 'Emergency',
          );

      if (requestId == null) {
        throw Exception('Failed to create rescue request');
      }

      // Step 3: Trigger matching engine
      await ref.read(dispatchProvider.notifier).dispatchTwoManCrew(
            userId: userId,
            userLat: _lat!,
            userLng: _lng!,
            requestId: requestId,
            userZone: 'urban',
          );

      if (!mounted) return;

      // Start timeout timer (5 min for SOS)
      _timeoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        final state = ref.read(dispatchProvider);
        if (state.searchElapsedSeconds >= AppConstants.sosTimeoutSeconds) {
          timer.cancel();
          if (mounted) {
            setState(() {
              _isSending = false;
              _errorMessage =
                  'No crew found nearby. We\'ve notified the admin for manual dispatch.';
            });
          }
        }
      });

      setState(() => _isSending = false);

      // Navigate to tracking screen
      if (mounted) {
        Navigator.pushReplacementNamed(
          context,
          '/request-status',
          arguments: {
            'requestId': requestId,
            'issue': 'Emergency SOS',
            'vehicle': 'Car',
            'location': _address ?? 'Your Location',
          },
        );
      }
    } catch (e) {
      setState(() {
        _isLocating = false;
        _isSending = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });

      // Reset after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() => _isActivated = false);
        }
      });
    }
  }

  /// ─── FEATURE 6: OTP-verify before SOS dispatch ───
  /// Sends an OTP to [phone], then prompts the user to enter it.
  /// Returns true only if the OTP is verified (and within daily limit).
  Future<bool> _verifySosOtp(String phone) async {
    final notifier = ref.read(sosSecurityProvider.notifier);

    if (phone.isNotEmpty) {
      await notifier.sendOtp(phone: phone);
    }

    if (!mounted) return false;

    final controller = TextEditingController();
    final submitted = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Text('Verify to Send SOS'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter the OTP sent to your phone to confirm the emergency request.',
              ),
              const SizedBox(height: 10),
              if (ref.read(sosSecurityProvider).devOtp?.isNotEmpty == true)
                Text(
                  'Dev OTP: ${ref.read(sosSecurityProvider).devOtp}',
                  style: const TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'OTP',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final code = controller.text.trim();
                if (code.isEmpty) return;
                Navigator.pop(dialogCtx, code);
              },
              child: const Text('Verify'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (submitted == null || submitted.isEmpty) {
      // User cancelled.
      ref.read(sosSecurityProvider.notifier).reset();
      return false;
    }

    final ok = await notifier.verifyOtp(otp: submitted);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ref.read(sosSecurityProvider).errorMessage ??
                'OTP verification failed',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
    return ok;
  }

  @override
  Widget build(BuildContext context) {
    final dispatchState = ref.watch(dispatchProvider);

    return Scaffold(
      backgroundColor:
          _isActivated ? const Color(0xFFB71C1C) : const Color(0xFFF7F9FC),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Status messages
                if (_isLocating)
                  _buildStatusCard(
                    icon: Icons.location_searching,
                    title: 'Getting your location...',
                    subtitle: 'Please stay where you are',
                    color: Colors.blue,
                  ),

                if (_isSending)
                  _buildStatusCard(
                    icon: Icons.sos,
                    title: 'Sending SOS...',
                    subtitle: 'Looking for nearest crew',
                    color: Colors.orange,
                  ),

                if (dispatchState.isSearching)
                  _buildStatusCard(
                    icon: Icons.search,
                    title: 'Searching for crew...',
                    subtitle:
                        'Time elapsed: ${dispatchState.searchElapsedSeconds}s',
                    color: Colors.deepPurple,
                  ),

                if (_errorMessage != null)
                  _buildStatusCard(
                    icon: Icons.error_outline,
                    title: 'Error',
                    subtitle: _errorMessage!,
                    color: Colors.red,
                  ),

                // SOS Button
                if (!_isActivated) ...[
                  const Spacer(),
                  _buildSosButton(),
                  const SizedBox(height: 24),
                  const Text(
                    'Tap to request\nemergency roadside assistance',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Your location will be shared with nearby mechanics',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                ],

                // Cancel button (when activated)
                if (_isActivated && !dispatchState.isSearching)
                  Padding(
                    padding: const EdgeInsets.only(top: 32),
                    child: OutlinedButton(
                      onPressed: () {
                        _timeoutTimer?.cancel();
                        setState(() {
                          _isActivated = false;
                          _errorMessage = null;
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white),
                        minimumSize: const Size(200, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Cancel SOS'),
                    ),
                  ),

                if (dispatchState.isSearching)
                  Padding(
                    padding: const EdgeInsets.only(top: 32),
                    child: TextButton(
                      onPressed: () {
                        _timeoutTimer?.cancel();
                        ref.read(dispatchProvider.notifier).cancelSearch();
                        setState(() {
                          _isActivated = false;
                        });
                      },
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSosButton() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Pulse ring
        ScaleTransition(
          scale: Tween<double>(begin: 1.0, end: 1.4).animate(
            CurvedAnimation(
              parent: _pulseController,
              curve: Curves.easeInOut,
            ),
          ),
          child: FadeTransition(
            opacity:
                Tween<double>(begin: 0.6, end: 0.0).animate(_pulseController),
            child: Container(
              width: 240,
              height: 240,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0x80D32F2F),
              ),
            ),
          ),
        ),
        // SOS button
        GestureDetector(
          onTapDown: (_) {
            // Visual feedback could go here
          },
          onTapUp: (_) => _triggerSos(),
          child: Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [
                  Color(0xFFFF5252),
                  Color(0xFFD32F2F),
                  Color(0xFFB71C1C)
                ],
                stops: [0.3, 0.7, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFD32F2F).withAlpha(120),
                  blurRadius: 40,
                  spreadRadius: 8,
                ),
              ],
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'SOS',
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 6,
                  ),
                ),
                Text(
                  'EMERGENCY',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(230),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withAlpha(40),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
