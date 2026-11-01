import 'package:flutter/painting.dart';
import 'package:napstop/core/design/tokens/nap_colors.dart';

/// Semantic tone shared by badges, banners, status tiles and icon tiles.
enum NapTone { neutral, accent, success, warning, danger }

/// Foreground (text, icon) and container colors of a [NapTone].
extension NapToneColors on NapTone {
  /// Text/icon color on [containerOf]. Neutral uses `textPrimary`.
  Color foregroundOf(NapColors c) => switch (this) {
    NapTone.neutral => c.textPrimary,
    NapTone.accent => c.accent,
    NapTone.success => c.success,
    NapTone.warning => c.warning,
    NapTone.danger => c.danger,
  };

  /// Container (background) color. Neutral uses `fill`.
  Color containerOf(NapColors c) => switch (this) {
    NapTone.neutral => c.fill,
    NapTone.accent => c.accentContainer,
    NapTone.success => c.successContainer,
    NapTone.warning => c.warningContainer,
    NapTone.danger => c.dangerContainer,
  };
}
