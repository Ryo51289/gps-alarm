import 'package:flutter/material.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/features/alarm_settings/presentation/alarm_settings_strings.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// "Cách tắt báo": three pill chips and the snooze line (T25 §3.2).
class DismissMethodPicker extends StatelessWidget {
  const new({
    required this.selected,
    required this.snoozeNote,
    required this.onChanged,
    super.key,
  });

  final DismissMethodMsg selected;
  final String snoozeNote;
  final ValueChanged<DismissMethodMsg> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NapSectionHeader(l.alarmSettingsDismissHeader),
        const SizedBox(height: NapSpace.s10),
        Wrap(
          spacing: NapSpace.s8,
          runSpacing: NapSpace.s8,
          children: [
            for (final method in DismissMethodMsg.values)
              NapChip(
                label: l.dismissLabel(method),
                style: NapChipStyle.choicePill,
                selected: method == selected,
                onTap: () => onChanged(method),
              ),
          ],
        ),
        const SizedBox(height: NapSpace.s8),
        SnoozeNoteText(snoozeNote),
      ],
    );
  }
}

/// The snooze line ("Báo lại tối đa 1 lần, sau 1 phút"): under the dismiss
/// chips, or alone where the dismiss method is not offered (iOS, T28.3 §3).
class SnoozeNoteText extends StatelessWidget {
  const new(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: context.napText.bodySmall!.copyWith(
      color: context.napColors.textSecondary,
    ),
  );
}
