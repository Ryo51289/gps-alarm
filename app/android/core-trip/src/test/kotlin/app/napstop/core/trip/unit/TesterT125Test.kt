package app.napstop.core.trip.unit

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmMode
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.AlarmSilenced
import app.napstop.core.trip.AvailabilityCause
import app.napstop.core.trip.EndReason
import app.napstop.core.trip.EngineInput
import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.FallbackFired
import app.napstop.core.trip.FallbackRestoreStatus
import app.napstop.core.trip.LocationAvailability
import app.napstop.core.trip.LocationFix
import app.napstop.core.trip.Overshoot
import app.napstop.core.trip.RestoreInfo
import app.napstop.core.trip.TripEnded
import app.napstop.core.trip.TripEngine
import app.napstop.core.trip.TripOutcome
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.UserAction
import app.napstop.core.trip.UserActionKind
import app.napstop.core.trip.support.DEST
import app.napstop.core.trip.support.EngineDriver
import app.napstop.core.trip.support.S
import app.napstop.core.trip.support.TestGeo
import app.napstop.core.trip.support.cfg
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Tester T12.5 (T10.8, PO P1), beyond U130–U132: risk areas of the "kêu lại khi chuông ngừng" rule.
 * Same base trip as T108Test (U34 build: DISTANCE 1000, fixes 60 s apart at 40 km/h, overshoot at t = 420 while the DISTANCE
 * alarm still rings).
 * - X1: a snapshot written by a pre-T10.8 engine after the chime stopped in OVERSHOT (ringing = false, lastReason = DISTANCE) is
 *   restored; the platform re-sends AlarmSilenced (T10 §7.2) → nothing (rule row "ringing == false"). A FallbackFired after it makes
 *   ringing true again, and its AlarmSilenced then rings OVERSHOOT once (U130 e on an old snapshot).
 * - X2: the expiry is measured from the latest ring (a FallbackFired in OVERSHOT moves lastRingAtMs): AlarmSilenced at
 *   ring1 + alarmMaxActiveS still rings when a fallback rang later; and at fallback + alarmMaxActiveS it ends without a ring.
 * - X3: a late AlarmSilenced (input atMs later than silencedAtMs; app dead 30 min) rings at the Step time, not at silencedAtMs.
 * - X4: location services turned off in OVERSHOT before the chime stops does not block the ring; DISMISS after the OVERSHOOT
 *   ring ends MISSED / DISMISSED; SNOOZE on the OVERSHOOT ring is ignored and the next AlarmSilenced is silent.
 */
class TesterT125Test {
    private val v40 = 40 / 3.6
    private val approach = listOf(3000.0, 2300.0, 1600.0, 900.0, 300.0)
    private val away = listOf(400.0, 800.0, 1350.0)
    private val maxActiveMs = EngineParams().alarmMaxActiveS * 1000L

    private fun ms(t: Int): Long = S + t * 1000L

    private fun fixIn(t: Int, d: Double): EngineInput {
        val p = TestGeo.pointOnMeridian(DEST, d)
        return LocationFix(ms(t), ms(t), p.lat, p.lng, 8.0, v40)
    }

    private fun overshotWhileRinging(): EngineDriver {
        val e = EngineDriver(cfg(AlarmMode.DISTANCE, thr = 1000))
        (approach + away).forEachIndexed { i, d -> e.feed(fixIn(60 * i, d)) }
        assertEquals(1, e.last.events.filterIsInstance<Overshoot>().size, "precondition: Overshoot at 420")
        assertTrue(e.last.events.none { it is Alarm }, "precondition: no Alarm with the Overshoot")
        assertTrue(e.state.alarm.ringing)
        assertEquals(AlarmReason.DISTANCE, e.state.alarm.lastReason)
        return e
    }

    private fun overshootAlarms(e: EngineDriver): List<Alarm> = e.all<Alarm>().filter { it.reason == AlarmReason.OVERSHOOT }

    @Test
    fun `X1 pre-T10_8 snapshot, chime already stopped in OVERSHOT - AlarmSilenced is silent, a later fallback ring re-rings OVERSHOOT once`() {
        val e = overshotWhileRinging()
        // What the engine before T10.8 left after AlarmSilenced at 425: OVERSHOT, ringing = false, lastReason = DISTANCE.
        val old = e.state.copy(nowMs = ms(425), alarm = e.state.alarm.copy(ringing = false))
        val st = TripEngine.decodeSnapshot(TripEngine.encodeSnapshot(old))
        val r = TripEngine.restore(st, ms(600), RestoreInfo(FallbackRestoreStatus.PENDING))
        assertTrue(r.events.none { it is Alarm }, "restore: ${r.events}")
        assertEquals(TripPhase.OVERSHOT, r.view.phase)
        val e2 = EngineDriver(cfg(AlarmMode.DISTANCE, thr = 1000)).also { it.state = r.state }
        val s = e2.feed(AlarmSilenced(ms(601), ms(601)))
        assertTrue(s.events.isEmpty(), "ringing == false: nothing (${s.events})")
        assertFalse(s.state.alarm.ringing)
        assertEquals(AlarmReason.DISTANCE, s.state.alarm.lastReason)
        val f = e2.feed(FallbackFired(ms(700), ms(700)))
        assertTrue(f.events.none { it is Alarm }, "FallbackFired in OVERSHOT: ${f.events}")
        assertTrue(f.state.alarm.ringing)
        val s2 = e2.feed(AlarmSilenced(ms(760), ms(760)))
        assertEquals(listOf(AlarmReason.OVERSHOOT), s2.events.filterIsInstance<Alarm>().map { it.reason }, "${s2.events}")
        assertTrue(s2.events.filterIsInstance<Alarm>().single().ringNow)
        assertTrue(e2.feed(AlarmSilenced(ms(765), ms(765))).events.isEmpty())
    }

    @Test
    fun `X2 the expiry counts from the latest ring - a fallback ring in OVERSHOT moves it`() {
        val e = overshotWhileRinging()
        val ring1 = e.state.alarm.lastRingAtMs!!
        val fbAt = ms(1_000)
        e.feed(FallbackFired(fbAt, fbAt))
        assertEquals(fbAt, e.state.alarm.lastRingAtMs)
        // At ring1 + alarmMaxActiveS (not expired from the fallback ring): step 3 does not end, the rule rings.
        val s = e.feed(AlarmSilenced(ring1 + maxActiveMs, ring1 + maxActiveMs))
        assertTrue(s.events.none { it is TripEnded }, "${s.events}")
        assertEquals(listOf(AlarmReason.OVERSHOOT), s.events.filterIsInstance<Alarm>().map { it.reason }, "${s.events}")
        // Second scenario: the chime stops exactly at fallback + alarmMaxActiveS → TripEnded, no ring.
        val e2 = overshotWhileRinging()
        e2.feed(FallbackFired(fbAt, fbAt))
        val g = e2.feed(AlarmSilenced(fbAt + maxActiveMs, fbAt + maxActiveMs))
        assertTrue(g.events.none { it is Alarm }, "${g.events}")
        assertEquals(EndReason.ALARM_UNANSWERED, g.events.filterIsInstance<TripEnded>().single().endReason)
        assertTrue(overshootAlarms(e2).isEmpty())
    }

    @Test
    fun `X3 a late AlarmSilenced rings at the Step time, alarmMaxActiveS counts from it`() {
        val e = overshotWhileRinging()
        val stepAt = ms(425 + 30 * 60)
        val s = e.feed(AlarmSilenced(stepAt, ms(425)))
        val a = s.events.filterIsInstance<Alarm>().single()
        assertEquals(AlarmReason.OVERSHOOT, a.reason)
        assertEquals(stepAt, a.atMs, "Alarm.atMs = now of the Step, not silencedAtMs")
        assertEquals(stepAt, s.state.alarm.lastRingAtMs)
        assertTrue(e.tickMs(stepAt + maxActiveMs - 1).events.none { it is TripEnded })
        assertEquals(EndReason.ALARM_UNANSWERED, e.tickMs(stepAt + maxActiveMs).events.filterIsInstance<TripEnded>().single().endReason)
    }

    @Test
    fun `X4 location services off before the chime stops still rings, SNOOZE on the OVERSHOOT ring is ignored, DISMISS ends MISSED`() {
        val e = overshotWhileRinging()
        e.feed(LocationAvailability(ms(422), AvailabilityCause.SERVICES_OFF))
        val s = e.feed(AlarmSilenced(ms(425), ms(425)))
        assertEquals(listOf(AlarmReason.OVERSHOOT), s.events.filterIsInstance<Alarm>().map { it.reason }, "${s.events}")
        val z = e.feed(UserAction(ms(430), UserActionKind.SNOOZE))
        assertTrue(z.events.isEmpty(), "SNOOZE in OVERSHOT ignored: ${z.events}")
        assertEquals(TripPhase.OVERSHOT, z.view.phase)
        assertTrue(z.state.alarm.ringing)
        assertTrue(e.feed(AlarmSilenced(ms(1_025), ms(1_025))).events.isEmpty())
        val d = e.feed(UserAction(ms(1_030), UserActionKind.DISMISS))
        val end = d.events.filterIsInstance<TripEnded>().single()
        assertEquals(EndReason.DISMISSED, end.endReason)
        assertEquals(TripOutcome.MISSED, end.outcome)
        assertEquals(1, overshootAlarms(e).size)
    }
}
