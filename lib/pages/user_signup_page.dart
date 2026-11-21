import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../core/router/app_router.dart';
import '../core/session/app_session.dart';
import '../services/module_api.dart';
import '../services/api_service.dart';
import '../core/utils/error_handler.dart';

class UserSignupPage extends StatefulWidget {
  const UserSignupPage({super.key});

  @override
  State<UserSignupPage> createState() => _UserSignupPageState();
}

class _UserSignupPageState extends State<UserSignupPage> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController vehicleController = TextEditingController();

  /// §7 — optional profile photo, uploaded after the account exists.
  XFile? _photo;

  bool isLoading = false;
  bool obscurePassword = true;

  Future<void> signup() async {
    final name = nameController.text.trim();
    final phone = phoneController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (name.isEmpty || phone.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields')),
      );
      return;
    }

    if (phone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid phone number')),
      );
      return;
    }

    if (email.isNotEmpty && !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email')),
      );
      return;
    }

    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must be at least 6 characters')),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final response = await ApiService.userSignup(
        name: name,
        phone: phone,
        email: email,
        password: password,
      );

      final user = (response['user'] as Map<String, dynamic>?) ?? const {};
      final userId = (user['id'] ?? user['_id'] ?? phone).toString();
      final vehicle = vehicleController.text.trim();

      // §7 — vehicle and photo are part of the profile, not an afterthought.
      // The account exists at this point, so both are saved against its id.
      // A failed photo upload must not lose the account that was just created.
      if (userId.isNotEmpty) {
        try {
          String? photoUrl;
          if (_photo != null) {
            photoUrl = await ModuleApi.upload(
              filePath: _photo!.path,
              kind: 'avatar',
            );
          }
          await ModuleApi.saveUserProfile(
            userId: userId,
            name: name,
            phone: phone,
            email: email,
            vehicle: vehicle,
            photoUrl: photoUrl,
          );
        } catch (e) {
          debugPrint('[signup] profile extras not saved: $e');
        }
      }

      await AppSession.save(
        role: 'user',
        id: userId,
        name: name,
        phone: phone,
        email: email,
        vehicle: vehicle,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account created successfully')),
      );

      context.go(AppRoutes.userHome);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Signup failed. ${ErrorHandler.getFriendlyMessage(e)}')));
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  InputDecoration buildInputDecoration({
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
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();
    passwordController.dispose();
    vehicleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        title: const Text('Create Account'),
        backgroundColor: const Color(0xFFD32F2F),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFD32F2F), Color(0xFFFF7043)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  children: const [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.white,
                      child: Icon(
                        Icons.person_add_alt_1,
                        color: Color(0xFFD32F2F),
                        size: 30,
                      ),
                    ),
                    SizedBox(height: 14),
                    Text(
                      'Join RoadResQ',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Create your account for instant roadside help',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha((0.05 * 255).round()),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: buildInputDecoration(
                        label: 'Full Name',
                        hint: 'Enter your name',
                        icon: Icons.person_outline,
                      ),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: buildInputDecoration(
                        label: 'Phone Number',
                        hint: 'Enter your mobile number',
                        icon: Icons.phone_outlined,
                      ),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: buildInputDecoration(
                        label: 'Email (optional)',
                        hint: 'Enter your email',
                        icon: Icons.email_outlined,
                      ),
                    ),
                    const SizedBox(height: 15),
                    // §7 — the vehicle is what a mechanic needs to bring the
                    // right parts; asking for it at signup avoids a repeat
                    // question at the roadside.
                    TextField(
                      controller: vehicleController,
                      decoration: buildInputDecoration(
                        label: 'Vehicle (optional)',
                        hint: 'e.g. Honda Activa · TN 01 AB 1234',
                        icon: Icons.directions_car_outlined,
                      ),
                    ),
                    const SizedBox(height: 15),
                    InkWell(
                      onTap: isLoading
                          ? null
                          : () async {
                              final messenger =
                                  ScaffoldMessenger.of(context);
                              try {
                                final picked = await ImagePicker().pickImage(
                                  source: ImageSource.gallery,
                                  imageQuality: 80,
                                  maxWidth: 1024,
                                );
                                if (picked != null && mounted) {
                                  setState(() => _photo = picked);
                                }
                              } catch (e) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Could not open the gallery: $e',
                                      style: const TextStyle(inherit: true),
                                    ),
                                  ),
                                );
                              }
                            },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: _photo == null
                                  ? const SizedBox(
                                      width: 44,
                                      height: 44,
                                      child: Icon(Icons.add_a_photo_outlined),
                                    )
                                  : Image.file(
                                      File(_photo!.path),
                                      width: 44,
                                      height: 44,
                                      fit: BoxFit.cover,
                                    ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _photo == null
                                    ? 'Add a profile photo (optional)'
                                    : 'Photo selected — tap to change',
                                style: const TextStyle(
                                    inherit: true, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: passwordController,
                      obscureText: obscurePassword,
                      decoration: buildInputDecoration(
                        label: 'Password',
                        hint: 'Create a password',
                        icon: Icons.lock_outline,
                        suffixIcon: IconButton(
                          onPressed: () {
                            setState(() {
                              obscurePassword = !obscurePassword;
                            });
                          },
                          icon: Icon(
                            obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: isLoading ? null : signup,
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
                                'Create Account',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


