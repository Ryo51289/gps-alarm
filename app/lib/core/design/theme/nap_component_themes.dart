import 'package:flutter/material.dart';
import 'package:napstop/core/design/tokens/nap_colors.dart';
import 'package:napstop/core/design/tokens/nap_metrics.dart';
import 'package:napstop/core/design/tokens/nap_typography.dart';
import 'package:napstop/core/design/widgets/nap_button.dart';

/// Component themes of the Material widgets the design system uses
/// (spec T20 section 4.2). The `textTheme` argument already carries the
/// font family and colors.
abstract final class NapComponentThemes {
  /// Geometry and text of a large NapButton, without colors.
  ///
  /// `FilledButton` and `FilledButton.tonal` read the same theme, and a theme
  /// color would override the tonal default. Colors therefore come from the
  /// color scheme: primary/onPrimary (accent/onAccent) for `FilledButton`,
  /// secondaryContainer/onSecondaryContainer (fill/textPrimary) for the tonal
  /// one, the same pairs as NapButton primary and tonal.
  static FilledButtonThemeData filledButton(NapColors c, TextTheme t) {
    final s = napButtonStyle(
      variant: NapButtonVariant.primary,
      size: NapButtonSize.large,
      colors: c,
      textTheme: t,
    );
    return FilledButtonThemeData(
      style: ButtonStyle(
        textStyle: s.textStyle,
        shadowColor: s.shadowColor,
        surfaceTintColor: s.surfaceTintColor,
        elevation: s.elevation,
        side: s.side,
        padding: s.padding,
        minimumSize: s.minimumSize,
        iconSize: s.iconSize,
        shape: s.shape,
        tapTargetSize: s.tapTargetSize,
        visualDensity: s.visualDensity,
        alignment: s.alignment,
      ),
    );
  }

  static OutlinedButtonThemeData outlinedButton(NapColors c, TextTheme t) =>
      OutlinedButtonThemeData(
        style: napButtonStyle(
          variant: NapButtonVariant.secondary,
          size: NapButtonSize.medium,
          colors: c,
          textTheme: t,
        ),
      );

  static TextButtonThemeData textButton(NapColors c, TextTheme t) =>
      TextButtonThemeData(
        style: napButtonStyle(
          variant: NapButtonVariant.text,
          size: NapButtonSize.medium,
          colors: c,
          textTheme: t,
        ),
      );

  static IconButtonThemeData iconButton(NapColors c) => IconButtonThemeData(
    style: IconButton.styleFrom(
      minimumSize: const Size.square(NapSizes.iconButton),
      tapTargetSize: MaterialTapTargetSize.padded,
      foregroundColor: c.textPrimary,
    ),
  );

  static SwitchThemeData switchTheme(NapColors c, Brightness brightness) {
    bool selected(Set<WidgetState> s) => s.contains(WidgetState.selected);
    bool disabled(Set<WidgetState> s) => s.contains(WidgetState.disabled);
    final offTrack = brightness == Brightness.light ? c.surface : c.fill;
    return SwitchThemeData(
      // Null for disabled states: Material 3 defaults apply.
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => disabled(s) ? null : (selected(s) ? c.onAccent : c.outline),
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => disabled(s) ? null : (selected(s) ? c.accent : offTrack),
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) =>
            selected(s) ? Colors.transparent : (disabled(s) ? null : c.outline),
      ),
      trackOutlineWidth: const WidgetStatePropertyAll(2),
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }

  static SliderThemeData slider(NapColors c) => SliderThemeData(
    activeTrackColor: c.accent,
    inactiveTrackColor: c.track,
    thumbColor: c.accent,
    overlayColor: c.accent.withValues(alpha: 0.12),
    trackHeight: 4,
    showValueIndicator: ShowValueIndicator.never,
  );

  static BottomSheetThemeData bottomSheet(NapColors c) => BottomSheetThemeData(
    backgroundColor: c.surface,
    modalBackgroundColor: c.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    modalElevation: 0,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(NapRadii.r24)),
    ),
    showDragHandle: true,
    dragHandleColor: c.border,
    dragHandleSize: NapSizes.sheetHandle,
    modalBarrierColor: c.scrim.withValues(alpha: NapColors.scrimOpacity),
  );

  static DividerThemeData divider(NapColors c) =>
      DividerThemeData(color: c.divider, thickness: 1, space: 1);

  static NavigationBarThemeData navigationBar(NapColors c, String fontFamily) {
    bool selected(Set<WidgetState> s) => s.contains(WidgetState.selected);
    final selectedLabel = NapTypography.captionStrong.copyWith(
      fontFamily: fontFamily,
      color: c.accent,
    );
    final label = NapTypography.caption.copyWith(
      fontFamily: fontFamily,
      color: c.textSecondary,
    );
    return NavigationBarThemeData(
      backgroundColor: c.background,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      height: 64,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          size: NapSizes.iconLarge,
          color: selected(s) ? c.accent : c.textSecondary,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => selected(s) ? selectedLabel : label,
      ),
    );
  }

  static TextSelectionThemeData textSelection(NapColors c) =>
      TextSelectionThemeData(
        cursorColor: c.accent,
        selectionColor: c.accent.withValues(alpha: 0.24),
        selectionHandleColor: c.accent,
      );

  static ProgressIndicatorThemeData progressIndicator(NapColors c) =>
      ProgressIndicatorThemeData(color: c.accent, linearTrackColor: c.track);

  static DialogThemeData dialog(NapColors c) => DialogThemeData(
    backgroundColor: c.surface,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(NapRadii.r20),
    ),
  );

  static SnackBarThemeData snackBar(NapColors c, TextTheme t) =>
      SnackBarThemeData(
        backgroundColor: c.inverseSurface,
        contentTextStyle: t.bodyMedium!.copyWith(color: c.onInverseSurface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NapRadii.r12),
        ),
      );
}
