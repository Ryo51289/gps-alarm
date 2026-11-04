package app.napstop.core.trip.runtime.sim

import app.napstop.core.trip.runtime.SimTimeline
import kotlinx.coroutines.delay

/**
 * Suspends until the trip clock reaches [tripMs] (T18 §4). Sleeps at most [pollMaxMs] at a time and reads the timeline
 * again after each sleep, so a rebase (speed change) takes effect within [pollMaxMs].
 */
suspend fun SimTimeline.awaitTrip(tripMs: Long, pollMaxMs: Long) {
    while (true) {
        val d = realDelayMs(tripMs)
        if (d <= 0L) return
        delay(minOf(d, pollMaxMs))
    }
}
