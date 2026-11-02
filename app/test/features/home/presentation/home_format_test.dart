// U18: alarmSummary.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/features/home/presentation/home_format.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

void main() {
  const vi = Locale('vi');
  const en = Locale('en');
  final lVi = lookupAppLocalizations(vi);
  final lEn = lookupAppLocalizations(en);

  TripAlarmChoice choice(AlarmModeMsg mode, {int? m, int? min}) =>
      TripAlarmChoice(
        mode: mode,
        distanceThresholdM: m,
        timeThresholdMin: min,
        preAlertEnabled: true,
      );

  test('U18 alarmSummary (vi)', () {
    expect(
      alarmSummary(choice(AlarmModeMsg.distance, m: 1000), lVi, vi),
      'Báo trước 1 km',
    );
    expect(
      alarmSummary(choice(AlarmModeMsg.distance, m: 500), lVi, vi),
      'Báo trước 500 m',
    );
    expect(
      alarmSummary(choice(AlarmModeMsg.distance, m: 1500), lVi, vi),
      'Báo trước 1,5 km',
    );
    expect(
      alarmSummary(choice(AlarmModeMsg.time, min: 15), lVi, vi),
      'Báo trước 15 phút',
    );
    expect(
      alarmSummary(choice(AlarmModeMsg.smart, m: 1000, min: 15), lVi, vi),
      'Báo thông minh',
    );
  });

  test('U18 alarmSummary (en)', () {
    expect(
      alarmSummary(choice(AlarmModeMsg.distance, m: 1500), lEn, en),
      'Alert 1.5 km before',
    );
    expect(
      alarmSummary(choice(AlarmModeMsg.time, min: 15), lEn, en),
      'Alert 15 min before',
    );
  });
}
