package app.napstop.core.trip.runtime

import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.TripView

/** Which AlarmManager call wakes the runtime at `wakeAtMs` (spec T15 §5.5, D6). Pure. */
object WakePolicy {
    fun mechanism(
        view: TripView,
        wakeAtMs: Long,
        canScheduleExact: Boolean,
        nearWakeUsesAlarmClock: Boolean = RuntimeConstants.NEAR_WAKE_USES_ALARM_CLOCK,
    ): WakeMechanism {
        if (!canScheduleExact) return WakeMechanism.INEXACT_IDLE
        // T16 D17: the end of a snooze is an alarm the user set ("Báo lại"): on time in Doze, and the receiver may start
        // the ring service from the background [A-AM].
        val until = view.snoozeUntilMs
        if (view.phase == TripPhase.SNOOZED && until != null && wakeAtMs >= until && wakeAtMs <= until + 2 * RuntimeConstants.WAKE_GUARD_MS) {
            return WakeMechanism.ALARM_CLOCK
        }
        val predicted = view.predictedAlarmAtMs
        val active = view.phase == TripPhase.ACQUIRING || view.phase == TripPhase.TRACKING
        if (nearWakeUsesAlarmClock && active && predicted != null &&
            wakeAtMs >= predicted && wakeAtMs <= predicted + 2 * RuntimeConstants.WAKE_GUARD_MS
        ) {
            return WakeMechanism.ALARM_CLOCK
        }
        return WakeMechanism.EXACT_IDLE
    }
}
