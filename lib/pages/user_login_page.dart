import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/router/app_router.dart';
import '../core/session/app_session.dart';
import '../services/api_service.dart';
import '../core/utils/error_handler.dart';
import 'user_signup_page.dart';

class UserLoginPage extends StatefulWidget {
  const UserLoginPage({super.key});

  @override
  State<UserLoginPage> createState() => _UserLoginPageState();
}

class _UserLoginPageState extends State<UserLoginPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final TextEditingController phoneController = TextEditingController();
  final TextEditingController otpController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool otpSent = false;
  bool isLoading = false;

  /// The code the server could not deliver, shown only when it says so
  /// (`smsSent: false`). Without this the customer screen was unusable once
  /// codes became random: the mechanic and rider screens showed their code,
  /// the customer screen silently swallowed it.
  String? devOtp;
  bool obscurePassword = true;

  /// §4 — resend cooldown. Without it a repeated tap sends a new OTP on every
  /// press and invalidates the code the user is still typing.
  Timer? _resendTimer;
  int _resendIn = 0;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _tabController.dispose();
    phoneController.dispose();
    otpController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  void _startResendCooldown([int seconds = 30]) {
    _resendTimer?.cancel();
    setState(() => _resendIn = seconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendIn <= 1) {
        timer.cancel();
        setState(() => _resendIn = 0);
      } else {
        setState(() => _resendIn -= 1);
      }
    });
  }

  Future<void> resendOtp() async {
    if (_resendIn > 0 || isLoading) return;
    await sendOtp();
    if (mounted && otpSent) _startResendCooldown();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  /// Requests a real OTP from the backend (POST /api/user/login-otp).
  ///
  /// This previously set `generatedOtp = '123456'` on the device and compared it
  /// locally, so anyone could log in as any phone number by typing 123456 —
  /// no network call was made at all.
  Future<void> sendOtp() async {
    final phone = phoneController.text.trim();
    if (phone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid mobile number')),
      );
      return;
    }
    setState(() => isLoading = true);
    try {
      final response = await ApiService.sendOtp(phone: phone);
      final code = response['devOtp']?.toString();
      if (!mounted) return;
      setState(() {
        otpSent = true;
        devOtp = code;
        if (code != null) otpController.text = code;
      });
      _startResendCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            code == null
                ? 'Code sent by SMS to $phone'
                : 'Demo access — code filled in',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send OTP. ${ErrorHandler.getFriendlyMessage(e)}')),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  /// Verifies the OTP with the backend (POST /api/user/verify-otp).
  Future<void> verifyOtpLogin() async {
    final phone = phoneController.text.trim();
    final otp = otpController.text.trim();
    if (otp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter OTP')),
      );
      return;
    }
    setState(() => isLoading = true);
    try {
      final res = await ApiService.verifyOtp(phone: phone, otp: otp);
      final user = (res['user'] as Map<String, dynamic>?) ?? const {};
      final userId = (user['id'] ?? user['_id'] ?? phone).toString();

      // §5 / §6 — persist the identity before navigating, so a cold start
      // resumes this dashboard instead of showing the role selector again.
      await AppSession.save(
        role: 'user',
        id: userId,
        name: (user['name'] as String?)?.isNotEmpty == true
            ? user['name'] as String
            : 'User',
        phone: phone,
        email: (user['email'] as String?) ?? '',
      );
      if (!mounted) return;
      context.go(AppRoutes.userHome);
    } catch (e) {
      if (!mounted) return;
      // A dead server must not be reported as a wrong code — that sends the
      // user off re-reading an OTP that was never transmitted.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ErrorHandler.isTransportFailure(e)
                ? ErrorHandler.getFriendlyMessage(e)
                : 'Invalid OTP',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> loginWithEmail() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter email and password')),
      );
      return;
    }
    setState(() => isLoading = true);
    try {
      final response = await ApiService.userLoginWithEmail(
        email: email,
        password: password,
      );
      if (!mounted) return;
      final user = response['user'] as Map<String, dynamic>? ?? {};
      await AppSession.save(
        role: 'user',
        id: (user['id'] ?? user['_id'] ?? email).toString(),
        name: (user['name'] ?? 'User').toString(),
        email: (user['email'] ?? email).toString(),
        phone: (user['phone'] ?? '').toString(),
      );
      if (!mounted) return;
      context.go(AppRoutes.userHome);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Login failed. ${ErrorHandler.getFriendlyMessage(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void forgotPassword() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Forgot password will be integrated next')),
    );
  }

  void newUserSignup() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const UserSignupPage()),
    );
  }

  Future<void> emergencyAccess() async {
    // Was pushReplacement into the dashboard, which replaced the router's page
    // with an imperative route: the next back press then emptied the Navigator
    // and left a black screen. Give the guest a real session and use the router.
    await AppSession.save(
      role: 'user',
      id: 'guest',
      name: 'Guest',
      phone: '',
      email: '',
    );
    if (!mounted) return;
    context.go(AppRoutes.userHome);
  }

  Widget buildTopHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFD32F2F), Color(0xFFFF7043)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white,
            child: Icon(Icons.car_repair, color: Color(0xFFD32F2F), size: 30),
          ),
          SizedBox(height: 16),
          Text(
            'RoadResQ',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Emergency roadside help in minutes',
            style: TextStyle(color: Colors.white70, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget buildPhoneLoginTab() {
    return Column(
      children: [
        const SizedBox(height: 20),
        TextField(
          controller: phoneController,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: 'Mobile Number',
            hintText: 'Enter your phone number',
            prefixIcon: const Icon(Icons.phone_android),
            prefixText: '+91 ',
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (otpSent)
          TextField(
            controller: otpController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Enter OTP',
              hintText: '6-digit OTP',
              prefixIcon: const Icon(Icons.lock_outline),
              filled: true,
              fillColor: Colors.grey.shade100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        if (otpSent && devOtp != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(
              'Demo access — code filled in automatically',
              style: TextStyle(fontSize: 11.5, color: Colors.white70),
            ),
          ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: otpSent ? verifyOtpLogin : sendOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              otpSent ? 'Verify OTP & Login' : 'Send OTP',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        if (otpSent)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _resendIn == 0 && !isLoading ? resendOtp : null,
              child: Text(
                _resendIn == 0
                    ? 'Resend OTP'
                    : 'Resend OTP in ${_resendIn}s',
                style: const TextStyle(inherit: true, fontSize: 13),
              ),
            ),
          ),
      ],
    );
  }

  Widget buildEmailLoginTab() {
    return Column(
      children: [
        const SizedBox(height: 20),
        TextField(
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: 'Email Address',
            hintText: 'Enter your email',
            prefixIcon: const Icon(Icons.email_outlined),
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: passwordController,
          obscureText: obscurePassword,
          decoration: InputDecoration(
            labelText: 'Password',
            hintText: 'Enter your password',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              onPressed: () {
                setState(() => obscurePassword = !obscurePassword);
              },
              icon: Icon(
                obscurePassword ? Icons.visibility_off : Icons.visibility,
              ),
            ),
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: forgotPassword,
            child: const Text(
              'Forgot Password?',
              style: TextStyle(
                color: Color(0xFFD32F2F),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: isLoading ? null : loginWithEmail,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: isLoading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Login with Email',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget buildQuickActions() {
    return Column(
      children: [
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton.icon(
            onPressed: emergencyAccess,
            icon: const Icon(Icons.warning_amber_rounded, color: Colors.red),
            label: const Text(
              'Emergency Fast Access',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.red),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('New user? '),
            GestureDetector(
              onTap: newUserSignup,
              child: const Text(
                'Create Account',
                style: TextStyle(
                  color: Color(0xFFD32F2F),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const Text(
          'By continuing, you agree to RoadResQ Terms, Policy and Emergency Response Guidelines.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FB),
      body: SafeArea(
        child: Column(
          children: [
            buildTopHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha((0.06 * 255).round()),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF2C2C2C)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: TabBar(
                          controller: _tabController,
                          indicator: BoxDecoration(
                            color: const Color(0xFFD32F2F),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          labelColor: Colors.white,
                          unselectedLabelColor:
                              isDark ? Colors.white70 : Colors.black87,
                          dividerColor: Colors.transparent,
                          tabs: const [
                            Tab(text: 'Phone Login'),
                            Tab(text: 'Email Login'),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 320,
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            buildPhoneLoginTab(),
                            buildEmailLoginTab(),
                          ],
                        ),
                      ),
                      buildQuickActions(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

