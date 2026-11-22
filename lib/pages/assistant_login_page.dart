import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import '../core/router/app_router.dart';
import '../core/session/app_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/assistant_service.dart';
import '../core/utils/error_handler.dart';
import 'assistant_signup_page.dart';

/// AssistantLoginPage — Redesigned with a gradient curved header + tabbed
/// login (Phone OTP / Email / Instant Access). All auth logic is preserved.
class AssistantLoginPage extends StatefulWidget {
  const AssistantLoginPage({super.key});

  @override
  State<AssistantLoginPage> createState() => _AssistantLoginPageState();
}

class _AssistantLoginPageState extends State<AssistantLoginPage>
    with SingleTickerProviderStateMixin {
  static const Color _green = Color(0xFF2E7D32);
  static const Gradient _gradient = LinearGradient(
    colors: [Color(0xFF1B5E20), Color(0xFF4CAF50)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  final AssistantService _service = AssistantService();

  late final TabController _tabController;

  final TextEditingController phoneController = TextEditingController();
  final TextEditingController otpController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController nameController = TextEditingController();

  bool isLoading = false;
  bool showOtpBox = false;
  bool obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Pre-fill demo phone for quick testing
    phoneController.text = '9876543211';
  }

  Future<void> sendOtp() async {
    final phone = phoneController.text.trim();
    if (phone.isEmpty || phone.length < 10) {
      _showSnack('Enter a valid phone number');
      return;
    }

    setState(() => isLoading = true);
    try {
      final response = await _service.loginOtp(phone: phone);
      if (response['success'] == true) {
        setState(() => showOtpBox = true);
        // Only surface an OTP when the SERVER explicitly supplied one under
        // DEV_MODE (with its own "not a production SMS flow" notice). This
        // previously fell back to a hardcoded '1234' on the client.
        final devOtp = response['devOtp']?.toString();
        // Fill it silently rather than printing it: the demo account code on
        // screen is not something to show in a room.
        if (devOtp != null) otpController.text = devOtp;
        _showSnack(
          devOtp != null
              ? 'Demo access — code filled in automatically'
              : 'OTP sent to your mobile number',
        );
      } else {
        _showSnack(response['message'] ?? 'Failed to send OTP');
      }
    } catch (e) {
      _showSnack(ErrorHandler.getFriendlyMessage(e));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> verifyOtp() async {
    final phone = phoneController.text.trim();
    final otp = otpController.text.trim();

    if (phone.isEmpty || otp.isEmpty) {
      _showSnack('Enter phone and OTP');
      return;
    }

    setState(() => isLoading = true);
    try {
      // Send the OTP the user actually typed to the verify endpoint. This
      // previously re-called send-OTP and never transmitted `otp` at all, so
      // any code was accepted.
      final response = await _service.verifyOtp(phone: phone, otp: otp);
      if (response['success'] == true) {
        final assistant = response['assistant'] as Map<String, dynamic>? ?? {};
        await _saveAssistantAndNavigate(assistant, phone);
      } else {
        _showSnack(response['message'] ?? 'Verification failed');
      }
    } catch (e) {
      _showSnack(ErrorHandler.getFriendlyMessage(e));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> loginWithEmail() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showSnack('Enter email and password');
      return;
    }

    setState(() => isLoading = true);
    try {
      final response = await _service.login(email: email, password: password);
      if (response['success'] == true) {
        final assistant = response['assistant'] as Map<String, dynamic>? ?? {};
        await _saveAssistantAndNavigate(assistant, '');
      } else {
        // Overwhelmingly the cause is "no such account yet", so say which two
        // routes do work instead of echoing a bare rejection and leaving the
        // reader stuck on a screen with no way forward.
        _showSnack(
          '${response['message'] ?? 'Login failed'}. New here? Tap Sign Up, or '
          'use the Instant tab to get in right away.',
        );
      }
    } catch (e) {
      _showSnack(ErrorHandler.getFriendlyMessage(e));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> instantAccess() async {
    final name = nameController.text.trim().isEmpty
        ? 'Assistant'
        : nameController.text.trim();
    final phone = phoneController.text.trim();

    if (phone.isEmpty) {
      _showSnack('Enter phone number');
      return;
    }

    setState(() => isLoading = true);
    try {
      final response = await _service.instantAccess(name: name, phone: phone);
      if (response['success'] == true) {
        final assistant = response['assistant'] as Map<String, dynamic>? ?? {};
        await _saveAssistantAndNavigate(assistant, phone);
      } else {
        _showSnack(response['message'] ?? 'Access failed');
      }
    } catch (e) {
      _showSnack(ErrorHandler.getFriendlyMessage(e));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _saveAssistantAndNavigate(
      Map<String, dynamic> assistant, String phone) async {
    final prefs = await SharedPreferences.getInstance();
    final assistantId = (assistant['_id'] ?? assistant['id'] ?? '').toString();

    await prefs.setString('assistantId',
        assistantId.isNotEmpty ? assistantId : 'ast_${phone}_demo');
    await prefs.setString(
        'assistantName', (assistant['name'] ?? 'Assistant').toString());
    await prefs.setString(
        'assistantEmail', (assistant['email'] ?? '').toString());
    await prefs.setString(
        'assistantPhone', (assistant['phone'] ?? phone).toString());

    // §6 — persist the identity so a restart resumes the assistant dashboard.
    await AppSession.save(
      role: 'assistant',
      id: assistantId.isNotEmpty ? assistantId : 'ast_${phone}_demo',
      name: (assistant['name'] ?? 'Assistant').toString(),
      email: (assistant['email'] ?? '').toString(),
      phone: (assistant['phone'] ?? phone).toString(),
    );

    if (!mounted) return;
    context.go(AppRoutes.assistantHome);
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
            color: _green.withAlpha((0.30 * 255).round()),
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
                child: const Icon(Icons.two_wheeler,
                    color: Colors.white, size: 26),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Text(
            'Welcome Rider',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Be the first responder. Pickup customers & coordinate the rescue.',
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
                Icon(Icons.bolt, color: Colors.white, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Quick response on 2-wheeler',
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
      style: TextStyle(color: isDark ? Colors.white : null),
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
    Color backgroundColor = _green,
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
          const SizedBox(height: 12),
          if (showOtpBox)
            _buildField(
              controller: otpController,
              hint: 'Enter OTP',
              icon: Icons.lock_outline,
              keyboardType: TextInputType.number,
              obscure: true,
            ),
          const SizedBox(height: 14),
          _buildButton(
            text: showOtpBox ? 'Verify OTP' : 'Send OTP',
            onPressed: () {
              if (showOtpBox) {
                verifyOtp();
              } else {
                sendOtp();
              }
            },
          ),
        ],
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
              onPressed: () =>
                  setState(() => obscurePassword = !obscurePassword),
            ),
          ),
          const SizedBox(height: 14),
          _buildButton(text: 'Login with Email', onPressed: loginWithEmail),
        ],
      ),
    );
  }

  Widget _buildInstantTab() {
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 20),
          _buildField(
            controller: nameController,
            hint: 'Enter name (optional)',
            icon: Icons.person_outline,
          ),
          const SizedBox(height: 12),
          _buildField(
            controller: phoneController,
            hint: 'Enter phone number',
            icon: Icons.phone_android,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 14),
          _buildButton(
            text: 'Instant Access',
            onPressed: instantAccess,
            backgroundColor: Colors.orange,
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    phoneController.dispose();
    otpController.dispose();
    emailController.dispose();
    passwordController.dispose();
    nameController.dispose();
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
                            color: _green,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          labelColor: Colors.white,
                          unselectedLabelColor:
                              isDark ? Colors.white70 : Colors.black87,
                          dividerColor: Colors.transparent,
                          isScrollable: true,
                          tabs: const [
                            Tab(text: 'Phone OTP'),
                            Tab(text: 'Email'),
                            Tab(text: 'Instant'),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 220,
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _buildOtpTab(),
                            _buildEmailTab(),
                            _buildInstantTab(),
                          ],
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
                          builder: (_) => const AssistantSignupPage(),
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


