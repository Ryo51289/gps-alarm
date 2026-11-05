import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:napstop/app/clock.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/device/device_providers.dart';
import 'package:napstop/core/telemetry/telemetry.dart';
import 'package:napstop/core/telemetry/telemetry_providers.dart';
import 'package:napstop/features/onboarding/domain/start_check.dart';
import 'package:napstop/features/tracking/data/battery_sheet_shown.dart';
import 'package:napstop/features/tracking/data/tracked_trip_provider.dart';
import 'package:napstop/features/tracking/domain/tracking_view.dart';
import 'package:napstop/features/tracking/presentation/trip_launch_scope.dart';
import 'package:napstop/features/tracking/presentation/widgets/battery_choice_sheet.dart';
import 'package:napstop/features/tracking/presentation/widgets/stop_confirm_sheet.dart';
import 'package:napstop/features/tracking/presentation/widgets/tracking_actions.dart';
import 'package:napstop/features/tracking/presentation/widgets/tracking_banners.dart';
import 'package:napstop/features/tracking/presentation/widgets/tracking_headline.dart';
import 'package:napstop/features/tracking/presentation/widgets/tracking_status_row.dart';
import 'package:napstop/features/tracking/presentation/widgets/trip_progress_bar.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Screen 4 "Đang theo dõi" with states 6 (estimated) and 7 (battery sheet)
/// (T26 §4-§6). Shows the native trip view; every decision stays native.
///
/// PRIVACY: never logs the trip, its view, a distance or the destination.
/// How long screen 4 waits for the TripEnded event (its end reason picks
/// the snack bar) after an ENDED view before going home.
const Duration kEndReasonWait = Duration(milliseconds: 300);

class TrackingScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends ConsumerState<TrackingScreen> {
  late final CoreBridge _bridge;
  late final Telemetry _telemetry;
  late final DateTime Function() _clock;
  late final AppLifecycleListener _lifecycle;
  late final ProviderSubscription<AsyncValue<TrackingStatus>> _status;

  /// D8 (a): blocking permission problems, read on open and resume.
  List<StartRequirement> _missing = const [];
  DeviceStatusMsg? _device;
  late int _nowMs;

  /// D16: device status every 30 s while visible.
  Timer? _poll;

  /// SNOOZED countdown, 1 s, only while visible.
  Timer? _tick;
  Timer? _previewEnd;

  bool _visible = true;

  /// Waiting for the TripEnded event after an ENDED view.
  Timer? _endReasonWait;
  bool _endReasonWaited = false;
  bool _routeCurrent = true;
  bool _previewing = false;
  bool _previewBusy = false;
  bool _busy = false;
  bool _leaving = false;
  bool _leaveScheduled = false;
  bool _sheetCheckScheduled = false;
  Animation<double>? _transition;
  AnimationStatusListener? _transitionListener;

  int get _now => _clock().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _bridge = ref.read(coreBridgeProvider);
    _telemetry = ref.read(telemetryProvider);
    _clock = ref.read(clockProvider);
    _nowMs = _now;
    _lifecycle = AppLifecycleListener(onHide: _onHide, onShow: _onShow);
    _status = ref.listenManual(
      trackedTripProvider,
      (_, next) => _onStatus(next.value),
      fireImmediately: true,
    );
    unawaited(_refreshEnv());
    _startPolling();
  }

  @override
  void dispose() {
    final listener = _transitionListener;
    if (listener != null) {
      _transition?.removeStatusListener(listener);
    }
    _status.close();
    _lifecycle.dispose();
    _poll?.cancel();
    _tick?.cancel();
    _previewEnd?.cancel();
    _endReasonWait?.cancel();
    if (_previewing) {
      unawaited(_stopPreviewQuietly());
    }
    super.dispose();
  }

  // ------------------------------------------------------------- lifecycle

  void _onHide() {
    _visible = false;
    _poll?.cancel();
    _poll = null;
    _tick?.cancel();
    _tick = null;
    if (_previewing) {
      _previewEnd?.cancel();
      setState(() => _previewing = false);
      unawaited(_stopPreviewQuietly());
    }
  }

  void _onShow() {
    _visible = true;
    unawaited(_refreshEnv());
    _startPolling();
    _syncTick(ref.read(trackedTripProvider).value);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // D16: poll only while screen 4 is the top route (not under /alarm or
    // a sheet); read once when it comes back on top.
    final current = ModalRoute.isCurrentOf(context) ?? true;
    if (current == _routeCurrent) {
      return;
    }
    _routeCurrent = current;
    if (current) {
      _startPolling();
      if (_visible) {
        unawaited(_pollDevice());
      }
    } else {
      _poll?.cancel();
      _poll = null;
    }
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = null;
    if (!_visible || !_routeCurrent) {
      return;
    }
    _poll = Timer.periodic(
      const Duration(milliseconds: kDeviceStatusPollMs),
      (_) => unawaited(_pollDevice()),
    );
  }

  void _syncTick(TrackingStatus? status) {
    final snoozed =
        status is TrackingActive &&
        status.trip.state.phase == TripPhaseMsg.snoozed;
    if (snoozed && _visible) {
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() => _nowMs = _now);
        }
      });
    } else {
      _tick?.cancel();
      _tick = null;
    }
  }

  /// Each read fails on its own; a failure only hides its hint.
  Future<void> _refreshEnv() async {
    final deviceInfo = ref.read(deviceInfoProvider.future);
    List<StartRequirement> missing;
    try {
      final permissions = await _bridge.permissionStatus();
      missing = checkStart(permissions, await deviceInfo).missing;
    } on Object {
      missing = const [];
    }
    DeviceStatusMsg? device;
    try {
      device = await _bridge.deviceStatus();
    } on Object {
      device = _device;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _missing = missing;
      _device = device;
      _nowMs = _now;
    });
  }

  Future<void> _pollDevice() async {
    DeviceStatusMsg? device;
    try {
      device = await _bridge.deviceStatus();
    } on Object {
      device = _device;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _device = device;
      _nowMs = _now;
    });
  }

  // ------------------------------------------------------------ the trip

  void _onStatus(TrackingStatus? status) {
    _nowMs = _now;
    _setCrashKeys(status);
    _syncTick(status);
    switch (status) {
      case TrackingActive(:final trip) when wantsBatterySheetOf(trip):
        _scheduleSheetCheck();
      case TrackingEnded() || TrackingNone():
        _scheduleLeave();
      default:
        break;
    }
  }

  /// T29 §11; `setKey` drops a value equal to the last one.
  void _setCrashKeys(TrackingStatus? status) {
    final crash = _telemetry.crash;
    switch (status) {
      case TrackingActive(:final trip):
        crash
          ..setKey(CrashKey.tripActive, true)
          ..setKey(CrashKey.tripPhase, trip.state.phase.name)
          ..setKey(
            CrashKey.samplingTier,
            trip.state.samplingTier?.name ?? 'none',
          );
      case TrackingEnded() || TrackingNone():
        crash
          ..setKey(CrashKey.tripActive, false)
          ..setKey(CrashKey.tripPhase, 'none')
          ..setKey(CrashKey.samplingTier, 'none');
      default:
        break;
    }
  }

  void _scheduleLeave() {
    if (_leaveScheduled || _leaving) {
      return;
    }
    _leaveScheduled = true;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) => _maybeLeave())
      ..ensureVisualUpdate();
  }

  /// D13: back to screen 1 once the trip is over, only while this screen is
  /// the top route (T27 may have pushed `/alarm` above it, or replaced the
  /// stack with `/overshoot`). Runs again when the route above is popped.
  void _maybeLeave() {
    _leaveScheduled = false;
    if (!mounted || _leaving) {
      return;
    }
    final status = ref.read(trackedTripProvider).value;
    if (status is! TrackingEnded && status is! TrackingNone) {
      return;
    }
    final router = GoRouter.of(context);
    final route = ModalRoute.of(context);
    if (route?.isCurrent != true ||
        topRoutePath(router) != AppRoutes.tracking) {
      return;
    }
    // The ENDED view comes before its TripEnded event (T10 §2.3), maybe in
    // another frame: wait a moment for the end reason that picks the text
    // (test report T26 #1).
    if (status is TrackingEnded &&
        status.endReason == null &&
        !_endReasonWaited) {
      _endReasonWait ??= Timer(kEndReasonWait, () {
        _endReasonWaited = true;
        if (mounted) {
          _scheduleLeave();
        }
      });
      return;
    }
    // Leaving while this route still animates in would rebuild the shell
    // of the stack being replaced (duplicate GlobalKey): wait for it.
    final animation = route?.animation;
    if (animation != null && animation.status != AnimationStatus.completed) {
      _waitForTransition(animation);
      return;
    }
    _leaving = true;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l = AppLocalizations.of(context);
    router.go(AppRoutes.home);
    if (status is TrackingEnded) {
      messenger?.showSnackBar(SnackBar(content: Text(_endedText(l, status))));
    }
  }

  void _waitForTransition(Animation<double> animation) {
    if (_transition != null) {
      return;
    }
    _transition = animation;
    void listener(AnimationStatus status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        animation.removeStatusListener(listener);
        _transition = null;
        _transitionListener = null;
        if (mounted) {
          _scheduleLeave();
        }
      }
    }

    _transitionListener = listener;
    animation.addStatusListener(listener);
  }

  static String _endedText(AppLocalizations l, TrackingEnded e) {
    if (e.endReason == EndReasonMsg.dismissed) {
      return l.trackingEndedDismissed;
    }
    if (e.endReason == EndReasonMsg.userStop ||
        e.outcome == TripOutcomeMsg.cancelled) {
      return l.trackingEndedStopped;
    }
    return l.trackingEndedOther;
  }

  void _scheduleSheetCheck() {
    if (_sheetCheckScheduled) {
      return;
    }
    _sheetCheckScheduled = true;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) => _maybeOpenBatterySheet())
      ..ensureVisualUpdate();
  }

  /// D10: screen 7 opens by itself once per trip and process.
  void _maybeOpenBatterySheet() {
    _sheetCheckScheduled = false;
    if (!mounted || !_visible || _leaving) {
      return;
    }
    final status = ref.read(trackedTripProvider).value;
    if (status is! TrackingActive || !wantsBatterySheetOf(status.trip)) {
      return;
    }
    if (ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    if (!ref
        .read(batterySheetShownProvider.notifier)
        .markShown(status.trip.tripId)) {
      return;
    }
    unawaited(_openBatterySheet(status.trip));
  }

  Future<void> _openBatterySheet(TrackedTrip trip) {
    final view = _viewOf(trip, AppLocalizations.of(context));
    return showBatteryChoiceSheet(
      context,
      tripId: trip.tripId,
      levelPct: view.batteryPct,
      params: view.params,
      estimate: trip.lowBattery,
      onApply: (choice) => _applyBattery(trip, choice),
    );
  }

  TrackingView _viewOf(TrackedTrip trip, AppLocalizations l) =>
      buildTrackingView(
        trip,
        TrackingEnv(
          nowMs: _nowMs,
          locale: l.localeName,
          missing: _missing,
          device: _device,
        ),
      );

  // -------------------------------------------------------------- actions

  void _goHome() => context.go(AppRoutes.home);

  void _showFailed() {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).trackingActionFailed),
      ),
    );
  }

  Future<void> _stopPreviewQuietly() async {
    try {
      await _bridge.stopPreview();
    } on Object {
      // Native stops by itself after PREVIEW_MAX_MS.
    }
  }

  Future<void> _togglePreview(TrackedTrip trip) async {
    if (_previewBusy) {
      return;
    }
    if (_previewing) {
      _previewEnd?.cancel();
      setState(() => _previewing = false);
      await _stopPreviewQuietly();
      return;
    }
    setState(() => _previewBusy = true);
    try {
      await _bridge.previewSound(
        trip.config.alarm.soundId,
        trip.config.alarm.volume,
      );
      if (!mounted) {
        return;
      }
      _previewEnd?.cancel();
      _previewEnd = Timer(const Duration(milliseconds: kPreviewMs), () {
        if (mounted) {
          setState(() => _previewing = false);
        }
      });
      setState(() => _previewing = true);
    } on Object {
      _showFailed();
    } finally {
      if (mounted) {
        setState(() => _previewBusy = false);
      }
    }
  }

  Future<void> _run(Future<void> Function() call) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await call();
    } on Object {
      _showFailed();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _dismiss(TrackedTrip trip) =>
      _run(() => _bridge.dismiss(trip.tripId));

  Future<void> _stop(TrackedTrip trip) async {
    if (_busy) {
      return;
    }
    final confirmed = await showStopConfirmSheet(
      context,
      destination: trip.config.destinationName,
    );
    if (!confirmed || !mounted) {
      return;
    }
    await _run(() => _bridge.stopTrip(trip.tripId));
  }

  Future<bool> _applyBattery(TrackedTrip trip, BatteryChoiceMsg choice) async {
    try {
      await _bridge.setBatteryChoice(trip.tripId, choice);
    } on Object {
      // The sheet shows the error itself (a snack bar would be under it).
      return false;
    }
    _telemetry.analytics.log(
      LowBatteryChoiceEvent(
        choice: switch (choice) {
          BatteryChoiceMsg.maxSaving => BatteryChoiceTag.maxSaving,
          BatteryChoiceMsg.alarmAt5 => BatteryChoiceTag.alarmAt5,
          BatteryChoiceMsg.alarmEarlier => BatteryChoiceTag.alarmEarlier,
        },
        simulated: trip.simulated,
      ),
    );
    return true;
  }

  Future<void> _openSettings(SettingsTargetMsg target) async {
    try {
      await _bridge.openSettings(target);
    } on Object {
      _showFailed();
    }
  }

  // ---------------------------------------------------------------- build

  String _formatTime(int ms) =>
      MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(ms)),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(trackedTripProvider);
    // Rebuilds when a route above is popped (D13 runs again).
    final isCurrent = ModalRoute.isCurrentOf(context) ?? true;
    final status = async.value;
    if (isCurrent && (status is TrackingEnded || status is TrackingNone)) {
      _scheduleLeave();
    }
    final body = switch (status) {
      TrackingActive(:final trip) => _active(context, l, trip),
      TrackingError() => _message(context, l, error: true),
      TrackingEnded() || TrackingNone() => _message(context, l),
      null when async.hasError => _message(context, l, error: true),
      null => _message(context, l, loading: true),
    };
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _goHome();
        }
      },
      child: Scaffold(body: SafeArea(child: body)),
    );
  }

  /// Loading, error (with retry) or the empty frame while leaving.
  Widget _message(
    BuildContext context,
    AppLocalizations l, {
    bool error = false,
    bool loading = false,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NapSpace.page,
        NapSpace.s8,
        NapSpace.page,
        NapSpace.s20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NapScreenHeader(title: l.appScreenTrackingTitle, onBack: _goHome),
          if (loading)
            const Expanded(child: Center(child: CircularProgressIndicator())),
          if (error) ...[
            const SizedBox(height: NapSpace.s20),
            Text(l.trackingLoadFailed, style: context.napText.bodyLarge),
            const SizedBox(height: NapSpace.s16),
            NapButton(
              label: l.commonRetry,
              variant: NapButtonVariant.secondary,
              onPressed: () => ref.invalidate(trackedTripProvider),
            ),
          ],
        ],
      ),
    );
  }

  Widget _active(BuildContext context, AppLocalizations l, TrackedTrip trip) {
    final view = _viewOf(trip, l);
    final simulation = trip.simulation;
    final progress = view.progress;
    final marker = view.markerProgress;
    const gap = SizedBox(height: NapSpace.section);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              NapSpace.page,
              NapSpace.s8,
              NapSpace.page,
              NapSpace.s16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                NapSectionHeader(l.appScreenTrackingTitle),
                NapScreenHeader(
                  title: trip.config.destinationName,
                  onBack: _goHome,
                ),
                if (simulation != null) ...[
                  const SizedBox(height: NapSpace.s8),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: NapBadge(
                      tone: NapTone.accent,
                      size: NapBadgeSize.medium,
                      label: l.alarmSettingsSimulationBanner(
                        simulation.speedFactor.round(),
                      ),
                    ),
                  ),
                ],
                gap,
                TrackingHeadline(
                  view: view,
                  destination: trip.config.destinationName,
                ),
                const SizedBox(height: NapSpace.s12),
                TrackingInfoLines(
                  view: view,
                  config: trip.config,
                  formatTime: _formatTime,
                ),
                if (progress != null) ...[
                  gap,
                  TripProgressBar(
                    progress: progress,
                    marker: marker,
                    markerLabel: l.trackingMarkerLabel,
                    estimated: view.progressEstimated,
                    semanticLabel: marker == null
                        ? l.trackingProgressA11yNoMarker(
                            (progress * 100).round(),
                          )
                        : l.trackingProgressA11y(
                            (progress * 100).round(),
                            (marker * 100).round(),
                          ),
                  ),
                ],
                gap,
                TrackingStatusRow(view: view),
                if (view.banners.isNotEmpty) ...[
                  gap,
                  TrackingBanners(
                    view: view,
                    onOpenSettings: (t) => unawaited(_openSettings(t)),
                    onChooseBattery: () => unawaited(_openBatterySheet(trip)),
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            NapSpace.page,
            NapSpace.s12,
            NapSpace.page,
            NapSpace.s20,
          ),
          child: TrackingActions(
            view: view,
            previewing: _previewing,
            onPreview: _previewBusy
                ? null
                : () => unawaited(_togglePreview(trip)),
            onDismiss: _busy ? null : () => unawaited(_dismiss(trip)),
            onStop: _busy ? null : () => unawaited(_stop(trip)),
          ),
        ),
      ],
    );
  }
}
