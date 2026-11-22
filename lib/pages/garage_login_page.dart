import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import '../core/router/app_router.dart';
import '../core/session/app_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../core/utils/error_handler.dart';

/// GarageLoginPage — purple-themed sign-in AND registration for garage
/// partners.
///
/// WHY REGISTRATION IS HERE
/// This page used to offer sign-in only: two credential fields, a decorative
/// name/phone pair, and the caption "Verified garage partners only." There was
/// no way to create an account anywhere in the app, even though the backend has
/// had `POST /api/garage/register` all along and the API client already had
/// `ApiService.garageRegister` — unused. The only garages in the database were
/// seeded with password hashes nobody holds, so every honest attempt ended in
/// "invalid login credentials" with no route out. A partner who has no account
/// now has one.
class GarageLoginPage extends StatefulWidget {
  const GarageLoginPage({super.key});

  @override
  State<GarageLoginPage> createState() => _GarageLoginPageState();
}

class _GarageLoginPageState extends State<GarageLoginPage>
    with SingleTickerProviderStateMixin {
  static const Color _purple = Color(0xFF7E57C2);
  static const Gradient _gradient = LinearGradient(
    colors: [Color(0xFF512DA8), Color(0xFF7E57C2)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  late final TabController _tabController;

  final TextEditingController garageIdController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();

  bool isLoading = false;
  bool obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Rebuild when the user switches tabs so the form matches the mode.
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  bool get _isRegistering => _tabController.index == 1;

  // ── Sign in ───────────────────────────────────────────────────────────────

  Future<void> signIn() async {
    final id = garageIdController.text.trim();
    final password = passwordController.text;

    if (id.isEmpty) {
      _showSnack('Enter your garage ID');
      return;
    }
    if (password.isEmpty) {
      _showSnack('Enter your garage password');
      return;
    }

    setState(() => isLoading = true);
    try {
      final response = await ApiService.garageLogin(
        garageId: id,
        password: password,
      );
      await _enterDashboard(
        response: response,
        fallbackId: id,
        fallbackName: nameController.text.trim(),
        fallbackPhone: phoneController.text.trim(),
      );
    } on ApiAuthException catch (e) {
      if (e.isUnauthorized) {
        _showSnack(
          'Incorrect garage ID or password. If you have not registered yet, '
          'use the Register tab.',
        );
      } else if (e.isConflict) {
        _showSnack('${e.message} — switch to the Sign In tab.');
      } else {
        _showSnack(e.message);
      }
    } catch (e) {
      _showSnack(ErrorHandler.getFriendlyMessage(e));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ── Register ──────────────────────────────────────────────────────────────

  Future<void> register() async {
    final id = garageIdController.text.trim();
    final name = nameController.text.trim();
    final password = passwordController.text;

    if (id.isEmpty) {
      _showSnack('Choose a garage ID (any code that identifies your garage)');
      return;
    }
    if (name.isEmpty) {
      _showSnack('Enter your garage name');
      return;
    }
    if (password.length < 6) {
      _showSnack('Choose a password of at least 6 characters');
      return;
    }

    setState(() => isLoading = true);
    try {
      await ApiService.garageRegister(
        garageId: id,
        name: name,
        password: password,
        phone: phoneController.text.trim(),
      );

      // Sign in straight away rather than bouncing back to the other tab — the
      // credentials were just chosen and are known-good.
      final response = await ApiService.garageLogin(
        garageId: id,
        password: password,
      );
      if (mounted) {
        _showSnack(
          'Garage registered. It is unverified until an admin approves it.',
        );
      }
      await _enterDashboard(
        response: response,
        fallbackId: id,
        fallbackName: name,
        fallbackPhone: phoneController.text.trim(),
      );
    } on ApiAuthException catch (e) {
      if (e.isConflict) {
        _showSnack(
          'That garage ID is already registered. Switch to the Sign In tab, '
          'or choose a different ID.',
        );
      } else {
        _showSnack(e.message);
      }
    } catch (e) {
      _showSnack('Registration failed. ${ErrorHandler.getFriendlyMessage(e)}');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  /// Persist the garage identity the dashboard reads, then open it.
  ///
  /// The identity is the backend's `garageId` string — NOT a Firebase uid. The
  /// dashboard used to read `FirebaseAuth.currentUser`, which is always null
  /// here because logins go through this backend.
  Future<void> _enterDashboard({
    required Map<String, dynamic> response,
    required String fallbackId,
    required String fallbackName,
    required String fallbackPhone,
  }) async {
    final garage = (response['garage'] as Map<String, dynamic>?) ?? const {};

    final prefs = await SharedPreferences.getInstance();
    final id = (garage['garageId'] as String?)?.trim();
    final name = (garage['name'] as String?)?.trim();
    final phone = (garage['phone'] as String?)?.trim();

    await prefs.setString('garageId', id?.isNotEmpty == true ? id! : fallbackId);
    await prefs.setString(
      'garageName',
      name?.isNotEmpty == true
          ? name!
          : (fallbackName.isEmpty ? 'Garage' : fallbackName),
    );
    await prefs.setString(
      'garagePhone',
      phone?.isNotEmpty == true ? phone! : fallbackPhone,
    );

    await AppSession.save(
      role: 'garage',
      id: id?.isNotEmpty == true ? id! : fallbackId,
      name: name?.isNotEmpty == true
          ? name!
          : (fallbackName.isEmpty ? 'Garage' : fallbackName),
      phone: phone?.isNotEmpty == true ? phone! : fallbackPhone,
    );

    if (!mounted) return;
    context.go(AppRoutes.garageHome);
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 5)),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool obscure = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure && obscurePassword,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: Colors.white70),
        suffixIcon: obscure
            ? IconButton(
                icon: Icon(
                  obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: Colors.white70,
                ),
                onPressed: () =>
                    setState(() => obscurePassword = !obscurePassword),
              )
            : null,
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: Colors.white.withAlpha((0.14 * 255).round()),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.white, width: 1.2),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    phoneController.dispose();
    nameController.dispose();
    garageIdController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final registering = _isRegistering;

    return Scaffold(
      backgroundColor: _purple,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(20),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.arrow_back, color: Colors.white),
                ),
              ),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: _gradient,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha((0.25 * 255).round()),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.white,
                      child: Icon(Icons.garage, color: _purple, size: 32),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      registering ? 'Register your garage' : 'Garage Partner',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      registering
                          ? 'Create a partner account to verify digital tokens '
                              'and manage towing jobs.'
                          : 'Verify digital tokens & manage towing jobs '
                              'assigned to your garage.',
                      style: const TextStyle(color: Colors.white70, height: 1.4),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha((0.16 * 255).round()),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        indicator: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerColor: Colors.transparent,
                        labelColor: _purple,
                        unselectedLabelColor: Colors.white,
                        labelStyle: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                        tabs: const [
                          Tab(text: 'Sign In'),
                          Tab(text: 'Register'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _field(
                      controller: garageIdController,
                      hint: registering
                          ? 'Choose a Garage ID'
                          : 'Enter Garage ID',
                      icon: Icons.badge_outlined,
                    ),
                    if (registering) ...[
                      const SizedBox(height: 12),
                      _field(
                        controller: nameController,
                        hint: 'Garage name',
                        icon: Icons.storefront_outlined,
                      ),
                      const SizedBox(height: 12),
                      _field(
                        controller: phoneController,
                        hint: 'Contact number',
                        icon: Icons.phone_android,
                        keyboardType: TextInputType.phone,
                      ),
                    ],
                    const SizedBox(height: 12),
                    _field(
                      controller: passwordController,
                      hint: registering
                          ? 'Choose a password (6+ characters)'
                          : 'Garage password',
                      icon: Icons.lock_outline,
                      obscure: true,
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: isLoading
                            ? null
                            : (registering ? register : signIn),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: _purple,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        child: isLoading
                            ? const CircularProgressIndicator(color: _purple)
                            : Text(
                                registering
                                    ? 'Create Garage Account'
                                    : 'Access Garage Dashboard',
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  registering
                      ? 'New garages start unverified until an admin approves '
                          'them.'
                      : 'Verified garage partners only.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


