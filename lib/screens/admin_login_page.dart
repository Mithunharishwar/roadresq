// FILE: lib/screens/admin_login_page.dart
/// §51 — entry point to the admin console.
///
/// The console already existed (`admin_dashboard_page.dart`) but nothing could
/// reach it. Credentials are checked by `POST /api/admin/login`, which compares
/// against `ROADRESQ_ADMIN_USER` / `ROADRESQ_ADMIN_PASSWORD`. With no password
/// configured the backend allows the documented development password only
/// while `DEV_MODE` is on, and this screen says so plainly.
library;

import 'package:material_ui/material_ui.dart';

import '../core/session/app_session.dart';
import '../core/theme/role_colors.dart';
import '../services/module_api.dart';
import '../widgets/rq_async.dart';
import 'admin_dashboard_page.dart';

class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key});

  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final TextEditingController _user = TextEditingController(text: 'admin');
  final TextEditingController _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final username = _user.text.trim();
    final password = _password.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter both the admin user and password.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final result = await ModuleApi.adminLogin(
        username: username,
        password: password,
      );
      await AppSession.save(role: 'admin', id: username, name: 'Admin');
      if (!mounted) return;

      final devMode = result['devMode'] == true;
      if (devMode) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Signed in with the development admin password. Set '
              'ROADRESQ_ADMIN_PASSWORD before exposing this server.',
              style: TextStyle(inherit: true),
            ),
            duration: Duration(seconds: 5),
          ),
        );
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AdminDashboardPage()),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = rqMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin console', style: TextStyle(inherit: true)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 12),
          const Icon(Icons.admin_panel_settings,
              size: 54, color: Color(0xFF37474F)),
          const SizedBox(height: 14),
          Text(
            'Operations sign-in',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium
                ?.copyWith(inherit: true, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'Users, mechanics, jobs, revenue and allocation evidence.',
            textAlign: TextAlign.center,
            style: TextStyle(
                inherit: true, fontSize: 12, color: RoleColors.neutral),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _user,
            style: const TextStyle(inherit: true),
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Admin user',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _password,
            obscureText: _obscure,
            style: const TextStyle(inherit: true),
            onSubmitted: (_) => _signIn(),
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: RoleColors.tint(RoleColors.user, opacity: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _error!,
                style: const TextStyle(inherit: true, color: RoleColors.user),
              ),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 50,
            child: FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF37474F)),
              onPressed: _busy ? null : _signIn,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Sign in',
                      style: TextStyle(
                          inherit: true, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Server-side note: the legacy /api/admin/* routes are not yet '
            'token-guarded. This screen controls who reaches the console in '
            'the app; on a public network the admin routes must be protected '
            'at the proxy until role-guarding is enabled.',
            style: TextStyle(
                inherit: true, fontSize: 11, color: RoleColors.neutral),
          ),
        ],
      ),
    );
  }
}
