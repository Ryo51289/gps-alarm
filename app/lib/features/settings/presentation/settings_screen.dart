import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/app/app.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/preferences/alarm_preferences.dart';
import 'package:napstop/core/preferences/app_settings.dart';
import 'package:napstop/core/preferences/display_preferences.dart';
import 'package:napstop/core/telemetry/remote_config/engine_params_providers.dart';
import 'package:napstop/core/telemetry/telemetry_providers.dart';
import 'package:napstop/core/trip/trip_providers.dart';
import 'package:napstop/features/alarm_settings/data/platform_alarm_caps_provider.dart';
import 'package:napstop/features/alarm_settings/domain/alarm_settings_args.dart';
import 'package:napstop/features/alarm_settings/domain/alarm_settings_params.dart';
import 'package:napstop/features/alarm_settings/domain/platform_alarm_caps.dart';
import 'package:napstop/features/alarm_settings/presentation/alarm_settings_strings.dart';
import 'package:napstop/features/feedback/presentation/feedback_action.dart';
import 'package:napstop/features/home/domain/readiness.dart';
import 'package:napstop/features/home/presentation/home_providers.dart';
import 'package:napstop/features/settings/domain/settings_logic.dart';
import 'package:napstop/features/settings/presentation/settings_providers.dart';
import 'package:napstop/features/settings/presentation/settings_strings.dart';
import 'package:napstop/features/settings/presentation/widgets/consent_switches.dart';
import 'package:napstop/features/settings/presentation/widgets/simulation_entry.dart';
import 'package:napstop/features/settings/presentation/widgets/sound_picker_sheet.dart';
import 'package:napstop/features/simulation/domain/sim_launch.dart';
import 'package:napstop/features/simulation/presentation/simulation_sheet.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Screen 12 "Cài đặt chung" (T28 §4.2): defaults for every new trip. Each
/// change is stored at once (D7); a running trip keeps its settings.
class SettingsScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final CoreBridge _bridge;
  late final AppLifecycleListener _lifecycle;

  /// "Nghe thử" is playing (as far as the UI knows; native stops by itself).
  bool _previewing = false;
  Timer? _previewReset;

  /// Slider value while dragging; stored on release only.
  double? _dragVolume;

  /// "Góp ý" is reading device details / opening the composer (T28.4 W04).
  bool _feedbackBusy = false;

  @override
  void initState() {
    super.initState();
    _bridge = ref.read(coreBridgeProvider);
    _lifecycle = AppLifecycleListener(onHide: _stopPreview);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Another tab selected (the shell branch keeps this screen, tickers off).
    if (!TickerMode.valuesOf(context).enabled) {
      _stopPreview(rebuild: false);
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _stopPreview(rebuild: false);
    super.dispose();
  }

  AppSettingsController get _settings => ref.read(appSettingsProvider.notifier);

  void _showSnack(String text, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), action: action, persist: false),
      );
  }

  // --- sound preview ---

  Future<void> _play(String soundId) async {
    final failed = AppLocalizations.of(context).settingsPreviewFailed;
    final alarm = ref.read(appSettingsProvider).alarm;
    _previewReset?.cancel();
    setState(() => _previewing = true);
    _previewReset = Timer(kPreviewUiReset, () {
      if (mounted) {
        setState(() => _previewing = false);
      }
    });
    try {
      await _bridge.previewSound(
        resolveSoundId(soundId),
        previewVolumeOf(alarm),
      );
    } on BridgeException {
      _previewReset?.cancel();
      if (mounted) {
        setState(() => _previewing = false);
        _showSnack(failed);
      }
    }
  }

  /// Stops a preview this screen started; [force] also when the UI thinks
  /// nothing plays (the sound sheet was closed). [rebuild] false where a
  /// build follows anyway or none may (dependencies changed, dispose).
  void _stopPreview({bool force = false, bool rebuild = true}) {
    if (!_previewing && !force) {
      return;
    }
    _previewReset?.cancel();
    _previewReset = null;
    if (_previewing && rebuild && mounted) {
      setState(() => _previewing = false);
    } else {
      _previewing = false;
    }
    _bridge.stopPreview().ignore();
  }

  void _togglePreview() {
    if (_previewing) {
      _stopPreview();
    } else {
      unawaited(_play(ref.read(appSettingsProvider).alarm.soundId));
    }
  }

  Future<void> _openSoundPicker() async {
    final caps = ref.read(platformAlarmCapsProvider);
    await showSoundPickerSheet(
      context,
      // T28.3 §4: no preview of `system` on iOS; stop the one playing.
      onPreview: (id) => canPreviewSound(caps, resolveSoundId(id))
          ? unawaited(_play(id))
          : _stopPreview(force: true),
    );
    if (mounted) {
      _stopPreview(force: true);
    }
  }

  void _volumeEnd(double v) {
    final alarm = ref.read(appSettingsProvider).alarm;
    setState(() => _dragVolume = null);
    _settings.setAlarm(alarm.copyWith(volumePct: volumePctOf(v)));
    if (_previewing) {
      unawaited(_play(alarm.soundId));
    }
  }

  // --- navigation ---

  Future<void> _openPermissions() async {
    await context.openOnboarding();
    if (mounted) {
      ref.invalidate(readinessProvider);
    }
  }

  void _onFeedback() {
    if (_feedbackBusy) {
      return;
    }
    _feedbackBusy = true;
    unawaited(
      openFeedback(context, ref).whenComplete(() => _feedbackBusy = false),
    );
  }

  void _openLicenses(String? version) => showLicensePage(
    context: context,
    applicationName: kAppName,
    applicationVersion: version,
  );

  Future<void> _openSimulation() async {
    if (ref.read(activeTripProvider).value != null) {
      final l = AppLocalizations.of(context);
      _showSnack(
        l.homeActiveTripBusy,
        action: SnackBarAction(
          label: l.homeActiveTripOpen,
          onPressed: () => context.openTracking(),
        ),
      );
      return;
    }
    unawaited(HapticFeedback.heavyImpact());
    final pick = await showSimulationSheet(context);
    if (pick == null || !mounted) {
      return;
    }
    unawaited(
      context.openAlarmSettingsWith(
        AlarmSettingsArgs(
          draft: simDraft(pick.trace, fallbackName: pick.trace.id),
          simulation: simulationOf(pick.trace, pick.speed),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.napColors;
    final settings = ref.watch(appSettingsProvider);
    final loaded = settings.loaded;
    final alarm = settings.alarm;
    final trip = settings.tripDefaults;
    final display = settings.display;
    final tripRunning = ref.watch(activeTripProvider).value != null;
    final readiness = ref.watch(readinessProvider);
    final appVersion = ref.watch(appVersionProvider).value;
    final versionText = appVersion == null
        ? null
        : l.settingsVersion(appVersion.version, appVersion.build);
    final params = AlarmSettingsParams.fromOverrideJson(
      ref.read(engineParamsReaderProvider).current().json,
    );
    final consent = ref.watch(telemetryProvider).consent;
    final caps = ref.watch(platformAlarmCapsProvider);
    final canPreview = canPreviewSound(caps, resolveSoundId(alarm.soundId));
    // T28.3 §4: options the iPhone alarm ignores are hidden, with one note.
    final optionsHidden =
        !caps.rampUp ||
        !caps.vibrationLevels ||
        !caps.flash ||
        !caps.headphones;
    final volume = _dragVolume ?? alarm.volumePct.toDouble();
    const gap = SizedBox(height: NapSpace.section);
    const headerGap = SizedBox(height: NapSpace.s10);
    final valueStyle = context.napText.bodyMedium!.copyWith(
      color: c.textSecondary,
    );

    Widget value(String text) => Text(text, style: valueStyle);

    void openTripDefaults() => unawaited(context.openTripDefaults());

    return Scaffold(
      backgroundColor: c.backgroundGrouped,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            NapSpace.page,
            NapSpace.s8,
            NapSpace.page,
            NapSpace.s16,
          ),
          children: [
            NapScreenHeader(title: l.appScreenSettingsTitle),
            if (tripRunning) ...[
              const SizedBox(height: NapSpace.s12),
              NapBanner(message: l.settingsActiveTripNote),
            ],
            gap,
            // 1. Alarm sound.
            NapSectionHeader(l.settingsSectionAlarm),
            headerGap,
            NapListGroup(
              children: [
                NapListRow(
                  title: l.settingsSound,
                  subtitle: l.soundLabel(alarm.soundId),
                  trailing: canPreview
                      ? NapButton(
                          label: _previewing
                              ? l.settingsPreviewStop
                              : l.settingsPreview,
                          size: NapButtonSize.compact,
                          variant: NapButtonVariant.tonal,
                          onPressed: loaded ? _togglePreview : null,
                        )
                      : null,
                  chevron: true,
                  onTap: loaded ? () => unawaited(_openSoundPicker()) : null,
                ),
                if (!caps.volumeSlider)
                  NapListRow(
                    title: l.settingsVolume,
                    subtitle: l.settingsVolumeIosNote,
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      NapSpace.s16,
                      NapSpace.s12,
                      NapSpace.s16,
                      NapSpace.s12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: NapSpace.s4,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                l.settingsVolume,
                                style: context.napText.titleSmall,
                              ),
                            ),
                            ExcludeSemantics(
                              child: value(
                                l.settingsVolumeValue(volumePctOf(volume)),
                              ),
                            ),
                          ],
                        ),
                        NapLabeledSlider(
                          value: volume,
                          min: kMinAlarmVolumePct.toDouble(),
                          max: kMaxAlarmVolumePct.toDouble(),
                          divisions: kVolumeDivisions,
                          semanticLabel: l.settingsVolume,
                          semanticFormatter: (v) =>
                              l.settingsVolumeSemantic(volumePctOf(v)),
                          onChanged: loaded
                              ? (v) => setState(() => _dragVolume = v)
                              : null,
                          onChangeEnd: loaded ? _volumeEnd : null,
                        ),
                        Text(
                          l.settingsVolumeHint,
                          style: context.napText.bodySmall!.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (caps.rampUp)
                  NapSwitchRow(
                    title: l.settingsRampUp,
                    subtitle: l.settingsRampUpHint,
                    value: alarm.rampUp,
                    onChanged: loaded
                        ? (v) => _settings.setAlarm(alarm.copyWith(rampUp: v))
                        : null,
                  ),
                if (caps.vibrationLevels)
                  Padding(
                    padding: const EdgeInsets.all(NapSpace.s16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: NapSpace.s10,
                      children: [
                        Text(
                          l.settingsVibration,
                          style: context.napText.titleSmall,
                        ),
                        NapSegmentedControl<VibrationMsg>(
                          semanticLabel: l.settingsVibration,
                          segments: [
                            for (final v in kVibrationOptions)
                              NapSegment(value: v, label: l.vibrationLabel(v)),
                          ],
                          selected: kVibrationOptions.contains(alarm.vibration)
                              ? alarm.vibration
                              : VibrationMsg.strong,
                          onChanged: loaded
                              ? (v) => _settings.setAlarm(
                                  alarm.copyWith(vibration: v),
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                if (caps.flash)
                  NapSwitchRow(
                    title: l.settingsFlash,
                    subtitle: l.settingsFlashHint,
                    value: alarm.flash,
                    onChanged: loaded
                        ? (v) => _settings.setAlarm(alarm.copyWith(flash: v))
                        : null,
                  ),
                if (caps.headphones)
                  NapSwitchRow(
                    title: l.settingsHeadphones,
                    subtitle: l.settingsHeadphonesHint,
                    value: prefersHeadphones(trip),
                    onChanged: loaded
                        ? (v) => _settings.setTripDefaults(
                            withHeadphones(trip, on: v),
                          )
                        : null,
                  ),
                if (optionsHidden)
                  Padding(
                    padding: const EdgeInsets.all(NapSpace.s16),
                    child: Text(
                      l.settingsAlarmIosOptionsNote,
                      style: context.napText.bodySmall!.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
            gap,
            // 2. Defaults for new trips.
            NapSectionHeader(l.settingsSectionTripDefaults),
            headerGap,
            NapListGroup(
              children: [
                NapListRow(
                  title: l.settingsTripMode,
                  trailing: value(l.tripDefaultsSummary(trip)),
                  chevron: true,
                  onTap: loaded ? openTripDefaults : null,
                ),
                if (caps.dismissMethodChoice)
                  NapListRow(
                    title: l.settingsDismiss,
                    trailing: value(l.dismissLabel(trip.dismissMethod)),
                    chevron: true,
                    onTap: loaded ? openTripDefaults : null,
                  ),
                NapListRow(
                  title: l.settingsSnooze,
                  trailing: value(l.snoozeValue(params)),
                ),
              ],
            ),
            gap,
            // 3. Display.
            NapSectionHeader(l.settingsSectionDisplay),
            headerGap,
            NapListGroup(
              children: [
                Padding(
                  padding: const EdgeInsets.all(NapSpace.s16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: NapSpace.s10,
                    children: [
                      Text(l.settingsTheme, style: context.napText.titleSmall),
                      NapSegmentedControl<AppThemeChoice>(
                        semanticLabel: l.settingsTheme,
                        segments: [
                          for (final t in const [
                            AppThemeChoice.light,
                            AppThemeChoice.dark,
                            AppThemeChoice.system,
                          ])
                            NapSegment(value: t, label: l.themeLabel(t)),
                        ],
                        selected: display.theme,
                        onChanged: loaded
                            ? (t) => _settings.setDisplay(
                                display.copyWith(theme: t),
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            gap,
            // 4. Language.
            NapSectionHeader(l.settingsSectionLanguage),
            headerGap,
            NapListGroup(
              children: [
                for (final language in const [
                  AppLanguage.vi,
                  AppLanguage.en,
                  AppLanguage.system,
                ])
                  NapListRow(
                    title: l.languageLabel(language),
                    titleWeight: NapRowTitle.regular,
                    semanticsChecked: display.language == language,
                    trailing: NapRadioIndicator(
                      selected: display.language == language,
                    ),
                    onTap: loaded
                        ? () => _settings.setDisplay(
                            display.copyWith(language: language),
                          )
                        : null,
                  ),
              ],
            ),
            gap,
            // 5. Privacy.
            NapSectionHeader(l.settingsSectionPrivacy),
            headerGap,
            ConsentSwitches(controller: consent),
            gap,
            // 6. Other.
            NapSectionHeader(l.settingsSectionOther),
            headerGap,
            NapListGroup(
              children: [
                NapListRow(
                  title: l.settingsPermissions,
                  trailing: switch (readiness.value?.level) {
                    ReadinessLevel.ready => NapBadge(
                      label: l.settingsPermissionsOk,
                      tone: NapTone.success,
                    ),
                    ReadinessLevel.check => NapBadge(
                      label: l.settingsPermissionsCheck,
                      tone: NapTone.warning,
                    ),
                    ReadinessLevel.blocked => NapBadge(
                      label: l.settingsPermissionsCheck,
                      tone: NapTone.danger,
                    ),
                    null => null,
                  },
                  chevron: true,
                  onTap: () => unawaited(_openPermissions()),
                ),
                NapListRow(
                  key: const ValueKey('settings-feedback'),
                  title: l.settingsFeedback,
                  subtitle: l.settingsFeedbackHint,
                  chevron: true,
                  onTap: _onFeedback,
                ),
                NapListRow(
                  title: l.settingsLicenses,
                  chevron: true,
                  onTap: () => _openLicenses(versionText),
                ),
              ],
            ),
            // 7. Logo + version (hidden simulation entry).
            SimulationEntry(
              appName: kAppName,
              version: versionText,
              holdDuration: kSimLongPress,
              onLongPress: () => unawaited(_openSimulation()),
            ),
          ],
        ),
      ),
    );
  }
}
