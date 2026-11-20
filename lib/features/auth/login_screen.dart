// FILE: lib/features/auth/login_screen.dart
/// LoginScreen — Rapido-style single Phone OTP login for all roles.
///
/// Flow:
///   1. User selects a role first (on RoleSelectionScreen) → arrives here with that [role].
///   2. Enters a 10-digit phone number → taps "Get OTP" → AuthService.sendOTP().
///   3. Enters the 4-digit OTP → AuthService.verifyOtpWithRole() saves `users/{uid}.role`
///      and returns the role.
///   4. Routes via `context.go` to the matching dashboard.
///
/// Uses the theme color of the selected role (red=user, blue=mechanic,
/// green=assistant, purple=garage).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/backend_auth_service.dart';

/// Role → theme color mapping used across the single-login flow and dashboards.
Color roleColor(String role) {
  switch (role) {
    case 'mechanic':
      return const Color(0xFF1976D2);
    case 'assistant':
      return const Color(0xFF388E3C);
    case 'garage':
      return const Color(0xFF7E57C2);
    default:
      return const Color(0xFFD32F2F);
  }
}

/// Role → dashboard route mapping.
String roleRoute(String role) {
  switch (role) {
    case 'mechanic':
      return '/mechanic-home';
    case 'assistant':
      return '/assistant-home';
    case 'garage':
      return '/garage-home';
    default:
      return '/user-home';
  }
}

class LoginScreen extends ConsumerStatefulWidget {
  final String role;
  const LoginScreen({super.key, this.role = 'user'});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final List<TextEditingController> _otpControllers = List.generate(
    4,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _otpFocusNodes = List.generate(4, (_) => FocusNode());

  bool _loading = false;
  bool _otpSent = false;
  bool _backendUp = true; // becomes false if the backend can't be reached

  Timer? _resendTimer;
  int _resendSeconds = 30;

  Color get _accent => roleColor(widget.role);

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _phoneController.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 30);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendSeconds <= 1) {
        timer.cancel();
        if (mounted) setState(() => _resendSeconds = 0);
      } else {
        if (mounted) setState(() => _resendSeconds--);
      }
    });
  }

  String get _otpCode => _otpControllers.map((c) => c.text).join().trim();
  bool get _otpComplete => _otpCode.length == 4;

  Future<void> _getOtp() async {
    final phone = _phoneController.text.trim();
    if (phone.length != 10) {
      _showError('Enter a valid 10-digit phone number');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
    });
    try {
      final result = await BackendAuthService.sendOtp(
        phone: phone,
        role: widget.role,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _otpSent = true;
        _backendUp = true;
      });
      final devOtp = result['otp'] ?? '1234';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('OTP sent successfully (use $devOtp)'),
          backgroundColor: Colors.green,
        ),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _otpFocusNodes[0].requestFocus();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _backendUp = false;
      });
      _showError('Failed to send OTP: $e');
    }
  }

  Future<void> _verifyOtp() async {
    if (!_otpComplete) {
      _showError('Enter the 4-digit OTP');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
    });
    try {
      if (!_otpSent) {
        throw Exception('No OTP was requested. Please send OTP first.');
      }

      // Verify the OTP against the Python backend.
      await BackendAuthService.verifyOtp(
        phone: _phoneController.text.trim(),
        code: _otpCode,
        role: widget.role,
      );

      if (!mounted) return;
      setState(() => _loading = false);

      // Navigate to the correct dashboard using go_router.
      context.go(roleRoute(widget.role));
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError('Verification failed: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  /// Demo mode — bypass Firebase Phone OTP and jump straight to this role's
  /// dashboard. Useful when the Phone provider is not yet enabled in Firebase.
  void _enterDemo() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Entering ${widget.role} dashboard (demo mode)'),
        backgroundColor: _accent,
        duration: const Duration(seconds: 1),
      ),
    );
    context.go(roleRoute(widget.role));
  }

  Widget _otpBox(int index) {
    return SizedBox(
      width: 62,
      height: 62,
      child: TextField(
        controller: _otpControllers[index],
        focusNode: _otpFocusNodes[index],
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 1,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: _accent,
        ),
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: Colors.white,
          contentPadding: EdgeInsets.zero,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: _accent, width: 2),
          ),
        ),
        onChanged: (value) {
          if (value.isNotEmpty && index < 3) {
            _otpFocusNodes[index + 1].requestFocus();
          } else if (value.isEmpty && index > 0) {
            _otpFocusNodes[index - 1].requestFocus();
          }
          if (_otpComplete) {
            _verifyOtp();
          }
          setState(() {});
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              Row(
                children: [
                  InkWell(
                    onTap: () => context.go('/role-select'),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(color: Colors.black12, blurRadius: 8),
                        ],
                      ),
                      child: const Icon(Icons.arrow_back),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _accent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.car_repair, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'RoadResQ',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: _accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (!_backendUp) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: const Text(
                    'Backend offline — start it with: python backend/roadresq_backend.py '
                    '(or use Demo Mode below).',
                    style: TextStyle(color: Colors.brown, fontSize: 12.5),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const SizedBox(height: 12),
              Text(
                '${widget.role[0].toUpperCase()}${widget.role.substring(1)} Login',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter your mobile number to continue',
                style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(13),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Mobile Number',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F3F5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            children: [
                              Text('🇮🇳  ', style: TextStyle(fontSize: 18)),
                              Text(
                                '+91',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Icon(
                                Icons.arrow_drop_down,
                                color: Colors.black54,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            maxLength: 10,
                            enabled: !_otpSent,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: InputDecoration(
                              counterText: '',
                              hintText: '9876543210',
                              hintStyle: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 18,
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF1F3F5),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_otpSent) ...[
                      const SizedBox(height: 24),
                      const Divider(),
                      const SizedBox(height: 16),
                      const Text(
                        'Enter OTP',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'OTP sent to +91 ${_phoneController.text.trim()}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(4, (i) => _otpBox(i)),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: _resendSeconds == 0
                            ? TextButton(
                                onPressed: _loading ? null : _getOtp,
                                child: Text(
                                  'Resend OTP',
                                  style: TextStyle(
                                    color: _accent,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              )
                            : Text(
                                'Resend OTP in 00:${_resendSeconds.toString().padLeft(2, '0')}',
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 13,
                                ),
                              ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _loading
                      ? null
                      : _otpSent
                          ? _verifyOtp
                          : _getOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade400,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 2,
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          _otpSent ? 'Verify & Continue' : 'Get OTP',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              // ─── Demo / Skip login (bypasses Firebase Phone OTP) ───
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: () => _enterDemo(),
                  icon: const Icon(Icons.rocket_launch),
                  label: const Text('Skip Login — Demo Mode'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _accent,
                    side: BorderSide(color: _accent.withAlpha(130)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Center(
                child: Text(
                  'Demo mode lets you explore this role without sending an OTP.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.grey.shade500,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  'By continuing, you agree to our Terms & Privacy Policy',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
