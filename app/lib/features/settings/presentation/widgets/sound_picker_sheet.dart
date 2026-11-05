import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/preferences/app_settings.dart';
import 'package:napstop/features/settings/domain/settings_logic.dart';
import 'package:napstop/features/settings/presentation/settings_strings.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// "Chọn âm báo" (T28 §4.3): one radio row per sound of [kAlarmSoundIds].
/// Picking a row stores it at once and calls [onPreview] so the user hears
/// it; the caller stops the preview when the sheet closes.
Future<void> showSoundPickerSheet(
  BuildContext context, {
  required void Function(String soundId) onPreview,
}) => showNapSheet<void>(
  context: context,
  builder: (_) => SoundPickerSheet(onPreview: onPreview),
);

class SoundPickerSheet extends ConsumerWidget {
  const new({required this.onPreview, super.key});

  final void Function(String soundId) onPreview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final alarm = ref.watch(appSettingsProvider.select((s) => s.alarm));
    final current = resolveSoundId(alarm.soundId);
    return NapSheetBody(
      title: l.settingsSoundPickerTitle,
      children: [
        NapListGroup(
          children: [
            for (final id in kAlarmSoundIds)
              NapListRow(
                title: l.soundLabel(id),
                titleWeight: NapRowTitle.regular,
                semanticsChecked: id == current,
                trailing: NapRadioIndicator(selected: id == current),
                onTap: () {
                  ref
                      .read(appSettingsProvider.notifier)
                      .setAlarm(
                        ref
                            .read(appSettingsProvider)
                            .alarm
                            .copyWith(soundId: id),
                      );
                  onPreview(id);
                },
              ),
          ],
        ),
      ],
    );
  }
}
