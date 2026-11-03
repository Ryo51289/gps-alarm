// T21 I01-I03 over the real PermissionHostApi (Android emulator/device,
// flavor dev). The host changes the device state with adb between steps; the
// test prints `T21> <step>` and then polls the bridge until the state shows
// up (or times out). Host commands: docs/test-protocols/T21.md, Part A.
//
//   adb uninstall app.napstop.dev   # fresh permission state
//   flutter test integration_test/permissions_t21_test.dart -d <device-id>
//
// Run only one part with --plain-name I01 / I02 / I03.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:napstop/core/bridge/core_bridge.dart';

const Duration _poll = Duration(milliseconds: 500);
const Duration _stepTimeout = Duration(seconds: 90);

void _say(String line) {
  // The host script waits for these lines (no coordinates are printed).
  debugPrint('T21> $line');
}

String _describe(PermissionStatusMsg s) =>
    'location=${s.location.name} precise=${s.precise.name} '
    'services=${s.locationServicesEnabled} '
    'notifications=${s.notifications.name} fsi=${s.fullScreenIntent.name} '
    'exact=${s.exactAlarm.name} battery=${s.batteryOptimizationIgnored.name} '
    'alarmKit=${s.alarmKit.name}';

void _invariants(PermissionStatusMsg s) {
  // T21 D2 / review T22 #9 / ADR-001.
  expect(s.precise, isNot(PermissionStateMsg.notApplicable));
  expect(s.location, isNot(LocationAccessMsg.always));
  expect(s.alarmKit, PermissionStateMsg.notApplicable);
  for (final v in [
    s.notifications,
    s.fullScreenIntent,
    s.exactAlarm,
    s.batteryOptimizationIgnored,
  ]) {
    expect(v, isNot(PermissionStateMsg.notApplicable));
  }
}

/// Announces [step] and polls status() until [ready] holds.
Future<PermissionStatusMsg> _step(
  CoreBridge bridge,
  String step,
  bool Function(PermissionStatusMsg s) ready,
) async {
  _say('STEP $step');
  final deadline = DateTime.now().add(_stepTimeout);
  PermissionStatusMsg s;
  do {
    s = await bridge.permissionStatus();
    _invariants(s);
    if (ready(s)) {
      _say('OK $step: ${_describe(s)}');
      return s;
    }
    await Future<void>.delayed(_poll);
  } while (DateTime.now().isBefore(deadline));
  _say('TIMEOUT $step: ${_describe(s)}');
  fail('step "$step" not reached: ${_describe(s)}');
}

Future<void> _waitResumedAfterPause() async {
  final binding = WidgetsBinding.instance;
  final deadline = DateTime.now().add(_stepTimeout);
  var paused = false;
  while (DateTime.now().isBefore(deadline)) {
    final state = binding.lifecycleState;
    if (state != AppLifecycleState.resumed) {
      paused = true;
    } else if (paused) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail('app did not come back (paused=$paused)');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('I01 status() follows the device state', () async {
    final bridge = CoreBridge();
    final sdk = (await bridge.deviceInfo()).androidSdkInt ?? 0;
    _say('SDK $sdk');

    // Fresh install: nothing asked yet.
    final fresh = await _step(
      bridge,
      'fresh',
      (s) => s.location == LocationAccessMsg.notDetermined,
    );
    expect(fresh.precise, PermissionStateMsg.notDetermined);
    if (sdk >= 33) {
      expect(fresh.notifications, PermissionStateMsg.notDetermined);
    }
    // R4: USE_EXACT_ALARM makes canScheduleExactAlarms() true on API 34.
    expect(fresh.exactAlarm, PermissionStateMsg.granted);

    // host: pm grant ACCESS_COARSE_LOCATION
    final coarse = await _step(
      bridge,
      'coarse',
      (s) => s.location == LocationAccessMsg.whileInUse,
    );
    // API 31+: one upgrade dialog allowed; below, only Settings (§4.2).
    expect(
      coarse.precise,
      sdk >= 31 ? PermissionStateMsg.notDetermined : PermissionStateMsg.denied,
    );

    // host: pm grant ACCESS_FINE_LOCATION
    await _step(bridge, 'fine', (s) => s.precise == PermissionStateMsg.granted);

    // host: cmd location set-location-enabled false
    await _step(bridge, 'servicesOff', (s) => !s.locationServicesEnabled);
    // host: cmd location set-location-enabled true
    await _step(bridge, 'servicesOn', (s) => s.locationServicesEnabled);

    if (sdk >= 34) {
      // host: appops set app.napstop.dev USE_FULL_SCREEN_INTENT deny
      await _step(
        bridge,
        'fsiDenied',
        (s) => s.fullScreenIntent == PermissionStateMsg.denied,
      );
      // host: appops set app.napstop.dev USE_FULL_SCREEN_INTENT allow
      await _step(
        bridge,
        'fsiAllowed',
        (s) => s.fullScreenIntent == PermissionStateMsg.granted,
      );
    } else {
      expect(fresh.fullScreenIntent, PermissionStateMsg.granted);
    }

    // host: appops set app.napstop.dev SCHEDULE_EXACT_ALARM deny (no effect
    // expected on 33+: USE_EXACT_ALARM cannot be revoked).
    final exact = await _step(bridge, 'exactAppopDenied', (s) => true);
    if (sdk >= 33 || sdk < 31) {
      expect(exact.exactAlarm, PermissionStateMsg.granted);
    }

    // host: dumpsys deviceidle whitelist +app.napstop.dev
    await _step(
      bridge,
      'batteryWhitelisted',
      (s) => s.batteryOptimizationIgnored == PermissionStateMsg.granted,
    );
    // host: dumpsys deviceidle whitelist -app.napstop.dev
    await _step(
      bridge,
      'batteryOptimized',
      (s) => s.batteryOptimizationIgnored == PermissionStateMsg.denied,
    );

    if (sdk >= 33) {
      // host: pm grant POST_NOTIFICATIONS
      await _step(
        bridge,
        'notificationsGranted',
        (s) => s.notifications == PermissionStateMsg.granted,
      );
    }
    _say('DONE I01');
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('I02 openSettings opens a page for every applicable target', () async {
    final bridge = CoreBridge();
    final sdk = (await bridge.deviceInfo()).androidSdkInt ?? 0;
    for (final target in SettingsTargetMsg.values) {
      // FSI below 34 and exact alarms below 31 are not applicable (§4.4).
      final applicable =
          !(target == SettingsTargetMsg.fullScreenIntent && sdk < 34) &&
          !(target == SettingsTargetMsg.exactAlarm && sdk < 31);
      final opened = await bridge.openSettings(target);
      _say('OPENED ${target.name} $opened');
      expect(opened, applicable, reason: target.name);
      if (opened) {
        // host: records the top activity + screenshot, then presses BACK.
        await _waitResumedAfterPause();
      }
    }
    _say('DONE I02');
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('I03 the 30 s check fires while locked, exact, once', () async {
    final bridge = CoreBridge();
    await bridge.cancelBackgroundCheck();
    expect(await bridge.backgroundCheck(), isNull);

    // (a) Start then cancel: the alarm must not fire.
    final cancelled = await bridge.startBackgroundCheck(
      const Duration(seconds: 5),
    );
    await bridge.cancelBackgroundCheck();
    _say('CANCELLED scheduledAt=${cancelled.scheduledAtMs}');
    await Future<void>.delayed(const Duration(seconds: 10));
    expect(await bridge.backgroundCheck(), isNull);

    // (b) Two starts in a row: the second replaces the first.
    final first = await bridge.startBackgroundCheck(
      const Duration(seconds: 30),
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    final m = await bridge.startBackgroundCheck(const Duration(seconds: 30));
    expect(m.scheduledAtMs, greaterThan(first.scheduledAtMs));
    expect(m.dueAtMs - m.scheduledAtMs, 30000);
    expect(m.exact, isTrue);
    expect(m.firedAtMs, isNull);
    _say('STARTED due=${m.dueAtMs}');
    // host: input keyevent KEYCODE_SLEEP now; KEYCODE_WAKEUP after ~40 s.

    final deadline = DateTime.now().add(const Duration(seconds: 120));
    BackgroundCheckMsg? r;
    do {
      await Future<void>.delayed(const Duration(seconds: 1));
      r = await bridge.backgroundCheck();
    } while (r?.firedAtMs == null && DateTime.now().isBefore(deadline));
    expect(r, isNotNull);
    final fired = r!.firedAtMs;
    _say(
      'FIRED lateMs=${fired == null ? null : fired - r.dueAtMs} '
      'screenOn=${r.screenOnAtFire} exact=${r.exact}',
    );
    expect(fired, isNotNull);
    expect(r.scheduledAtMs, m.scheduledAtMs);
    expect(fired! - r.dueAtMs, inInclusiveRange(0, 15000));
    expect(r.screenOnAtFire, isFalse);
    expect(r.exact, isTrue);

    // Stays fired (no second fire rewrites it).
    await Future<void>.delayed(const Duration(seconds: 35));
    final again = await bridge.backgroundCheck();
    expect(again!.firedAtMs, fired);
    await bridge.cancelBackgroundCheck();
    _say('DONE I03');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
