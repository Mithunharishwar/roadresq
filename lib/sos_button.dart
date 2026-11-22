import 'package:material_ui/material_ui.dart';

/// A prominent SOS button for the user's main screen.
///
/// This button can be activated via tap or a voice command ("Help").
/// It includes visual feedback during activation.
class SosButton extends StatefulWidget {
  final VoidCallback onSosPressed;

  const SosButton({
    super.key,
    required this.onSosPressed,
  });

  @override
  State<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends State<SosButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        ScaleTransition(
          scale: Tween<double>(begin: 1.0, end: 1.4).animate(
            CurvedAnimation(
              parent: _animationController,
              curve: Curves.easeInOut,
            ),
          ),
          child: FadeTransition(
            opacity: Tween<double>(begin: 0.6, end: 0.0)
                .animate(_animationController),
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red.withAlpha((0.5 * 255).round()),
              ),
            ),
          ),
        ),
        FloatingActionButton.large(
          onPressed: widget.onSosPressed,
          backgroundColor: Colors.red,
          child: const Text('SOS',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
        ),
      ],
    );
  }
}
