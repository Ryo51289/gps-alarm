// U05-U09: evaluateReadiness (T22 §8.3), plus the muted alarm stream case
// from T14.1 O1 (DND "total silence").
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/features/home/domain/readiness.dart';

import '../../../helpers/fake_core_bridge.dart';

Readiness _eval({
  PermissionStatusMsg? permissions,
  DeviceInfoMsg? device,
  DeviceStatusMsg? status,
}) => evaluateReadiness(
  permissions: permissions ?? androidPermissions(),
  device: device ?? androidDevice(),
  status: status,
);

List<ReadinessChipKind> _kinds(Readiness r) =>
    r.chips.map((c) => c.kind).toList();

ReadinessChip? _chip(Readiness r, ReadinessChipKind kind) {
  for (final c in r.chips) {
    if (c.kind == kind) {
      return c;
    }
  }
  return null;
}

void main() {
  test('U05 everything fine on Android', () {
    final r = _eval(status: deviceStatusMsg());
    expect(r.level, ReadinessLevel.ready);
    expect(r.chips, const [
      ReadinessChip(ReadinessChipKind.locationWhileInUse, ReadinessSeverity.ok),
      ReadinessChip(
        ReadinessChipKind.battery,
        ReadinessSeverity.ok,
        percent: 82,
      ),
      ReadinessChip(
        ReadinessChipKind.alarmVolume,
        ReadinessSeverity.ok,
        percent: 100,
      ),
    ]);
    expect(r.action, ReadinessAction.none);
    expect(r.showSleepModeHint, isTrue);
  });

  test('U05 location always', () {
    final r = _eval(
      permissions: androidPermissions(location: LocationAccessMsg.always),
    );
    // T21 §12 (O6): Android without a device status adds "not checked".
    expect(_kinds(r), [
      ReadinessChipKind.locationAlways,
      ReadinessChipKind.deviceStatusUnknown,
    ]);
  });

  group('U06 battery', () {
    test('20 % not charging: low (caution)', () {
      final r = _eval(status: deviceStatusMsg(batteryPct: 20));
      expect(
        _chip(r, ReadinessChipKind.batteryLow),
        const ReadinessChip(
          ReadinessChipKind.batteryLow,
          ReadinessSeverity.caution,
          percent: 20,
        ),
      );
      expect(r.level, ReadinessLevel.check);
      expect(r.action, ReadinessAction.none);
    });

    test('21 % not charging: ok', () {
      final r = _eval(status: deviceStatusMsg(batteryPct: 21));
      expect(
        _chip(r, ReadinessChipKind.battery)?.severity,
        ReadinessSeverity.ok,
      );
      expect(r.level, ReadinessLevel.ready);
    });

    test('15 % charging: charging (ok)', () {
      final r = _eval(status: deviceStatusMsg(batteryPct: 15, charging: true));
      expect(
        _chip(r, ReadinessChipKind.batteryCharging),
        const ReadinessChip(
          ReadinessChipKind.batteryCharging,
          ReadinessSeverity.ok,
          percent: 15,
        ),
      );
    });

    test('unknown: no battery chip', () {
      final r = _eval(status: deviceStatusMsg(batteryPct: null));
      expect(
        _kinds(r),
        isNot(
          anyOf(
            contains(ReadinessChipKind.battery),
            contains(ReadinessChipKind.batteryLow),
            contains(ReadinessChipKind.batteryCharging),
          ),
        ),
      );
    });
  });

  group('U07 alarm volume', () {
    test('muted at 70 %: muted (warning)', () {
      final r = _eval(
        status: deviceStatusMsg(alarmVolumePct: 70, alarmMuted: true),
      );
      expect(
        _chip(r, ReadinessChipKind.alarmMuted)?.severity,
        ReadinessSeverity.warning,
      );
      expect(_chip(r, ReadinessChipKind.alarmVolume), isNull);
    });

    test('0 %: muted', () {
      final r = _eval(status: deviceStatusMsg(alarmVolumePct: 0));
      expect(_chip(r, ReadinessChipKind.alarmMuted), isNotNull);
    });

    test('29 %: low (caution)', () {
      final r = _eval(status: deviceStatusMsg(alarmVolumePct: 29));
      expect(
        _chip(r, ReadinessChipKind.alarmVolumeLow),
        const ReadinessChip(
          ReadinessChipKind.alarmVolumeLow,
          ReadinessSeverity.caution,
          percent: 29,
        ),
      );
    });

    test('30 %: ok', () {
      final r = _eval(status: deviceStatusMsg(alarmVolumePct: 30));
      expect(
        _chip(r, ReadinessChipKind.alarmVolume),
        const ReadinessChip(
          ReadinessChipKind.alarmVolume,
          ReadinessSeverity.ok,
          percent: 30,
        ),
      );
    });

    // T21 §12 (O6): the device here is Android, where an unreadable volume
    // is "not checked" (caution); iOS keeps no chip (T21 U13).
    test(
      'unknown on Android: deviceStatusUnknown instead of a volume chip',
      () {
        final r = _eval(
          status: deviceStatusMsg(alarmVolumePct: null, alarmMuted: null),
        );
        expect(_kinds(r), [
          ReadinessChipKind.locationWhileInUse,
          ReadinessChipKind.battery,
          ReadinessChipKind.deviceStatusUnknown,
        ]);
      },
    );

    test('muted with unknown percent still warns', () {
      final r = _eval(
        status: deviceStatusMsg(alarmVolumePct: null, alarmMuted: true),
      );
      expect(_chip(r, ReadinessChipKind.alarmMuted), isNotNull);
      expect(r.level, ReadinessLevel.check);
    });
  });

  test('T14.1 O1: DND total silence (muted, 0 %, filter none) warns twice', () {
    final r = _eval(
      status: deviceStatusMsg(
        alarmVolumePct: 0,
        alarmMuted: true,
        interruptionFilter: InterruptionFilterMsg.none,
      ),
    );
    expect(_kinds(r), [
      ReadinessChipKind.locationWhileInUse,
      ReadinessChipKind.battery,
      ReadinessChipKind.alarmMuted,
      ReadinessChipKind.dndBlocksAlarms,
    ]);
    expect(r.level, ReadinessLevel.check);
    // The app cannot change volume or DND: information only.
    expect(r.action, ReadinessAction.none);
  });

  group('U08 Do Not Disturb', () {
    final cases = <(InterruptionFilterMsg, bool?, bool)>[
      (InterruptionFilterMsg.none, null, true),
      (InterruptionFilterMsg.priority, false, true),
      (InterruptionFilterMsg.priority, null, false),
      (InterruptionFilterMsg.priority, true, false),
      (InterruptionFilterMsg.alarms, null, false),
      (InterruptionFilterMsg.unknown, null, false),
    ];
    for (final (filter, allows, blocks) in cases) {
      test('$filter allowsAlarms=$allows: blocks=$blocks', () {
        final r = _eval(
          status: deviceStatusMsg(
            interruptionFilter: filter,
            priorityAllowsAlarms: allows,
          ),
        );
        final chip = _chip(r, ReadinessChipKind.dndBlocksAlarms);
        expect(chip != null, blocks);
        if (blocks) {
          expect(chip!.severity, ReadinessSeverity.warning);
        }
      });
    }
  });

  group('U09 level and action', () {
    test('(a) location denied: blocked, open permissions', () {
      final r = _eval(
        permissions: androidPermissions(location: LocationAccessMsg.denied),
      );
      expect(r.level, ReadinessLevel.blocked);
      expect(r.action, ReadinessAction.openPermissions);
      expect(
        r.chips.first,
        const ReadinessChip(
          ReadinessChipKind.locationDenied,
          ReadinessSeverity.blocking,
        ),
      );
    });

    test('(b) only exact alarm denied: check, open permissions', () {
      final r = _eval(
        permissions: androidPermissions(exactAlarm: PermissionStateMsg.denied),
        status: deviceStatusMsg(),
      );
      expect(r.level, ReadinessLevel.check);
      expect(r.action, ReadinessAction.openPermissions);
      expect(
        _chip(r, ReadinessChipKind.exactAlarmOff)?.severity,
        ReadinessSeverity.warning,
      );
    });

    test('(c) only battery optimization: ready, battery guide', () {
      final r = _eval(
        permissions: androidPermissions(
          batteryOptimizationIgnored: PermissionStateMsg.denied,
        ),
        status: deviceStatusMsg(),
      );
      expect(r.level, ReadinessLevel.ready);
      expect(r.action, ReadinessAction.openBatteryGuide);
      expect(
        r.chips.last,
        const ReadinessChip(
          ReadinessChipKind.batteryOptimization,
          ReadinessSeverity.guide,
        ),
      );
    });

    test('(d) only low volume: check, no action', () {
      final r = _eval(status: deviceStatusMsg(alarmVolumePct: 10));
      expect(r.level, ReadinessLevel.check);
      expect(r.action, ReadinessAction.none);
    });

    test(
      '(e) blocked + battery optimization: open permissions, guide last',
      () {
        final r = _eval(
          permissions: androidPermissions(
            locationServicesEnabled: false,
            batteryOptimizationIgnored: PermissionStateMsg.denied,
          ),
          status: deviceStatusMsg(),
        );
        expect(r.level, ReadinessLevel.blocked);
        expect(r.action, ReadinessAction.openPermissions);
        expect(r.chips.first.kind, ReadinessChipKind.locationServicesOff);
        expect(r.chips.last.kind, ReadinessChipKind.batteryOptimization);
      },
    );

    test('approximate location: blocking chip', () {
      final r = _eval(
        permissions: androidPermissions(precise: PermissionStateMsg.denied),
      );
      // T21 §12 (O6): Android without a device status adds "not checked".
      expect(_kinds(r), [
        ReadinessChipKind.locationApproximate,
        ReadinessChipKind.deviceStatusUnknown,
      ]);
      expect(r.level, ReadinessLevel.blocked);
    });

    test('chip order for several Android warnings (W09 data)', () {
      final r = _eval(
        permissions: androidPermissions(
          notifications: PermissionStateMsg.denied,
          exactAlarm: PermissionStateMsg.denied,
        ),
        status: deviceStatusMsg(
          alarmMuted: true,
          interruptionFilter: InterruptionFilterMsg.none,
        ),
      );
      expect(_kinds(r), [
        ReadinessChipKind.locationWhileInUse,
        ReadinessChipKind.notificationsOff,
        ReadinessChipKind.exactAlarmOff,
        ReadinessChipKind.battery,
        ReadinessChipKind.alarmMuted,
        ReadinessChipKind.dndBlocksAlarms,
      ]);
    });
  });

  group('iOS', () {
    test('no alarm channel: blocking chip, no sleep hint', () {
      final r = _eval(
        permissions: iosPermissions(
          alarmKit: PermissionStateMsg.denied,
          notifications: PermissionStateMsg.denied,
        ),
        device: iosDevice(),
        status: deviceStatusMsg(
          alarmVolumePct: null,
          alarmMuted: null,
          interruptionFilter: InterruptionFilterMsg.unknown,
        ),
      );
      expect(_kinds(r), [
        ReadinessChipKind.locationWhileInUse,
        ReadinessChipKind.noAlarmChannel,
        ReadinessChipKind.battery,
      ]);
      expect(r.level, ReadinessLevel.blocked);
      expect(r.showSleepModeHint, isFalse);
    });

    test('notifications off with AlarmKit: caution, open permissions', () {
      final r = _eval(
        permissions: iosPermissions(notifications: PermissionStateMsg.denied),
        device: iosDevice(),
      );
      expect(
        _chip(r, ReadinessChipKind.notificationsNoStatus)?.severity,
        ReadinessSeverity.caution,
      );
      expect(r.level, ReadinessLevel.check);
      expect(r.action, ReadinessAction.openPermissions);
    });
  });

  group('T21 §12 (O6)', () {
    test('U12 Android, permissions fine, no device status: check', () {
      final r = _eval();
      expect(
        _chip(r, ReadinessChipKind.deviceStatusUnknown),
        const ReadinessChip(
          ReadinessChipKind.deviceStatusUnknown,
          ReadinessSeverity.caution,
        ),
      );
      expect(r.level, ReadinessLevel.check);
      expect(r.action, ReadinessAction.none);
    });

    test('U13 unreadable volume and filter: exactly one chip; iOS none', () {
      final r = _eval(
        status: deviceStatusMsg(
          alarmVolumePct: null,
          alarmMuted: null,
          interruptionFilter: InterruptionFilterMsg.unknown,
        ),
      );
      expect(
        r.chips.where((c) => c.kind == ReadinessChipKind.deviceStatusUnknown),
        hasLength(1),
      );
      expect(_chip(r, ReadinessChipKind.battery), isNotNull);

      // Only the filter unknown.
      final f = _eval(
        status: deviceStatusMsg(
          interruptionFilter: InterruptionFilterMsg.unknown,
        ),
      );
      expect(_kinds(f), [
        ReadinessChipKind.locationWhileInUse,
        ReadinessChipKind.battery,
        ReadinessChipKind.alarmVolume,
        ReadinessChipKind.deviceStatusUnknown,
      ]);

      final ios = _eval(permissions: iosPermissions(), device: iosDevice());
      expect(_chip(ios, ReadinessChipKind.deviceStatusUnknown), isNull);
      expect(ios.level, ReadinessLevel.ready);
      final iosStatus = _eval(
        permissions: iosPermissions(),
        device: iosDevice(),
        status: deviceStatusMsg(
          alarmVolumePct: null,
          alarmMuted: null,
          interruptionFilter: InterruptionFilterMsg.unknown,
        ),
      );
      expect(_kinds(iosStatus), [
        ReadinessChipKind.locationWhileInUse,
        ReadinessChipKind.battery,
      ]);
      expect(iosStatus.level, ReadinessLevel.ready);
    });

    test('U14 Do Not Disturb priority', () {
      DeviceStatusMsg dnd({bool? allows, bool muted = false}) =>
          deviceStatusMsg(
            alarmMuted: muted,
            interruptionFilter: InterruptionFilterMsg.priority,
            priorityAllowsAlarms: allows,
          );

      final unknown = _eval(status: dnd());
      expect(
        _chip(unknown, ReadinessChipKind.dndCheckAlarms)?.severity,
        ReadinessSeverity.caution,
      );
      expect(unknown.level, ReadinessLevel.check);

      final muted = _eval(status: dnd(muted: true));
      expect(_chip(muted, ReadinessChipKind.alarmMuted), isNotNull);
      expect(_chip(muted, ReadinessChipKind.dndCheckAlarms), isNull);
      expect(_chip(muted, ReadinessChipKind.dndBlocksAlarms), isNull);

      final allows = _eval(status: dnd(allows: true));
      expect(_chip(allows, ReadinessChipKind.dndCheckAlarms), isNull);
      expect(_chip(allows, ReadinessChipKind.dndBlocksAlarms), isNull);
      expect(allows.level, ReadinessLevel.ready);

      final blocks = _eval(status: dnd(allows: false));
      expect(_chip(blocks, ReadinessChipKind.dndBlocksAlarms), isNotNull);
      expect(_chip(blocks, ReadinessChipKind.dndCheckAlarms), isNull);

      final none = _eval(
        status: deviceStatusMsg(interruptionFilter: InterruptionFilterMsg.none),
      );
      expect(_chip(none, ReadinessChipKind.dndBlocksAlarms), isNotNull);
      expect(_chip(none, ReadinessChipKind.dndCheckAlarms), isNull);
    });
  });
}
