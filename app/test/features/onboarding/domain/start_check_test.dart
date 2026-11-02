// U01-U04: checkStart (T19 §1.3), shared by T21, T22, T25.
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/features/onboarding/domain/start_check.dart';

import '../../../helpers/fake_core_bridge.dart';

void main() {
  final android = androidDevice();

  test('U01 Android, while in use + precise + services on: can start', () {
    final check = checkStart(androidPermissions(), android);
    expect(check.canStart, isTrue);
    expect(check.missing, isEmpty);
    expect(check.warnings, isEmpty);
    expect(canStart(androidPermissions(), android), isTrue);
  });

  group('U02 Android blocking', () {
    test('(a) location denied: only location, no precise', () {
      final check = checkStart(
        androidPermissions(
          location: LocationAccessMsg.denied,
          precise: PermissionStateMsg.denied,
        ),
        android,
      );
      expect(check.missing, [StartRequirement.location]);
      expect(check.canStart, isFalse);
    });

    test('(b) approximate location: precise', () {
      final check = checkStart(
        androidPermissions(precise: PermissionStateMsg.denied),
        android,
      );
      expect(check.missing, [StartRequirement.precise]);
    });

    test('(c) location services off', () {
      final check = checkStart(
        androidPermissions(locationServicesEnabled: false),
        android,
      );
      expect(check.missing, [StartRequirement.locationServices]);
    });

    test('(d) not determined + services off', () {
      final check = checkStart(
        androidPermissions(
          location: LocationAccessMsg.notDetermined,
          precise: PermissionStateMsg.notDetermined,
          locationServicesEnabled: false,
        ),
        android,
      );
      expect(check.missing, [
        StartRequirement.location,
        StartRequirement.locationServices,
      ]);
    });
  });

  test('U03 Android warnings in order, still can start', () {
    final check = checkStart(
      androidPermissions(
        notifications: PermissionStateMsg.denied,
        exactAlarm: PermissionStateMsg.denied,
        fullScreenIntent: PermissionStateMsg.denied,
        batteryOptimizationIgnored: PermissionStateMsg.denied,
      ),
      android,
    );
    expect(check.canStart, isTrue);
    expect(check.warnings, [
      PermissionWarning.notifications,
      PermissionWarning.exactAlarm,
      PermissionWarning.fullScreenIntent,
      PermissionWarning.batteryOptimization,
    ]);
  });

  test('U03 notDetermined exact/full-screen warn; notApplicable never', () {
    final check = checkStart(
      androidPermissions(
        notifications: PermissionStateMsg.notApplicable,
        exactAlarm: PermissionStateMsg.notDetermined,
        fullScreenIntent: PermissionStateMsg.notApplicable,
        batteryOptimizationIgnored: PermissionStateMsg.notDetermined,
      ),
      android,
    );
    expect(check.warnings, [PermissionWarning.exactAlarm]);
  });

  group('U04 iOS', () {
    test('(a) 26, AlarmKit granted, notifications denied', () {
      final check = checkStart(
        iosPermissions(notifications: PermissionStateMsg.denied),
        iosDevice(),
      );
      expect(check.canStart, isTrue);
      expect(check.warnings, [PermissionWarning.notificationsNoStatus]);
    });

    test('(b) 26, AlarmKit denied, notifications granted', () {
      final check = checkStart(
        iosPermissions(alarmKit: PermissionStateMsg.denied),
        iosDevice(),
      );
      expect(check.canStart, isTrue);
      expect(check.warnings, [PermissionWarning.alarmKit]);
    });

    test('(c) 26, both denied: no alarm channel, no warnings', () {
      final check = checkStart(
        iosPermissions(
          alarmKit: PermissionStateMsg.denied,
          notifications: PermissionStateMsg.denied,
        ),
        iosDevice(),
      );
      expect(check.missing, [StartRequirement.alarmChannel]);
      expect(check.warnings, isEmpty);
    });

    test('(d) 17, AlarmKit not applicable, notifications granted', () {
      final check = checkStart(
        iosPermissions(alarmKit: PermissionStateMsg.notApplicable),
        iosDevice(major: 17),
      );
      expect(check.canStart, isTrue);
      expect(check.warnings, isEmpty);
    });

    test('(e) 17, notifications denied: no alarm channel', () {
      final check = checkStart(
        iosPermissions(
          alarmKit: PermissionStateMsg.notApplicable,
          notifications: PermissionStateMsg.denied,
        ),
        iosDevice(major: 17),
      );
      expect(check.missing, [StartRequirement.alarmChannel]);
    });

    test('(e2) 17 with AlarmKit reported granted does not count', () {
      final check = checkStart(
        iosPermissions(notifications: PermissionStateMsg.denied),
        iosDevice(major: 17),
      );
      expect(check.missing, [StartRequirement.alarmChannel]);
    });

    test('(f) location always is enough', () {
      final check = checkStart(
        iosPermissions(location: LocationAccessMsg.always),
        iosDevice(),
      );
      expect(check.canStart, isTrue);
      expect(check.missing, isEmpty);
    });
  });
}
