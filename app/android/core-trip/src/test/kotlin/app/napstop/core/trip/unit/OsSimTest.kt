package app.napstop.core.trip.unit

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.EngineInput
import app.napstop.core.trip.FallbackAlarmChanged
import app.napstop.core.trip.FallbackCause
import app.napstop.core.trip.FallbackFired
import app.napstop.core.trip.FallbackRestoreStatus
import app.napstop.core.trip.FallbackStatus
import app.napstop.core.trip.Overshoot
import app.napstop.core.trip.RestoreInfo
import app.napstop.core.trip.Step
import app.napstop.core.trip.TripEngine
import app.napstop.core.trip.UserActionKind
import app.napstop.core.trip.harness.OsSim
import app.napstop.core.trip.harness.Ringing
import app.napstop.core.trip.support.S
import app.napstop.core.trip.support.driverFrom
import app.napstop.core.trip.support.trackingState
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** U89: platform obligation 3 as modelled by the harness osSim (T10 §8.1-4, T12 §8.4). */
class OsSimTest {
    private fun react(os: OsSim, s: Step, violations: MutableList<String> = ArrayList()): ArrayDeque<EngineInput> {
        val q = ArrayDeque<EngineInput>()
        os.react(s, q, violations, "unit")
        return q
    }

    @Test
    fun `U89 a fallback fired, snooze, snooze end rings now and supersedes the snooze fallback`() {
        val e = driverFrom(trackingState(d = 20_000.0, inStop = true))
        val os = OsSim(true, null, null)
        os.ringing = Ringing.FALLBACK
        os.ringStartMs = S
        react(os, e.fired(0, S))
        val sn = e.user(10, UserActionKind.SNOOZE)
        react(os, sn)
        assertEquals(Ringing.NONE, os.ringing)
        assertEquals(S + 100_000, sn.view.fallbackAtMs)
        assertEquals(FallbackStatus.REQUESTED, sn.view.fallbackStatus)
        val before = e.tick(69)
        assertEquals(S + 100_000, before.view.fallbackAtMs)
        val end = e.tick(70)
        val a = end.events.filterIsInstance<Alarm>().single()
        assertEquals(AlarmReason.SNOOZE_END, a.reason)
        assertTrue(a.ringNow)
        assertTrue(end.events.contains(FallbackAlarmChanged(S + 70_000, null, FallbackCause.SUPERSEDED)))
        react(os, end)
        assertEquals(Ringing.ENGINE, os.ringing)
    }

    @Test
    fun `U89 b restore RANG, silenced, overshoot rings now`() {
        val s0 = trackingState(d = 300.0, minD = 300.0, ground = 11.1, closing = 11.1)
        val target = S + 50_000
        val e = driverFrom(s0.copy(fallback = s0.fallback.copy(targetAtMs = target, emittedAtMs = S, status = FallbackStatus.CONFIRMED)))
        val os = OsSim(true, null, null)
        e.restore(55, RestoreInfo(FallbackRestoreStatus.RANG, target))
        os.ringing = Ringing.NONE
        e.silenced(56)
        val before = e.last
        assertNull(before.view.fallbackAtMs)
        for ((i, d) in listOf(400.0, 800.0).withIndex()) e.fix(60 + 60 * i, d, spd = 40 / 3.6)
        val ov = e.fix(180, 1350.0, spd = 40 / 3.6)
        assertEquals(AlarmReason.OVERSHOOT, ov.events.filterIsInstance<Alarm>().single().reason)
        assertTrue(ov.events.any { it is Overshoot })
        react(os, ov)
        assertEquals(Ringing.ENGINE, os.ringing)
    }

    @Test
    fun `U89 c engine alarm while the fallback is ringing is not sounded, FallbackFired goes back in the same tick`() {
        val e = driverFrom(trackingState(d = 900.0, inStop = true))
        val os = OsSim(true, null, null)
        os.ringing = Ringing.FALLBACK
        os.ringStartMs = S - 2000
        val s = e.tick(0)
        assertTrue(s.events.any { it is Alarm && it.ringNow })
        val q = react(os, s)
        assertEquals(Ringing.FALLBACK, os.ringing)
        assertEquals(FallbackFired(S, S - 2000), q.single())
        val back = TripEngine.reduce(e.state, q.single())
        assertTrue(back.events.isEmpty())
        assertTrue(back.view.alarmRinging)
    }

    @Test
    fun `U89 d no trip-wide flag, snooze end after a snoozed fallback rings`() {
        val e = driverFrom(trackingState(d = 20_000.0, inStop = true))
        val os = OsSim(true, null, null)
        os.ringing = Ringing.FALLBACK
        os.ringStartMs = S
        react(os, e.fired(0, S))
        react(os, e.user(5, UserActionKind.SNOOZE))
        assertEquals(Ringing.NONE, os.ringing)
        react(os, e.tick(65))
        assertEquals(Ringing.ENGINE, os.ringing)
    }

    @Test
    fun `U89 e alarm while the engine alarm rings is a P07 violation`() {
        val e = driverFrom(trackingState(d = 900.0, inStop = true))
        val os = OsSim(true, null, null)
        os.ringing = Ringing.ENGINE
        val v = ArrayList<String>()
        react(os, e.tick(0), v)
        assertTrue(v.single().startsWith("P07(i)"))
    }
}
