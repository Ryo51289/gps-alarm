import 'package:flutter/material.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/features/tracking/domain/tracking_view.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Bottom buttons of screen 4 (T26 §4.7). A null callback disables its
/// button (a call is in flight).
class TrackingActions extends StatelessWidget {
  const new({
    required this.view,
    required this.previewing,
    required this.onPreview,
    required this.onDismiss,
    required this.onStop,
    super.key,
  });

  final TrackingView view;
  final bool previewing;
  final VoidCallback? onPreview;
  final VoidCallback? onDismiss;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: NapSpace.s10,
      children: [
        if (view.canPreview)
          NapButton(
            label: previewing ? l.trackingPreviewStop : l.trackingPreview,
            onPressed: onPreview,
            variant: NapButtonVariant.tonal,
            size: NapButtonSize.medium,
            icon: NapIcons.play,
          ),
        if (view.canDismiss)
          NapButton(label: l.trackingDismiss, onPressed: onDismiss),
        if (view.canStop)
          NapButton(
            label: l.trackingStop,
            onPressed: onStop,
            variant: NapButtonVariant.danger,
          ),
      ],
    );
  }
}
