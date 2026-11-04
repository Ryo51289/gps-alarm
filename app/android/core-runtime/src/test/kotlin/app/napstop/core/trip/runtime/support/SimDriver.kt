package app.napstop.core.trip.runtime.support

import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.runtime.ForegroundResult
import app.napstop.core.trip.runtime.RingEvent
import app.napstop.core.trip.runtime.RingEventKind
import app.napstop.core.trip.runtime.StartOutcome
import app.napstop.core.trip.runtime.TripMeta
import app.napstop.core.trip.runtime.sim.SimSpec
import kotlin.math.ceil

/**
 * T18: drives a simulated trip in a [World] that has a [RecordingJournal]. The runtime runs everything itself (simulated
 * source, in-process timers, awake Tick); the driver only moves the test clock, reads the trip clock from the journal
 * lines `sim` / `sim_speed`, and plays the T16 auto-silence ([silenceAfterMs], real ms) as TraceRun does.
 */
class SimDriver(val world: World, val meta: TripMeta, val silenceAfterMs: Long? = null, val maxStepRealMs: Long = 10_000L) {
    private val journal: RecordingJournal = world.journal as RecordingJournal

    /** Trip time at commit = trace t 0. */
    val simStart: Long get() = journal.lines.first { it.ev == "sim" }.tripMs!!

    /** Wall time at commit. */
    val commitWall: Long get() = journal.lines.first { it.ev == "sim" }.wallMs

    val speed: Double get() = meta.simulation!!.speedFactor

    /** Trip clock now, from the journal (the runtime's clock is private). */
    fun tripNow(): Long {
        val wall = world.time.wallMs()
        val rebase = journal.lines.firstOrNull { it.ev == "sim_speed" }
        return if (rebase != null) {
            rebase.tripMs!! + (wall - rebase.wallMs)
        } else {
            simStart + kotlin.math.floor((wall - commitWall) * speed).toLong()
        }
    }

    private fun currentSpeed(): Double = if (journal.lines.any { it.ev == "sim_speed" }) 1.0 else speed

    fun start(destLat: Double, destLng: Double): StartOutcome {
        world.tracking.autoResult = ForegroundResult.Started
        return world.now { world.runtime.start(meta, destLat, destLng) }
    }

    /** Trace second of a trip time. */
    fun t(atMs: Long): Int = ((atMs - simStart) / 1000L).toInt()

    /** Runs until trace second [endT] (trip clock), the trip ended, or [stop] says so (checked after each clock step). */
    fun runTo(endT: Int, stop: () -> Boolean = { false }) {
        val end = simStart + endT * 1000L
        var guard = 0
        while (tripNow() < end) {
            if (stop()) return
            if (world.seen.isNotEmpty() && world.seen.last().view.phase == TripPhase.ENDED) return
            val s = currentSpeed()
            var stepReal = minOf(maxStepRealMs, ceil((end - tripNow()) / s).toLong())
            silenceAt()?.let { at -> stepReal = minOf(stepReal, maxOf(0L, at - world.time.wallMs())) }
            world.advance(maxOf(1L, stepReal))
            silenceIfDue()
            check(++guard < 5_000_000) { "driver loop" }
        }
    }

    private fun silenceAt(): Long? {
        val after = silenceAfterMs ?: return null
        val x = world.alarm.facts[meta.tripId] ?: return null
        val s = x.startedAtWall ?: return null
        return if (x.ringing) s + after else null
    }

    private fun silenceIfDue() {
        val at = silenceAt() ?: return
        if (world.time.wallMs() < at) return
        world.alarm.silence(meta.tripId, at)
        world.now { world.runtime.onRingEvent(RingEvent(meta.tripId, RingEventKind.SILENCED, at)) }
    }

    companion object {
        fun simMeta(trace: TraceCase, c: ExpectCase, speed: Double, tripId: String? = null): TripMeta {
            val m = if (tripId != null) ExpectReader.meta(trace, c, tripId) else ExpectReader.meta(trace, c)
            return m.copy(simulation = SimSpec(trace.traceId, speed))
        }
    }
}
