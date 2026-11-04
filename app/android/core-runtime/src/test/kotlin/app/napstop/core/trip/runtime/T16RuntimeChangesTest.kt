package app.napstop.core.trip.runtime

import app.napstop.core.alarm.RingFacts
import app.napstop.core.trip.AlarmMode
import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.PreAlert
import app.napstop.core.trip.Snoozed
import app.napstop.core.trip.Step
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.runtime.support.EngineStates
import app.napstop.core.trip.runtime.support.TestData
import app.napstop.core.trip.runtime.support.World
import app.napstop.core.trip.runtime.support.fixNorth
import app.napstop.core.trip.runtime.support.startTrip
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** T16 §11 changes in the T15 runtime: A40 (WakePolicy snooze end), A41 (RingConfig.snoozeS), A42 (ignored snooze), A43 (byDistance). */
@OptIn(ExperimentalCoroutinesApi::class)
class T16RuntimeChangesTest {
    private val meta = TestData.meta()
    private val tracking = EngineStates.drive(meta, 1_000_000, 30_000.0, 30)

    @Test
    fun a40_snoozeEndWakesWithAlarmClock() {
        val u = 5_000_000L
        val snoozed = tracking.view.copy(phase = TripPhase.SNOOZED, snoozeUntilMs = u, predictedAlarmAtMs = null)
        assertEquals(WakeMechanism.ALARM_CLOCK, WakePolicy.mechanism(snoozed, u, canScheduleExact = true))
        assertEquals(WakeMechanism.ALARM_CLOCK, WakePolicy.mechanism(snoozed, u + 1_000, canScheduleExact = true))
        assertEquals(WakeMechanism.EXACT_IDLE, WakePolicy.mechanism(snoozed, u + 10_000, canScheduleExact = true))
        assertEquals(WakeMechanism.EXACT_IDLE, WakePolicy.mechanism(snoozed, u - 1_000, canScheduleExact = true))
        assertEquals(WakeMechanism.INEXACT_IDLE, WakePolicy.mechanism(snoozed, u, canScheduleExact = false))
        // Not snoozed: unchanged (L28).
        assertEquals(WakeMechanism.EXACT_IDLE, WakePolicy.mechanism(tracking.view.copy(snoozeUntilMs = u), u, canScheduleExact = true))
    }

    @Test
    fun a41_ringConfigSnoozeS() {
        val rc = RingConfig("t1", "Ga", TestData.settings, 0, 1, snoozeS = 90)
        assertEquals(rc, RuntimeCodec.decodeRingConfig(RuntimeCodec.encodeRingConfig(rc)))
        val old = RuntimeCodec.encodeRingConfig(rc).apply { remove("snoozeS") }
        assertEquals(60, RuntimeCodec.decodeRingConfig(old).snoozeS)
        assertTrue(rc.toString().contains("snoozeS=90"))
    }

    @Test
    fun a41_runtimeWritesSnoozeSFromTheParams() =
        runTest {
            val w = World(this)
            w.startTrip(meta.copy(engineParamsJson = "{\"snoozeS\":90}"))
            assertEquals(90, w.store.readRingConfig()!!.snoozeS)
        }

    @Test
    fun a42_ignoredSnoozeSilencesTheEngine() =
        runTest {
            val w = World(this)
            w.listen()
            w.startTrip(meta.copy(engineParamsJson = "{\"maxSnoozes\":0}"))
            var m = 1_300.0
            while (m >= 900.0) {
                w.fixNorth(m)
                w.advance(5_000)
                m -= 75.0
            }
            assertEquals(TripPhase.ALARMING, w.seen.last().view.phase)
            assertTrue(w.seen.last().view.alarmRinging)
            // The native screen snoozed (pending snooze in the book) and the ring has stopped.
            w.alarm.facts["t1"]!!.ringing = false
            w.alarm.facts["t1"]!!.pendingSnooze = w.nowMs
            val n = w.seen.size
            w.now { w.runtime.onRingEvent(RingEvent("t1", RingEventKind.SNOOZED, w.nowMs)) }
            val after = w.seen.drop(n)
            assertFalse(after.any { s -> s.events.any { it is Snoozed } }, "no snooze left: the engine ignores it")
            assertFalse(w.seen.last().view.alarmRinging, "AlarmSilenced reached the engine")
            assertEquals(TripPhase.ALARMING, w.seen.last().view.phase)
            assertNull(w.alarm.facts["t1"]!!.pendingSnooze, "the pending snooze is handled")
            assertTrue(w.alarm.stops.isNotEmpty())
        }

    @Test
    fun a42_aSnoozeThatWorksIsUnchanged() =
        runTest {
            val w = World(this)
            w.listen()
            w.startTrip(meta)
            var m = 1_300.0
            while (m >= 900.0) {
                w.fixNorth(m)
                w.advance(5_000)
                m -= 75.0
            }
            w.alarm.facts["t1"]!!.ringing = false
            val n = w.seen.size
            w.now { w.runtime.onRingEvent(RingEvent("t1", RingEventKind.SNOOZED, w.nowMs)) }
            assertTrue(w.seen.drop(n).any { s -> s.events.any { it is Snoozed } })
            assertEquals(TripPhase.SNOOZED, w.seen.last().view.phase)
        }

    @Test
    fun a43_preAlertByDistance() {
        val now = tracking.state.nowMs
        val pre = PreAlert(now, 3_000, 240)
        for ((mode, want) in listOf(AlarmMode.DISTANCE to true, AlarmMode.SMART to false, AlarmMode.TIME to false)) {
            val m = meta.copy(mode = mode)
            val fx =
                EffectPlanner.plan(
                    PlanInput(tracking.view, Step(tracking.state, listOf(pre), tracking.view), m, TrackingMode.TRACKING_FGS, RingFacts.NONE, null, EngineParams(), now, now, true),
                )
            val p = fx.filterIsInstance<Effect.PreAlertFx>().single().request
            assertEquals(want, p.byDistance, "$mode")
            assertEquals(3_000, p.distanceM)
        }
    }
}
