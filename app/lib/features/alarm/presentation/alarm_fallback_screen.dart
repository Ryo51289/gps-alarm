import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/diagnostics/report_error.dart';
import 'package:napstop/features/alarm/domain/alarm_copy.dart';
import 'package:napstop/features/alarm/domain/ring_ui_rules.dart';
import 'package:napstop/features/alarm/domain/route_back.dart';
import 'package:napstop/features/alarm/presentation/widgets/alarm_glow.dart';
import 'package:napstop/features/alarm/presentation/widgets/swipe_to_stop_bar.dart';
import 'package:napstop/features/alarm_settings/data/platform_alarm_caps_provider.dart';
import 'package:napstop/features/alarm_settings/domain/alarm_settings_params.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Tells `AlarmUiCoordinator` that the fallback screen went away (T27 D10):
/// popped, or removed by a `go` (whose push future never completes).
final class AlarmFallbackClosedSignal {
  final Set<VoidCallback> _listeners = {};

  void addListener(VoidCallback l) => _listeners.add(l);

  void removeListener(VoidCallback l) => _listeners.remove(l);

  void notify() {
    for (final l in List.of(_listeners)) {
      l();
    }
  }
}

final alarmFallbackClosedSignalProvider = Provider<AlarmFallbackClosedSignal>(
  (ref) => AlarmFallbackClosedSignal(),
);

/// Screen 5 on the Flutter side (T27 §8): only a safety net, shown by
/// `AlarmUiCoordinator` when the native alarm screen did not cover the app
/// (D1). Always a swipe bar to stop, whatever the dismiss method (D2).
/// Snooze / stop go through Pigeon; the screen closes itself when the ring
/// stops (D10).
class AlarmFallbackScreen extends ConsumerStatefulWidget {
  const new({required this.tripId, super.key});

  final String tripId;

  @override
  ConsumerState<AlarmFallbackScreen> createState() =>
      _AlarmFallbackScreenState();
}

class _AlarmFallbackScreenState extends ConsumerState<AlarmFallbackScreen> {
  // Read in initState: `ref` is unusable in dispose.
  late final CoreBridge _bridge;
  late final AlarmFallbackClosedSignal _closedSignal;
  late final AppLifecycleListener _lifecycle;
  // Cancelled in _unfollow() and dispose (field cleared first).
  // ignore: cancel_subscriptions
  StreamSubscription<TripUpdateMsg>? _updates;
  TripConfigMsg? _config;
  TripStateMsg? _state;

  /// [_state] came from the stream after the last [_load] started: newer than
  /// the snapshot.
  bool _stateFresh = false;
  AlarmSettingsParams _params = AlarmSettingsParams.defaults;

  /// A Pigeon command is on its way (no double taps).
  bool _busy = false;
  bool _closing = false;

  /// "Xem đường quay lại" is stopping the alarm before going to screen 8.
  bool _routingBack = false;

  @override
  void initState() {
    super.initState();
    _bridge = ref.read(coreBridgeProvider);
    _closedSignal = ref.read(alarmFallbackClosedSignalProvider);
    // Review T27 #4 (D13): no updates while the app is not visible; back
    // in front, read the trip again (the ring may have ended meanwhile).
    _lifecycle = AppLifecycleListener(
      onStateChange: (s) {
        if (s == AppLifecycleState.resumed) {
          _follow();
          unawaited(_load());
        } else {
          _unfollow();
        }
      },
    );
    _follow();
    unawaited(_load());
  }

  void _follow() {
    _updates ??= _bridge.updates.listen(_onUpdate, onError: (Object _) {});
  }

  void _unfollow() {
    final updates = _updates;
    _updates = null;
    unawaited(updates?.cancel());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _unfollow();
    _closedSignal.notify();
    super.dispose();
  }

  /// Reads the running trip. Only "no trip" or another trip closes the
  /// screen; a failed read keeps it (review T27 #2: the safety net must not
  /// blink while the alarm sounds) and it follows the stream alone.
  Future<void> _load() async {
    _stateFresh = false;
    final ActiveTripMsg? trip;
    try {
      trip = await _bridge.currentTrip();
    } on BridgeException {
      return;
    } on Object catch (error, stack) {
      reportNonFatal('alarmFallback.currentTrip', error, stack);
      return;
    }
    if (!mounted) {
      return;
    }
    if (trip == null || trip.config.tripId != widget.tripId) {
      _close();
      return;
    }
    final state = _stateFresh ? _state! : trip.state;
    final config = trip.config;
    setState(() {
      _config = config;
      _params = AlarmSettingsParams.fromOverrideJson(config.engineParamsJson);
      _state = state;
    });
    _closeIfQuiet(state);
  }

  void _onUpdate(TripUpdateMsg update) {
    switch (update) {
      case TripStateUpdateMsg(:final state) when state.tripId == widget.tripId:
        _stateFresh = true;
        setState(() => _state = state);
        _closeIfQuiet(state);
      case TripEndedMsg(:final trip) when trip.tripId == widget.tripId:
        _close();
      default:
        break;
    }
  }

  void _closeIfQuiet(TripStateMsg state) {
    if (!ringingNow(state) || state.phase == TripPhaseMsg.snoozed) {
      _close();
    }
  }

  void _close() {
    if (_closing || _routingBack || !mounted) {
      return;
    }
    _closing = true;
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(AppRoutes.home);
    }
  }

  /// Runs [command] unless another one is on its way. A false answer or an
  /// error shows a SnackBar and returns false; unexpected errors are
  /// reported (type only).
  Future<bool> _send(_Command which, Future<bool> Function() command) async {
    if (_busy) {
      return false;
    }
    _busy = true;
    var ok = false;
    try {
      ok = await command();
    } on BridgeException {
      ok = false;
    } on Object catch (error, stack) {
      // Literal `where` per command (T29 R2-1).
      switch (which) {
        case _Command.dismiss:
          reportNonFatal('alarmFallback.dismiss', error, stack);
        case _Command.snooze:
          reportNonFatal('alarmFallback.snooze', error, stack);
        case _Command.openNative:
          reportNonFatal('alarmFallback.showAlarmScreen', error, stack);
      }
      ok = false;
    } finally {
      _busy = false;
    }
    if (!ok) {
      _failed();
    }
    return ok;
  }

  void _failed() {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).alarmActionFailed),
          persist: false,
          // Floats above the swipe bar: a retry must never wait for it.
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(
            NapSpace.alarmPage,
            0,
            NapSpace.alarmPage,
            _kSnackBarBottom,
          ),
        ),
      );
  }

  Future<bool> _dismiss() => _send(_Command.dismiss, () async {
    await _bridge.dismiss(widget.tripId);
    return true;
  });

  Future<void> _snooze() async {
    await _send(_Command.snooze, () async {
      await _bridge.snooze(widget.tripId);
      return true;
    });
  }

  Future<void> _openNative() async {
    await _send(
      _Command.openNative,
      () => _bridge.showAlarmScreen(widget.tripId),
    );
  }

  /// Stop, then screen 8 (`go`, D9). The end of the ring that follows the
  /// dismissal must not pop this screen first.
  Future<void> _routeBack() async {
    if (_busy) {
      return;
    }
    final router = GoRouter.of(context);
    final pastM = _state?.overshootPastM;
    _routingBack = true;
    final ok = await _dismiss();
    _routingBack = false;
    if (ok) {
      _closing = true;
      router.go(
        OvershootArgs(
          tripId: widget.tripId,
          pastM: pastM,
          autoOpen: true,
        ).toLocation(),
      );
    } else if (mounted && _state != null) {
      _closeIfQuiet(_state!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Theme(
      data: NapThemes.alarm(),
      child: PopScope<Object?>(
        // Back never closes the screen while the alarm sounds.
        canPop: false,
        child: Semantics(
          namesRoute: true,
          explicitChildNodes: true,
          label: l.appScreenAlarmTitle,
          child: Builder(builder: (context) => _body(context, l)),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l) {
    final c = context.napColors;
    // T28.3 D6: iOS has no app alarm screen to bring back (T17.2 D9).
    final nativeScreen = ref.watch(platformAlarmCapsProvider).nativeAlarmScreen;
    final text = context.napText;
    final state = _state;
    final config = _config;
    final overshoot =
        state != null && alarmVariant(state) == AlarmVariant.overshoot;
    final name = config?.destinationName ?? '';
    final destination = name.isEmpty ? l.notifDestinationUnknown : name;
    final pastM = state?.overshootPastM;
    final reason = state == null || config == null
        ? null
        : overshoot
        ? l.alarmReasonOvershoot(destination)
        : alarmReasonText(
            l,
            reason: state.alarmReason,
            destination: name,
            distanceM: state.distanceM,
            etaS: state.etaS,
            batteryPct: state.batteryPct,
          );
    final canSnooze =
        state != null && config != null && snoozeAllowed(state, _params);
    final accent = overshoot ? c.overshootAccent : c.alarmAccent;
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: NapSpace.alarmPage,
              vertical: NapSpace.s24,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 2 * NapSpace.s24,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: NapSpace.s16),
                      AlarmGlow(color: accent),
                      const SizedBox(height: NapSpace.s24),
                      Text(
                        (overshoot
                                ? l.alarmOverlineOvershoot
                                : l.alarmOverlineArriving)
                            .toUpperCase(),
                        textAlign: TextAlign.center,
                        style: context
                            .napStyle(NapTypography.alarmOverline)
                            .copyWith(
                              color: overshoot ? c.overshootLabel : accent,
                            ),
                      ),
                      const SizedBox(height: NapSpace.s12),
                      Semantics(
                        header: true,
                        child: Text(
                          destination,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: text.displaySmall,
                        ),
                      ),
                      if (reason != null) ...[
                        const SizedBox(height: NapSpace.s12),
                        Text(
                          reason,
                          textAlign: TextAlign.center,
                          style: text.bodyLarge?.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                      if (overshoot && pastM != null) ...[
                        const SizedBox(height: NapSpace.s8),
                        Text(
                          alarmPastText(l, pastM),
                          textAlign: TextAlign.center,
                          style: text.titleMedium,
                        ),
                      ],
                      const SizedBox(height: NapSpace.s16),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          nativeScreen
                              ? l.alarmFallbackNote
                              : l.alarmFallbackNoteIos,
                          textAlign: TextAlign.center,
                          style: text.bodyMedium?.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: NapSpace.s24),
                      if (overshoot) ...[
                        NapButton(
                          label: l.alarmRouteBack,
                          onPressed: () => unawaited(_routeBack()),
                        ),
                        const SizedBox(height: NapSpace.s12),
                      ],
                      if (canSnooze) ...[
                        NapButton(
                          label: snoozeLabel(l, _params.snoozeS),
                          variant: NapButtonVariant.secondary,
                          pill: true,
                          onPressed: () => unawaited(_snooze()),
                        ),
                        const SizedBox(height: NapSpace.s12),
                      ],
                      if (nativeScreen) ...[
                        NapButton(
                          label: l.alarmOpenAlarmScreen,
                          variant: NapButtonVariant.secondary,
                          onPressed: () => unawaited(_openNative()),
                        ),
                        const SizedBox(height: NapSpace.s16),
                      ] else
                        const SizedBox(height: NapSpace.s16),
                      SwipeToStopBar(
                        hint: l.alarmSwipeHint,
                        semanticsLabel: l.alarmStopA11y,
                        onComplete: _dismiss,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pigeon commands of the screen.
enum _Command { dismiss, snooze, openNative }

/// Bottom margin of the SnackBar: above the swipe bar (72 + page padding).
const double _kSnackBarBottom = 120;
