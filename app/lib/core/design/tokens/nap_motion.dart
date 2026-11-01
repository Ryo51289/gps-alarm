import 'package:flutter/widgets.dart';

/// Animation tokens (spec T20 section 3.3).
abstract final class NapMotion {
  /// Segmented thumb, chip color change.
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration standard = Duration(milliseconds: 250);
  static const Curve curve = Curves.easeOutCubic;

  /// [Duration.zero] when the user asked for reduced motion
  /// (`MediaQuery.disableAnimationsOf`), otherwise [d].
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false ? Duration.zero : d;
}
