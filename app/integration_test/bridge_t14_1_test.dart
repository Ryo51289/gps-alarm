// Tester additions for T14.1 over the real platform channels (Android
// emulator/device, flavor dev): V11 on `engineParamsJson` checked by the
// native validator, the value kept verbatim by the stub, and a live
// PermissionHostApi.deviceStatus() read.
//
//   flutter test integration_test/bridge_t14_1_test.dart -d <device-id>
//
// Optional expectations for deviceStatus(), set them after changing the device
// state with adb (docs/test-protocols/T14.1.md):
//   --dart-define=T141_FILTER=all|priority|alarms|none
//   --dart-define=T141_BATTERY=<0..100>
//   --dart-define=T141_CHARGING=true|false|null
//   --dart-define=T141_VOLUME=<0..100>
//   --dart-define=T141_MUTED=true|false
//   --dart-define=T141_ALLOWS_ALARMS=true|false|null
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:napstop/core/bridge/core_bridge.dart';

const _filter = String.fromEnvironment('T141_FILTER');
const _battery = String.fromEnvironment('T141_BATTERY');
const _charging = String.fromEnvironment('T141_CHARGING');
const _volume = String.fromEnvironment('T141_VOLUME');
const _muted = String.fromEnvironment('T141_MUTED');
const _allowsAlarms = String.fromEnvironment('T141_ALLOWS_ALARMS');

/// V11 limit (T14.1, T29 kEngineParamsMaxChars), UTF-16 code units.
const _max = 16384;

TripConfigMsg _config(String tripId, {String? engineParamsJson}) =>
    TripConfigMsg(
      tripId: tripId,
      destinationName: 'Ga Đông Hà',
      mode: AlarmModeMsg.smart,
      preAlertEnabled: true,
      vehicleHint: VehicleKindMsg.train,
      alarm: AlarmSettingsMsg(
        soundId: 'default',
        volume: 0.8,
        rampUp: true,
        vibration: VibrationMsg.medium,
        flash: false,
        preferHeadphones: false,
        dismissMethod: DismissMethodMsg.swipe,
      ),
      engineParamsJson: engineParamsJson,
    );

/// Exactly [length] UTF-16 code units, with every character the stub
/// snapshot (java.util.Properties) has to escape, Vietnamese and emoji.
String _awkwardJson(int length) {
  const head =
      '{"note": "Ga Đông Hà = a:b #c !d \\\\e\\n\\t \u{1F634}", '
      '"smartTargetS": 60.0, "pad": "';
  const tail = '"}\n';
  final pad = length - head.length - tail.length;
  final s = '$head${'x' * pad}$tail';
  assert(s.length == length, 'length');
  return s;
}

Future<void> _cleanSlate(CoreBridge bridge) async {
  final leftover = await bridge.currentTrip();
  if (leftover != null) {
    await bridge.stopTrip(leftover.config.tripId);
  }
  final old = await bridge.pendingFinishedTrips();
  await bridge.ackFinishedTrips([for (final t in old) t.tripId]);
}

Future<BridgeException> _failure(Future<Object?> call) async {
  try {
    await call;
  } on BridgeException catch (e) {
    return e;
  }
  fail('expected BridgeException');
}

String _id(String prefix) => '$prefix-${DateTime.now().millisecondsSinceEpoch}';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final bridge = CoreBridge();

  testWidgets('V11 through the native validator', (tester) async {
    await _cleanSlate(bridge);

    // 16 385 code units: rejected, nothing started.
    for (final tooLong in [
      'x' * (_max + 1),
      // 8 192 emoji = 16 384 code units, plus one.
      '${'\u{1F634}' * (_max ~/ 2)}x',
      _awkwardJson(_max + 1),
    ]) {
      expect(tooLong.length, _max + 1);
      final e = await _failure(
        bridge.startTrip(
          _config(_id('v11'), engineParamsJson: tooLong),
          destLat: 16.8163,
          destLng: 107.1003,
        ),
      );
      expect(e.code, BridgeErrorCode.invalidConfig);
      expect(e.message, 'engineParamsJson: too long');
      expect(await bridge.currentTrip(), isNull);
    }

    // 16 384 code units: accepted and handed back verbatim.
    final params = _awkwardJson(_max);
    final tripId = _id('v11ok');
    await bridge.startTrip(
      _config(tripId, engineParamsJson: params),
      destLat: 16.8163,
      destLng: 107.1003,
    );
    final active = await bridge.currentTrip();
    expect(active, isNotNull);
    expect(active!.config.tripId, tripId);
    expect(active.config.engineParamsJson, params);

    // While a trip runs: V11 is reported before trip-active (spec T14.1).
    final order = await _failure(
      bridge.startTrip(
        _config(_id('v11b'), engineParamsJson: 'x' * (_max + 1)),
        destLat: 16.8163,
        destLng: 107.1003,
      ),
    );
    expect(order.code, BridgeErrorCode.invalidConfig);
    final active2 = await _failure(
      bridge.startTrip(
        _config(_id('v11c'), engineParamsJson: 'x' * _max),
        destLat: 16.8163,
        destLng: 107.1003,
      ),
    );
    expect(active2.code, BridgeErrorCode.tripActive);
    expect((await bridge.currentTrip())!.config.tripId, tripId);

    await bridge.stopTrip(tripId);
    await _cleanSlate(bridge);

    // The 16 384-emoji-pair value is accepted too (UTF-16 count, not code
    // points or UTF-8 bytes).
    final emoji = '\u{1F634}' * (_max ~/ 2);
    final emojiTrip = _id('v11emoji');
    await bridge.startTrip(
      _config(emojiTrip, engineParamsJson: emoji),
      destLat: 16.8163,
      destLng: 107.1003,
    );
    expect((await bridge.currentTrip())!.config.engineParamsJson, emoji);
    await bridge.stopTrip(emojiTrip);
    await _cleanSlate(bridge);
  });

  testWidgets('deviceStatus() reads the device', (tester) async {
    final first = await bridge.deviceStatus();
    final second = await bridge.deviceStatus();
    final s = second;
    final values = <String, Object?>{
      'batteryPct': s.batteryPct,
      'charging': s.charging,
      'alarmVolumePct': s.alarmVolumePct,
      'alarmMuted': s.alarmMuted,
      'interruptionFilter': s.interruptionFilter.name,
      'priorityAllowsAlarms': s.priorityAllowsAlarms,
    };
    binding.reportData = {'deviceStatus': values};
    debugPrint('T14_1_DEVICE_STATUS $values');

    // Two reads in a row agree (nothing changed in between).
    expect(first, second);

    // A real device / emulator can read every item (no permission needed).
    expect(s.batteryPct, isNotNull);
    expect(s.batteryPct, inInclusiveRange(0, 100));
    expect(s.alarmVolumePct, isNotNull);
    expect(s.alarmVolumePct, inInclusiveRange(0, 100));
    expect(s.alarmMuted, isNotNull);
    expect(s.interruptionFilter, isNot(InterruptionFilterMsg.unknown));
    if (s.interruptionFilter != InterruptionFilterMsg.priority) {
      expect(s.priorityAllowsAlarms, isNull);
    }

    if (_filter.isNotEmpty) {
      expect(s.interruptionFilter.name, _filter);
    }
    if (_battery.isNotEmpty) {
      expect(s.batteryPct, int.parse(_battery));
    }
    if (_charging.isNotEmpty) {
      expect(s.charging, bool.tryParse(_charging));
    }
    if (_volume.isNotEmpty) {
      expect(s.alarmVolumePct, int.parse(_volume));
    }
    if (_muted.isNotEmpty) {
      expect(s.alarmMuted, bool.parse(_muted));
    }
    if (_allowsAlarms.isNotEmpty) {
      expect(s.priorityAllowsAlarms, bool.tryParse(_allowsAlarms));
    }
  });
}
