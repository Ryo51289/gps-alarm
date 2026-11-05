// T28.3 PU03: the iOS "rings in Silent" line of the home card (D5).
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/features/home/domain/readiness.dart';
import 'package:napstop/features/home/presentation/home_strings.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

import '../../helpers/fake_core_bridge.dart';

List<ReadinessChipKind> _kinds(Readiness r) =>
    r.chips.map((c) => c.kind).toList();

const Set<ReadinessChipKind> _iosKinds = {
  ReadinessChipKind.iosAlarmKitOn,
  ReadinessChipKind.iosSilentRisk,
};

void main() {
  test('PU03 (a) iOS 27 + AlarmKit: ok chip, level unchanged', () {
    final r = evaluateReadiness(
      permissions: iosPermissions(),
      device: iosDevice(major: 27),
      status: deviceStatusMsg(),
    );
    expect(
      r.chips,
      contains(
        const ReadinessChip(
          ReadinessChipKind.iosAlarmKitOn,
          ReadinessSeverity.ok,
        ),
      ),
    );
    // Right after the location line (step 2).
    expect(_kinds(r).take(2), [
      ReadinessChipKind.locationWhileInUse,
      ReadinessChipKind.iosAlarmKitOn,
    ]);
    expect(r.level, ReadinessLevel.ready);
    expect(r.action, ReadinessAction.none);
  });

  test('PU03 (b) iOS 17 + notifications: caution → check', () {
    final r = evaluateReadiness(
      permissions: iosPermissions(alarmKit: PermissionStateMsg.notApplicable),
      device: iosDevice(major: 17),
      status: deviceStatusMsg(),
    );
    expect(
      r.chips,
      contains(
        const ReadinessChip(
          ReadinessChipKind.iosSilentRisk,
          ReadinessSeverity.caution,
        ),
      ),
    );
    expect(_kinds(r), isNot(contains(ReadinessChipKind.iosAlarmKitOn)));
    expect(r.level, ReadinessLevel.check);
    // Not a permission problem: no "open permissions" action.
    expect(r.action, ReadinessAction.none);
  });

  test('PU03 (c) iOS 27, AlarmKit denied, notifications: only alarmKitOff', () {
    final r = evaluateReadiness(
      permissions: iosPermissions(alarmKit: PermissionStateMsg.denied),
      device: iosDevice(major: 27),
      status: deviceStatusMsg(),
    );
    expect(_kinds(r), contains(ReadinessChipKind.alarmKitOff));
    expect(_kinds(r).toSet().intersection(_iosKinds), isEmpty);
  });

  test('PU03 (d) iOS 27 without any channel: noAlarmChannel only', () {
    final r = evaluateReadiness(
      permissions: iosPermissions(
        alarmKit: PermissionStateMsg.denied,
        notifications: PermissionStateMsg.denied,
      ),
      device: iosDevice(major: 27),
      status: deviceStatusMsg(),
    );
    expect(_kinds(r), contains(ReadinessChipKind.noAlarmChannel));
    expect(_kinds(r).toSet().intersection(_iosKinds), isEmpty);
    expect(r.level, ReadinessLevel.blocked);
  });

  // Test report O1: iOS 26+ whose build has no AlarmKit (notApplicable),
  // notifications only: no alarmKitOff, so the caution line says it.
  test('PU03 iOS 27, AlarmKit not applicable: iosSilentRisk', () {
    final r = evaluateReadiness(
      permissions: iosPermissions(alarmKit: PermissionStateMsg.notApplicable),
      device: iosDevice(major: 27),
      status: deviceStatusMsg(),
    );
    expect(_kinds(r), contains(ReadinessChipKind.iosSilentRisk));
    expect(_kinds(r), isNot(contains(ReadinessChipKind.alarmKitOff)));
    expect(r.level, ReadinessLevel.check);
  });

  test('PU03 iOS 27, AlarmKit not determined: only alarmKitOff', () {
    final r = evaluateReadiness(
      permissions: iosPermissions(alarmKit: PermissionStateMsg.notDetermined),
      device: iosDevice(major: 27),
    );
    expect(_kinds(r), contains(ReadinessChipKind.alarmKitOff));
    expect(_kinds(r).toSet().intersection(_iosKinds), isEmpty);
  });

  test('PU03 iOS 17 without notifications: no iOS line either', () {
    final r = evaluateReadiness(
      permissions: iosPermissions(
        alarmKit: PermissionStateMsg.notApplicable,
        notifications: PermissionStateMsg.denied,
      ),
      device: iosDevice(major: 17),
    );
    expect(_kinds(r), contains(ReadinessChipKind.noAlarmChannel));
    expect(_kinds(r).toSet().intersection(_iosKinds), isEmpty);
  });

  test('PU03 Android: never an iOS chip', () {
    for (final permissions in [
      androidPermissions(),
      androidPermissions(notifications: PermissionStateMsg.denied),
      androidPermissions(location: LocationAccessMsg.denied),
    ]) {
      for (final status in [null, deviceStatusMsg()]) {
        final r = evaluateReadiness(
          permissions: permissions,
          device: androidDevice(),
          status: status,
        );
        expect(_kinds(r).toSet().intersection(_iosKinds), isEmpty);
      }
    }
  });

  test('PU03 chip copy (vi, en)', () {
    final vi = lookupAppLocalizations(const Locale('vi'));
    final en = lookupAppLocalizations(const Locale('en'));
    const on = ReadinessChip(
      ReadinessChipKind.iosAlarmKitOn,
      ReadinessSeverity.ok,
    );
    const risk = ReadinessChip(
      ReadinessChipKind.iosSilentRisk,
      ReadinessSeverity.caution,
    );
    expect(vi.readinessChip(on), 'Báo thức kêu cả khi Im lặng');
    expect(
      vi.readinessChip(risk),
      'Báo bằng thông báo: tắt Im lặng trước khi ngủ',
    );
    expect(en.readinessChip(on), 'Alarm rings even on Silent');
    expect(
      en.readinessChip(risk),
      'Notification alarm: turn off Silent before sleeping',
    );
  });
}
