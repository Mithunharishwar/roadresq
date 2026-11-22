import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';

/// A lightweight, self-contained animated **Fireworks** overlay.
///
/// Paints a soft night-sky background and repeatedly launches colourful
/// firework bursts that streak upward, explode into radial trails, and
/// fade out — the same celebratory effect as the splash screen's "firework"
/// aesthetic, but reusable anywhere in the app.
///
/// Turn it off by passing [enabled: false] (e.g. in dark mode when you want
/// a solid background) or by setting [showBackground] false to keep just the
/// particles over the existing screen.
class Fireworks extends StatefulWidget {
  final bool enabled;
  final bool showBackground;
  final Color background;
  final Duration burstInterval;
  final int maxBursts;

  const Fireworks({
    super.key,
    this.enabled = true,
    this.showBackground = false,
    this.background = const Color(0xFF0B1026),
    this.burstInterval = const Duration(milliseconds: 900),
    this.maxBursts = 4,
  });

  @override
  State<Fireworks> createState() => _FireworksState();
}

class _FireworksState extends State<Fireworks>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final math.Random _rng = math.Random();
  final List<_Burst> _bursts = [];
  Duration _elapsed = Duration.zero;
  Duration _nextBurst = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    if (widget.enabled) _ticker.start();
  }

  @override
  void didUpdateWidget(Fireworks oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !_ticker.isActive) {
      _ticker.start();
    } else if (!widget.enabled && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    setState(() {
      _elapsed = elapsed;

      if (elapsed >= _nextBurst && _bursts.length < widget.maxBursts) {
        _bursts.add(_Burst(
          x: 0.15 + _rng.nextDouble() * 0.7,
          y: 0.18 + _rng.nextDouble() * 0.4,
          color: _pickColor(),
          particleCount: 26 + _rng.nextInt(18),
          speed: 0.5 + _rng.nextDouble() * 0.6,
          born: elapsed,
        ));
        _nextBurst = elapsed + widget.burstInterval;
      }

      _bursts
          .removeWhere((b) => (elapsed - b.born) > const Duration(seconds: 3));
    });
  }

  Color _pickColor() {
    const colors = [
      Color(0xFFFF5252),
      Color(0xFFFFB74D),
      Color(0xFFFFD54F),
      Color(0xFF69F0AE),
      Color(0xFF40C4FF),
      Color(0xFFB388FF),
      Color(0xFFFF80AB),
    ];
    return colors[_rng.nextInt(colors.length)];
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          if (widget.showBackground)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      widget.background,
                      widget.background,
                      const Color(0xFF1A1A3A),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
          if (widget.enabled)
            Positioned.fill(
              child: CustomPaint(
                painter: _FireworksPainter(_bursts, _elapsed),
              ),
            ),
        ],
      ),
    );
  }
}

class _Burst {
  final double x;
  final double y;
  final Color color;
  final int particleCount;
  final double speed;
  final Duration born;

  _Burst({
    required this.x,
    required this.y,
    required this.color,
    required this.particleCount,
    required this.speed,
    required this.born,
  });
}

class _FireworksPainter extends CustomPainter {
  final List<_Burst> bursts;
  final Duration elapsed;

  _FireworksPainter(this.bursts, this.elapsed);

  @override
  void paint(Canvas canvas, Size size) {
    if (bursts.isEmpty) return;

    for (final burst in bursts) {
      final ageMs = (elapsed - burst.born).inMilliseconds.toDouble();
      if (ageMs < 0 || ageMs > 3000) continue;

      final progress = ageMs / 3000;
      final opacity = (1 - progress).clamp(0.0, 1.0);
      final cx = burst.x * size.width;
      final cy = burst.y * size.height;

      // Explosion radius grows over time.
      final radius = (progress * 130 * burst.speed).clamp(4.0, 220.0);

      final paint = Paint()
        ..color = burst.color.withAlpha((opacity * 255).round());

      for (var i = 0; i < burst.particleCount; i++) {
        final angle = (i / burst.particleCount) * 2 * math.pi;
        final dist = radius * (0.6 + 0.4 * math.sin(i * 12.9898));
        final px = cx + math.cos(angle) * dist;
        final py = cy + math.sin(angle) * dist;

        // Particle trail length grows with age.
        final trail = 4.0 + progress * 16;
        final tailX = cx + math.cos(angle) * (dist - trail);
        final tailY = cy + math.sin(angle) * (dist - trail);

        canvas.drawLine(
          Offset(px, py),
          Offset(tailX, tailY),
          paint..strokeWidth = 2.0,
        );
        canvas.drawCircle(
          Offset(px, py),
          1.6,
          paint,
        );
      }

      // Bright core flash that quickly fades.
      canvas.drawCircle(
        Offset(cx, cy),
        3.0 + (1 - progress) * 6,
        paint..color = Colors.white.withAlpha((opacity * 200).round()),
      );
    }
  }

  @override
  bool shouldRepaint(_FireworksPainter oldDelegate) => true;
}
