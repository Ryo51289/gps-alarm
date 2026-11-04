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
