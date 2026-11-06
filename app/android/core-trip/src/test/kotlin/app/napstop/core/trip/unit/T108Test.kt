package app.napstop.core.trip.unit

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmMode
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.AlarmSilenced
import app.napstop.core.trip.EndReason
import app.napstop.core.trip.EngineInput
import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.EngineState
import app.napstop.core.trip.FallbackFired
import app.napstop.core.trip.FallbackRestoreStatus
import app.napstop.core.trip.LocationFix
import app.napstop.core.trip.Overshoot
import app.napstop.core.trip.RestoreInfo
import app.napstop.core.trip.Step
import app.napstop.core.trip.Tick
import app.napstop.core.trip.TripEnded
import app.napstop.core.trip.TripEngine
import app.napstop.core.trip.TripOutcome
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.UserAction
import app.napstop.core.trip.UserActionKind
import app.napstop.core.trip.harness.Transcript
import app.napstop.core.trip.support.DEST
import app.napstop.core.trip.support.EngineDriver
import app.napstop.core.trip.support.S
import app.napstop.core.trip.support.TestGeo
import app.napstop.core.trip.support.cfg
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

/**
 * T10 "T10.8" (PO P1, 06/11/2026, C32): in OVERSHOT, `AlarmSilenced` while `ringing == true` and `alarm.lastReason ≠ OVERSHOOT`
 * rings `Alarm(OVERSHOOT, ringNow=true)` once and marks the ring (U130–U132 of "T10.8" §3).
 * Base trip = OvershootDetectorTest U34: DISTANCE 1000, fixes every 60 s at 40 km/h, the vehicle passes the destination while the
 * DISTANCE alarm still rings (overshoot at t = 420 s with `Overshoot` only), the OS ring stops at t = 425 s (inputs come within
 * 60 s of the last fix so that no GpsLost joins the Step).
 * Report: `u130.txt` (times relative to the trip start, transcript encoding of T12 §9.2; no coordinates).
 */
class T108Test {
    private val outDir = File(System.getProperty("napstop.outDir") ?: "build/napstop").also { it.mkdirs() }
    private val v40 = 40 / 3.6
    private val approach = listOf(3000.0, 2300.0, 1600.0, 900.0, 300.0)
    private val away = listOf(400.0, 800.0, 1350.0)
    private val overshootT = 420
    private val silencedT = 425
    private val maxActiveMs = EngineParams().alarmMaxActiveS * 1000L

    private fun ms(t: Int): Long = S + t * 1000L

    private fun fixIn(t: Int, d: Double): EngineInput {
        val p = TestGeo.pointOnMeridian(DEST, d)
        return LocationFix(ms(t), ms(t), p.lat, p.lng, 8.0, v40)
    }

    private fun silencedIn(atMs: Long): EngineInput = AlarmSilenced(atMs, atMs)

    /** U130 (a) up to the overshoot Step: 8 fixes, 60 s apart. */
    private val toOvershoot: List<EngineInput> = (approach + away).mapIndexed { i, d -> fixIn(60 * i, d) }

    private fun startStep(): Step = TripEngine.start(cfg(AlarmMode.DISTANCE, thr = 1000), EngineParams(), S)

    private fun drive(from: EngineState, inputs: List<EngineInput>): List<Step> {
        var s = from
        return inputs.map { x -> TripEngine.reduce(s, x).also { s = it.state } }
    }

    /** Driver at the overshoot Step of (a): OVERSHOT entered while the DISTANCE alarm rings (asserted). */
    private fun overshotWhileRinging(): EngineDriver {
        val e = EngineDriver(cfg(AlarmMode.DISTANCE, thr = 1000))
        for (x in toOvershoot) e.feed(x)
        val ov = e.last
        assertEquals(ms(overshootT), ov.state.nowMs)
        assertEquals(1, ov.events.filterIsInstance<Overshoot>().size, "precondition: Overshoot at t = $overshootT")
        assertTrue(ov.events.none { it is Alarm }, "precondition: no Alarm with the Overshoot (ringing)")
        assertEquals(TripPhase.OVERSHOT, ov.view.phase)
        assertTrue(ov.state.alarm.ringing)
        assertEquals(AlarmReason.DISTANCE, ov.state.alarm.lastReason)
        assertEquals(listOf(AlarmReason.DISTANCE), e.all<Alarm>().map { it.reason })
        return e
    }

    private fun overshootAlarms(e: EngineDriver): List<Alarm> = e.all<Alarm>().filter { it.reason == AlarmReason.OVERSHOOT }

    private fun note(key: String, text: String) {
        synchronized(LOG) {
            LOG[key] = text
            File(outDir, "u130.txt").writeText(LOG.entries.joinToString("\n", postfix = "\n") { "${it.key}: ${it.value}" })
        }
    }

    private fun enc(s: Step): String = "t=${(s.state.nowMs - S) / 1000} [${s.events.joinToString(",") { Transcript.encodeEvent(it, S) }}]"

    // ---------------------------------------------------------------- U130

    @Test
    fun `U130 a ALARMING ringing, overshoot, AlarmSilenced rings OVERSHOOT once and marks the ring, b second AlarmSilenced is silent`() {
        val e = overshotWhileRinging()
        val ring1 = e.state.alarm.lastRingAtMs!!
        val firstAt = e.state.alarm.atMs
        val a = e.feed(silencedIn(ms(silencedT)))
        val v = a.view
        assertEquals(listOf(Alarm(ms(silencedT), AlarmReason.OVERSHOOT, true, false, v.distanceM, v.etaS, v.batteryPct)), a.events)
        assertEquals(AlarmReason.OVERSHOOT, a.state.alarm.lastReason)
        assertEquals(ms(silencedT), a.state.alarm.lastRingAtMs)
        assertTrue(a.state.alarm.ringing)
        assertTrue(v.alarmRinging)
        assertEquals(TripPhase.OVERSHOT, v.phase)
        // The first alarm of the trip (atMs, reason, source) is unchanged; the overshoot itself is not re-reported.
        assertEquals(firstAt, a.state.alarm.atMs)
        assertEquals(AlarmReason.DISTANCE, a.state.alarm.reason)
        assertEquals(ms(overshootT), a.state.overshootAtMs)
        assertTrue(ring1 < ms(silencedT))
        // (b) the overshoot ring stops too: nothing, ringing = false.
        val b = e.feed(silencedIn(ms(silencedT + 5)))
        assertTrue(b.events.isEmpty(), "b: ${b.events}")
        assertTrue(!b.state.alarm.ringing)
        assertEquals(AlarmReason.OVERSHOOT, b.state.alarm.lastReason)
        assertEquals(ms(silencedT), b.state.alarm.lastRingAtMs)
        assertEquals(1, overshootAlarms(e).size)
        note("a", enc(a) + " lastRingAtMs=${(a.state.alarm.lastRingAtMs!! - S) / 1000} ringing=${a.state.alarm.ringing}")
        note("b", enc(b) + " ringing=${b.state.alarm.ringing}")
    }

    @Test
    fun `U130 c TRACKING overshoot already rang OVERSHOOT, AlarmSilenced is silent`() {
        val e = EngineDriver(cfg(AlarmMode.DISTANCE, thr = 500))
        listOf(900.0, 800.0, 1100.0, 2000.0).forEachIndexed { i, d -> e.feed(fixIn(180 * i, d)) }
        assertEquals(TripPhase.OVERSHOT, e.view.phase)
        assertEquals(AlarmReason.OVERSHOOT, e.last.events.filterIsInstance<Alarm>().single().reason)
        val s = e.feed(silencedIn(ms(545)))
        assertTrue(s.events.isEmpty(), "c: ${s.events}")
        assertTrue(!s.state.alarm.ringing)
        assertEquals(1, overshootAlarms(e).size)
        note("c", enc(s))
    }

    @Test
    fun `U130 d ALARMING not ringing, overshoot rings (PO 18), AlarmSilenced is silent`() {
        val e = EngineDriver(cfg(AlarmMode.DISTANCE, thr = 1000))
        approach.forEachIndexed { i, d -> e.feed(fixIn(60 * i, d)) }
        e.feed(silencedIn(ms(300)))
        away.forEachIndexed { i, d -> e.feed(fixIn(305 + 60 * i, d)) }
        val ov = e.last.events
        assertEquals(1, ov.filterIsInstance<Overshoot>().size)
        assertEquals(AlarmReason.OVERSHOOT, ov.filterIsInstance<Alarm>().single().reason)
        val s = e.feed(silencedIn(ms(430)))
        assertTrue(s.events.isEmpty(), "d: ${s.events}")
        assertEquals(1, overshootAlarms(e).size)
        note("d", enc(s))
    }

    @Test
    fun `U130 e FallbackFired in OVERSHOT before AlarmSilenced does not count as the overshoot ring`() {
        val e = overshotWhileRinging()
        val f = e.feed(FallbackFired(ms(422), ms(422)))
        assertTrue(f.events.isEmpty(), "e fired: ${f.events}")
        assertEquals(AlarmReason.DISTANCE, f.state.alarm.lastReason)
        val s = e.feed(silencedIn(ms(silencedT)))
        assertEquals(AlarmReason.OVERSHOOT, s.events.filterIsInstance<Alarm>().single().reason)
        assertTrue(s.events.filterIsInstance<Alarm>().single().ringNow)
        assertTrue(e.feed(silencedIn(ms(silencedT + 5))).events.isEmpty())
        assertEquals(1, overshootAlarms(e).size)
        note("e", enc(s))
    }

    @Test
    fun `U130 f DISMISS before AlarmSilenced ends the trip, no ring`() {
        val e = overshotWhileRinging()
        val d = e.feed(UserAction(ms(422), UserActionKind.DISMISS))
        assertEquals(EndReason.DISMISSED, d.events.filterIsInstance<TripEnded>().single().endReason)
        val s = e.feed(silencedIn(ms(silencedT)))
        assertTrue(s.events.isEmpty(), "f: ${s.events}")
        assertEquals(TripPhase.ENDED, s.view.phase)
        assertTrue(overshootAlarms(e).isEmpty())
        note("f", enc(s))
    }

    @Test
    fun `U130 g AlarmSilenced at lastRingAtMs + alarmMaxActiveS ends ALARM_UNANSWERED without a ring, 1 ms earlier it rings`() {
        val e = overshotWhileRinging()
        val ring1 = e.state.alarm.lastRingAtMs!!
        val g = e.feed(silencedIn(ring1 + maxActiveMs))
        assertTrue(g.events.none { it is Alarm }, "g: ${g.events}")
        val end = g.events.filterIsInstance<TripEnded>().single()
        assertEquals(EndReason.ALARM_UNANSWERED, end.endReason)
        assertEquals(TripOutcome.MISSED, end.outcome)
        assertEquals(TripPhase.ENDED, g.view.phase)
        val e2 = overshotWhileRinging()
        val g2 = e2.feed(silencedIn(ring1 + maxActiveMs - 1))
        assertEquals(AlarmReason.OVERSHOOT, g2.events.filterIsInstance<Alarm>().single().reason)
        assertTrue(g2.events.none { it is TripEnded })
        assertEquals(ring1 + maxActiveMs - 1, g2.state.alarm.lastRingAtMs)
        note("g", enc(g))
        note("g2", enc(g2))
    }

    // ---------------------------------------------------------------- U131

    @Test
    fun `U131 alarmMaxActiveS counts from the overshoot ring`() {
        val e = overshotWhileRinging()
        val ring1 = e.state.alarm.lastRingAtMs!!
        e.feed(silencedIn(ms(silencedT)))
        val ring2 = e.state.alarm.lastRingAtMs!!
        assertEquals(ms(silencedT), ring2)
        assertTrue(e.tickMs(ring1 + maxActiveMs).events.none { it is TripEnded }, "old mark must not end the trip")
        assertTrue(e.tickMs(ring2 + maxActiveMs - 1).events.none { it is TripEnded })
        val end = e.tickMs(ring2 + maxActiveMs)
        assertEquals(EndReason.ALARM_UNANSWERED, end.events.filterIsInstance<TripEnded>().single().endReason)
        assertEquals(listOf(AlarmReason.DISTANCE, AlarmReason.OVERSHOOT), e.all<Alarm>().map { it.reason })
        note("u131", enc(end))
    }

    // ---------------------------------------------------------------- U132

    @Test
    fun `U132 snapshot round trip and restore PENDING after any Step of (a) continues the same, no new snapshot key`() {
        val inputs = toOvershoot + silencedIn(ms(silencedT)) + silencedIn(ms(silencedT + 5)) + Tick(ms(silencedT + 60))
        val start = startStep()
        val ref = listOf(start) + drive(start.state, inputs)
        fun line(s: Step) = "${s.state.nowMs - S} ${s.events.joinToString { Transcript.encodeEvent(it, S) }} ${Transcript.encodeView(s.view, S)}"
        val want = ref.map(::line)
        val reRing = ref[toOvershoot.size + 1]
        assertEquals(AlarmReason.OVERSHOOT, reRing.events.filterIsInstance<Alarm>().single().reason)
        for (k in 0 until ref.size - 1) {
            val st = TripEngine.decodeSnapshot(TripEngine.encodeSnapshot(ref[k].state))
            assertEquals(ref[k].state, st, "decode after Step $k")
            val rp = TripEngine.restore(st, st.nowMs, RestoreInfo(FallbackRestoreStatus.PENDING))
            assertTrue(rp.events.isEmpty(), "restore PENDING at now after Step $k: ${rp.events}")
            assertEquals(want.drop(k + 1), drive(rp.state, inputs.drop(k)).map(::line), "after Step $k")
        }
        // The rule reads phase, alarm.lastReason and alarm.ringing only: the snapshot keys are those of the Step before.
        val keys = Regex("\"([A-Za-z0-9]+)\":")
        fun keysOf(s: EngineState) = keys.findAll(TripEngine.encodeSnapshot(s)).map { it.groupValues[1] }.toList()
        assertEquals(keysOf(ref[toOvershoot.size].state), keysOf(reRing.state))
        note("u132", "round trip + restore PENDING after each of ${ref.size - 1} Steps: equal; snapshot keys unchanged")
    }

    private companion object {
        val LOG = java.util.TreeMap<String, String>()
    }
}
