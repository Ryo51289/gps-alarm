import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/preferences/app_settings.dart';
import 'package:napstop/core/telemetry/remote_config/engine_params_providers.dart';
import 'package:napstop/features/alarm_settings/data/platform_alarm_caps_provider.dart';
import 'package:napstop/features/alarm_settings/domain/alarm_settings_params.dart';
import 'package:napstop/features/alarm_settings/domain/pre_alert_hint.dart';
import 'package:napstop/features/alarm_settings/presentation/alarm_settings_strings.dart';
import 'package:napstop/features/alarm_settings/presentation/widgets/dismiss_method_picker.dart';
import 'package:napstop/features/alarm_settings/presentation/widgets/mode_panel.dart';
import 'package:napstop/features/alarm_settings/presentation/widgets/pre_alert_row.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// "Mặc định cho chuyến mới" (T28 §4.4, `/settings/trip-defaults`): the
/// middle of screen 3 without destination, alarm style (D11: the headphones
/// switch of screen 12) or start button. Each change is stored at once. The
/// "distance too short" warning needs a vehicle, so screen 3 shows it.
class TripDefaultsScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<TripDefaultsScreen> createState() => _TripDefaultsScreenState();
}

class _TripDefaultsScreenState extends ConsumerState<TripDefaultsScreen> {
  /// Read once, like screen 3 (T29 §6).
  late final AlarmSettingsParams _params = AlarmSettingsParams.fromOverrideJson(
    ref.read(engineParamsReaderProvider).current().json,
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(appSettingsProvider.select((a) => a.tripDefaults));
    final set = ref.read(appSettingsProvider.notifier).setTripDefaults;
    final caps = ref.watch(platformAlarmCapsProvider);
    const gap = SizedBox(height: NapSpace.section);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            NapSpace.page,
            NapSpace.s16,
            NapSpace.page,
            NapSpace.s24,
          ),
          children: [
            NapScreenHeader(
              title: l.settingsTripDefaultsTitle,
              onBack: () => context.pop(),
            ),
            const SizedBox(height: NapSpace.s8),
            Text(
              l.settingsTripDefaultsHint,
              style: context.napText.bodySmall!.copyWith(
                color: context.napColors.textSecondary,
              ),
            ),
            gap,
            NapSectionHeader(l.alarmSettingsModeHeader),
            const SizedBox(height: NapSpace.s10),
            NapSegmentedControl<AlarmModeMsg>(
              semanticLabel: l.alarmSettingsModeHeader,
              segments: [
                for (final mode in const [
                  AlarmModeMsg.distance,
                  AlarmModeMsg.time,
                  AlarmModeMsg.smart,
                ])
                  NapSegment(value: mode, label: l.modeLabel(mode)),
              ],
              selected: s.mode,
              onChanged: (mode) => set(s.copyWith(mode: mode)),
            ),
            const SizedBox(height: NapSpace.s12),
            ModePanel(
              settings: s,
              params: _params,
              shortDistance: null,
              onDistanceChanged: (m) => set(s.copyWith(distanceThresholdM: m)),
              onTimeChanged: (t) => set(s.copyWith(timeThresholdMin: t)),
            ),
            const SizedBox(height: NapSpace.s12),
            PreAlertRow(
              enabled: s.preAlertEnabled,
              hint: preAlertHint(s, _params),
              onChanged: (v) => set(s.copyWith(preAlertEnabled: v)),
            ),
            gap,
            // T28.3 §4: iOS ignores the dismiss method; the snooze line stays.
            if (caps.dismissMethodChoice)
              DismissMethodPicker(
                selected: s.dismissMethod,
                snoozeNote: l.snoozeNote(_params),
                onChanged: (m) => set(s.copyWith(dismissMethod: m)),
              )
            else
              SnoozeNoteText(l.snoozeNote(_params)),
          ],
        ),
      ),
    );
  }
}
