import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:napstop/app/router/app_router.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/core/diagnostics/report_error.dart';
import 'package:napstop/features/alarm/domain/ring_ui_policy.dart';
import 'package:napstop/features/alarm/domain/ring_ui_rules.dart';
import 'package:napstop/features/alarm/domain/route_back.dart';
import 'package:napstop/features/alarm/presentation/alarm_fallback_screen.dart';

/// The Flutter side of the native alarm screens (T27 §6), above the router
/// (`MaterialApp.router(builder:)`):
/// - reads the launch action of "Xem đường quay lại" after the first frame
///   and on every resume (D4) → screen 8 with `go` (D9);
/// - only while the app is `resumed` (D13), follows the trip updates and
///   runs [reduceRingUi]: never pushes a screen because an alarm started
///   (T16 D8), only the fallback of screen 5 when the native screen did not
///   cover the app (D1).
class AlarmUiCoordinator extends ConsumerStatefulWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AlarmUiCoordinator> createState() => _AlarmUiCoordinatorState();
}

class _AlarmUiCoordinatorState extends ConsumerState<AlarmUiCoordinator> {
  late final CoreBridge _bridge = ref.read(coreBridgeProvider);
  late final AlarmFallbackClosedSignal _fallbackClosed = ref.read(
    alarmFallbackClosedSignalProvider,
  );
  late final AppLifecycleListener _lifecycle;
  RingUiState _ui = const RingUiState();
  Timer? _grace;
  // Cancelled in _unwatch() (field cleared before the cancel).
  // ignore: cancel_subscriptions
  StreamSubscription<TripUpdateMsg>? _updates;

  /// Bumped on every watch/unwatch: a late `currentTrip()` answer of an
  /// older watch is dropped.
  int _watchSeq = 0;

  /// An update has arrived since the current watch started: the snapshot
  /// read at the start is older and is dropped.
  bool _sawUpdate = false;
  bool _resumed = false;
  bool _launchInFlight = false;
  bool _launchAgain = false;

  @override
  void initState() {
    super.initState();
    _fallbackClosed.addListener(_onFallbackClosed);
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final state = WidgetsBinding.instance.lifecycleState;
      if (state == null || state == AppLifecycleState.resumed) {
        _onResumed();
      } else {
        unawaited(_consumeLaunch());
      }
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _fallbackClosed.removeListener(_onFallbackClosed);
    _unwatch();
    super.dispose();
  }

  void _onLifecycle(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onResumed();
    } else {
      _onLeft();
    }
  }

  void _onResumed() {
    if (_resumed) {
      return;
    }
    _resumed = true;
    unawaited(_consumeLaunch());
    _apply(const LifecycleChanged(resumed: true));
    _watch();
  }

  void _onLeft() {
    if (!_resumed) {
      return;
    }
    _resumed = false;
    _apply(const LifecycleChanged(resumed: false));
    _unwatch();
  }

  // ---------------------------------------------------------- launch action

  /// One call in flight; a resume during it reads the slot once more after.
  Future<void> _consumeLaunch() async {
    if (_launchInFlight) {
      _launchAgain = true;
      return;
    }
    _launchInFlight = true;
    try {
      do {
        _launchAgain = false;
        LaunchActionMsg? action;
        try {
          action = await _bridge.consumeLaunchAction();
        } on BridgeException {
          action = null;
        } on Object catch (error, stack) {
          reportNonFatal('alarmUi.launch', error, stack);
          action = null;
        }
        if (!mounted) {
          return;
        }
        if (action != null &&
            action.kind == LaunchActionKindMsg.overshootRoute &&
            isValidTripId(action.tripId)) {
          final past = action.pastM;
          _router.go(
            OvershootArgs(
              tripId: action.tripId,
              pastM: past != null && past >= 0 && past <= kOvershootPastMax
                  ? past
                  : null,
              autoOpen: true,
            ).toLocation(),
          );
        }
      } while (_launchAgain && mounted);
    } finally {
      _launchInFlight = false;
    }
  }

  GoRouter get _router => ref.read(appRouterProvider);

  // ---------------------------------------------------------- ringing

  void _watch() {
    final seq = ++_watchSeq;
    _sawUpdate = false;
    _updates ??= _bridge.updates.listen(
      _onUpdate,
      // A broken update channel never breaks the app.
      onError: (Object _) {},
    );
    unawaited(_readSnapshot(seq));
  }

  void _unwatch() {
    _watchSeq++;
    final updates = _updates;
    _updates = null;
    unawaited(updates?.cancel());
    _grace?.cancel();
    _grace = null;
  }

  Future<void> _readSnapshot(int seq) async {
    ActiveTripMsg? trip;
    try {
      trip = await _bridge.currentTrip();
    } on BridgeException {
      trip = null;
    } on Object catch (error, stack) {
      reportNonFatal('alarmUi.currentTrip', error, stack);
      trip = null;
    }
    if (!mounted || seq != _watchSeq || _sawUpdate) {
      return;
    }
    _apply(StateSeen(trip?.state));
  }

  void _onUpdate(TripUpdateMsg update) {
    switch (update) {
      case TripStateUpdateMsg(:final state):
        _sawUpdate = true;
        _apply(StateSeen(state));
      case TripEndedMsg(:final trip) when trip.tripId == _ui.ringingTripId:
        _sawUpdate = true;
        _apply(const StateSeen(null));
      default:
        break;
    }
  }

  void _onFallbackClosed() => _apply(const FallbackClosed());

  void _apply(RingUiInput input) {
    if (!mounted) {
      return;
    }
    final (next, effects) = reduceRingUi(_ui, input);
    _ui = next;
    effects.forEach(_run);
  }

  void _run(RingUiEffect effect) {
    switch (effect) {
      case StartGrace(:final tripId, :final generation):
        _grace?.cancel();
        _grace = Timer(
          kRingUiGrace,
          () => _apply(GraceElapsed(tripId, generation)),
        );
      case CancelGrace():
        _grace?.cancel();
        _grace = null;
      case AskNative(:final tripId, :final generation):
        unawaited(_askNative(tripId, generation));
      case PushFallback(:final tripId):
        if (_router.state.matchedLocation != AppRoutes.alarm) {
          unawaited(_router.push<void>(alarmFallbackLocation(tripId)));
        }
    }
  }

  Future<void> _askNative(String tripId, int generation) async {
    var shown = false;
    try {
      shown = await _bridge.showAlarmScreen(tripId);
    } on BridgeException {
      shown = false;
    } on Object catch (error, stack) {
      reportNonFatal('alarmUi.showAlarmScreen', error, stack);
      shown = false;
    }
    _apply(NativeAnswered(tripId, generation, shown: shown));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
