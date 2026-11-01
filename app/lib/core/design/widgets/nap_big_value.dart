import 'package:flutter/material.dart';
import 'package:napstop/core/design/theme/nap_theme_context.dart';
import 'package:napstop/core/design/tokens/nap_metrics.dart';
import 'package:napstop/core/design/tokens/nap_typography.dart';

/// xl = displayLarge 52 (screens 4, 6); l = displayMedium 44 (screen 3).
enum NapBigValueSize { xl, l }

/// Large formatted value with small text before/after, e.g.
/// "152 km  ~2 h 10 min" (spec T20 section 5.18).
///
/// Text scaling is clamped at 1.3x: 52 px is already large. Not a live
/// region (the value changes every few seconds).
final class NapBigValue extends StatelessWidget {
  const new({
    required this.value,
    this.leading,
    this.trailing,
    this.size = NapBigValueSize.xl,
    this.estimated = false,
    this.alignment = WrapAlignment.start,
    super.key,
  });

  /// Maximum text scale of this widget.
  static const double maxTextScale = 1.3;

  /// Already formatted by the feature.
  final String value;
  final String? leading;
  final String? trailing;
  final NapBigValueSize size;

  /// Estimated value: shown in `textSecondary`.
  final bool estimated;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final c = context.napColors;
    final text = context.napText;
    final xl = size == NapBigValueSize.xl;
    final valueStyle = (xl ? text.displayLarge! : text.displayMedium!).copyWith(
      color: estimated ? c.textSecondary : c.textPrimary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final smallStyle =
        (xl ? context.napStyle(NapTypography.etaSecondary) : text.bodyMedium!)
            .copyWith(color: c.textSecondary);
    final leading = this.leading;
    final trailing = this.trailing;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: maxTextScale,
      child: MergeSemantics(
        child: Wrap(
          spacing: NapSpace.s8,
          alignment: alignment,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            if (leading != null) Text(leading, style: smallStyle),
            Text(value, style: valueStyle),
            if (trailing != null) Text(trailing, style: smallStyle),
          ],
        ),
      ),
    );
  }
}
