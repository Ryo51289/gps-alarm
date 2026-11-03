import 'package:flutter/material.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/preferences/trip_settings.dart';
import 'package:napstop/features/alarm_settings/domain/alarm_settings_hints.dart';
import 'package:napstop/features/alarm_settings/presentation/alarm_settings_strings.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

IconData _iconOf(AlarmStyle style) => switch (style) {
  AlarmStyle.ringAndVibrate => NapIcons.alarm,
  AlarmStyle.vibrateOnly => NapIcons.vibrate,
  AlarmStyle.headphonesOnly => NapIcons.headphones,
};

/// "Kiểu báo": three option tiles and the hint of the selected one
/// (T25 §3.2).
class AlarmStylePicker extends StatelessWidget {
  const new({
    required this.selected,
    required this.hint,
    required this.onChanged,
    super.key,
  });

  final AlarmStyle selected;
  final AlarmStyleHint hint;
  final ValueChanged<AlarmStyle> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NapSectionHeader(l.alarmSettingsStyleHeader),
        const SizedBox(height: NapSpace.s10),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: NapSpace.s8,
            children: [
              for (final style in AlarmStyle.values)
                Expanded(
                  child: NapOptionCard(
                    title: l.styleLabel(style),
                    icon: _iconOf(style),
                    layout: NapOptionLayout.tile,
                    selected: style == selected,
                    onTap: () => onChanged(style),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: NapSpace.s8),
        Text(
          l.styleHint(hint),
          style: context.napText.bodySmall!.copyWith(
            color: context.napColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
