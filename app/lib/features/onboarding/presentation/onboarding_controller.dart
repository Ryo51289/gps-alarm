import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/core/device/device_providers.dart';
import 'package:napstop/features/battery_guide/data/battery_guide_providers.dart';
import 'package:napstop/features/battery_guide/domain/battery_guide.dart';
import 'package:napstop/features/onboarding/domain/onboarding_items.dart';
import 'package:napstop/features/onboarding/domain/start_check.dart';

/// State of screen 0 (T21 §7.4).
@immutable
final class OnboardingState {
  const new({
    required this.status,
    required this.device,
    required this.items,
    required this.check,
    required this.busy,
  });

  final PermissionStatusMsg status;
  final DeviceInfoMsg device;
  final List<OnboardingItem> items;
  final StartCheck check;

  /// A request / openSettings is running: every row button is disabled.
  final bool busy;

  OnboardingState withBusy({required bool value}) => OnboardingState(
    status: status,
    device: device,
    items: items,
    check: check,
    busy: value,
  );
}

/// Result of [OnboardingController.act], for the screen's snack bars.
enum OnboardingOutcome { done, settingsUnavailable, requestFailed, ignored }

/// State of screen 0. autoDispose: a new visit starts with an empty sticky
/// set (D12).
final AsyncNotifierProvider<OnboardingController, OnboardingState>
onboardingControllerProvider =
    AsyncNotifierProvider.autoDispose<OnboardingController, OnboardingState>(
      OnboardingController.new,
    );

final class OnboardingController extends AsyncNotifier<OnboardingState> {
  /// Optional rows already shown during this visit (D12).
  final Set<OnboardingItemKind> _sticky = {};

  CoreBridge get _bridge => ref.read(coreBridgeProvider);

  @override
  Future<OnboardingState> build() async {
    final bridge = ref.watch(coreBridgeProvider);
    final results = await Future.wait<Object>([
      bridge.permissionStatus(),
      ref.watch(deviceInfoProvider.future),
    ]);
    return _stateOf(
      results[0] as PermissionStatusMsg,
      results[1] as DeviceInfoMsg,
      busy: false,
    );
  }

  OnboardingState _stateOf(
    PermissionStatusMsg status,
    DeviceInfoMsg device, {
    required bool busy,
  }) {
    final items = buildOnboardingItems(status, device, sticky: _sticky);
    _sticky.addAll(kindsOf(items));
    return OnboardingState(
      status: status,
      device: device,
      items: items,
      check: checkStart(status, device),
      busy: busy,
    );
  }

  /// Reads `permissionStatus()` again (resume, "Thử lại"). From the error
  /// state it rebuilds; otherwise a failure shows the error state.
  Future<void> refresh() async {
    final current = state.value;
    if (current == null || state.hasError) {
      // A failed deviceInfo() is kept for the session: read it again too
      // (review T21 #5), like screens 1 and 9.
      if (ref.read(deviceInfoProvider).hasError) {
        ref.invalidate(deviceInfoProvider);
      }
      ref.invalidateSelf();
      return;
    }
    try {
      final status = await _bridge.permissionStatus();
      if (!ref.mounted) {
        return;
      }
      state = AsyncData(
        _stateOf(status, current.device, busy: state.value?.busy ?? false),
      );
    } on Object catch (e, st) {
      if (ref.mounted) {
        state = AsyncError(e, st);
      }
    }
  }

  /// Runs [item]'s request or settings page (the screen shows the
  /// explainer sheet first). Ignored while another action runs.
  Future<OnboardingOutcome> act(OnboardingItem item) async {
    final current = state.value;
    if (current == null || current.busy) {
      return OnboardingOutcome.ignored;
    }
    state = AsyncData(current.withBusy(value: true));
    try {
      final kind = item.request;
      if (kind != null) {
        return await _request(kind, current.device);
      }
      final target = item.settings;
      if (target != null) {
        try {
          final opened = await _bridge.openSettings(target);
          // Opened: the screen refreshes on resume.
          return opened
              ? OnboardingOutcome.done
              : OnboardingOutcome.settingsUnavailable;
        } on Object {
          return OnboardingOutcome.settingsUnavailable;
        }
      }
      return OnboardingOutcome.ignored;
    } finally {
      final latest = state.value;
      if (ref.mounted && latest != null) {
        state = AsyncData(latest.withBusy(value: false));
      }
    }
  }

  Future<OnboardingOutcome> _request(
    PermissionKindMsg kind,
    DeviceInfoMsg device,
  ) async {
    try {
      final status = await _bridge.requestPermission(kind);
      if (ref.mounted) {
        state = AsyncData(_stateOf(status, device, busy: true));
      }
      return OnboardingOutcome.done;
    } on BridgeException catch (e) {
      if (e.code == BridgeErrorCode.requestInProgress) {
        return OnboardingOutcome.ignored;
      }
    } on Object {
      // Below.
    }
    await _rereadQuietly(device);
    return OnboardingOutcome.requestFailed;
  }

  /// After a failed request: the status may have changed anyway.
  Future<void> _rereadQuietly(DeviceInfoMsg device) async {
    try {
      final status = await _bridge.permissionStatus();
      if (ref.mounted) {
        state = AsyncData(_stateOf(status, device, busy: true));
      }
    } on Object {
      // Keep the previous rows.
    }
  }
}

/// The battery card of screen 0 (Android). While the guides load, or when
/// they fail, the generic card (no brand, no step count).
final Provider<BatteryCardModel?> onboardingBatteryCardProvider =
    Provider.autoDispose<BatteryCardModel?>((ref) {
      final state = ref.watch(onboardingControllerProvider).value;
      if (state == null) {
        return null;
      }
      final catalog = ref.watch(batteryGuideCatalogProvider).value;
      final guide = catalog == null
          ? const BatteryGuide(
              id: kGenericGuideId,
              labelKey: null,
              manufacturers: [],
              brands: [],
              steps: [],
            )
          : matchGuide(catalog, state.device);
      return buildBatteryCard(state.status, state.device, guide);
    });
