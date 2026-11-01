import 'package:flutter/material.dart';
import 'package:napstop/core/design/theme/nap_theme_context.dart';
import 'package:napstop/core/design/tokens/nap_metrics.dart';
import 'package:napstop/core/design/tokens/nap_motion.dart';

/// Radio circle, drawing only (spec T20 section 5.7). The row or card that
/// contains it carries the `checked` semantics.
final class NapRadioIndicator extends StatelessWidget {
  const new({required this.selected, super.key});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.napColors;
    return ExcludeSemantics(
      child: AnimatedContainer(
        duration: NapMotion.of(context, NapMotion.fast),
        curve: NapMotion.curve,
        width: NapSizes.radio,
        height: NapSizes.radio,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? c.accent : c.outline,
            width: selected ? 7 : 2,
          ),
        ),
      ),
    );
  }
}
