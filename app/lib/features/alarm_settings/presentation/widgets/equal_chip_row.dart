import 'package:flutter/material.dart';
import 'package:napstop/core/design/design.dart';

/// The style a `Text` inside a `NapChip` really lays out with: [base] plus
/// what `Text.build` adds on its own (flutter/widgets/text.dart): system bold
/// text merges `FontWeight.bold`; MediaQuery letter/word spacing and line
/// height overrides replace the style values. Measuring with [base] alone
/// could call a label "fits" that then renders wider (T25.1 review #1).
TextStyle chipLabelStyle(
  TextStyle base, {
  required bool boldText,
  double? letterSpacing,
  double? wordSpacing,
  double? lineHeightScaleFactor,
}) {
  var style = base;
  if (boldText) {
    style = style.merge(const TextStyle(fontWeight: FontWeight.bold));
  }
  if (letterSpacing != null ||
      wordSpacing != null ||
      lineHeightScaleFactor != null) {
    style = style.merge(
      TextStyle(
        letterSpacing: letterSpacing,
        wordSpacing: wordSpacing,
        height: lineHeightScaleFactor,
      ),
    );
  }
  return style;
}

/// A row of chips with equal widths, as in the wireframe. When a label would
/// not fit its share without breaking a word (large text scale or narrow
/// screen), the chips take their natural widths and wrap onto more lines, so
/// a label is never cut (T25.1, test report T25 #2: "500 m" became
/// "50 / 0 ..." at font scale 2.0).
class EqualChipRow extends StatelessWidget {
  const new({required this.labels, required this.chipBuilder, super.key});

  /// Visible label of each chip, as passed to its `NapChip`.
  final List<String> labels;
  final Widget Function(int index) chipBuilder;

  static const double _gap = NapSpace.s8;

  /// Horizontal padding of a regular `NapChip` (both sides).
  static const double _chipChrome = NapSpace.s16 * 2;

  /// `NapChip` shows at most 2 lines.
  static const int _maxLines = 2;

  /// Whether [label] fits [width] in at most 2 lines without a broken word.
  static bool _fits(
    String label,
    double width,
    TextStyle style,
    TextScaler scaler,
    TextDirection direction,
  ) {
    TextPainter painter(String text, {int? maxLines}) => TextPainter(
      text: TextSpan(text: text, style: style),
      textScaler: scaler,
      textDirection: direction,
      maxLines: maxLines,
    );
    for (final word in label.split(' ')) {
      final p = painter(word)..layout();
      final wide = p.width > width;
      p.dispose();
      if (wide) {
        return false;
      }
    }
    final p = painter(label, maxLines: _maxLines)..layout(maxWidth: width);
    final exceeded = p.didExceedMaxLines;
    p.dispose();
    return !exceeded;
  }

  @override
  Widget build(BuildContext context) {
    final style = chipLabelStyle(
      context.napText.labelMedium!,
      boldText: MediaQuery.boldTextOf(context),
      letterSpacing: MediaQuery.maybeLetterSpacingOverrideOf(context),
      wordSpacing: MediaQuery.maybeWordSpacingOverrideOf(context),
      lineHeightScaleFactor: MediaQuery.maybeLineHeightScaleFactorOverrideOf(
        context,
      ),
    );
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final n = labels.length;
        // Floored so rounding never pushes the last chip to a new line.
        final share = ((constraints.maxWidth - _gap * (n - 1)) / n)
            .floorToDouble();
        final equal = labels.every(
          (l) => _fits(l, share - _chipChrome, style, scaler, direction),
        );
        if (equal) {
          return Row(
            spacing: _gap,
            children: [
              for (var i = 0; i < n; i++) Expanded(child: chipBuilder(i)),
            ],
          );
        }
        return Wrap(
          spacing: _gap,
          runSpacing: _gap,
          alignment: WrapAlignment.center,
          children: [
            for (var i = 0; i < n; i++)
              ConstrainedBox(
                constraints: BoxConstraints(minWidth: share),
                child: chipBuilder(i),
              ),
          ],
        );
      },
    );
  }
}
