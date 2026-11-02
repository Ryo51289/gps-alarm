package app.napstop.core.trip.unit

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.EndReason
import app.napstop.core.trip.FallbackAlarmChanged
import app.napstop.core.trip.FallbackCause
import app.napstop.core.trip.FallbackRestoreStatus
import app.napstop.core.trip.FallbackState
import app.napstop.core.trip.FallbackStatus
import app.napstop.core.trip.RestoreInfo
import app.napstop.core.trip.TripEnded
import app.napstop.core.trip.TripEvent
import app.napstop.core.trip.TripOutcome
import app.napstop.core.trip.UserActionKind
import app.napstop.core.trip.support.EngineDriver
import app.napstop.core.trip.support.S
import app.napstop.core.trip.support.driverFrom
import app.napstop.core.trip.support.trackingState
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class RestoreTest {
    /** TRACKING after one fix; fb target T from the planner. */
    private fun tracking(): EngineDriver = EngineDriver().also { it.fix(0, 50_000.0) }

    private fun alarms(events: List<TripEvent>) = events.filterIsInstance<Alarm>()

    private fun facs(events: List<TripEvent>) = events.filterIsInstance<FallbackAlarmChanged>()

    @Test
    fun `U49 restore on a trip that has not alarmed yet`() {
        val t0 = tracking()
        val target = t0.state.fallback.targetAtMs!!
        val after = ((target - S) / 1000 + 1).toInt()
        fun r(info: RestoreInfo, t: Int, st: EngineDriver = tracking()) = st.restore(t, info).events
        alarms(r(RestoreInfo(FallbackRestoreStatus.RANG, target), after)).single().let { assertEquals(AlarmReason.FALLBACK, it.reason); assertEquals(false, it.ringNow) }
        alarms(r(RestoreInfo(FallbackRestoreStatus.UNKNOWN), after)).single().let { assertEquals(AlarmReason.FALLBACK, it.reason); assertEquals(false, it.ringNow) }
        assertTrue(r(RestoreInfo(FallbackRestoreStatus.UNKNOWN), 10).isEmpty())
        assertTrue(r(RestoreInfo(FallbackRestoreStatus.PENDING), 10).isEmpty())
        alarms(r(RestoreInfo(FallbackRestoreStatus.MISSING), after)).single().let { assertEquals(AlarmReason.FALLBACK_MISSED, it.reason); assertEquals(true, it.ringNow) }
        assertEquals(FallbackCause.RESYNC, facs(r(RestoreInfo(FallbackRestoreStatus.MISSING), 10)).single().cause)
        val cleared = tracking().also { it.state = it.state.copy(fallback = FallbackState.CLEARED) }
        assertEquals(FallbackCause.RESYNC, facs(r(RestoreInfo(FallbackRestoreStatus.MISSING), 10, cleared)).single().cause)
    }

    @Test
    fun `U50 restore on an alarmed trip never rings now`() {
        for (st in listOf(FallbackRestoreStatus.RANG, FallbackRestoreStatus.PENDING, FallbackRestoreStatus.MISSING, FallbackRestoreStatus.UNKNOWN)) {
            val e = driverFrom(trackingState(d = 900.0, inStop = true))
            e.tick(0)
            assertTrue(alarms(e.restore(30, RestoreInfo(st, S + 10_000)).events).none { it.ringNow }, "$st")
        }
    }

    @Test
    fun `U75 dismissed while the process was dead`() {
        val a = tracking()
        val ra = a.restore(20, RestoreInfo(FallbackRestoreStatus.DISMISSED, S + 10_000, S + 15_000)).events
        assertEquals(AlarmReason.FALLBACK, alarms(ra).single().reason)
        val ea = ra.filterIsInstance<TripEnded>().single()
        assertEquals(EndReason.DISMISSED, ea.endReason)
        assertEquals(TripOutcome.ON_TIME, ea.outcome)
        assertEquals(S + 15_000, ea.summary.dismissedAtMs)
        assertEquals(S + 10_000, ea.summary.alarmAtMs)

        val b = driverFrom(trackingState(d = 900.0, inStop = true))
        b.tick(0)
        b.user(1, UserActionKind.SNOOZE)
        val rb = b.restore(30, RestoreInfo(FallbackRestoreStatus.DISMISSED, S + 25_000, S + 28_000)).events
        assertEquals(AlarmReason.SNOOZE_END, alarms(rb).single().reason)
        assertEquals(TripOutcome.SNOOZED, rb.filterIsInstance<TripEnded>().single().outcome)

        val c = driverFrom(trackingState(d = 900.0, inStop = true))
        c.tick(0)
        val rc = c.restore(7200, RestoreInfo(FallbackRestoreStatus.DISMISSED, null, S + 7_100_000)).events
        val ec = rc.filterIsInstance<TripEnded>().single()
        assertEquals(EndReason.DISMISSED, ec.endReason)
        assertEquals(TripOutcome.ON_TIME, ec.outcome)
        assertTrue(alarms(rc).isEmpty())
    }

    /** SNOOZED at t = 1 (alarm at t = 0): snoozeUntil = S + 61 000, snooze fallback S + 91 000. */
    private fun snoozed(): EngineDriver {
        val e = driverFrom(trackingState(d = 900.0, inStop = true))
        e.tick(0)
        e.user(1, UserActionKind.SNOOZE)
        return e
    }

    @Test
    fun `U84 snoozed trip restored with MISSING or UNKNOWN`() {
        val a = snoozed()
        val ra = a.restore(30, RestoreInfo(FallbackRestoreStatus.MISSING)).events
        assertEquals(listOf(FallbackAlarmChanged(S + 30_000, S + 91_000, FallbackCause.RESYNC)), facs(ra))
        assertTrue(alarms(ra).isEmpty())

        val b = snoozed()
        val rb = b.restore(95, RestoreInfo(FallbackRestoreStatus.MISSING)).events
        assertEquals(AlarmReason.SNOOZE_END, alarms(rb).single().reason)
        assertTrue(alarms(rb).single().ringNow)
        assertTrue(facs(rb).isEmpty())

        val c = snoozed()
        val rc = c.restore(75, RestoreInfo(FallbackRestoreStatus.MISSING)).events
        assertTrue(alarms(rc).single().ringNow)
        assertTrue(facs(rc).isEmpty())

        val d = snoozed()
        val rd = d.restore(95, RestoreInfo(FallbackRestoreStatus.UNKNOWN)).events
        assertEquals(AlarmReason.SNOOZE_END, alarms(rd).single().reason)
        assertEquals(false, alarms(rd).single().ringNow)
        assertTrue(d.tickMs(d.state.nowMs).events.isEmpty())
    }

    @Test
    fun `U84 e R3-1 resync fallback of a snoozed trip is REQUESTED, confirmable and superseded at snooze end`() {
        val e = snoozed()
        val r = e.restore(30, RestoreInfo(FallbackRestoreStatus.MISSING))
        assertEquals(S + 91_000, r.view.fallbackAtMs)
        assertEquals(FallbackStatus.REQUESTED, r.view.fallbackStatus)
        assertEquals(FallbackStatus.CONFIRMED, e.scheduled(30, S + 91_000, true).view.fallbackStatus)
        val end = e.tick(61)
        assertEquals(AlarmReason.SNOOZE_END, alarms(end.events).single().reason)
        assertTrue(alarms(end.events).single().ringNow)
        assertEquals(listOf(FallbackAlarmChanged(S + 61_000, null, FallbackCause.SUPERSEDED)), facs(end.events))
        for (s in e.steps) assertTrue(facs(s.events).size <= 1)
    }

    @Test
    fun `U84 f merged restore Step keeps the stable event order of section 2_3 (C6)`() {
        val e = tracking()
        val r = e.restore(3600, RestoreInfo(FallbackRestoreStatus.RANG, S + 3_000_000)).events
        val names = r.map { it::class.simpleName }
        assertEquals(listOf("GpsLost", "Alarm", "SamplingPolicyChanged"), names)
    }
}
