import 'package:flutter/material.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// "Kiểu báo" on iOS (T28.3 §3): no choice, only how the iPhone alarm
/// rings — AlarmKit rings even in Silent mode, a notification may not.
class IosAlarmStyleNote extends StatelessWidget {
  const new({required this.ringsInSilent, super.key});

  /// Null while unknown (permissions not read yet, or unreadable): only the
  /// header, no claim either way (T28.3 test report #1, like screen 4).
  final bool? ringsInSilent;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final note = switch (ringsInSilent) {
      true => l.alarmSettingsIosAlarmKitNote,
      false => l.alarmSettingsStyleRingHintNoSilent,
      null => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NapSectionHeader(l.alarmSettingsStyleHeader),
        if (note != null) ...[
          const SizedBox(height: NapSpace.s10),
          Text(
            note,
            style: context.napText.bodyMedium!.copyWith(
              color: context.napColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}
