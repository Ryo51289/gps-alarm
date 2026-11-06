package app.napstop.core.trip.runtime

import app.napstop.core.alarm.AlarmConstants
import app.napstop.core.alarm.RingVariant
import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.EndReason
import app.napstop.core.trip.Overshoot
import app.napstop.core.trip.TripEnded
import app.napstop.core.trip.UserActionKind
import app.napstop.core.trip.runtime.sim.SimSpec
import app.napstop.core.trip.runtime.support.ExpectReader
import app.napstop.core.trip.runtime.support.FakeStore
import app.napstop.core.trip.runtime.support.FixFeed
import app.napstop.core.trip.runtime.support.RecordingJournal
import app.napstop.core.trip.runtime.support.SimDriver
import app.napstop.core.trip.runtime.support.SimRing
import app.napstop.core.trip.runtime.support.SimRingProcess
import app.napstop.core.trip.runtime.support.TraceRun
import app.napstop.core.trip.runtime.support.World
import java.io.File
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Tag
import org.junit.jupiter.api.Test

/**
 * Tester T12.5 (T10.8, PO P1 for T16.2): the T16.2 repro "`coach_gb_phuly_overshoot` 60×, DISTANCE 1 000, nobody touches the
 * first alarm" on the JVM, over many phases of "when does the first ring stop by itself vs when is the overshoot".
 *
 * R1 (simulated trip at 60×, SimDriver, T16 auto-stop played by the driver): ring max 200…400 s step 10 (the overshoot comes
 *    ≈ 280 s after the first ring, so both orders occur) × 3 start phases (wall offset 0 / 123 / 777 ms) × driver step 250 ms or
 *    10 s = 126 runs. Each run: exactly [DISTANCE, OVERSHOOT] rings, no double ring; when the overshoot came while the first ring
 *    still rang, the Overshoot Step does not ring and the OVERSHOOT ring starts exactly at the auto-stop; otherwise the
 *    Overshoot Step rings (#18).
 * R2 (real trip at 1×, the real AlarmControllerCore + `:ring` session machine of T16 with its own RING_MAX auto-stop, nobody
 *    touches): RING_MAX 240…340 s step 20 × 2 start phases = 12 runs. Each run: two ring sessions [DISTANCE, OVERSHOOT], never two at
 *    once; when the first session was still on at the overshoot the second starts at its auto-stop, shows the overshoot variant, and
 *    its own RING_MAX counts again from its start (T10.8 §5, input for T16.2).
 * Report: build/core-runtime/napstop/t125-repro-r1.txt, t125-repro-r2.txt (trip seconds, counts; no coordinates).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class T125TesterOvershootRingReproTest {
    private val outDir: File = File(System.getProperty("napstop.outDir") ?: "build/napstop")
    private val trace by lazy { ExpectReader.read("coach_gb_phuly_overshoot") }
    private val case by lazy { trace.cases.single { it.id == "distance_1000_overshoot_ringing" } }

    private class Outcome(val tag: String, val whileRinging: Boolean, val line: String)

    private fun report(name: String, lines: List<String>) {
        outDir.mkdirs()
        File(outDir, "t125-repro-$name.txt").writeText(lines.joinToString("\n", postfix = "\n"))
    }

    // ---------------------------------------------------------------- R1 simulated 60×

    private fun simRun(ringMaxMs: Long, wallOffsetMs: Long, stepMs: Long, fails: MutableList<String>): Outcome {
        var out: Outcome? = null
        val tag = "R1 ringMax=${ringMaxMs / 1000}s offset=${wallOffsetMs}ms step=${stepMs}ms"
        runTest(timeout = kotlin.time.Duration.parse("10m")) {
            val world = World(this, startWall = 1_700_000_000_000L + wallOffsetMs, journal = RecordingJournal())
            world.listen()
            val meta = SimDriver.simMeta(trace, case, 60.0)
            val d = SimDriver(world, meta, silenceAfterMs = ringMaxMs, maxStepRealMs = stepMs)
            assertEquals(StartOutcome.Started, d.start(trace.destLat, trace.destLng))
            var overWall: Long? = null
            var overStepRang = false
            var overStepRinging: Boolean? = null
            world.runtime.addListener { _, view, _, events ->
                if (overWall == null && events.any { it is Overshoot }) {
                    overWall = world.time.wallMs()
                    overStepRang = events.any { it is Alarm && it.reason == AlarmReason.OVERSHOOT }
                    overStepRinging = view.alarmRinging
                }
            }
            d.runTo(trace.durationS)
            val alarms = world.events.map { it.second }.filterIsInstance<Alarm>()
            val ends = world.events.map { it.second }.filterIsInstance<TripEnded>()
            val rings = world.alarm.ringNowCalls
            val f = ArrayList<String>()
            if (alarms.map { it.reason } != listOf(AlarmReason.DISTANCE, AlarmReason.OVERSHOOT) || alarms.any { !it.ringNow }) {
                f += "alarms ${alarms.map { "${it.reason}:${it.ringNow}" }}"
            }
            if (world.alarm.doubleRings != 0) f += "double rings ${world.alarm.doubleRings}"
            if (ends.isNotEmpty()) f += "trip ended before the user stop: ${ends.map { it.endReason }}"
            val ow = overWall
            if (ow == null || rings.isEmpty()) {
                f += "no overshoot or no ring"
                fails += f.map { "$tag: $it" }
                out = Outcome(tag, false, "$tag FAIL")
                world.kill()
                return@runTest
            }
            val ringStart = rings.first().atWallMs
            val stopAt = ringStart + ringMaxMs
            val whileRinging = ow < stopAt
            if (whileRinging) {
                if (overStepRang) f += "rang OVERSHOOT in the Overshoot Step while the first ring was on"
                if (overStepRinging != true) f += "view not ringing at the overshoot"
                if (rings.map { it.atWallMs - ringStart } != listOf(0L, ringMaxMs)) {
                    f += "rings at ${rings.map { it.atWallMs - ringStart }} ms from the first, want [0, $ringMaxMs] (OVERSHOOT at the auto-stop)"
                }
            } else {
                if (!overStepRang) f += "first ring stopped before the overshoot but the Overshoot Step did not ring (#18)"
                if (rings.map { it.atWallMs - ringStart } != listOf(0L, ow - ringStart)) f += "rings ${rings.map { it.atWallMs - ringStart }}"
            }
            val over = alarms.last()
            val line =
                "$tag alarm=${d.t(alarms.first().atMs)} overshoot=${(ow - ringStart) / 1000.0}s after ring1 " +
                    "${if (whileRinging) "WHILE-RINGING" else "after-stop"} overshootRing=${d.t(over.atMs)} " +
                    "(+${(rings.last().atWallMs - ringStart) / 1000.0}s) ${if (f.isEmpty()) "ok" else "FAIL $f"}"
            fails += f.map { "$tag: $it" }
            out = Outcome(tag, whileRinging, line)
            world.now { world.runtime.userAction(meta.tripId, UserActionKind.STOP_TRIP) }
            world.kill()
        }
        return out!!
    }

    @Tag("slow")
    @Test
    fun r1_simulated60xEveryRunWithAnOvershootWhileRingingGetsTheOvershootRing() {
        val fails = ArrayList<String>()
        val outs = ArrayList<Outcome>()
        for (ringMaxS in 200..400 step 10) {
            for (offset in listOf(0L, 123L, 777L)) {
                for (step in listOf(250L, 10_000L)) outs += simRun(ringMaxS * 1000L, offset, step, fails)
            }
        }
        val whileRinging = outs.count { it.whileRinging }
        report("r1", outs.map { it.line } + "runs ${outs.size}, overshoot while ringing $whileRinging, after the stop ${outs.size - whileRinging}")
        assertEquals(126, outs.size)
        // Both orders must be exercised for the sweep to mean anything.
        assertTrue(whileRinging in 1 until outs.size, "while ringing $whileRinging of ${outs.size}")
        assertTrue(fails.isEmpty()) { fails.joinToString("\n") }
    }

    // ---------------------------------------------------------------- R2 real trip, real ring machine

    private fun realRun(ringMaxMs: Long, wallOffsetMs: Long, fails: MutableList<String>): Outcome {
        var out: Outcome? = null
        val tag = "R2 RING_MAX=${ringMaxMs / 1000}s offset=${wallOffsetMs}ms"
        runTest(timeout = kotlin.time.Duration.parse("10m")) {
            val c = AlarmConstants(ringMaxMs = ringMaxMs)
            var sim: SimRing? = null
            val scope = this
            val world =
                World(
                    scope, startWall = trace.gpx.startMs + wallOffsetMs, store = FakeStore(),
                    ringPort = { w ->
                        w.time.bootCountValue = 7
                        SimRing(w, SimRingProcess(scope, w.time, c)).also { sim = it }
                    },
                )
            world.listen()
            val proc = sim!!.proc
            proc.dismissAfterMs = null // nobody wakes up
            val meta = ExpectReader.meta(trace, case)
            assertEquals(StartOutcome.Started, world.now { world.runtime.start(meta, trace.destLat, trace.destLng) })
            var overWall: Long? = null
            world.runtime.addListener { _, _, _, events -> if (overWall == null && events.any { it is Overshoot }) overWall = world.time.wallMs() }
            // No silenceAfterMs: the `:ring` machine stops by itself after RING_MAX and sends SILENCED.
            TraceRun(world, FixFeed(trace.gpx, trace.intervalS), meta.tripId).run(trace.durationS)
            val f = ArrayList<String>()
            val reasons = proc.sessions.map { it.second.request.reason }
            if (reasons != listOf(AlarmReason.DISTANCE, AlarmReason.OVERSHOOT)) f += "sessions $reasons"
            if (proc.overlaps != 0) f += "two sessions at once (${proc.overlaps})"
            val ends = world.events.map { it.second }.filterIsInstance<TripEnded>().filter { it.endReason != EndReason.USER_STOP }
            if (ends.isNotEmpty()) f += "trip ended ${ends.map { it.endReason }}"
            val ow = overWall
            var whileRinging = false
            if (ow == null || proc.sessions.size < 2) {
                f += "no overshoot or < 2 sessions"
            } else {
                val s1 = proc.sessions[0].first
                val s2 = proc.sessions[1].first
                whileRinging = ow < s1 + ringMaxMs
                if (whileRinging) {
                    if (s2 < s1 + ringMaxMs) f += "second session at ${s2 - s1} ms, before the first stopped"
                    // The engine rings at the SILENCED Step; the session starts after the confirm delay of the fake `:ring`.
                    if (s2 - (s1 + ringMaxMs) > 5_000) f += "second session ${s2 - s1 - ringMaxMs} ms after the first stopped"
                } else if (s2 < ow) {
                    f += "second session before the overshoot"
                }
                if (proc.sessionContent.getOrNull(1)?.variant != RingVariant.OVERSHOOT) f += "second session variant ${proc.sessionContent.getOrNull(1)}"
                // RING_MAX counts again from the second session: its own auto-stop at s2 + RING_MAX when that is inside the trace.
                val silenced = proc.ring.events.filter { it.kind == RingEventKind.SILENCED }.map { it.atWallMs }
                val traceEndWall = trace.gpx.startMs + wallOffsetMs + trace.durationS * 1000L
                val want = listOf(s1 + ringMaxMs, s2 + ringMaxMs).filter { it <= traceEndWall }
                if (silenced != want) f += "SILENCED at ${silenced.map { it - s1 }} ms from s1, want ${want.map { it - s1 }}"
            }
            val line = "$tag sessions=$reasons ${if (whileRinging) "WHILE-RINGING" else "after-stop"} " +
                "starts=${proc.sessions.map { (it.first - (proc.sessions.firstOrNull()?.first ?: 0L)) / 1000.0 }} ${if (f.isEmpty()) "ok" else "FAIL $f"}"
            fails += f.map { "$tag: $it" }
            out = Outcome(tag, whileRinging, line)
            world.now { world.runtime.userAction(meta.tripId, UserActionKind.STOP_TRIP) }
        }
        return out!!
    }

    @Test
    fun r2_realTripRealRingMachineSecondSessionIsANewOvershootSession() {
        val fails = ArrayList<String>()
        val outs = ArrayList<Outcome>()
        for (ringMaxS in 240..340 step 20) {
            for (offset in listOf(0L, 431L)) outs += realRun(ringMaxS * 1000L, offset, fails)
        }
        val whileRinging = outs.count { it.whileRinging }
        report("r2", outs.map { it.line } + "runs ${outs.size}, overshoot while ringing $whileRinging, after the stop ${outs.size - whileRinging}")
        assertTrue(whileRinging in 1 until outs.size, "while ringing $whileRinging of ${outs.size}")
        assertTrue(fails.isEmpty()) { fails.joinToString("\n") }
    }

    /** Sanity: the case used here is the T11.5 one (osRingMaxS 600, DISTANCE 1000) and the trace has a single overshoot window. */
    @Test
    fun r0_theReproUsesTheTr44Case() {
        assertEquals(600, case.osRingMaxS)
        assertTrue(case.expect.any { it.event == "overshoot" })
        assertTrue(SimSpec(trace.traceId, 60.0).speedFactor == 60.0)
    }
}
