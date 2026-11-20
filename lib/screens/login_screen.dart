import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'user_home_screen.dart';
import 'user_main_screen.dart';
import 'mechanic_main_screen.dart';

class LoginScreen extends StatefulWidget {
  final bool isMechanic;

  const LoginScreen({super.key, required this.isMechanic});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController otpController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool isLoading = false;
  bool showOtpBox = false;
  bool showEmailLogin = false;
  bool obscurePassword = true;

  String get title => widget.isMechanic ? 'Mechanic Access' : 'User Access';

  Color get themeColor =>
      widget.isMechanic ? const Color(0xFF0D47A1) : const Color(0xFFD32F2F);

  List<Color> get gradientColors => widget.isMechanic
      ? const [Color(0xFF0D47A1), Color(0xFF1976D2)]
      : const [Color(0xFFD32F2F), Color(0xFFFF7043)];

  Future<void> loginAsDemoUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userId', 'demo_user_001');
    await prefs.setString('userName', 'Demo User');
    await prefs.setString('userEmail', 'demo@roadresq.com');

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const UserMainScreen(
          name: 'Demo User',
          email: 'demo@roadresq.com',
          homeScreen: UserHomeScreen(),
        ),
      ),
    );
  }

  Future<void> loginAsDemoMechanic() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mechanicId', 'demo_mechanic_001');
    await prefs.setString('mechanicName', 'Demo Mechanic');
    await prefs.setString('mechanicEmail', 'mechanic@roadresq.com');

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const MechanicMainScreen(
          mechanicId: 'demo_mechanic_001',
          mechanicName: 'Demo Mechanic',
          mechanicEmail: 'mechanic@roadresq.com',
        ),
      ),
    );
  }

  Future<void> sendOtp() async {
    final phone = phoneController.text.trim();

    if (phone.isEmpty || phone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid phone number')),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final response = await ApiService.sendOtp(phone: phone);

      if ((response['success'] ?? false) == true) {
        setState(() {
          showOtpBox = true;
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              response['message']?.toString() ?? 'OTP sent successfully',
            ),
          ),
        );
      } else {
        throw Exception(response['message'] ?? 'Failed to send OTP');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send OTP: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> verifyOtp() async {
    final phone = phoneController.text.trim();
    final otp = otpController.text.trim();

    if (phone.isEmpty || phone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid phone number')),
      );
      return;
    }

    if (otp.isEmpty || otp.length < 4) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a valid OTP')));
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final response = await ApiService.verifyOtp(
        phone: phone,
        otp: otp,
        isMechanic: widget.isMechanic,
      );

      if ((response['success'] ?? false) != true) {
        throw Exception(response['message'] ?? 'OTP verification failed');
      }

      final prefs = await SharedPreferences.getInstance();

      if (widget.isMechanic) {
        final mechanic = Map<String, dynamic>.from(
          response['mechanic'] ?? const {},
        );
        final mechanicId = (mechanic['_id'] ?? mechanic['id'] ?? '').toString();

        if (mechanicId.isEmpty) {
          throw Exception('Mechanic ID missing');
        }

        await prefs.setString('mechanicId', mechanicId);
        await prefs.setString(
          'mechanicName',
          (mechanic['name'] ?? 'Mechanic').toString(),
        );
        await prefs.setString(
          'mechanicEmail',
          (mechanic['email'] ?? '').toString(),
        );

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => MechanicMainScreen(
              mechanicId: mechanicId,
              mechanicName: (mechanic['name'] ?? 'Mechanic').toString(),
              mechanicEmail: (mechanic['email'] ?? '').toString(),
            ),
          ),
        );
      } else {
        final user = Map<String, dynamic>.from(response['user'] ?? const {});
        final userId = (user['_id'] ?? user['id'] ?? '').toString();

        if (userId.isEmpty) {
          throw Exception('User ID missing');
        }

        await prefs.setString('userId', userId);
        await prefs.setString('userName', (user['name'] ?? 'User').toString());
        await prefs.setString('userEmail', (user['email'] ?? '').toString());

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => UserMainScreen(
              name: (user['name'] ?? 'User').toString(),
              email: (user['email'] ?? '').toString(),
              homeScreen: const UserHomeScreen(),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('OTP verification failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> handleEmailLogin() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter email and password')),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      if (widget.isMechanic) {
        final response = await ApiService.mechanicLogin(
          email: email,
          password: password,
        );

        final mechanic = Map<String, dynamic>.from(
          response['mechanic'] ?? const {},
        );
        final prefs = await SharedPreferences.getInstance();

        await prefs.setString(
          'mechanicId',
          (mechanic['_id'] ?? mechanic['id'] ?? '').toString(),
        );
        await prefs.setString(
          'mechanicName',
          (mechanic['name'] ?? '').toString(),
        );
        await prefs.setString(
          'mechanicEmail',
          (mechanic['email'] ?? '').toString(),
        );

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => MechanicMainScreen(
              mechanicId: (mechanic['_id'] ?? mechanic['id'] ?? '').toString(),
              mechanicName: (mechanic['name'] ?? 'Mechanic').toString(),
              mechanicEmail: (mechanic['email'] ?? '').toString(),
            ),
          ),
        );
      } else {
        final response = await ApiService.userLoginWithEmail(
          email: email,
          password: password,
        );

        final user = Map<String, dynamic>.from(response['user'] ?? const {});
        final prefs = await SharedPreferences.getInstance();

        await prefs.setString(
          'userId',
          (user['_id'] ?? user['id'] ?? '').toString(),
        );
        await prefs.setString('userName', (user['name'] ?? '').toString());
        await prefs.setString('userEmail', (user['email'] ?? '').toString());

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => UserMainScreen(
              name: (user['name'] ?? 'User').toString(),
              email: (user['email'] ?? '').toString(),
              homeScreen: const UserHomeScreen(),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      String message = 'Login failed. Please try again.';
      final text = e.toString().toLowerCase();

      if (text.contains('401') || text.contains('invalid')) {
        message = 'Invalid email or password';
      } else if (text.contains('timeout')) {
        message = 'Server is taking too long to respond';
      } else if (text.contains('socketexception') ||
          text.contains('connection') ||
          text.contains('failed host lookup')) {
        message = 'Could not connect to backend server';
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  InputDecoration inputDecoration({
    required String label,
    required IconData icon,
    String? hint,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.grey.shade100,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradientColors),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white,
            child: Icon(
              widget.isMechanic ? Icons.build_circle : Icons.person,
              color: themeColor,
              size: 30,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 29,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.isMechanic
                ? 'OTP access, partner login, safety tools, community, and passbook features.'
                : 'OTP access, emergency rescue, email login, and live tracking.',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildOtpCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha((0.05 * 255).round()),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              widget.isMechanic ? 'Partner OTP Access' : 'Quick OTP Access',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: phoneController,
            keyboardType: TextInputType.phone,
            decoration: inputDecoration(
              label: 'Phone Number',
              hint: 'Enter mobile number',
              icon: Icons.phone_iphone,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: isLoading ? null : sendOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: themeColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: isLoading && !showOtpBox
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      widget.isMechanic ? 'Send Partner OTP' : 'Send OTP',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
          ),
          if (showOtpBox) ...[
            const SizedBox(height: 14),
            TextField(
              controller: otpController,
              keyboardType: TextInputType.number,
              decoration: inputDecoration(
                label: 'Enter OTP',
                hint: 'Enter OTP received from backend',
                icon: Icons.password,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: isLoading ? null : verifyOtp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        widget.isMechanic ? 'Verify Partner OTP' : 'Verify OTP',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          TextButton(
            onPressed: () {
              setState(() {
                showEmailLogin = !showEmailLogin;
              });
            },
            child: Text(
              showEmailLogin
                  ? 'Hide email login'
                  : 'Use email and password instead',
              style: TextStyle(color: themeColor, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildEmailCard() {
    if (!showEmailLogin) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha((0.05 * 255).round()),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              widget.isMechanic ? 'Mechanic Email Login' : 'Email Login',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: themeColor,
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: inputDecoration(
              label: 'Email',
              hint: 'Enter registered email',
              icon: Icons.email_outlined,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: passwordController,
            obscureText: obscurePassword,
            decoration: inputDecoration(
              label: 'Password',
              hint: 'Enter password',
              icon: Icons.lock_outline,
              suffixIcon: IconButton(
                onPressed: () {
                  setState(() {
                    obscurePassword = !obscurePassword;
                  });
                },
                icon: Icon(
                  obscurePassword ? Icons.visibility_off : Icons.visibility,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: isLoading ? null : handleEmailLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: themeColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Login',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildFastAccessCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: widget.isMechanic
            ? const Color(0xFFEAF2FF)
            : const Color(0xFFFFF3F2),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: widget.isMechanic
              ? const Color(0xFFBBDEFB)
              : const Color(0xFFFFCDD2),
        ),
      ),
      child: Column(
        children: [
          Icon(
            widget.isMechanic
                ? Icons.workspace_premium
                : Icons.warning_amber_rounded,
            color: widget.isMechanic ? const Color(0xFF0D47A1) : Colors.red,
            size: 38,
          ),
          const SizedBox(height: 10),
          Text(
            widget.isMechanic ? 'Fast Partner Access' : 'Emergency Fast Access',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: widget.isMechanic ? const Color(0xFF0D47A1) : Colors.red,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.isMechanic
                ? 'Open the mechanic app directly with demo partner access.'
                : 'Need immediate help? Enter the app directly and request rescue now.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Colors.black87),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed:
                  widget.isMechanic ? loginAsDemoMechanic : loginAsDemoUser,
              icon: const Icon(Icons.flash_on),
              label: Text(
                widget.isMechanic
                    ? 'Continue to Partner Access'
                    : 'Continue to Emergency Access',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: themeColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    phoneController.dispose();
    otpController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      body: SafeArea(
        child: Column(
          children: [
            buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    buildOtpCard(),
                    buildEmailCard(),
                    buildFastAccessCard(),
                    const SizedBox(height: 14),
                    Text(
                      widget.isMechanic
                          ? 'OTP access • Email login • Partner tools'
                          : 'OTP access • Email login • Emergency rescue access',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
