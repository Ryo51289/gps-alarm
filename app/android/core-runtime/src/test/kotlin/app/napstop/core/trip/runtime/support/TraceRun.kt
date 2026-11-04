package app.napstop.core.trip.runtime.support

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.Arrived
import app.napstop.core.trip.FallbackAlarmChanged
import app.napstop.core.trip.GpsLost
import app.napstop.core.trip.GpsRecovered
import app.napstop.core.trip.LowBatteryRisk
import app.napstop.core.trip.Overshoot
import app.napstop.core.trip.PreAlert
import app.napstop.core.trip.SamplingPolicyChanged
import app.napstop.core.trip.Snoozed
import app.napstop.core.trip.TripEnded
import app.napstop.core.trip.TripEvent
import app.napstop.core.trip.runtime.RawFix

/**
 * Where fixes come from in a trace run (spec T15 L30–L32). `policy` (README §6, phase 0): the GPX sample at t is
 * delivered when t − last delivered ≥ the interval the runtime asked the location source for; nothing while the
 * runtime has no request (no FGS). [wakeOnly] (L32 b): fixes only when the app is woken by an alarm — the latest
 * sample, aged. Samples at t ≥ [dropFromT] are never delivered (simulated GPS loss).
 */
class FixFeed(val gpx: Gpx, val intervalS: Int, val dropFromT: Int? = null, val wakeOnly: Boolean = false) {
    var idx = 0
    var lastDelivered: Int? = null

    fun copy(): FixFeed = FixFeed(gpx, intervalS, dropFromT, wakeOnly).also { it.idx = idx; it.lastDelivered = lastDelivered }

    /** Next deliverable sample t ≥ [fromT] for a request with [intervalMs] (null = no request: nothing). */
    fun nextSampleT(fromT: Int, intervalMs: Long?): Int? {
        if (wakeOnly || intervalMs == null) return null
        val last = lastDelivered
        val minT = if (last == null) fromT else maxOf(fromT, last + (intervalMs / 1000L).toInt())
        while (idx < gpx.samples.size && gpx.samples[idx].t < minT) idx++
        val s = gpx.samples.getOrNull(idx) ?: return null
        if (dropFromT != null && s.t >= dropFromT) return null
        return s.t
    }

    fun latestAt(t: Int): Sample? {
        if (dropFromT != null && t >= dropFromT) return null
        val s = gpx.at(t - t % intervalS) ?: return null
        return s
    }
}

fun eventName(e: TripEvent): String =
    when (e) {
        is PreAlert -> "preAlert"
        is Alarm -> "alarm"
        is Snoozed -> "snoozed"
        is GpsLost -> "gpsLost"
        is GpsRecovered -> "gpsRecovered"
        is LowBatteryRisk -> "lowBatteryRisk"
        is Overshoot -> "overshoot"
        is Arrived -> "arrived"
        is FallbackAlarmChanged -> "fallbackAlarmChanged"
        is SamplingPolicyChanged -> "samplingPolicyChanged"
        is TripEnded -> "tripEnded"
    }

/**
 * Discrete-event driver of one runtime "process" over a trace. Virtual time 0 = trace second [offsetS]. Between two
 * deliveries the test clock advances in steps of ≤ [stepMs]; the runtime's own timers (awake Tick) run on time.
 */
class TraceRun(
    val world: World,
    val feed: FixFeed,
    val tripId: String,
    val offsetS: Int = 0,
    val silenceAfterMs: Long? = null,
    /** Called once, right after the first fake OS delivery (L31: the system restarts LocationService then). */
    var afterFirstDelivery: (() -> Unit)? = null,
    /**
     * Longest clock step between two deliveries. A wake alarm set by a Step inside a step is delivered up to this late;
     * with the FGS up the runtime's own awake Tick (exact, a coroutine timer) covers it anyway.
     */
    val stepMs: Long = 1_000L,
) {
    var fixesDelivered = 0
    var wakeDeliveries = 0

    private fun tNow(): Int = offsetS + (world.scope.testScheduler.currentTime / 1000L).toInt()

    private fun emit(s: Sample, ageS: Int) {
        val nanos = world.time.elapsedNanos() - ageS * 1_000_000_000L
        world.location.emit(RawFix(s.lat, s.lng, s.accuracyM.toFloat(), s.speedMps?.toFloat(), nanos))
        fixesDelivered++
        world.settle()
    }

    /** Runs until trace second [endT] (inclusive), the first Alarm when [stopAtFirstAlarm], or [captureAt] hooks. */
    fun run(endT: Int, stopAtFirstAlarm: Boolean = false, captureAt: List<Int> = emptyList(), onCapture: (Int) -> Unit = {}) {
        val captures = ArrayDeque(captureAt.sorted())
        val endV = (endT - offsetS) * 1000L
        while (true) {
            if (stopAtFirstAlarm && world.firstAlarm() != null) return
            val v = world.scope.testScheduler.currentTime
            val spec = world.location.spec
            val sampleT = feed.nextSampleT(tNow(), spec?.intervalMs)
            val sampleV = sampleT?.let { (it - offsetS) * 1000L }
            val osV = world.nextOsDeliveryMs(silenceAfterMs, tripId)
            val capV = captures.firstOrNull()?.let { (it - offsetS) * 1000L }
            val next = listOfNotNull(sampleV, osV, capV).minOrNull() ?: return
            if (next > endV) {
                if (v < endV) world.advance(endV - v)
                return
            }
            // Advance in ≤ 1 s steps; re-plan if the runtime set an earlier alarm meanwhile.
            var replan = false
            while (world.scope.testScheduler.currentTime < next) {
                val d = minOf(stepMs, next - world.scope.testScheduler.currentTime)
                world.advance(d)
                val os2 = world.nextOsDeliveryMs(silenceAfterMs, tripId)
                if (os2 != null && os2 < next && os2 <= world.scope.testScheduler.currentTime) {
                    replan = true
                    break
                }
                if (world.location.spec != spec) {
                    replan = true
                    break
                }
                if (stopAtFirstAlarm && world.firstAlarm() != null) return
            }
            val now = world.scope.testScheduler.currentTime
            while (capV != null && captures.isNotEmpty() && (captures.first() - offsetS) * 1000L <= now) onCapture(captures.removeFirst())
            val delivered =
                world.deliverDue(silenceAfterMs, tripId) {
                    wakeDeliveries++
                    if (feed.wakeOnly && world.location.spec != null) feed.latestAt(tNow())?.let { emit(it, tNow() - it.t) }
                }
            if (delivered) {
                afterFirstDelivery?.let {
                    afterFirstDelivery = null
                    it()
                    world.settle()
                }
            }
            if (replan) continue
            if (sampleV != null && sampleV <= now && world.location.spec != null) {
                val s = feed.gpx.samples[feed.idx]
                feed.idx++
                feed.lastDelivered = s.t
                emit(s, 0)
            }
        }
    }
}
