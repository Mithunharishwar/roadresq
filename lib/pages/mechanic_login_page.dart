import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/router/app_router.dart';
import '../core/session/app_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme/app_theme.dart';
import '../services/api_service.dart';
import '../core/utils/error_handler.dart';
import 'mechanic_signup_page.dart';

/// MechanicLoginPage — Redesigned with a gradient curved header + tabbed
/// login (Phone OTP / Email). All auth logic is preserved.
class MechanicLoginPage extends StatefulWidget {
  const MechanicLoginPage({super.key});

  @override
  State<MechanicLoginPage> createState() => _MechanicLoginPageState();
}

class _MechanicLoginPageState extends State<MechanicLoginPage>
    with SingleTickerProviderStateMixin {
  static const Color _blue = Color(0xFF0D47A1);
  static const Gradient _gradient = LinearGradient(
    colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  late final TabController _tabController;

  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();

  bool isLoading = false;
  bool obscurePassword = true;

  /// Two-step phone login. The screen used to call /mechanic/login-otp and go
  /// straight to the dashboard, so no code was ever requested, displayed or
  /// checked — the OTP step simply did not exist. It now mirrors the user and
  /// assistant login: request a code, then verify it.
  final TextEditingController otpController = TextEditingController();
  bool otpSent = false;
  String? devOtp;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  Future<void> loginWithEmail() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter email and password')),
      );
      return;
    }

    try {
      setState(() => isLoading = true);

      final response = await ApiService.mechanicLogin(
        email: email,
        password: password,
      );

      final mechanic = Map<String, dynamic>.from(response['mechanic'] ?? {});
      final mechanicId = (mechanic['_id'] ?? mechanic['id'] ?? '').toString();

      if (mechanicId.isEmpty) {
        throw Exception('Mechanic ID not found');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('mechanicId', mechanicId);
      await prefs.setString(
        'mechanicName',
        (mechanic['name'] ?? 'Mechanic').toString(),
      );
      await prefs.setString(
        'mechanicEmail',
        (mechanic['email'] ?? '').toString(),
      );
      await prefs.setString(
        'mechanicPhone',
        (mechanic['phone'] ?? '').toString(),
      );

      // §6 — persist the crew identity so a cold start resumes this dashboard.
      await AppSession.save(
        role: 'mechanic',
        id: mechanicId,
        name: (mechanic['name'] ?? 'Mechanic').toString(),
        email: (mechanic['email'] ?? '').toString(),
        phone: (mechanic['phone'] ?? '').toString(),
      );

      if (!mounted) return;
      context.go(AppRoutes.mechanicHome);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(content: Text('Login failed. ${ErrorHandler.getFriendlyMessage(e)}')),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  /// Step 1 — ask the backend for a code.
  Future<void> sendOtp() async {
    final phone = phoneController.text.trim();

    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter phone number')),
      );
      return;
    }

    try {
      setState(() => isLoading = true);

      final response = await ApiService.mechanicLoginOtp(phone: phone);

      // Development builds get the fixed code back under an explicitly named
      // field (`devOtp`) so it can be shown on screen. A production build with
      // ROADRESQ_DEV_MODE off returns nothing here — the code then only exists
      // in the SMS.
      final code = response['devOtp']?.toString();

      if (!mounted) return;
      setState(() {
        otpSent = true;
        devOtp = code;
        // Fill it for the operator instead of printing it on screen: a code
        // laid out in plain text is exactly what a room full of people should
        // not read off the display.
        if (code != null) otpController.text = code;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            code == null
                ? 'OTP sent to $phone'
                : 'OTP sent to $phone — dev code: $code',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not send OTP. ${ErrorHandler.getFriendlyMessage(e)}'),
        ),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  /// Step 2 — check the code and only then open the dashboard.
  Future<void> verifyOtp() async {
    final phone = phoneController.text.trim();
    final otp = otpController.text.trim();

    if (otp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the OTP sent to your phone')),
      );
      return;
    }

    try {
      setState(() => isLoading = true);

      final response = await ApiService.verifyOtp(
        phone: phone,
        otp: otp,
        isMechanic: true,
      );

      final mechanic = Map<String, dynamic>.from(response['mechanic'] ?? {});
      final mechanicId = (mechanic['_id'] ?? mechanic['id'] ?? '').toString();

      if (mechanicId.isEmpty) {
        throw Exception('Mechanic ID not found');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('mechanicId', mechanicId);
      await prefs.setString(
        'mechanicName',
        (mechanic['name'] ?? 'Mechanic').toString(),
      );
      await prefs.setString(
        'mechanicEmail',
        (mechanic['email'] ?? '').toString(),
      );
      await prefs.setString(
        'mechanicPhone',
        (mechanic['phone'] ?? phone).toString(),
      );

      await AppSession.save(
        role: 'mechanic',
        id: mechanicId,
        name: (mechanic['name'] ?? 'Mechanic').toString(),
        email: (mechanic['email'] ?? '').toString(),
        phone: (mechanic['phone'] ?? phone).toString(),
      );

      if (!mounted) return;
      context.go(AppRoutes.mechanicHome);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('OTP login failed. ${ErrorHandler.getFriendlyMessage(e)}'),
        ),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 30),
      decoration: BoxDecoration(
        gradient: _gradient,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: _blue.withAlpha((0.30 * 255).round()),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.arrow_back, color: Colors.white),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(30),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.build, color: Colors.white, size: 26),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Text(
            'Welcome Partner',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Login to service nearby jobs & share live route progress.',
            style: TextStyle(
              color: Colors.white.withAlpha((0.8 * 255).round()),
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha((0.14 * 255).round()),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                Icon(Icons.verified_user_outlined,
                    color: Colors.white, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Verified mechanics earn per job',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffixIcon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        prefixIcon: Icon(icon),
        suffixIcon: suffixIcon,
        hintText: hint,
        filled: true,
        fillColor: isDark ? const Color(0xFF2C2C2C) : Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildButton({
    required String text,
    required VoidCallback onPressed,
    Color backgroundColor = _blue,
    Color foregroundColor = Colors.white,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: isLoading
            ? const CircularProgressIndicator(color: Colors.white)
            : Text(
                text,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Widget _buildEmailTab() {
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 20),
          _buildField(
            controller: emailController,
            hint: 'Enter email',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),
          _buildField(
            controller: passwordController,
            hint: 'Enter password',
            icon: Icons.lock_outline,
            obscure: obscurePassword,
            suffixIcon: IconButton(
              icon: Icon(
                obscurePassword ? Icons.visibility : Icons.visibility_off,
              ),
              onPressed: () {
                setState(() => obscurePassword = !obscurePassword);
              },
            ),
          ),
          const SizedBox(height: 14),
          _buildButton(text: 'Login with Email', onPressed: loginWithEmail),
        ],
      ),
    );
  }

  Widget _buildOtpTab() {
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 20),
          _buildField(
            controller: phoneController,
            hint: 'Enter phone number',
            icon: Icons.phone_android,
            keyboardType: TextInputType.phone,
          ),
          if (!otpSent) ...[
            const SizedBox(height: 14),
            _buildButton(
              text: 'Send OTP',
              onPressed: sendOtp,
              backgroundColor: Colors.green,
            ),
          ] else ...[
            const SizedBox(height: 12),
            _buildField(
              controller: otpController,
              hint: 'Enter the 6-digit code',
              obscure: devOtp != null,
              icon: Icons.password,
              keyboardType: TextInputType.number,
            ),
            if (devOtp != null) ...[
              const SizedBox(height: 6),
              Text(
                'Demo access — code filled in automatically',
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppTheme.mutedOf(context),
                ),
              ),
            ],
            const SizedBox(height: 12),
            _buildButton(
              text: 'Verify & Login',
              onPressed: verifyOtp,
              backgroundColor: Colors.green,
            ),
            TextButton(
              onPressed: isLoading
                  ? null
                  : () {
                      setState(() {
                        otpSent = false;
                        devOtp = null;
                        otpController.clear();
                      });
                    },
              child: const Text('Change number'),
            ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    emailController.dispose();
    passwordController.dispose();
    phoneController.dispose();
    otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF121212) : const Color(0xFFF4F7FB),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
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
                        color: Colors.black.withAlpha((0.07 * 255).round()),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF2C2C2C)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: TabBar(
                          controller: _tabController,
                          indicator: BoxDecoration(
                            color: _blue,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          labelColor: Colors.white,
                          unselectedLabelColor:
                              isDark ? Colors.white70 : Colors.black87,
                          dividerColor: Colors.transparent,
                          tabs: const [
                            Tab(text: 'Phone OTP'),
                            Tab(text: 'Email Login'),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 330,
                        child: TabBarView(
                          controller: _tabController,
                          children: [_buildOtpTab(), _buildEmailTab()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Don't have an account? ",
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MechanicSignupPage(),
                        ),
                      );
                    },
                    child: const Text('Sign Up'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}



