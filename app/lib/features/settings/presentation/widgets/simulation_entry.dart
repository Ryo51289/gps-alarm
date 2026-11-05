import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:napstop/core/design/design.dart';

/// Logo + version at the end of screen 12 (T28 §4.2 block 7). Holding it for
/// [holdDuration] calls [onLongPress]: the hidden entry of the simulation
/// mode (D13). No semantics action on purpose (demo tool, §8 a11y). A finger
/// that moves (scrolling) loses the gesture arena, so scrolling still works.
class SimulationEntry extends StatelessWidget {
  const new({
    required this.appName,
    required this.version,
    required this.holdDuration,
    required this.onLongPress,
    super.key,
  });

  final String appName;

  /// "phiên bản 0.1.0 (1)"; null hides the line.
  final String? version;
  final Duration holdDuration;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = context.napColors;
    final version = this.version;
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
              () => LongPressGestureRecognizer(duration: holdDuration),
              (r) => r.onLongPress = onLongPress,
            ),
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: NapSpace.s24),
        child: Column(
          spacing: NapSpace.s4,
          children: [
            Icon(NapIcons.sleep, size: NapSizes.iconXLarge, color: c.accent),
            Text(appName, style: context.napText.titleSmall),
            if (version != null)
              Text(
                version,
                style: context.napText.bodySmall!.copyWith(
                  color: c.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
