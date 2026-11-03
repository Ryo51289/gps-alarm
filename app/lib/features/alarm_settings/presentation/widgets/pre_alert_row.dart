import 'package:flutter/material.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/features/alarm_settings/domain/pre_alert_hint.dart';
import 'package:napstop/features/alarm_settings/presentation/alarm_settings_strings.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// "Nhắc nhẹ trước 1 lần" switch (T25 §3.2). Always switchable: the value
/// is sent anyway and the engine skips a pre-alert that does not apply.
class PreAlertRow extends StatelessWidget {
  const new({
    required this.enabled,
    required this.hint,
    required this.onChanged,
    super.key,
  });

  final bool enabled;
  final PreAlertHint hint;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return NapCard(
      padding: EdgeInsets.zero,
      child: NapSwitchRow(
        title: l.alarmSettingsPreAlertTitle,
        subtitle: l.preAlertSubtitle(hint),
        value: enabled,
        onChanged: onChanged,
      ),
    );
  }
}
