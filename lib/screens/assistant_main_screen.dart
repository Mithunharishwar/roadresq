import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../core/navigation/exit_guard.dart';
import '../core/router/app_router.dart';
import '../core/theme/app_theme.dart';
import '../widgets/module_switcher.dart';

import '../core/session/app_session.dart';
import '../services/session_service.dart';
import '../services/socket_service.dart';
import 'assistant_home_screen.dart';
import 'assistant_history_screen.dart';
import 'profile_screen.dart';

/// AssistantMainScreen
///
/// Bottom navigation wrapper for the assistant (rider) app.
/// Tabs: Home (dashboard), History, Profile.
class AssistantMainScreen extends StatefulWidget {
  final String assistantId;
  final String assistantName;
  final String assistantEmail;

  const AssistantMainScreen({
    super.key,
    required this.assistantId,
    required this.assistantName,
    required this.assistantEmail,
  });

  @override
  State<AssistantMainScreen> createState() => _AssistantMainScreenState();
}

class _AssistantMainScreenState extends State<AssistantMainScreen> {
  int currentIndex = 0;
  late final List<Widget> pages;

  final List<String> titles = const [
    'Rider Dashboard',
    'My Rides',
    'Profile',
  ];

  @override
  void initState() {
    super.initState();

    pages = [
      AssistantHomeScreen(
        assistantId: widget.assistantId,
        assistantName: widget.assistantName,
      ),
      AssistantHistoryScreen(assistantId: widget.assistantId),
      ProfileScreen(
        name: widget.assistantName,
        email: widget.assistantEmail,
        role: 'Assistant Rider',
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
          content: const Text('Do you want to logout from assistant account?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
              ),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );

    if (shouldLogout != true || !mounted) return;

    // Same reason as the mechanic panel: a stored identity would sign the same
    // rider back in on the next launch.
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
                  : const Color(0xFF2E7D32),
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
            : const Color(0xFF2E7D32),
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
