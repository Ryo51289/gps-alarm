import 'package:flutter/material.dart';

/// Pulsing disc of the alarm screens (T27 §7, §8): [color] fading between
/// full and 35 % every 1.2 s, like the native screen; static when the user
/// asked for reduced motion. Decorative (no semantics).
final class AlarmGlow extends StatefulWidget {
  const new({
    required this.color,
    this.icon,
    this.iconColor,
    this.pulse = true,
    this.size = 96,
    super.key,
  });

  final Color color;
  final IconData? icon;
  final Color? iconColor;

  /// Screen 8 after the alarm was dismissed: no pulse.
  final bool pulse;
  final double size;

  @override
  State<AlarmGlow> createState() => _AlarmGlowState();
}

class _AlarmGlowState extends State<AlarmGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate =
        widget.pulse &&
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (animate && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!animate && _controller.isAnimating) {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icon = widget.icon;
    return ExcludeSemantics(
      child: FadeTransition(
        opacity: Tween<double>(begin: 1, end: 0.35).animate(_controller),
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
          ),
          child: icon == null
              ? null
              : Icon(icon, color: widget.iconColor, size: widget.size / 2),
        ),
      ),
    );
  }
}
