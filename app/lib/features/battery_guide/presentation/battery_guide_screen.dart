import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:napstop/app/clock.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/device/device_providers.dart';
import 'package:napstop/features/battery_guide/data/battery_guide_providers.dart';
import 'package:napstop/features/battery_guide/domain/background_check.dart';
import 'package:napstop/features/battery_guide/domain/battery_guide.dart';
import 'package:napstop/features/battery_guide/presentation/widgets/brand_chips.dart';
import 'package:napstop/features/battery_guide/presentation/widgets/check_view.dart';
import 'package:napstop/features/battery_guide/presentation/widgets/step_view.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Phase of screen 9 (T21 §8.2).
sealed class _Phase {
  const new();
}

final class _Loading extends _Phase {
  const new();
}

final class _Step extends _Phase {
  const new(this.index);
  final int index;
}

final class _Done extends _Phase {
  const new();
}

final class _Running extends _Phase {
  const new(this.record);
  final BackgroundCheckMsg record;
}

final class _Result extends _Phase {
  const new(this.result);
  final BackgroundCheckResult result;
}

/// Screen 9 "Hướng dẫn pin theo hãng" (T21 §8): brand detected from the
/// device, 1-3 steps from data, then a 30 second background check.
class BatteryGuideScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<BatteryGuideScreen> createState() => _BatteryGuideScreenState();
}

class _BatteryGuideScreenState extends ConsumerState<BatteryGuideScreen> {
  late final AppLifecycleListener _lifecycle;
  late final CoreBridge _bridge;
  late final DateTime Function() _clock;
  Timer? _ticker;
  bool _polling = false;

  /// startBackgroundCheck() sent, no answer yet (review T21 #4).
  Future<BackgroundCheckMsg>? _pendingStart;

  _Phase _phase = const _Loading();

  /// Chip chosen by the user; null = the detected guide.
  String? _chosenId;

  @override
  void initState() {
    super.initState();
    // Read once: dispose() still needs the bridge to cancel a running check.
    _bridge = ref.read(coreBridgeProvider);
    _clock = ref.read(clockProvider);
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    unawaited(_restore());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _lifecycle.dispose();
    // No surprise vibration after leaving. T29: battery_guide_test cancelled.
    final pending = _pendingStart;
    if (pending != null) {
      // Cancel once the alarm is set, not before: both run off the main
      // thread and could overtake each other.
      unawaited(
        pending
            .then((_) => _bridge.cancelBackgroundCheck())
            .catchError((Object _) {}),
      );
    } else if (_phase is _Running) {
      unawaited(_bridge.cancelBackgroundCheck().catchError((Object _) {}));
    }
    super.dispose();
  }

  int get _nowMs => _clock().millisecondsSinceEpoch;

  /// Opening the screen: a recent check shows its state, else step 1.
  Future<void> _restore() async {
    BackgroundCheckMsg? record;
    try {
      record = await _bridge.backgroundCheck();
    } on Object {
      record = null;
    }
    if (!mounted) {
      return;
    }
    _apply(evaluateBackgroundCheck(record, _nowMs), record);
  }

  /// [r] null (no recent check): step 1.
  void _apply(BackgroundCheckResult? r, BackgroundCheckMsg? record) {
    final _Phase next;
    if (r == null) {
      next = const _Step(0);
    } else if (r.verdict == BackgroundCheckVerdict.running && record != null) {
      next = _Running(record);
    } else {
      // T29: battery_guide_test (oemTelemetryId,
      // backgroundCheckTelemetryResult).
      next = _Result(r);
    }
    setState(() => _phase = next);
    if (next is _Running) {
      _startTicker();
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void _onTick() {
    final phase = _phase;
    if (!mounted || phase is! _Running) {
      return;
    }
    if (_nowMs >= phase.record.dueAtMs) {
      unawaited(_poll());
    } else {
      setState(() {});
    }
  }

  void _onResume() {
    if (_phase is _Running) {
      unawaited(_poll());
    }
  }

  /// Reads the record again while running.
  Future<void> _poll() async {
    if (_polling) {
      return;
    }
    _polling = true;
    try {
      final record = await _bridge.backgroundCheck();
      final phase = _phase;
      if (!mounted || phase is! _Running) {
        return;
      }
      final current = record ?? phase.record;
      final r = evaluateBackgroundCheck(current, _nowMs);
      if (r == null || r.verdict == BackgroundCheckVerdict.running) {
        setState(() => _phase = _Running(current));
      } else {
        _apply(r, current);
      }
    } on Object {
      // Next tick tries again.
    } finally {
      _polling = false;
    }
  }

  Future<void> _start() async {
    if (_pendingStart != null) {
      return;
    }
    final failed = AppLocalizations.of(context).batteryGuideTestStartFailed;
    final pending = _bridge.startBackgroundCheck(kBackgroundCheckDelay);
    _pendingStart = pending;
    try {
      final record = await pending;
      _pendingStart = null;
      if (!mounted) {
        return;
      }
      setState(() => _phase = _Running(record));
      _startTicker();
    } on Object {
      _pendingStart = null;
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failed), persist: false));
    }
  }

  Future<void> _cancel() async {
    _ticker?.cancel();
    _ticker = null;
    setState(() => _phase = const _Done());
    // T29: battery_guide_test cancelled.
    try {
      await _bridge.cancelBackgroundCheck();
    } on Object {
      // The alarm may still vibrate once; nothing else to do.
    }
  }

  Future<void> _openSettings(GuideSettings settings) async {
    final target = settings.target;
    if (target == null) {
      return;
    }
    final unavailable = AppLocalizations.of(context)
        .onboardingSettingsUnavailable;
    bool opened;
    try {
      opened = await _bridge.openSettings(target);
    } on Object {
      opened = false;
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(unavailable), persist: false));
    }
  }

  void _next(BatteryGuide guide, int index) => setState(
    () => _phase = index + 1 < guide.steps.length
        ? _Step(index + 1)
        : const _Done(),
  );

  void _choose(String id) => setState(() {
    _chosenId = id;
    _phase = const _Step(0);
  });

  void _review() => setState(() => _phase = const _Step(0));

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final device = ref.watch(deviceInfoProvider);
    final catalog = ref.watch(batteryGuideCatalogProvider);
    final header = Padding(
      padding: const EdgeInsets.symmetric(horizontal: NapSpace.page),
      child: NapScreenHeader(
        title: l.batteryGuideTitle,
        onBack: () => context.pop(),
      ),
    );
    final Widget body;
    final Widget? bottom;
    final deviceValue = device.value;
    final catalogValue = catalog.value;
    if (deviceValue?.platform == PlatformMsg.ios) {
      body = _padded(Text(l.batteryGuideIosNotNeeded));
      bottom = null;
    } else if (catalog.hasError || device.hasError) {
      body = _padded(
        NapBanner(
          message: l.batteryGuideError,
          action: NapButton(
            label: l.commonRetry,
            onPressed: () => ref
              ..invalidate(batteryGuideCatalogProvider)
              ..invalidate(deviceInfoProvider),
            variant: NapButtonVariant.secondary,
            size: NapButtonSize.small,
          ),
        ),
      );
      bottom = null;
    } else if (catalogValue == null ||
        deviceValue == null ||
        _phase is _Loading) {
      body = const SizedBox.shrink();
      bottom = null;
    } else {
      final detected = matchGuide(catalogValue, deviceValue);
      final guide = catalogValue.byId(_chosenId ?? detected.id) ?? detected;
      (body, bottom) = _content(context, catalogValue, detected, guide);
    }
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Expanded(child: body),
            if (bottom != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  NapSpace.page,
                  NapSpace.s12,
                  NapSpace.page,
                  NapSpace.s28,
                ),
                child: bottom,
              ),
          ],
        ),
      ),
    );
  }

  Widget _padded(Widget child) => SingleChildScrollView(
    padding: const EdgeInsets.all(NapSpace.page),
    child: child,
  );

  (Widget, Widget) _content(
    BuildContext context,
    BatteryGuideCatalog catalog,
    BatteryGuide detected,
    BatteryGuide guide,
  ) {
    final l = AppLocalizations.of(context);
    final c = context.napColors;
    final phase = _phase;
    final n = guide.steps.length;
    final running = phase is _Running;
    final Widget main;
    final List<Widget> buttons;
    switch (phase) {
      case _Step(:final index):
        final step = guide.steps[index.clamp(0, n - 1)];
        main = StepContent(guide: guide, index: index.clamp(0, n - 1));
        buttons = [
          if (step.settings != GuideSettings.none)
            NapButton(
              label: l.batteryGuideOpenSettings,
              variant: NapButtonVariant.secondary,
              onPressed: () => unawaited(_openSettings(step.settings)),
            ),
          NapButton(
            label: l.batteryGuideStepDone,
            onPressed: () => _next(guide, index),
          ),
        ];
      case _Done() || _Loading():
        main = CheckIntro(steps: n);
        buttons = [
          NapButton(
            label: l.batteryGuideTestStart,
            onPressed: () => unawaited(_start()),
          ),
          NapButton(
            label: l.batteryGuideReview,
            variant: NapButtonVariant.text,
            onPressed: _review,
          ),
        ];
      case _Running(:final record):
        main = CheckRunning(
          remaining: Duration(milliseconds: record.dueAtMs - _nowMs),
        );
        buttons = [
          NapButton(
            label: l.batteryGuideTestCancel,
            variant: NapButtonVariant.secondary,
            onPressed: () => unawaited(_cancel()),
          ),
        ];
      case _Result(:final result):
        main = CheckResultBanner(result: result);
        buttons = result.verdict == BackgroundCheckVerdict.passed
            ? [NapButton(label: l.commonDone, onPressed: () => context.pop())]
            : [
                NapButton(
                  label: l.commonRetry,
                  onPressed: () => unawaited(_start()),
                ),
                NapButton(
                  label: l.batteryGuideReview,
                  variant: NapButtonVariant.text,
                  onPressed: _review,
                ),
              ];
    }
    final current = phase is _Step ? phase.index : n;
    final body = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        NapSpace.page,
        NapSpace.s8,
        NapSpace.page,
        NapSpace.s16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: NapSpace.s18,
        children: [
          Text(
            detected.isGeneric
                ? l.batteryGuidePickBrand
                : l.batteryGuideDetected,
            style: context.napText.bodySmall!.copyWith(color: c.textSecondary),
          ),
          BrandChips(
            catalog: catalog,
            ids: guideChips(catalog, detected),
            selectedId: guide.id,
            onSelect: running ? null : _choose,
          ),
          StepProgress(steps: n, current: current),
          main,
        ],
      ),
    );
    return (
      body,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: NapSpace.s8,
        children: buttons,
      ),
    );
  }
}
