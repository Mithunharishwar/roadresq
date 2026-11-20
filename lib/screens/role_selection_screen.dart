import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/config/app_config.dart';
import '../core/router/app_router.dart';
import '../services/api_service.dart';

/// RoleSelectionScreen — Advanced 4-box 3D role grid.
///
/// Presents User / Mechanic / Garage / Assistant as a 2×2 grid of cards with
/// a 3D perspective-tilt effect, layered shadows and press animation.
/// Navigations are identical to the previous version (no workflow changes).
class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF121212) : const Color(0xFFF7F9FC);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              _buildBrandHeader(context),
              const SizedBox(height: 26),
              Text(
                'Choose your role',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : const Color(0xFF212121),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Continue as a customer, mechanic, garage or first-responder.',
                style: TextStyle(
                  color: isDark ? Colors.white60 : Colors.black54,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 24),

              // ───── 2×2 3D Grid ─────
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.92,
                children: [
                  _RoleCard3D(
                    title: 'User',
                    subtitle: 'Request rescue',
                    badge: 'LIVE',
                    icon: Icons.person,
                    gradient: const [Color(0xFFD32F2F), Color(0xFFFF7043)],
                    glow: const Color(0xFFD32F2F),
                    onTap: () => context.go(AppRoutes.login('user')),
                  ),
                  _RoleCard3D(
                    title: 'Mechanic',
                    subtitle: 'Partner panel',
                    badge: 'SERVICE',
                    icon: Icons.build,
                    gradient: const [Color(0xFF0D47A1), Color(0xFF1976D2)],
                    glow: const Color(0xFF0D47A1),
                    onTap: () => context.go(AppRoutes.login('mechanic')),
                  ),
                  _RoleCard3D(
                    title: 'Garage',
                    subtitle: 'Token verify',
                    badge: 'TOW',
                    icon: Icons.garage,
                    gradient: const [Color(0xFF512DA8), Color(0xFF7E57C2)],
                    glow: const Color(0xFF7E57C2),
                    onTap: () => context.go(AppRoutes.login('garage')),
                  ),
                  _RoleCard3D(
                    title: 'Assistant',
                    subtitle: 'First responder',
                    badge: 'RIDER',
                    icon: Icons.two_wheeler,
                    gradient: const [Color(0xFF2E7D32), Color(0xFF4CAF50)],
                    glow: const Color(0xFF2E7D32),
                    onTap: () => context.go(AppRoutes.login('assistant')),
                  ),
                ],
              ),

              const SizedBox(height: 24),
              _buildFeatureChips(context),
              const SizedBox(height: 18),
              const _BackendAddressTile(),
              const SizedBox(height: 10),
              Center(
                child: TextButton.icon(
                  onPressed: () => context.go(AppRoutes.admin),
                  icon: const Icon(Icons.admin_panel_settings_outlined, size: 16),
                  label: const Text(
                    'Admin console',
                    style: TextStyle(inherit: true, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBrandHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFD32F2F), Color(0xFFFF7043)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD32F2F).withAlpha((0.28 * 255).round()),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha((0.2 * 255).round()),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.car_repair,
              color: Colors.white,
              size: 34,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RoadResQ',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Real-time roadside rescue with live tracking',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureChips(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chipBg = isDark ? const Color(0xFF2A2A2A) : Colors.white;

    Widget chip(IconData icon, String text) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: chipBg,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha((0.06 * 255).round()),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: const Color(0xFFD32F2F)),
            const SizedBox(width: 8),
            Text(
              text,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        chip(Icons.verified_user_outlined, 'Verified'),
        chip(Icons.location_on_outlined, 'Live location'),
        chip(Icons.route_outlined, 'Route updates'),
        chip(Icons.support_agent_outlined, 'Fast support'),
      ],
    );
  }
}

/// A single 3D-tilted role card with layered shadow + press animation.
class _RoleCard3D extends StatefulWidget {
  final String title;
  final String subtitle;
  final String badge;
  final IconData icon;
  final List<Color> gradient;
  final Color glow;
  final VoidCallback onTap;

  const _RoleCard3D({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.icon,
    required this.gradient,
    required this.glow,
    required this.onTap,
  });

  @override
  State<_RoleCard3D> createState() => _RoleCard3DState();
}

class _RoleCard3DState extends State<_RoleCard3D> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    // 3D perspective tilt: rotate the card slightly on the X axis and apply
    // a perspective transform so it appears to "lean" back toward the viewer.
    final Matrix4 transform = Matrix4.identity()
      ..setEntry(3, 2, 0.0016)
      ..rotateX(_pressed ? -0.06 : 0.035)
      ..rotateY(_pressed ? 0.0 : -0.02);

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        transform: transform,
        transformAlignment: Alignment.center,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: widget.gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              // outer glow
              BoxShadow(
                color: widget.glow.withAlpha((0.35 * 255).round()),
                blurRadius: _pressed ? 10 : 22,
                offset: const Offset(0, 12),
              ),
              // inner depth
              BoxShadow(
                color: Colors.black.withAlpha((0.18 * 255).round()),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: Stack(
              children: [
                // subtle top-light sheen
                Positioned(
                  top: -40,
                  right: -30,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withAlpha((0.12 * 255).round()),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(
                                (0.2 * 255).round(),
                              ),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Text(
                              widget.badge,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.arrow_outward_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ],
                      ),
                      const Spacer(),
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha((0.18 * 255).round()),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(widget.icon, color: Colors.white, size: 28),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        widget.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          height: 1.3,
                        ),
                       ),
                     ],
                   ),
                 ),
               ],
             ),
           ),
         ),
       ),
     );
   }
}

/// Shows the backend address the app is using, whether it answers, and lets it
/// be changed on the device.
///
/// WHY THIS IS HERE
/// The host used to be settable only at build time
/// (`--dart-define=ROADRESQ_HOST=...`). Forgetting that flag is invisible: the
/// app silently targets `10.0.2.2`, an alias that only exists on an Android
/// emulator, so on a real phone every request dies at the 15s timeout while the
/// server log stays completely empty — which reads exactly like a dead server.
///
/// This tile makes the current address visible and fixable without a rebuild,
/// and remembers the choice across restarts.
class _BackendAddressTile extends StatefulWidget {
  const _BackendAddressTile();

  @override
  State<_BackendAddressTile> createState() => _BackendAddressTileState();
}

class _BackendAddressTileState extends State<_BackendAddressTile> {
  /// null = not checked yet.
  bool? _reachable;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final ok = await ApiService.probeBackend();
    // The address answers again, so the boot-time complaint no longer applies.
    if (ok) AppConfig.clearStartupNotice();
    if (!mounted) return;
    setState(() {
      _reachable = ok;
      _checking = false;
    });
  }

  Future<void> _edit() async {
    final controller = TextEditingController(text: AppConfig.host);
    String? error;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Backend address'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The address of the RoadResQ server this app talks to. '
                'On a phone this is your computer\'s LAN address, '
                'for example http://192.168.1.20:5050',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Server address',
                  hintText: 'http://192.168.1.20:5050',
                  border: OutlineInputBorder(),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(
                  error!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final message = await AppConfig.persistHost(controller.text);
                if (message != null) {
                  setDialogState(() => error = message);
                  return;
                }
                if (dialogContext.mounted) Navigator.pop(dialogContext, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    controller.dispose();
    if (saved == true && mounted) {
      await _check();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color statusColor;
    final String statusText;
    if (_checking) {
      statusColor = Colors.orange;
      statusText = 'checking…';
    } else if (_reachable == true) {
      statusColor = Colors.green;
      statusText = 'reachable';
    } else {
      statusColor = Colors.red;
      statusText = 'unreachable';
    }

    // Only shown while the address is actually failing: the boot-time probe
    // explains WHY every request is timing out, instead of leaving the user with
    // a bare "unreachable".
    final String? notice = _reachable == false ? AppConfig.startupNotice : null;

    return InkWell(
      onTap: _edit,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: statusColor.withAlpha((0.4 * 255).round()),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.dns_outlined, size: 18, color: statusColor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Server: ${AppConfig.host}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$statusText  •  tap to change',
                    style: TextStyle(fontSize: 11.5, color: statusColor),
                  ),
                  if (notice != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      notice,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.3,
                        color: isDark ? Colors.orange.shade200 : Colors.red.shade700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              onPressed: _checking ? null : _check,
              icon: const Icon(Icons.refresh, size: 18),
              tooltip: 'Re-check',
            ),
          ],
        ),
      ),
    );
  }
}



