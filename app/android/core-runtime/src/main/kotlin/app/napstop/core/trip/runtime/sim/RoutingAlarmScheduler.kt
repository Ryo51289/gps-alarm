package app.napstop.core.trip.runtime.sim

import app.napstop.core.trip.runtime.OsAlarmScheduler
import app.napstop.core.trip.runtime.RestoreCause
import app.napstop.core.trip.runtime.SlotKind
import app.napstop.core.trip.runtime.WakeMechanism

/**
 * The scheduler the runtime uses (T18 §5): while a simulated trip runs ([simulated]) wake and fallback alarms go to the
 * in-process [sim] timers, otherwise to the [os]. Cancels go to both, so the order of switching never leaves an alarm
 * behind. Restore retries are always the OS's.
 */
class RoutingAlarmScheduler(private val os: OsAlarmScheduler, private val sim: SimAlarmScheduler) : OsAlarmScheduler {
    @Volatile
    var simulated: Boolean = false

    override fun canScheduleExact(): Boolean = if (simulated) true else os.canScheduleExact()

    override fun setWake(triggerElapsedMs: Long, mechanism: WakeMechanism, triggerWallMs: Long, wakeAtMs: Long) {
        if (simulated) {
            sim.setWake(triggerElapsedMs, mechanism, triggerWallMs, wakeAtMs)
        } else {
            os.setWake(triggerElapsedMs, mechanism, triggerWallMs, wakeAtMs)
        }
    }

    override fun cancelWake() {
        try {
            os.cancelWake()
        } finally {
            sim.cancelWake()
        }
    }

    override fun setFallback(slot: Int, tripId: String, generation: Long, targetAtMs: Long, triggerWallMs: Long, exact: Boolean, kind: SlotKind) {
        if (simulated) {
            sim.setFallback(slot, tripId, generation, targetAtMs, triggerWallMs, exact, kind)
        } else {
            os.setFallback(slot, tripId, generation, targetAtMs, triggerWallMs, exact, kind)
        }
    }

    override fun cancelFallback(slot: Int) {
        try {
            os.cancelFallback(slot)
        } finally {
            sim.cancelFallback(slot)
        }
    }

    override fun setRestoreRetry(triggerElapsedMs: Long, attempt: Int, cause: RestoreCause, sinceWallMs: Long, exact: Boolean) =
        os.setRestoreRetry(triggerElapsedMs, attempt, cause, sinceWallMs, exact)

    override fun cancelRestoreRetry() = os.cancelRestoreRetry()
}
