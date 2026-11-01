import 'package:flutter/painting.dart';

/// Spacing scale (spec T20 section 3.3).
abstract final class NapSpace {
  static const double s2 = 2;
  static const double s4 = 4;
  static const double s6 = 6;
  static const double s8 = 8;
  static const double s10 = 10;
  static const double s12 = 12;
  static const double s14 = 14;
  static const double s16 = 16;
  static const double s18 = 18;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s28 = 28;
  static const double s32 = 32;
  static const double s40 = 40;

  /// Horizontal screen margin.
  static const double page = 20;

  /// Horizontal margin of the alarm screens (5, 8).
  static const double alarmPage = 24;

  /// Gap between blocks on a screen.
  static const double section = 20;
}

/// Corner radii.
abstract final class NapRadii {
  static const double r4 = 4;
  static const double r6 = 6;
  static const double r8 = 8;
  static const double r10 = 10;
  static const double r12 = 12;
  static const double r14 = 14;
  static const double r16 = 16;
  static const double r20 = 20;
  static const double r24 = 24;

  /// Fully rounded ends.
  static const double pill = 999;
}

/// Sizes. Control heights are minimums (they grow with the text scale).
abstract final class NapSizes {
  /// Minimum touch target of every control (androidTapTargetGuideline).
  static const double minTouch = 48;

  static const double buttonLarge = 56;
  static const double buttonMedium = 52;
  static const double buttonSmall = 44;
  static const double buttonCompact = 36;

  static const double iconButton = 44;
  static const double chip = 44;
  static const double chipCompact = 40;

  static const double segmentItem = 44;
  static const double segmentItemCompact = 40;
  static const double segmentPadding = 4;

  static const double iconTile = 40;
  static const double iconTileLarge = 56;

  static const double listRowMin = 56;
  static const double listRowWithSubtitleMin = 64;
  static const double switchRowMin = 60;

  static const double radio = 22;
  static const double statusDot = 8;
  static const Size sheetHandle = Size(40, 4);

  static const double icon = 20;
  static const double iconLarge = 22;
  static const double iconXLarge = 24;
  static const double iconSmall = 18;
}
