import 'package:flutter/material.dart';
import 'package:napstop/core/design/theme/nap_theme_context.dart';
import 'package:napstop/core/design/tokens/nap_metrics.dart';
import 'package:napstop/core/design/tokens/nap_typography.dart';

/// Modal bottom sheet styled by the theme (spec T20 section 5.17): top
/// radius 24, 40x4 drag handle, 55% scrim. It avoids the status bar and side
/// cutouts but, like every Material bottom sheet, extends under the bottom
/// system bar: [NapSheetBody] pads its content above it.
Future<T?> showNapSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool enableDrag = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    builder: builder,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
  );
}

/// Content layout of a sheet (screen 7): header, children, primary action,
/// footnote. Scrolls when the content is too tall. The bottom padding
/// includes the bottom system bar (`MediaQuery.viewPaddingOf`), which covers
/// the sheet on Android 15+ edge-to-edge with 3-button navigation.
final class NapSheetBody extends StatelessWidget {
  const new({
    required this.title,
    required this.children,
    this.subtitle,
    this.leading,
    this.primaryAction,
    this.footnote,
    super.key,
  });

  final String title;
  final String? subtitle;

  /// Usually a NapIconTile of size 56.
  final Widget? leading;
  final List<Widget> children;

  /// Usually a large NapButton.
  final Widget? primaryAction;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final c = context.napColors;
    final text = context.napText;
    final subtitle = this.subtitle;
    final footnote = this.footnote;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        NapSpace.page,
        0,
        NapSpace.page,
        NapSpace.s28 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: NapSpace.s18,
        children: [
          Row(
            spacing: NapSpace.s14,
            children: [
              ?leading,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: NapSpace.s2,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(title, style: text.titleLarge),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: context
                            .napStyle(NapTypography.body14)
                            .copyWith(color: c.textSecondary),
                      ),
                  ],
                ),
              ),
            ],
          ),
          ...children,
          ?primaryAction,
          if (footnote != null)
            Text(
              footnote,
              textAlign: TextAlign.center,
              style: text.bodySmall!.copyWith(color: c.textSecondary),
            ),
        ],
      ),
    );
  }
}

/// Non-modal sheet frame resting on the map (screen 2 panel): top radius 20,
/// `surface`, sheet shadow (a top border on dark themes), drawn handle.
/// Drag behavior belongs to the screen (T23).
final class NapSheetContainer extends StatelessWidget {
  const new({required this.child, this.showHandle = true, super.key});

  final Widget child;
  final bool showHandle;

  @override
  Widget build(BuildContext context) {
    final c = context.napColors;
    final shadows = context.napShadows;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(NapRadii.r20),
        ),
        boxShadow: shadows.sheet,
        border: shadows.borderInsteadOfShadow
            ? Border(top: BorderSide(color: c.border))
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHandle)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: NapSpace.s12),
              child: Center(
                child: Container(
                  width: NapSizes.sheetHandle.width,
                  height: NapSizes.sheetHandle.height,
                  decoration: BoxDecoration(
                    color: c.border,
                    borderRadius: BorderRadius.circular(NapRadii.pill),
                  ),
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}
