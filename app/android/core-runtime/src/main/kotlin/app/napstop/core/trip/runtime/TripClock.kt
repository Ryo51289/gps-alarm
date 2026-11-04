package app.napstop.core.trip.runtime

/** Wall/elapsed pair the trip clock is measured from (T10 §2.6). Survives process death in the snapshot. */
data class ClockAnchor(val wallMs: Long, val elapsedMs: Long, val bootCount: Int?)

/**
 * Trip clock (spec T15 §5.3): monotonic (elapsed realtime from [anchor]), close to wall clock, never goes back.
 * [floorMs] = the engine's `nowMs` when restoring, so the clock never issues a time before the last Step.
 * Not thread-safe: the runtime uses it from its actor only.
 */
class TripClock(val anchor: ClockAnchor, private val time: TimeSource, floorMs: Long = Long.MIN_VALUE) {
    private var lastIssued = floorMs

    fun now(): Long {
        val t = maxOf(lastIssued, anchor.wallMs + (time.elapsedMs() - anchor.elapsedMs))
        lastIssued = t
        return t
    }

    /** For ELAPSED_REALTIME_WAKEUP. Times in the past map to now. */
    fun toElapsed(tripMs: Long): Long {
        val now = now()
        return time.elapsedMs() + maxOf(0L, tripMs - now)
    }

    /** For setAlarmClock (AlarmClockInfo takes wall time [A-ACI]). Times in the past map to now. */
    fun toWall(tripMs: Long): Long {
        val now = now()
        return time.wallMs() + maxOf(0L, tripMs - now)
    }

    /** A wall time reported by T16 or a receiver, on the trip clock. Future wall times map to now. */
    fun toTrip(wallMs: Long): Long {
        val now = now()
        return now - maxOf(0L, time.wallMs() - wallMs)
    }

    companion object {
        fun anchorNow(time: TimeSource): ClockAnchor = ClockAnchor(time.wallMs(), time.elapsedMs(), time.bootCount())

        /**
         * Same boot as [a]: equal BOOT_COUNT when both are known; otherwise (BOOT_COUNT unreadable) elapsed realtime
         * has not gone back. After a reboot the anchor is replaced and the engine clamps `now` (T10 RK9).
         */
        fun anchorValid(a: ClockAnchor, time: TimeSource): Boolean {
            val current = time.bootCount()
            return if (a.bootCount != null && current != null) a.bootCount == current else time.elapsedMs() >= a.elapsedMs
        }
    }
}
