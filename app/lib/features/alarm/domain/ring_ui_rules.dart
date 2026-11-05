/// When the Flutter side of screen 5 may act on a ring, and what it shows
/// (T27 §4.1). Pure.
library;

import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/features/alarm_settings/domain/alarm_settings_params.dart';

/// Grace before Flutter acts on a ring while the app is visible (T27 D1):
/// `RING_CONFIRM_MS` 3 s (T16 §6) + about 1.2 s to open the native screen.
const Duration kRingUiGrace = Duration(seconds: 4);

/// The engine says this trip's alarm is sounding now.
bool ringingNow(TripStateMsg? s) =>
    s != null &&
    s.alarmRinging &&
    (s.phase == TripPhaseMsg.alarming || s.phase == TripPhaseMsg.overshot);

/// Screen 5 (arriving) or screen 8 while ringing (overshoot).
enum AlarmVariant { arriving, overshoot }

/// Same rule as `RingCopy.variant` (T16).
AlarmVariant alarmVariant(TripStateMsg s) =>
    s.phase == TripPhaseMsg.overshot ||
        s.overshootPastM != null ||
        s.alarmReason == AlarmReasonMsg.overshoot
    ? AlarmVariant.overshoot
    : AlarmVariant.arriving;

/// T10 §2.3: phase ALARMING && snoozeCount < maxSnoozes; never on overshoot.
bool snoozeAllowed(TripStateMsg s, AlarmSettingsParams p) =>
    s.phase == TripPhaseMsg.alarming &&
    s.snoozeCount < p.maxSnoozes &&
    alarmVariant(s) == AlarmVariant.arriving;
