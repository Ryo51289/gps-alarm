// Tester T21 (§12, O6): the "Sẵn sàng" card never says ready when the alarm
// sound could not be checked, on API 26-29 (no applied DND policy) and 30+.
// Sweeps every device status the native side can send.
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/features/home/domain/readiness.dart';

import '../../../helpers/fake_core_bridge.dart';

const _volumes = <int?>[null, 0, 10, 29, 30, 100];
const _muted = <bool?>[null, false, true];
const _allows = <bool?>[null, false, true];

/// What DeviceStatusReader sends for [sdk] (T21 §4.6, T14.1): the applied
/// policy is only readable from API 30.
DeviceStatusMsg _native(
  int sdk, {
  required int? volume,
  required bool? muted,
  required InterruptionFilterMsg filter,
  required bool? allows,
}) => deviceStatusMsg(
  alarmVolumePct: volume,
  alarmMuted: muted,
  interruptionFilter: filter,
  priorityAllowsAlarms: sdk >= 30 && filter == InterruptionFilterMsg.priority
      ? allows
      : null,
);

List<ReadinessChipKind> _kinds(Readiness r) => [
  for (final c in r.chips) c.kind,
];

void main() {
  test('Android sweep: ready only when the alarm sound is known to ring', () {
    var cases = 0;
    for (final sdk in [26, 28, 29, 30, 31, 34, 35]) {
      final device = androidDevice(sdk: sdk);
      for (final volume in _volumes) {
        for (final muted in _muted) {
          for (final filter in InterruptionFilterMsg.values) {
            for (final allows in _allows) {
              final status = _native(
                sdk,
                volume: volume,
                muted: muted,
                filter: filter,
                allows: allows,
              );
              final r = evaluateReadiness(
                permissions: androidPermissions(),
                device: device,
                status: status,
              );
              final kinds = _kinds(r);
              final why =
                  '$sdk v=$volume m=$muted f=${filter.name} '
                  'a=${status.priorityAllowsAlarms} -> $kinds';
              final soundKnown =
                  muted != true && volume != null && volume >= 30;
              final dndLetsAlarmsThrough =
                  filter == InterruptionFilterMsg.all ||
                  filter == InterruptionFilterMsg.alarms ||
                  (filter == InterruptionFilterMsg.priority &&
                      status.priorityAllowsAlarms == true);
              expect(
                r.level == ReadinessLevel.ready,
                soundKnown && dndLetsAlarmsThrough,
                reason: why,
              );
              expect(
                kinds.where((k) => k == ReadinessChipKind.deviceStatusUnknown),
                hasLength(lessThanOrEqualTo(1)),
                reason: why,
              );
              expect(
                kinds.contains(ReadinessChipKind.dndCheckAlarms),
                filter == InterruptionFilterMsg.priority &&
                    status.priorityAllowsAlarms == null &&
                    muted != true,
                reason: why,
              );
              expect(
                kinds.contains(ReadinessChipKind.dndBlocksAlarms),
                filter == InterruptionFilterMsg.none ||
                    (filter == InterruptionFilterMsg.priority &&
                        status.priorityAllowsAlarms == false),
                reason: why,
              );
              // Unreadable volume (not muted) or filter: one "not checked".
              final unknown =
                  (volume == null && muted != true) ||
                  filter == InterruptionFilterMsg.unknown;
              expect(
                kinds.contains(ReadinessChipKind.deviceStatusUnknown),
                unknown,
                reason: why,
              );
              for (final c in r.chips) {
                if (c.kind == ReadinessChipKind.deviceStatusUnknown ||
                    c.kind == ReadinessChipKind.dndCheckAlarms) {
                  expect(c.severity, ReadinessSeverity.caution, reason: why);
                }
              }
              // The app cannot fix volume or DND: no action for them.
              expect(r.action, ReadinessAction.none, reason: why);
              cases++;
            }
          }
        }
      }
    }
    expect(cases, 7 * 6 * 3 * InterruptionFilterMsg.values.length * 3);
  });

  test('API 26-29 "Ưu tiên" always asks to check; 30+ reads the policy', () {
    for (final sdk in [26, 27, 28, 29]) {
      for (final allows in _allows) {
        final r = evaluateReadiness(
          permissions: androidPermissions(),
          device: androidDevice(sdk: sdk),
          status: _native(
            sdk,
            volume: 80,
            muted: false,
            filter: InterruptionFilterMsg.priority,
            allows: allows,
          ),
        );
        expect(_kinds(r), contains(ReadinessChipKind.dndCheckAlarms));
        expect(r.level, ReadinessLevel.check, reason: '$sdk');
      }
    }
    for (final sdk in [30, 34, 35]) {
      ReadinessLevel level({required bool? allows}) => evaluateReadiness(
        permissions: androidPermissions(),
        device: androidDevice(sdk: sdk),
        status: _native(
          sdk,
          volume: 80,
          muted: false,
          filter: InterruptionFilterMsg.priority,
          allows: allows,
        ),
      ).level;
      expect(level(allows: true), ReadinessLevel.ready, reason: '$sdk');
      expect(level(allows: false), ReadinessLevel.check, reason: '$sdk');
      expect(
        level(allows: null),
        ReadinessLevel.check,
        reason: '$sdk read error',
      );
    }
  });

  test('deviceStatus() failed: never ready, whatever the permissions', () {
    final r = evaluateReadiness(
      permissions: androidPermissions(),
      device: androidDevice(),
    );
    expect(r.level, ReadinessLevel.check);
    expect(_kinds(r), [
      ReadinessChipKind.locationWhileInUse,
      ReadinessChipKind.deviceStatusUnknown,
    ]);
    // Blocking permissions still win over the caution chip.
    final blocked = evaluateReadiness(
      permissions: androidPermissions(location: LocationAccessMsg.denied),
      device: androidDevice(),
    );
    expect(blocked.level, ReadinessLevel.blocked);
    expect(blocked.action, ReadinessAction.openPermissions);
    expect(_kinds(blocked), contains(ReadinessChipKind.deviceStatusUnknown));
  });

  test('iOS: the Android-only chips never show', () {
    final statuses = <DeviceStatusMsg?>[
      null,
      deviceStatusMsg(
        alarmVolumePct: null,
        alarmMuted: null,
        interruptionFilter: InterruptionFilterMsg.unknown,
      ),
      deviceStatusMsg(alarmVolumePct: null, alarmMuted: null),
    ];
    for (final s in statuses) {
      final r = evaluateReadiness(
        permissions: iosPermissions(),
        device: iosDevice(),
        status: s,
      );
      expect(
        _kinds(r),
        isNot(contains(ReadinessChipKind.deviceStatusUnknown)),
        reason: '$s',
      );
      expect(r.level, ReadinessLevel.ready, reason: '$s');
    }
  });
}
