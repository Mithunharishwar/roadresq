import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../core/navigation/exit_guard.dart';
import '../core/router/app_router.dart';
import '../core/theme/app_theme.dart';
import '../widgets/module_switcher.dart';

import '../core/session/app_session.dart';
import '../services/session_service.dart';
import '../services/socket_service.dart';
import 'mechanic_home_screen.dart';
import 'mechanic_history_screen.dart';
import 'mechanic_passbook_screen.dart';
import 'profile_screen.dart';

class MechanicMainScreen extends StatefulWidget {
  final String mechanicId;
  final String mechanicName;
  final String mechanicEmail;

  const MechanicMainScreen({
    super.key,
    required this.mechanicId,
    required this.mechanicName,
    required this.mechanicEmail,
  });

  @override
  State<MechanicMainScreen> createState() => _MechanicMainScreenState();
}

class _MechanicMainScreenState extends State<MechanicMainScreen> {
  int currentIndex = 0;
  late final List<Widget> pages;

  final List<String> titles = const [
    'Captain Dashboard',
    'Job History',
    'Passbook',
    'Profile',
  ];

  @override
  void initState() {
    super.initState();

    pages = [
      MechanicHomeScreen(
        mechanicId: widget.mechanicId,
        mechanicName: widget.mechanicName,
      ),
      // Both tabs read real backend data scoped to this mechanic; they used to
      // be hardcoded sample jobs and fabricated earnings.
      MechanicHistoryScreen(mechanicId: widget.mechanicId),
      MechanicPassbookScreen(mechanicId: widget.mechanicId),
      ProfileScreen(
        name: widget.mechanicName,
        email: widget.mechanicEmail,
        role: 'Mechanic Partner',
        onSwitchModule: () => ModuleSwitcher.open(context),
        phone: AppSession.phone ?? '',
        embedded: true,
      ),
    ];
  }

  Future<void> handleLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Do you want to logout from mechanic account?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D47A1),
                foregroundColor: Colors.white,
              ),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );

    if (shouldLogout != true || !mounted) return;

    // Clear the persisted identity too. Without this the splash screen found a
    // stored mechanic and signed the same account straight back in, so "logout"
    // only lasted until the next launch.
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
    final bool showAppBar = currentIndex != 0;

    return Scaffold(
      appBar: showAppBar
          ? AppBar(
              title: Text(titles[currentIndex]),
              backgroundColor: Theme.of(context).brightness == Brightness.dark
                  ? AppTheme.darkSurface
                  : const Color(0xFF0D47A1),
              foregroundColor: Colors.white,
              actions: [
                IconButton(
                  tooltip: 'Switch module',
                  onPressed: () => ModuleSwitcher.open(context),
                  icon: const Icon(Icons.grid_view_rounded),
                ),
                IconButton(
                  onPressed: handleLogout,
                  icon: const Icon(Icons.logout),
                ),
              ],
            )
          : null,
      body: IndexedStack(index: currentIndex, children: pages),
      // 8 dp of breathing room inside the bar's own surface colour: some ROMs
      // report an app area deeper than the system navigation bar they paint, and
      // the labels were clipped flush against the screen edge.
      bottomNavigationBar: Container(
        color: AppTheme.surfaceOf(context),
        padding: const EdgeInsets.only(bottom: 8),
        child: BottomNavigationBar(
        currentIndex: currentIndex,
        selectedItemColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFFEF5350)
            : const Color(0xFF0D47A1),
        unselectedItemColor: AppTheme.mutedOf(context),
        backgroundColor: AppTheme.surfaceOf(context),
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        onTap: (value) {
          setState(() {
            currentIndex = value;
          });
        },
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
            icon: Icon(Icons.account_balance_wallet_outlined),
            activeIcon: Icon(Icons.account_balance_wallet),
            label: 'Passbook',
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
