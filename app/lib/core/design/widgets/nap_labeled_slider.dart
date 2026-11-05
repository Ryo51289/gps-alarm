import 'package:flutter/material.dart';
import 'package:napstop/core/design/theme/nap_theme_context.dart';
import 'package:napstop/core/design/tokens/nap_metrics.dart';
import 'package:napstop/core/design/tokens/nap_typography.dart';

/// Material [Slider] with min/max captions (spec T20 section 5.19).
final class NapLabeledSlider extends StatelessWidget {
  const new({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.semanticLabel,
    required this.semanticFormatter,
    this.divisions,
    this.onChangeEnd,
    this.minLabel,
    this.maxLabel,
    super.key,
  });

  final double value;
  final double min;
  final double max;
  final int? divisions;

  /// Null disables the slider.
  final ValueChanged<double>? onChanged;

  /// Called once when the user lets go (T28: write on release only).
  final ValueChanged<double>? onChangeEnd;

  /// E.g. "Alarm distance".
  final String semanticLabel;

  /// Spoken value, e.g. "1.5 km".
  final String Function(double value) semanticFormatter;
  final String? minLabel;
  final String? maxLabel;

  @override
  Widget build(BuildContext context) {
    final captionStyle = context
        .napStyle(NapTypography.caption)
        .copyWith(color: context.napColors.textSecondary);
    final minLabel = this.minLabel;
    final maxLabel = this.maxLabel;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MergeSemantics(
          child: Semantics(
            label: semanticLabel,
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
              semanticFormatterCallback: semanticFormatter,
            ),
          ),
        ),
        if (minLabel != null || maxLabel != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: NapSpace.s8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(minLabel ?? '', style: captionStyle),
                Text(maxLabel ?? '', style: captionStyle),
              ],
            ),
          ),
      ],
    );
  }
}
