package app.napstop.core.trip.runtime

import kotlin.math.ceil
import kotlin.math.floor

/**
 * Wall/elapsed pair the trip clock is measured from (T10 §2.6). Survives process death in the snapshot.
 * [wallMs] = trip time at the anchor (≈ wall clock at trip start; after a [TripClock.rebase], the trip time of the
 * rebase). [speed] = trip ms per real ms (T18 D1): 1.0 for a real trip, the simulation speed for a simulated one.
 */
data class ClockAnchor(val wallMs: Long, val elapsedMs: Long, val bootCount: Int?, val speed: Double = 1.0)

/** Read-only, thread-safe view of a trip clock (no monotonic floor): for the simulation source and timers (T18 §3). */
interface SimTimeline {
    fun tripNow(): Long

    /** Real ms until trip time [tripMs]; 0 if reached. */
    fun realDelayMs(tripMs: Long): Long
}

/**
 * Duration conversions of a clock with a speed factor (T18 §3). `speed == 1.0` takes the integer path, so a real trip
 * computes exactly what it did before T18 (SM01).
 */
object ClockMath {
    /** Real duration → trip duration. */
    fun up(d: Long, speed: Double): Long = if (speed == 1.0) d else floor(d * speed).toLong()

    /** Trip duration → real duration; ceil: when it is due, the trip time has been reached. */
    fun down(d: Long, speed: Double): Long = if (speed == 1.0) d else ceil(d / speed).toLong()
}

/**
 * Trip clock (spec T15 §5.3, T18 §3): monotonic (elapsed realtime from [anchor], times [speed]), close to wall clock at
 * 1×, never goes back. [floorMs] = the engine's `nowMs` when restoring, so the clock never issues a time before the
 * last Step. [now], [rebase] and the conversions are for the runtime's actor only; [timeline] may be read from any
 * thread.
 */
class TripClock(anchor: ClockAnchor, private val time: TimeSource, floorMs: Long = Long.MIN_VALUE) {
    @Volatile
    var anchor: ClockAnchor = anchor
        private set

    @Volatile
    private var lastIssued = floorMs

    val speed: Double get() = anchor.speed

    /** Backed by the trip time at the current elapsed realtime; does not move [now]'s floor. */
    val timeline: SimTimeline =
        object : SimTimeline {
            override fun tripNow(): Long = tripAt(this@TripClock.anchor, time.elapsedMs())

            override fun realDelayMs(tripMs: Long): Long {
                val a = this@TripClock.anchor
                return ClockMath.down(maxOf(0L, tripMs - tripAt(a, time.elapsedMs())), a.speed)
            }
        }

    private fun tripAt(a: ClockAnchor, elapsed: Long): Long = a.wallMs + ClockMath.up(elapsed - a.elapsedMs, a.speed)

    fun now(): Long {
        val t = maxOf(lastIssued, tripAt(anchor, time.elapsedMs()))
        lastIssued = t
        return t
    }

    /** For ELAPSED_REALTIME_WAKEUP. Times in the past map to now. */
    fun toElapsed(tripMs: Long): Long {
        val now = now()
        return time.elapsedMs() + ClockMath.down(maxOf(0L, tripMs - now), speed)
    }

    /** For setAlarmClock (AlarmClockInfo takes wall time [A-ACI]). Times in the past map to now. */
    fun toWall(tripMs: Long): Long {
        val now = now()
        return time.wallMs() + ClockMath.down(maxOf(0L, tripMs - now), speed)
    }

    /** A wall time reported by T16 or a receiver, on the trip clock. Future wall times map to now. */
    fun toTrip(wallMs: Long): Long {
        val now = now()
        return now - ClockMath.up(maxOf(0L, time.wallMs() - wallMs), speed)
    }

    /** A wall time in the future (ring guard), on the trip clock. Past wall times map to now. */
    fun futureWallToTrip(wallMs: Long): Long {
        val now = now()
        return now + ClockMath.up(maxOf(0L, wallMs - time.wallMs()), speed)
    }

    /** Real ms until trip time [tripMs]; 0 if reached. */
    fun realDelayMs(tripMs: Long): Long = ClockMath.down(maxOf(0L, tripMs - now()), speed)

    /** New speed from now on (T18 D2, D3): continuous, never goes back. Actor only. */
    fun rebase(newSpeed: Double) {
        require(newSpeed.isFinite() && newSpeed > 0.0) { "speed" }
        val e = time.elapsedMs()
        val a = anchor
        val n = maxOf(lastIssued, tripAt(a, e))
        lastIssued = n
        anchor = ClockAnchor(n, e, a.bootCount, newSpeed)
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
