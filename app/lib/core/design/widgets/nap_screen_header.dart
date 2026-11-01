import 'package:flutter/material.dart';
import 'package:napstop/core/design/nap_icons.dart';
import 'package:napstop/core/design/theme/nap_theme_context.dart';
import 'package:napstop/core/design/tokens/nap_metrics.dart';
import 'package:napstop/core/design/widgets/nap_icon_button.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Screen title row with an optional back button (spec T20 section 5.14).
/// Replaces `AppBar`.
final class NapScreenHeader extends StatelessWidget {
  const new({required this.title, this.onBack, this.trailing, super.key});

  final String title;

  /// Shows the back button when non-null.
  final VoidCallback? onBack;
  final Widget? trailing;

  /// The back button is shifted so its icon lines up with the page margin.
  static const double _backShift = 10;

  @override
  Widget build(BuildContext context) {
    final onBack = this.onBack;
    final titleText = Semantics(
      header: true,
      child: Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: context.napText.titleLarge,
      ),
    );
    final Widget lead;
    if (onBack == null) {
      lead = titleText;
    } else {
      final rtl = Directionality.of(context) == TextDirection.rtl;
      lead = Transform.translate(
        offset: Offset(rtl ? _backShift : -_backShift, 0),
        child: Row(
          children: [
            NapIconButton(
              icon: NapIcons.back,
              semanticLabel: AppLocalizations.of(context).commonBack,
              onPressed: onBack,
              variant: NapIconButtonVariant.plain,
            ),
            const SizedBox(width: NapSpace.s8),
            Expanded(child: titleText),
          ],
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: NapSizes.minTouch),
      child: Row(
        children: [
          Expanded(child: lead),
          ?trailing,
        ],
      ),
    );
  }
}
