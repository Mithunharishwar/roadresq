import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../core/navigation/exit_guard.dart';
import '../core/router/app_router.dart';
import '../core/theme/app_theme.dart';
import '../widgets/module_switcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/session/app_session.dart';
import '../services/session_service.dart';
import '../services/socket_service.dart';
import 'my_requests_screen.dart';
import 'support_center_screen.dart';
import 'profile_screen.dart';
import 'request_status_screen.dart';

class UserMainScreen extends StatefulWidget {
  final String name;
  final String email;
  final Widget homeScreen;

  const UserMainScreen({
    super.key,
    required this.name,
    required this.email,
    required this.homeScreen,
  });

  @override
  State<UserMainScreen> createState() => _UserMainScreenState();
}

class _UserMainScreenState extends State<UserMainScreen> {
  int currentIndex = 0;
  String? lastRequestId;
  bool loadingTrack = true;

  late final List<Widget> pages;

  final List<String> titles = const [
    'Home',
    'Track Rescue',
    'My Requests',
    'Support',
    'Profile',
  ];

  @override
  void initState() {
    super.initState();
    loadLastRequest();

    pages = [
      widget.homeScreen,
      const SizedBox(),
      const MyRequestsScreen(embedded: true),
      const SupportCenterScreen(isMechanic: false, embedded: true),
      ProfileScreen(
        name: widget.name,
        email: widget.email,
        phone: AppSession.phone ?? '',
        role: 'User',
        onSwitchModule: () => ModuleSwitcher.open(context),
        embedded: true,
      ),
    ];
  }

  Future<void> loadLastRequest() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('last_request_id');

    if (!mounted) return;

    setState(() {
      lastRequestId = id;
      loadingTrack = false;
    });
  }

  Widget buildTrackRescueScreen() {
    if (loadingTrack) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (lastRequestId == null || lastRequestId!.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFFF7F9FC),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha((0.05 * 255).round()),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.route, size: 46, color: Colors.red),
                  SizedBox(height: 14),
                  Text(
                    'No Active Rescue',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Create a rescue request to start live tracking.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return RequestStatusScreen(
      requestId: lastRequestId!,
      issue: 'Current Rescue',
      vehicle: '',
      location: '',
    );
  }

  Future<void> handleLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Do you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );

    if (shouldLogout != true || !mounted) return;

    // Clearing only the screen was the bug: AppSession/SessionService kept the
    // customer signed in, so the next launch went straight back to the customer
    // home. The other three roles already clear all three stores here.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('userId');
    await prefs.remove('userName');
    await prefs.remove('userEmail');
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
    final updatedPages = [
      pages[0],
      buildTrackRescueScreen(),
      pages[2],
      pages[3],
      pages[4],
    ];

    final bool showAppBar = currentIndex != 0;

    return Scaffold(
      appBar: showAppBar
          ? AppBar(
              title: Text(titles[currentIndex]),
              backgroundColor: Theme.of(context).brightness == Brightness.dark
                  ? AppTheme.darkSurface
                  : const Color(0xFFD32F2F),
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
      body: IndexedStack(
        index: currentIndex,
        children: updatedPages,
      ),
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
            : const Color(0xFFD32F2F),
        unselectedItemColor: AppTheme.mutedOf(context),
        backgroundColor: AppTheme.surfaceOf(context),
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        onTap: (value) async {
          if (value == 1) {
            await loadLastRequest();
          }

          if (!mounted) return;

          setState(() {
            currentIndex = value;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.route_outlined),
            activeIcon: Icon(Icons.route),
            label: 'Track',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_outlined),
            activeIcon: Icon(Icons.history),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.support_agent_outlined),
            activeIcon: Icon(Icons.support_agent),
            label: 'Support',
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
