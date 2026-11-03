import 'package:flutter/material.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/features/onboarding/domain/onboarding_items.dart';
import 'package:napstop/features/onboarding/presentation/onboarding_strings.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// The short explanation before a system dialog or a special settings page
/// (PRD §3.1, T21 D13, §7.3). True when the user chose to go on.
Future<bool> showPermissionExplainer(
  BuildContext context,
  OnboardingExplainer explainer,
) async {
  final texts = AppLocalizations.of(context).explainer(explainer);
  if (texts == null) {
    return true;
  }
  final result = await showNapSheet<bool>(
    context: context,
    builder: (context) => _ExplainerSheet(texts: texts),
  );
  return result ?? false;
}

class _ExplainerSheet extends StatelessWidget {
  const new({required this.texts});

  final ExplainerTexts texts;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return NapSheetBody(
      leading: NapIconTile(
        icon: texts.icon,
        tone: NapTone.accent,
        size: NapSizes.iconTileLarge,
      ),
      title: texts.title,
      subtitle: texts.body,
      // "Để sau" under the primary button (NapSheetBody puts children above
      // it): it closes the sheet and does nothing.
      primaryAction: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: NapSpace.s8,
        children: [
          NapButton(
            label: texts.primary,
            onPressed: () => Navigator.of(context).pop(true),
          ),
          NapButton(
            label: l.commonLater,
            variant: NapButtonVariant.text,
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
      footnote: texts.hint,
      children: const [],
    );
  }
}
