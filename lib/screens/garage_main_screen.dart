// FILE: lib/screens/garage_main_screen.dart
//
// Bottom-navigation shell for the garage role.
//
// WHY THIS EXISTS
// The mechanic and assistant apps each have Home / History / Profile. The
// garage landed straight on a single scrolling dashboard with a logout button,
// so a garage had no history and no profile — the visible gap between "garage
// works" and "garage works like the others". This shell gives the garage the
// same three tabs, reusing the existing screens:
//
//   Home    → GarageDashboard (queue, inbox, service actions, payment)
//   History → GarageHistoryScreen (finished jobs and billed amounts)
//   Profile → ProfileScreen (shared across roles)

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/session/app_session.dart';
import '../core/navigation/exit_guard.dart';
import '../core/router/app_router.dart';
import '../core/theme/app_theme.dart';
import '../services/session_service.dart';
import '../services/socket_service.dart';

import '../features/garage/garage_dashboard.dart';
import 'garage_history_screen.dart';
import '../widgets/module_switcher.dart';
import 'profile_screen.dart';

class GarageMainScreen extends StatefulWidget {
  const GarageMainScreen({super.key});

  @override
  State<GarageMainScreen> createState() => _GarageMainScreenState();
}

class _GarageMainScreenState extends State<GarageMainScreen> {
  static const Color _purple = Color(0xFF7E57C2);

  int currentIndex = 0;
  String garageName = 'Garage';
  String garagePhone = '';

  @override
  void initState() {
    super.initState();
    _loadIdentity();
  }

  Future<void> _loadIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      garageName = prefs.getString('garageName') ?? 'Garage';
      garagePhone = prefs.getString('garagePhone') ?? '';
    });
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Do you want to logout from the garage account?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _purple,
              foregroundColor: Colors.white,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('garageId');
    await prefs.remove('garageName');
    await prefs.remove('garagePhone');
    await AppSession.clear();
    await SessionService.clear();
    SocketService().disconnect();

    if (!mounted) return;
    // Go through the router, not the Navigator. pushAndRemoveUntil removed the
    // router's page and left one imperative route behind, so the next back press
    // emptied the Navigator and drew a black screen.
    Navigator.of(context).popUntil((route) => route.isFirst);
    if (!mounted) return;
    context.go(AppRoutes.roleSelect);
  }

  @override
  Widget build(BuildContext context) {
    // A back press at a module root must never pop the router's last page: that
    // is what drew the black screen. ExitGuard asks first, then leaves the app.
    return ExitGuard(child: _buildScaffold(context));
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: currentIndex,
        children: [
          const GarageDashboard(),
          GarageHistoryScreen(onLogout: _logout),
          ProfileScreen(
            name: garageName,
            email: garagePhone.isEmpty ? 'Garage partner account' : garagePhone,
            role: 'Garage Partner',
        onSwitchModule: () => ModuleSwitcher.open(context),
        phone: garagePhone,
          ),
        ],
      ),
      // The activity is edge-to-edge, and some ROMs (Samsung with 3-button
      // navigation) report an app area 15 px deeper than the system bar they
      // actually paint: the labels were flush against the edge and cut in half.
      // 8 dp of breathing room inside the bar's own surface colour keeps them
      // clear on both 3-button and gesture navigation.
      bottomNavigationBar: Container(
        color: AppTheme.surfaceOf(context),
        padding: const EdgeInsets.only(bottom: 8),
        child: BottomNavigationBar(
        currentIndex: currentIndex,
        selectedItemColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFFB39DDB)
            : _purple,
        unselectedItemColor: AppTheme.mutedOf(context),
        backgroundColor: AppTheme.surfaceOf(context),
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        onTap: (value) => setState(() => currentIndex = value),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            activeIcon: Icon(Icons.history),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
        ),
      ),
    );
  }
}
