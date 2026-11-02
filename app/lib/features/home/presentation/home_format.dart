import 'package:flutter/widgets.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/format/distance_format.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// "Báo trước 1 km", "Báo trước 15 phút", "Báo thông minh" (T22 §9.3).
String alarmSummary(TripAlarmChoice alarm, AppLocalizations l, Locale locale) {
  final distance = alarm.distanceThresholdM;
  final time = alarm.timeThresholdMin;
  return switch (alarm.mode) {
    AlarmModeMsg.distance when distance != null => l.homeAlarmDistance(
      formatDistanceShort(distance, locale.toLanguageTag()),
    ),
    AlarmModeMsg.time when time != null => l.homeAlarmTime(time),
    // Invalid choices never reach the database (insertStarted validates).
    _ => l.homeAlarmSmart,
  };
}
