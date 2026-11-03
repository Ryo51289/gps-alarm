import 'package:flutter/material.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/features/alarm_settings/presentation/alarm_settings_strings.dart';
import 'package:napstop/features/onboarding/domain/start_check.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Missing permissions after "Bắt đầu theo dõi" (T25 §3.4). Resolves to
/// true when the user chose "Cấp quyền".
Future<bool> showStartBlockedSheet(
  BuildContext context,
  List<StartRequirement> missing,
) async {
  final grant = await showNapSheet<bool>(
    context: context,
    builder: (context) => StartBlockedSheet(missing: missing),
  );
  return grant ?? false;
}

class StartBlockedSheet extends StatelessWidget {
  const new({required this.missing, super.key});

  final List<StartRequirement> missing;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return NapSheetBody(
      leading: const NapIconTile(
        icon: NapIcons.warning,
        tone: NapTone.danger,
        size: NapSizes.iconTileLarge,
      ),
      title: l.alarmSettingsBlockedTitle,
      subtitle: l.alarmSettingsBlockedSubtitle,
      primaryAction: NapButton(
        label: l.alarmSettingsBlockedAction,
        onPressed: () => Navigator.of(context).pop(true),
      ),
      children: [
        for (final r in missing)
          NapListRow(
            title: l.requirementLabel(r),
            leading: const NapIconTile(
              icon: NapIcons.error,
              tone: NapTone.danger,
            ),
          ),
      ],
    );
  }
}
