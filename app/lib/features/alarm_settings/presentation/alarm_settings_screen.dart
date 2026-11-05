import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/device/device_providers.dart';
import 'package:napstop/core/preferences/alarm_preferences.dart';
import 'package:napstop/core/preferences/preferences_repository.dart';
import 'package:napstop/core/preferences/trip_settings.dart';
import 'package:napstop/core/telemetry/remote_config/engine_params_override.dart';
import 'package:napstop/core/telemetry/remote_config/engine_params_providers.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/features/alarm_settings/data/alarm_settings_providers.dart';
import 'package:napstop/features/alarm_settings/data/platform_alarm_caps_provider.dart';
import 'package:napstop/features/alarm_settings/domain/alarm_settings_args.dart';
import 'package:napstop/features/alarm_settings/domain/alarm_settings_hints.dart';
import 'package:napstop/features/alarm_settings/domain/alarm_settings_params.dart';
import 'package:napstop/features/alarm_settings/domain/platform_alarm_caps.dart';
import 'package:napstop/features/alarm_settings/domain/pre_alert_hint.dart';
import 'package:napstop/features/alarm_settings/domain/trip_starter.dart';
import 'package:napstop/features/alarm_settings/presentation/alarm_settings_strings.dart';
import 'package:napstop/features/alarm_settings/presentation/widgets/alarm_style_picker.dart';
import 'package:napstop/features/alarm_settings/presentation/widgets/destination_summary_card.dart';
import 'package:napstop/features/alarm_settings/presentation/widgets/dismiss_method_picker.dart';
import 'package:napstop/features/alarm_settings/presentation/widgets/ios_alarm_style_note.dart';
import 'package:napstop/features/alarm_settings/presentation/widgets/mode_panel.dart';
import 'package:napstop/features/alarm_settings/presentation/widgets/pre_alert_row.dart';
import 'package:napstop/features/alarm_settings/presentation/widgets/start_bar.dart';
import 'package:napstop/features/alarm_settings/presentation/widgets/start_blocked_sheet.dart';
import 'package:napstop/features/onboarding/domain/start_check.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Screen 3 "Cài đặt báo thức" (T25 §1, §3).
///
/// States: loading (preferences not read yet) → editing → starting. The
/// per-trip choices live here and are never written back as defaults (Q1).
class AlarmSettingsScreen extends ConsumerStatefulWidget {
  const new({required this.args, super.key});

  final AlarmSettingsArgs args;

  @override
  ConsumerState<AlarmSettingsScreen> createState() =>
      _AlarmSettingsScreenState();
}

class _AlarmSettingsScreenState extends ConsumerState<AlarmSettingsScreen> {
  late final AppLifecycleListener _lifecycle;

  /// Read ONCE when the screen opens (T29 §6): the warning on screen and
  /// the engine use the same parameters.
  late final EngineParamsOverride _override;
  late final AlarmSettingsParams _params;

  /// Null while loading.
  TripSettings? _settings;
  AlarmPreferences _alarmPrefs = AlarmPreferences.defaults;

  /// Hints only; the start flow reads them again.
  PermissionStatusMsg? _permissions;
  DeviceInfoMsg? _device;
  DeviceStatusMsg? _status;

  bool _starting = false;
  StartError? _error;

  @override
  void initState() {
    super.initState();
    _override = ref.read(engineParamsReaderProvider).current();
    _params = AlarmSettingsParams.fromOverrideJson(_override.json);
    // Permissions, battery or Do Not Disturb may change while away.
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(_refreshDevice()),
    );
    unawaited(_load());
    unawaited(_refreshDevice());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = ref.read(preferencesRepositoryProvider);
    final defaults = await repo.loadTripDefaults();
    final alarmPrefs = await repo.loadAlarmPreferences();
    if (!mounted) {
      return;
    }
    setState(() {
      _alarmPrefs = alarmPrefs;
      _settings = initialTripSettings(
        defaults: defaults,
        preset: widget.args.preset,
        choice: widget.args.draft.alarm,
      );
    });
  }

  /// Each read fails on its own: a missing value only hides its hint.
  Future<void> _refreshDevice() async {
    final bridge = ref.read(coreBridgeProvider);
    PermissionStatusMsg? permissions;
    DeviceInfoMsg? device;
    DeviceStatusMsg? status;
    try {
      permissions = await bridge.permissionStatus();
    } on Object {
      permissions = null;
    }
    try {
      device = await ref.read(deviceInfoProvider.future);
    } on Object {
      device = null;
    }
    try {
      status = await bridge.deviceStatus();
    } on Object {
      status = null;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _permissions = permissions;
      _device = device;
      _status = status;
    });
  }

  void _update(TripSettings settings) => setState(() {
    _settings = settings;
    _error = null;
  });

  Future<void> _start() async {
    final settings = _settings;
    if (_starting || settings == null) {
      return;
    }
    setState(() {
      _starting = true;
      _error = null;
    });
    final args = widget.args;
    final outcome = await ref
        .read(tripStarterProvider)
        .start(
          StartRequest(
            draft: args.draft,
            settings: settings,
            alarmPrefs: _alarmPrefs,
            engineParams: _override,
            shortDistanceWarning:
                shortDistanceInfo(settings, args.draft.vehicleHint, _params) !=
                null,
            simulation: args.simulation,
          ),
        );
    if (!mounted) {
      return;
    }
    switch (outcome) {
      case StartSucceeded():
        // `go`: screen 3 leaves the stack, Back does not return here.
        context.openTracking();
      case StartBlocked(:final missing):
        setState(() => _starting = false);
        await _showBlocked(missing);
      case StartFailed(:final error):
        setState(() {
          _starting = false;
          _error = error;
        });
    }
  }

  Future<void> _showBlocked(List<StartRequirement> missing) async {
    final grant = await showStartBlockedSheet(context, missing);
    if (!grant || !mounted) {
      return;
    }
    await context.openOnboarding();
    // Hints only: never starts by itself.
    if (mounted) {
      await _refreshDevice();
    }
  }

  /// "Xem chuyến": screen 4 when a trip runs, else drop the banner.
  Future<void> _viewActiveTrip() async {
    ActiveTripMsg? active;
    try {
      active = await ref.read(coreBridgeProvider).currentTrip();
    } on Object {
      active = null;
    }
    if (!mounted) {
      return;
    }
    if (active != null && active.state.phase != TripPhaseMsg.ended) {
      context.openTracking();
    } else {
      setState(() => _error = null);
    }
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  /// From screen 2: back to it. From screen 1 (saved place, recent trip):
  /// screen 2 replaces this one.
  void _changeDestination() {
    switch (widget.args.draft.source) {
      case DestinationSource.station ||
          DestinationSource.places ||
          DestinationSource.mapPin:
        _back();
      case DestinationSource.savedPlace || DestinationSource.recentTrip:
        context.pushReplacement(AppRoutes.destination);
    }
  }

  StartBarAction? _errorAction(AppLocalizations l) => switch (_error) {
    StartError.tripActive => (
      label: l.alarmSettingsViewActiveTrip,
      onPressed: () => unawaited(_viewActiveTrip()),
    ),
    StartError.generic || StartError.timeout => (
      label: l.commonRetry,
      onPressed: () => unawaited(_start()),
    ),
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final settings = _settings;
    final header = NapScreenHeader(
      title: l.appScreenAlarmSettingsTitle,
      onBack: _starting ? null : _back,
    );
    final Widget body;
    if (settings == null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(padding: _pagePadding, child: header),
          const Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      );
    } else {
      final error = _error;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: _pagePadding,
              child: AbsorbPointer(
                absorbing: _starting,
                child: _Content(
                  header: header,
                  args: widget.args,
                  settings: settings,
                  params: _params,
                  alarmPrefs: _alarmPrefs,
                  caps: ref.watch(platformAlarmCapsProvider),
                  ringsInSilent: ringsInSilent(_permissions, _device),
                  iosRingsInSilent: ringsInSilentIfKnown(_permissions, _device),
                  lowBatteryPct: lowBatteryWarningPct(_status, _params),
                  alarmMuted: alarmMayBeSilenced(_status),
                  onChanged: _update,
                  onChangeDestination: _starting ? null : _changeDestination,
                ),
              ),
            ),
          ),
          StartBar(
            summaryValue: l.summaryValue(settings, _params),
            starting: _starting,
            onStart: () => unawaited(_start()),
            error: error == null ? null : l.startError(error),
            errorAction: _errorAction(l),
          ),
        ],
      );
    }
    // While starting, Back could leave a trip running unseen (T25 §1).
    return PopScope(
      canPop: !_starting,
      child: Scaffold(body: SafeArea(child: body)),
    );
  }

  static const EdgeInsets _pagePadding = EdgeInsets.fromLTRB(
    NapSpace.page,
    NapSpace.s16,
    NapSpace.page,
    NapSpace.s24,
  );
}

/// Scrollable blocks 1-9 of T25 §3.
class _Content extends StatelessWidget {
  const new({
    required this.header,
    required this.args,
    required this.settings,
    required this.params,
    required this.alarmPrefs,
    required this.caps,
    required this.ringsInSilent,
    required this.iosRingsInSilent,
    required this.lowBatteryPct,
    required this.alarmMuted,
    required this.onChanged,
    required this.onChangeDestination,
  });

  final Widget header;
  final AlarmSettingsArgs args;
  final TripSettings settings;
  final AlarmSettingsParams params;
  final AlarmPreferences alarmPrefs;
  final PlatformAlarmCaps caps;
  final bool ringsInSilent;

  /// iOS note: null while unknown, so it claims nothing (test report #1).
  final bool? iosRingsInSilent;
  final int? lowBatteryPct;
  final bool alarmMuted;
  final ValueChanged<TripSettings> onChanged;
  final VoidCallback? onChangeDestination;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final battery = lowBatteryPct;
    final simulation = args.simulation;
    const gap = SizedBox(height: NapSpace.section);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: NapSpace.s12),
        DestinationSummaryCard(
          destination: args.draft.destination,
          onChange: onChangeDestination,
        ),
        if (battery != null) ...[
          const SizedBox(height: NapSpace.s12),
          // Live region: it appears after the first frame or on resume.
          NapBanner(
            tone: NapTone.warning,
            announce: true,
            title: l.alarmSettingsBatteryLowTitle(battery),
            message: l.alarmSettingsBatteryLowBody,
          ),
        ],
        if (alarmMuted) ...[
          const SizedBox(height: NapSpace.s12),
          NapBanner(
            tone: NapTone.warning,
            announce: true,
            title: l.alarmSettingsAlarmMutedTitle,
            message: l.alarmSettingsAlarmMutedBody,
          ),
        ],
        if (simulation != null) ...[
          const SizedBox(height: NapSpace.s12),
          NapBanner(
            message: l.alarmSettingsSimulationBanner(
              simulation.speedFactor.round(),
            ),
          ),
        ],
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
          selected: settings.mode,
          onChanged: (mode) => onChanged(settings.copyWith(mode: mode)),
        ),
        const SizedBox(height: NapSpace.s12),
        ModePanel(
          settings: settings,
          params: params,
          shortDistance: shortDistanceInfo(
            settings,
            args.draft.vehicleHint,
            params,
          ),
          onDistanceChanged: (m) =>
              onChanged(settings.copyWith(distanceThresholdM: m)),
          onTimeChanged: (t) =>
              onChanged(settings.copyWith(timeThresholdMin: t)),
        ),
        const SizedBox(height: NapSpace.s12),
        PreAlertRow(
          enabled: settings.preAlertEnabled,
          hint: preAlertHint(settings, params),
          onChanged: (v) => onChanged(settings.copyWith(preAlertEnabled: v)),
        ),
        gap,
        // T28.3 §3: on iOS the system alarm ignores style and dismiss
        // method; the stored values stay (D4).
        if (caps.alarmStyleChoice)
          AlarmStylePicker(
            selected: settings.alarmStyle,
            hint: alarmStyleHint(
              settings.alarmStyle,
              ringsInSilent: ringsInSilent,
              rampUp: alarmPrefs.rampUp,
            ),
            onChanged: (s) => onChanged(settings.copyWith(alarmStyle: s)),
          )
        else
          IosAlarmStyleNote(ringsInSilent: iosRingsInSilent),
        gap,
        if (caps.dismissMethodChoice)
          DismissMethodPicker(
            selected: settings.dismissMethod,
            snoozeNote: l.snoozeNote(params),
            onChanged: (m) => onChanged(settings.copyWith(dismissMethod: m)),
          )
        else
          SnoozeNoteText(l.snoozeNote(params)),
      ],
    );
  }
}
