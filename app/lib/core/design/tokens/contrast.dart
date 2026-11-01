import 'package:flutter/painting.dart';
import 'package:napstop/core/design/theme/nap_theme_kind.dart';
import 'package:napstop/core/design/tokens/nap_colors.dart';

/// Minimum contrast of text (NapStop uses it for large text too).
const double kMinTextContrast = 4.5;

/// Minimum contrast of non-text state indicators (WCAG 1.4.11).
const double kMinNonTextContrast = 3;

/// WCAG 2.x contrast ratio between [a] and [b], from 1.0 to 21.0. Symmetric;
/// alpha is ignored (uses [Color.computeLuminance]).
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// A foreground/background pair that must reach [minRatio].
final class NapContrastPair {
  const new(this.name, this.foreground, this.background, this.minRatio);

  /// `foreground / background` token names.
  final String name;
  final Color foreground;
  final Color background;
  final double minRatio;

  /// True for text pairs (4.5), false for non-text pairs (3.0).
  bool get isText => minRatio >= kMinTextContrast;

  double get ratio => contrastRatio(foreground, background);

  bool get passes => ratio >= minRatio;
}

/// Pairs to check for [kind] (spec T20 section 2.1, plus pairs used by
/// the components).
List<NapContrastPair> napContrastPairs(NapColors c, NapThemeKind kind) {
  final t = c.tokens;
  final pairs = <NapContrastPair>[];
  void text(String fg, String bg) =>
      pairs.add(NapContrastPair('$fg / $bg', t[fg]!, t[bg]!, kMinTextContrast));
  void nonText(String fg, String bg) => pairs.add(
    NapContrastPair('$fg / $bg', t[fg]!, t[bg]!, kMinNonTextContrast),
  );
  final isAlarm = kind == NapThemeKind.alarm;

  for (final bg in ['background', 'surface', 'fill']) {
    text('textPrimary', bg);
  }
  for (final bg in [
    'background',
    'surface',
    'fill',
    'backgroundGrouped',
    'accentContainer',
  ]) {
    text('textSecondary', bg);
  }
  for (final bg in ['surfaceFloating', 'segmentThumb', 'accentContainer']) {
    text('textPrimary', bg);
  }
  text('textSecondary', 'surfaceFloating');
  text('onAccentContainer', 'accentContainer');
  if (!isAlarm) {
    for (final bg in [
      'warningContainer',
      'successContainer',
      'dangerContainer',
    ]) {
      text('textSecondary', bg);
    }
    for (final bg in ['background', 'surface', 'fill', 'accentContainer']) {
      text('accent', bg);
    }
  }
  text('onAccent', 'accent');
  text('onInverseSurface', 'inverseSurface');
  for (final bg in ['background', 'successContainer', 'fill']) {
    text('success', bg);
  }
  text('onSuccess', 'success');
  text('danger', 'background');
  if (!isAlarm) {
    text('warning', 'warningContainer');
    text('warning', 'background');
    text('warning', 'surface');
    text('warning', 'surfaceFloating');
    text('danger', 'dangerContainer');
    text('onDanger', 'danger');
  }
  if (isAlarm) {
    text('alarmAccent', 'background');
    text('onAlarmAccent', 'alarmAccent');
    text('overshootLabel', 'background');
    text('onAlarmAccent', 'overshootAccent');
  }

  for (final bg in ['surface', 'fill', 'backgroundGrouped', 'background']) {
    nonText('outline', bg);
  }
  nonText('onAccent', 'accent');
  nonText('accent', 'surface');
  if (!isAlarm) {
    nonText('warningIndicator', 'surfaceFloating');
  }
  return pairs;
}
