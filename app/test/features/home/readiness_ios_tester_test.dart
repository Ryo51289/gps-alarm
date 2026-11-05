// T28.3 tester (outside the spec, D5): boundaries of the iOS "rings in
// Silent" line, its agreement with screens 3/4 (`ringsInSilent`), no double
// warning with alarmKitOff, and the card at 320 px, text ×2.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/features/alarm_settings/domain/alarm_settings_hints.dart';
import 'package:napstop/features/home/domain/readiness.dart';
import 'package:napstop/features/onboarding/domain/start_check.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/fake_core_bridge.dart';

List<ReadinessChipKind> _kinds(Readiness r) =>
    r.chips.map((c) => c.kind).toList();

DeviceInfoMsg _ios(int? major) => DeviceInfoMsg(
  platform: PlatformMsg.ios,
  manufacturer: 'Apple',
  brand: 'Apple',
  model: 'iPhone',
  osVersion: major == null ? '' : '$major.0',
  iosMajor: major,
);

const _on = 'Báo thức kêu cả khi Im lặng';
const _risk = 'Báo bằng thông báo: tắt Im lặng trước khi ngủ';

void main() {
  group('evaluateReadiness, iOS line boundaries', () {
    test('TR01 iOS 26.0 exactly + AlarmKit: iosAlarmKitOn', () {
      final r = evaluateReadiness(
        permissions: iosPermissions(),
        device: _ios(26),
        status: deviceStatusMsg(),
      );
      expect(_kinds(r), contains(ReadinessChipKind.iosAlarmKitOn));
      expect(_kinds(r), isNot(contains(ReadinessChipKind.iosSilentRisk)));
      expect(r.level, ReadinessLevel.ready);
    });

    test('TR02 iOS 25 + notifications: iosSilentRisk (caution → check)', () {
      final r = evaluateReadiness(
        permissions: iosPermissions(alarmKit: PermissionStateMsg.notApplicable),
        device: _ios(25),
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
      expect(r.level, ReadinessLevel.check);
    });

    test('TR03 iOS version unknown + notifications: iosSilentRisk (no '
        'optimistic claim)', () {
      final r = evaluateReadiness(
        permissions: iosPermissions(alarmKit: PermissionStateMsg.notApplicable),
        device: _ios(null),
        status: deviceStatusMsg(),
      );
      expect(_kinds(r), contains(ReadinessChipKind.iosSilentRisk));
      expect(_kinds(r), isNot(contains(ReadinessChipKind.iosAlarmKitOn)));
    });

    test(
      'TR04 iOS 26, AlarmKit not asked yet: alarmKitOff only, not twice',
      () {
        final r = evaluateReadiness(
          permissions: iosPermissions(
            alarmKit: PermissionStateMsg.notDetermined,
          ),
          device: _ios(26),
          status: deviceStatusMsg(),
        );
        expect(_kinds(r), contains(ReadinessChipKind.alarmKitOff));
        expect(_kinds(r), isNot(contains(ReadinessChipKind.iosSilentRisk)));
        expect(_kinds(r), isNot(contains(ReadinessChipKind.iosAlarmKitOn)));
      },
    );

    test('TR05 iOS 17 + notifications but location denied: blocked, the '
        'Silent line still shown', () {
      final r = evaluateReadiness(
        permissions: iosPermissions(
          location: LocationAccessMsg.denied,
          alarmKit: PermissionStateMsg.notApplicable,
        ),
        device: _ios(17),
        status: deviceStatusMsg(),
      );
      expect(r.level, ReadinessLevel.blocked);
      expect(_kinds(r), contains(ReadinessChipKind.iosSilentRisk));
    });

    test('TR06 sweep: at most one Silent line, it agrees with screens 3/4 '
        '(ringsInSilent), never next to alarmKitOff', () {
      const states = PermissionStateMsg.values;
      for (final major in const [null, 15, 17, 25, 26, 27]) {
        for (final alarmKit in states) {
          for (final notifications in states) {
            final permissions = iosPermissions(
              alarmKit: alarmKit,
              notifications: notifications,
            );
            final device = _ios(major);
            final r = evaluateReadiness(
              permissions: permissions,
              device: device,
              status: deviceStatusMsg(),
            );
            final kinds = _kinds(r);
            final why = 'iOS $major, alarmKit $alarmKit, notif $notifications';
            final on = kinds.where((k) => k == ReadinessChipKind.iosAlarmKitOn);
            final risk = kinds.where(
              (k) => k == ReadinessChipKind.iosSilentRisk,
            );
            expect(on.length + risk.length, lessThanOrEqualTo(1), reason: why);
            final channel = !checkStart(
              permissions,
              device,
            ).missing.contains(StartRequirement.alarmChannel);
            // "Rings in Silent" on the card ⇔ screens 3/4 say so too.
            expect(
              on.isNotEmpty,
              channel && ringsInSilent(permissions, device),
              reason: why,
            );
            if (kinds.contains(ReadinessChipKind.alarmKitOff)) {
              expect(risk, isEmpty, reason: why);
            }
            // A start-able iPhone that may stay quiet in Silent mode always
            // gets exactly one warning, including iOS 26+ reporting AlarmKit
            // notApplicable (test report O1, fixed in round 2).
            final quiet = channel && !ringsInSilent(permissions, device);
            if (quiet) {
              expect(
                risk.isNotEmpty ||
                    kinds.contains(ReadinessChipKind.alarmKitOff),
                isTrue,
                reason: why,
              );
            }
          }
        }
      }
    });
  });

  group('screen 1 card on iOS', () {
    List<String> labels(WidgetTester tester) => tester
        .widgetList<NapBadge>(find.byType(NapBadge))
        .map((b) => b.label)
        .toList();

    NapTone tone(WidgetTester tester, String label) => tester
        .widget<NapBadge>(
          find.byWidgetPredicate((w) => w is NapBadge && w.label == label),
        )
        .tone;

    testWidgets('TR07 iOS 27 + AlarmKit: "$_on", neutral, card ready', (
      tester,
    ) async {
      await pumpAppHarness(
        tester,
        bridge: FakeCoreBridge(
          permissions: iosPermissions(),
          deviceInfoValue: iosDevice(major: 27),
          deviceStatusValue: DeviceStatusMsg(
            batteryPct: 64,
            charging: false,
            interruptionFilter: InterruptionFilterMsg.unknown,
          ),
        ),
      );
      expect(labels(tester), contains(_on));
      expect(labels(tester), isNot(contains(_risk)));
      expect(tone(tester, _on), NapTone.neutral);
      expect(find.text('Sẵn sàng cho chuyến đi'), findsOneWidget);
    });

    testWidgets('TR08 iOS 17 + notifications: "$_risk", warning, check', (
      tester,
    ) async {
      await pumpAppHarness(
        tester,
        bridge: FakeCoreBridge(
          permissions: iosPermissions(
            alarmKit: PermissionStateMsg.notApplicable,
          ),
          deviceInfoValue: iosDevice(major: 17),
          deviceStatusValue: DeviceStatusMsg(
            batteryPct: 64,
            charging: false,
            interruptionFilter: InterruptionFilterMsg.unknown,
          ),
        ),
      );
      expect(labels(tester), contains(_risk));
      expect(labels(tester), isNot(contains(_on)));
      expect(tone(tester, _risk), NapTone.warning);
      expect(find.text('Nên kiểm tra trước khi ngủ'), findsOneWidget);
    });

    for (final locale in const [Locale('vi'), Locale('en')]) {
      for (final major in const [17, 27]) {
        testWidgets('TR09 iOS $major card, 320 px, text ×2, $locale: no '
            'overflow', (tester) async {
          await pumpAppHarness(
            tester,
            bridge: FakeCoreBridge(
              permissions: iosPermissions(
                alarmKit: major >= 26
                    ? PermissionStateMsg.granted
                    : PermissionStateMsg.notApplicable,
              ),
              deviceInfoValue: iosDevice(major: major),
              deviceStatusValue: DeviceStatusMsg(
                batteryPct: 12,
                charging: false,
                interruptionFilter: InterruptionFilterMsg.unknown,
              ),
            ),
            textScale: 2,
            locale: locale,
            size: const Size(320, 844),
          );
          expect(tester.takeException(), isNull);
          final chip = switch ((locale.languageCode, major)) {
            ('vi', 17) => _risk,
            ('vi', _) => _on,
            (_, 17) => 'Notification alarm: turn off Silent before sleeping',
            _ => 'Alarm rings even on Silent',
          };
          final badge = find.byWidgetPredicate(
            (w) => w is NapBadge && w.label == chip,
          );
          await tester.scrollUntilVisible(
            badge,
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(badge, findsOneWidget);
          expect(tester.getRect(badge).right, lessThanOrEqualTo(320));
        }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
      }
    }
  });
}
