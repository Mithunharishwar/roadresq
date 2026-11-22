import 'dart:async';
import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';
import '../core/router/app_router.dart';
import '../core/session/app_session.dart';

/// SplashScreen — Professional 3D cover intro for RoadResQ.
///
/// A cinematic entry visualisation: a 3D perspective-tilted emblem that
/// continuously rotates and pulses, floating particles, a glowing "road"
/// sweep, animated brand reveal, and a skip button. Auto-navigates to the
/// role-selection screen after ~3.2s.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _mainController;
  late AnimationController _pulseController;
  late AnimationController _rotateController;

  late Animation<double> scaleAnim;
  late Animation<double> fadeAnim;
  late Animation<Offset> slideAnim;
  late Animation<double> pulseAnim;
  late Animation<double> roadAnim;

  Timer? _navTimer;
  final List<_Particle> _particles = [];

  @override
  void initState() {
    super.initState();
    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );
    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    );

    scaleAnim = Tween<double>(begin: 0.7, end: 1).animate(
      CurvedAnimation(parent: _mainController, curve: Curves.easeOutBack),
    );
    fadeAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _mainController, curve: Curves.easeIn));
    slideAnim = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _mainController, curve: Curves.easeOutCubic));
    pulseAnim = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    roadAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _mainController, curve: Curves.easeInOut),
    );

    _mainController.forward();
    _pulseController.repeat(reverse: true);
    _rotateController.repeat();

    // Seed floating particles.
    final rng = math.Random(7);
    for (var i = 0; i < 26; i++) {
      _particles.add(_Particle(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        size: 2 + rng.nextDouble() * 4,
        speed: 0.004 + rng.nextDouble() * 0.01,
        opacity: 0.25 + rng.nextDouble() * 0.5,
      ));
    }

    _navTimer = Timer(const Duration(milliseconds: 3400), () => _goNext());
  }

  /// §1 / §6 — decide where the user actually belongs.
  ///
  /// Before this the splash always pushed the role selector, so a signed-in
  /// user was asked to log in again on every cold start. Order matters:
  /// onboarding first (a first-run user has no session), then the saved
  /// dashboard, then role selection.
  Future<void> _goNext() async {
    if (!mounted) return;

    var onboarded = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      onboarded = prefs.getBool(AppConstants.keyOnboarded) ?? false;
    } catch (_) {
      // Treat unreadable prefs as "not onboarded" is worse than skipping it:
      // a returning user would see the intro again. Only a failed read on a
      // first run lands here, and the Skip button covers it.
      onboarded = true;
    }

    if (!mounted) return;

    if (!onboarded) {
      context.go(AppRoutes.onboarding);
      return;
    }

    if (AppSession.isSignedIn) {
      debugPrint('[splash] resuming ${AppSession.role} session');
      context.go(AppSession.homeRoute);
      return;
    }

    context.go(AppRoutes.roleSelect);
  }

  @override
  void dispose() {
    _navTimer?.cancel();
    _mainController.dispose();
    _pulseController.dispose();
    _rotateController.dispose();
    super.dispose();
  }

  Widget _featureChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha((0.14 * 255).round()),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withAlpha((0.12 * 255).round())),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// 3D rotating, perspective-tilted logo emblem.
  Widget _build3DEmblem() {
    return AnimatedBuilder(
      animation: _rotateController,
      builder: (context, _) {
        final angle = _rotateController.value * 2 * math.pi;
        // Perspective transform + slight oscillating tilt.
        final transform = Matrix4.identity()
          ..setEntry(3, 2, 0.0022)
          ..rotateY(math.sin(angle) * 0.35)
          ..rotateX(math.cos(angle * 0.5) * 0.12);
        return Transform(
          alignment: Alignment.center,
          transform: transform,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // outer glow ring
              Container(
                width: 168,
                height: 168,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withAlpha((0.28 * 255).round()),
                      Colors.white.withAlpha((0 * 255).round()),
                    ],
                  ),
                ),
              ),
              // pulsing ring
              ScaleTransition(
                scale: pulseAnim,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withAlpha((0.35 * 255).round()),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              // core emblem
              ScaleTransition(
                scale: scaleAnim,
                child: Container(
                  height: 118,
                  width: 118,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withAlpha((0.35 * 255).round()),
                        blurRadius: 38,
                        offset: const Offset(0, 6),
                      ),
                      BoxShadow(
                        color: Colors.black.withAlpha((0.12 * 255).round()),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.car_repair,
                    size: 58,
                    color: Color(0xFFD32F2F),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Animated glowing "road" sweep line under the emblem.
  Widget _buildRoadSweep() {
    return AnimatedBuilder(
      animation: roadAnim,
      builder: (context, _) {
        final t = roadAnim.value;
        return Container(
          height: 5,
          constraints: const BoxConstraints(maxWidth: 190),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white.withAlpha((0.18 * 255).round()),
          ),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: math.max(0.05, t),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  colors: [Colors.white, Color(0xFFFFC107)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0xFFFFC107).withAlpha((0.6 * 255).round()),
                    blurRadius: 12,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFB71C1C), Color(0xFFD32F2F), Color(0xFFFF7043)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            // glowing accent blobs
            Positioned(
              top: -70,
              right: -50,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha((0.08 * 255).round()),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              bottom: -90,
              left: -40,
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  color: Colors.amber.withAlpha((0.10 * 255).round()),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            // floating particles
            ..._particles.map((p) => AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, _) {
                    final driftY =
                        (p.y - (_pulseController.value * p.speed * 40)) % 1.0;
                    return Positioned(
                      left: p.x * MediaQuery.of(context).size.width,
                      top: driftY * MediaQuery.of(context).size.height,
                      child: Container(
                        width: p.size,
                        height: p.size,
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(
                            (p.opacity * 255).round(),
                          ),
                          shape: BoxShape.circle,
                        ),
                      ),
                    );
                  },
                )),
            SafeArea(
              child: FadeTransition(
                opacity: fadeAnim,
                child: SlideTransition(
                  position: slideAnim,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _build3DEmblem(),
                          const SizedBox(height: 40),
                          _buildRoadSweep(),
                          const SizedBox(height: 22),
                          const Text(
                            'RoadResQ',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 38,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                              shadows: [
                                Shadow(
                                  color: Colors.black26,
                                  blurRadius: 12,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Real-time roadside rescue with live tracking,\nverified mechanics & instant support',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 15,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 28),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _featureChip(
                                Icons.location_on_outlined,
                                'Live location',
                              ),
                              _featureChip(
                                Icons.verified_user_outlined,
                                'Verified support',
                              ),
                              _featureChip(
                                Icons.route_outlined,
                                'Fast response',
                              ),
                            ],
                          ),
                          const SizedBox(height: 36),
                          Column(
                            children: [
                              SizedBox(
                                width: 34,
                                child: LinearProgressIndicator(
                                  minHeight: 4,
                                  borderRadius: BorderRadius.circular(20),
                                  backgroundColor: Colors.white24,
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Launching your rescue network...',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Skip button
            Positioned(
              bottom: 18,
              right: 18,
              child: TextButton.icon(
                onPressed: _goNext,
                icon: const Icon(Icons.arrow_forward, color: Colors.white70),
                label: const Text(
                  'Skip Intro',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single floating particle descriptor.
class _Particle {
  final double x;
  final double y;
  final double size;
  final double speed;
  final double opacity;

  _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.opacity,
  });
}
