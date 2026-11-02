package app.napstop.core.trip.unit

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.EndReason
import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.FallbackAlarmChanged
import app.napstop.core.trip.FallbackCause
import app.napstop.core.trip.FallbackStatus
import app.napstop.core.trip.Overshoot
import app.napstop.core.trip.Snoozed
import app.napstop.core.trip.TripEnded
import app.napstop.core.trip.TripOutcome
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.UserActionKind
import app.napstop.core.trip.support.EngineDriver
import app.napstop.core.trip.support.S
import app.napstop.core.trip.support.cfg
import app.napstop.core.trip.support.driverFrom
import app.napstop.core.trip.support.params
import app.napstop.core.trip.support.trackingState
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import app.napstop.core.trip.FallbackRestoreStatus
import app.napstop.core.trip.RestoreInfo
import app.napstop.core.trip.Step
import app.napstop.core.trip.TripEngine

class AlarmLifecycleTest {
    /** Stopped 900 m away (DISTANCE 1000): the Tick at t = 0 rings Alarm(DISTANCE). */
    private fun alarmed(p: EngineParams = EngineParams()): EngineDriver {
        val e = driverFrom(trackingState(cfg(), p, d = 900.0, inStop = true))
        assertEquals(AlarmReason.DISTANCE, e.tick(0).events.filterIsInstance<Alarm>().single().reason)
        return e
    }

    @Test
    fun `U45 snooze then snooze end after 60 s`() {
        val e = alarmed()
        val s = e.user(0, UserActionKind.SNOOZE)
        assertEquals(listOf(Snoozed(S, S + 60_000), FallbackAlarmChanged(S, S + 90_000, FallbackCause.SNOOZE)), s.events)
        assertTrue(e.tick(59).events.isEmpty())
        val end = e.tick(60).events.filterIsInstance<Alarm>().single()
        assertEquals(AlarmReason.SNOOZE_END, end.reason)
        assertTrue(end.ringNow)
        assertEquals(false, end.snoozeAllowed)
    }

    @Test
    fun `U45 b R3-1 snooze fallback state REQUESTED, FAILED, other time ignored, superseded at snooze end`() {
        val e = alarmed()
        val s = e.user(0, UserActionKind.SNOOZE)
        assertEquals(S + 90_000, s.view.fallbackAtMs)
        assertEquals(FallbackStatus.REQUESTED, s.view.fallbackStatus)
        assertEquals(FallbackStatus.FAILED, e.scheduled(1, S + 90_000, false).view.fallbackStatus)
        val other = e.scheduled(2, S + 91_000, true)
        assertEquals(FallbackStatus.FAILED, other.view.fallbackStatus)
        assertEquals(S + 90_000, other.view.fallbackAtMs)
        val end = e.tick(60)
        assertTrue(end.events.contains(FallbackAlarmChanged(S + 60_000, null, FallbackCause.SUPERSEDED)))
        assertNull(end.view.fallbackAtMs)
        assertEquals(FallbackStatus.NONE, end.view.fallbackStatus)
    }

    @Test
    fun `U46 second snooze is ignored with maxSnoozes 1`() {
        val e = alarmed()
        e.user(0, UserActionKind.SNOOZE)
        e.tick(60)
        val s = e.user(61, UserActionKind.SNOOZE)
        assertTrue(s.events.isEmpty())
        assertEquals(TripPhase.ALARMING, s.view.phase)
    }

    @Test
    fun `U47 outcomes and summary times`() {
        val a = alarmed()
        val endA = a.user(10, UserActionKind.DISMISS).events.filterIsInstance<TripEnded>().single()
        assertEquals(TripOutcome.ON_TIME, endA.outcome)
        assertEquals(S, endA.summary.alarmAtMs)
        assertEquals(S + 10_000, endA.summary.dismissedAtMs)
        val b = alarmed()
        b.user(0, UserActionKind.SNOOZE)
        b.tick(60)
        assertEquals(TripOutcome.SNOOZED, b.user(70, UserActionKind.DISMISS).events.filterIsInstance<TripEnded>().single().outcome)
        val c = alarmed()
        c.state = c.state.copy(phase = TripPhase.OVERSHOT, overshootAtMs = S + 5000, overshootPastM = 1000)
        assertEquals(TripOutcome.MISSED, c.user(10, UserActionKind.DISMISS).events.filterIsInstance<TripEnded>().single().outcome)
        val d = EngineDriver()
        d.fix(0, 50_000.0)
        val endD = d.user(10, UserActionKind.STOP_TRIP).events.filterIsInstance<TripEnded>().single()
        assertEquals(TripOutcome.CANCELLED, endD.outcome)
        assertEquals(EndReason.USER_STOP, endD.endReason)
        assertNull(endD.summary.dismissedAtMs)
        assertNull(endD.summary.alarmAtMs)
    }

    @Test
    fun `U48 fallback fired while tracking, then the mode condition does not ring again`() {
        val e = driverFrom(trackingState(d = 3000.0, ground = 10.0, closing = 10.0, inStop = true))
        val s = e.fired(1, S + 1000)
        assertEquals(Alarm(S + 1000, AlarmReason.FALLBACK, false, true, 3000, s.view.etaS, null), s.events.filterIsInstance<Alarm>().single())
        assertTrue(s.events.none { it is FallbackAlarmChanged && it.cause == FallbackCause.SUPERSEDED })
        e.fix(60, 900.0, spd = 10.0)
        assertTrue(e.all<Alarm>().none { it.ringNow })
    }

    @Test
    fun `U68 maxSnoozes 2 and 0`() {
        val e = alarmed(params("{\"maxSnoozes\": 2}"))
        val allowed = arrayListOf(e.steps.last().events.filterIsInstance<Alarm>().single().snoozeAllowed)
        e.user(1, UserActionKind.SNOOZE)
        allowed += e.tick(61).events.filterIsInstance<Alarm>().single().snoozeAllowed
        e.user(62, UserActionKind.SNOOZE)
        allowed += e.tick(122).events.filterIsInstance<Alarm>().single().snoozeAllowed
        assertEquals(listOf(true, true, false), allowed)
        val z = alarmed(params("{\"maxSnoozes\": 0}"))
        assertEquals(false, z.steps.last().events.filterIsInstance<Alarm>().single().snoozeAllowed)
        assertTrue(z.user(1, UserActionKind.SNOOZE).events.isEmpty())
        assertEquals(TripPhase.ALARMING, z.view.phase)
    }

    @Test
    fun `U76 timeout rings instead of a silent end, then ends unanswered`() {
        val a = driverFrom(trackingState(d = 400_000.0, inStop = true, maxTripS = 14_400))
        assertTrue(a.tickMs(S + 14_399_000).events.none { it is Alarm })
        val t = a.tickMs(S + 14_400_000).events.filterIsInstance<Alarm>().single()
        assertEquals(AlarmReason.TIMEOUT, t.reason)
        assertTrue(t.ringNow)
        assertEquals(TripPhase.ALARMING, a.view.phase)
        val end = a.tickMs(S + 18_000_000).events.filterIsInstance<TripEnded>().single()
        assertEquals(TripOutcome.MISSED, end.outcome)
        assertEquals(EndReason.ALARM_UNANSWERED, end.endReason)
        val b = EngineDriver()
        val bt = b.tick(14_400).events.filterIsInstance<Alarm>().single()
        assertEquals(AlarmReason.TIMEOUT, bt.reason)
        assertNull(bt.distanceM)
    }

    @Test
    fun `U83 fallback fired while already ringing changes nothing but ringing`() {
        for (phase in listOf(TripPhase.ALARMING, TripPhase.OVERSHOT)) {
            val e = alarmed()
            e.state = e.state.copy(phase = phase)
            e.silenced(1)
            val s = e.fired(2, S + 2000)
            assertTrue(s.events.isEmpty())
            assertTrue(s.view.alarmRinging)
        }
    }

    @Test
    fun `U88 markRing times for fallback alarms`() {
        val n = S + 100_000
        val a = driverFrom(trackingState(now = n, d = 20_000.0, lastFixAt = n, gps = app.napstop.core.trip.GpsStatus.LOST))
        val s = a.fired(100, n - 3000)
        assertEquals(n, s.events.filterIsInstance<Alarm>().single().atMs)
        assertEquals(n - 3000, s.view.alarmAtMs)
        assertTrue(s.view.alarmRinging)
        assertTrue(a.tickMs(n - 3000 + 3_600_000 - 1).events.isEmpty())
        val end = a.tickMs(n - 3000 + 3_600_000).events.filterIsInstance<TripEnded>().single()
        assertEquals(EndReason.ALARM_UNANSWERED, end.endReason)
        assertEquals(n - 3000, end.summary.alarmAtMs)

        val b = driverFrom(trackingState(d = 300.0, minD = 300.0, ground = 11.1, closing = 11.1))
        b.fired(1, S)
        for ((i, d) in listOf(400.0, 800.0, 1350.0).withIndex()) b.fix(60 * (i + 1), d, spd = 40 / 3.6)
        assertEquals(1, b.all<Overshoot>().size)
        assertEquals(1, b.all<Alarm>().size)

        val c = alarmed()
        c.user(0, UserActionKind.SNOOZE)
        val cs = c.fired(95, S + 90_000)
        assertEquals(AlarmReason.SNOOZE_END, cs.events.filterIsInstance<Alarm>().single().reason)
        assertEquals(false, cs.events.filterIsInstance<Alarm>().single().ringNow)
        assertEquals(S + 90_000, c.state.alarm.lastRingAtMs)

        val e = alarmed()
        e.fired(20, S + 10_000)
        assertEquals(S + 10_000, e.state.alarm.lastRingAtMs)

        val f = driverFrom(trackingState(d = 20_000.0))
        f.fired(0, S + 5000)
        assertEquals(S, f.state.alarm.atMs)
    }

    /** U98 setup: ALARMING at N = S (alarm at t = 0), SNOOZE at N: snoozeUntil = N + 60 000. */
    private fun snoozedAtN(): EngineDriver {
        val e = alarmed()
        val s = e.user(0, UserActionKind.SNOOZE)
        assertEquals(S + 60_000, s.view.snoozeUntilMs)
        assertEquals(TripPhase.SNOOZED, s.view.phase)
        return e
    }

    private fun assertCleared(s: Step, tag: String) {
        assertTrue(s.view.phase != TripPhase.SNOOZED, tag)
        assertNull(s.view.snoozeUntilMs, tag)
        assertNull(s.state.alarm.snoozeUntilMs, tag)
        assertNull(TripEngine.decodeSnapshot(TripEngine.encodeSnapshot(s.state)).alarm.snoozeUntilMs, tag)
    }

    private fun alarmOf(s: Step) = s.events.filterIsInstance<Alarm>().single()

    @Test
    fun `U98 C16 snoozeUntilMs is cleared on every exit from SNOOZED`() {
        snoozedAtN().tick(60).let {
            assertCleared(it, "a")
            assertEquals(AlarmReason.SNOOZE_END, alarmOf(it).reason)
            assertTrue(alarmOf(it).ringNow)
        }
        snoozedAtN().fired(30, S + 30_000).let {
            assertCleared(it, "b")
            assertEquals(AlarmReason.SNOOZE_END, alarmOf(it).reason)
            assertEquals(false, alarmOf(it).ringNow)
        }
        snoozedAtN().let { e ->
            e.fix(5, 1000.0, spd = 40 / 3.6)
            e.fix(15, 1500.0, spd = 40 / 3.6)
            val s = e.fix(25, 1950.0, spd = 40 / 3.6)
            assertCleared(s, "c")
            assertEquals(AlarmReason.OVERSHOOT, alarmOf(s).reason)
            assertEquals(1, s.events.filterIsInstance<Overshoot>().size)
        }
        assertCleared(snoozedAtN().user(10, UserActionKind.DISMISS), "d")
        assertCleared(snoozedAtN().user(10, UserActionKind.STOP_TRIP), "e")
        snoozedAtN().restore(30, RestoreInfo(FallbackRestoreStatus.RANG, S + 30_000)).let {
            assertCleared(it, "f")
            assertEquals(AlarmReason.SNOOZE_END, alarmOf(it).reason)
        }
        assertCleared(snoozedAtN().restore(30, RestoreInfo(FallbackRestoreStatus.DISMISSED, S + 30_000, S + 30_000)), "g")
        snoozedAtN().restore(70, RestoreInfo(FallbackRestoreStatus.MISSING)).let {
            assertCleared(it, "h")
            assertEquals(AlarmReason.SNOOZE_END, alarmOf(it).reason)
            assertTrue(alarmOf(it).ringNow)
        }
        snoozedAtN().restore(30, RestoreInfo(FallbackRestoreStatus.MISSING)).let {
            assertEquals(TripPhase.SNOOZED, it.view.phase)
            assertEquals(S + 60_000, it.view.snoozeUntilMs)
            assertEquals(listOf(FallbackAlarmChanged(S + 30_000, S + 90_000, FallbackCause.RESYNC)), it.events.filterIsInstance<FallbackAlarmChanged>())
        }
    }
}
