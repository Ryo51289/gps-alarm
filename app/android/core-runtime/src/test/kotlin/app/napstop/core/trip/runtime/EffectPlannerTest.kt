package app.napstop.core.trip.runtime

import app.napstop.core.alarm.RingFacts
import app.napstop.core.alarm.RingSource
import app.napstop.core.alarm.StopCause
import app.napstop.core.trip.AccuracyLevel
import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.EndReason
import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.FallbackAlarmChanged
import app.napstop.core.trip.FallbackCause
import app.napstop.core.trip.FallbackFired
import app.napstop.core.trip.FallbackStatus
import app.napstop.core.trip.GpsLost
import app.napstop.core.trip.GpsLostCause
import app.napstop.core.trip.SamplingPolicy
import app.napstop.core.trip.SamplingPolicyChanged
import app.napstop.core.trip.SamplingTier
import app.napstop.core.trip.Snoozed
import app.napstop.core.trip.Step
import app.napstop.core.trip.TripEnded
import app.napstop.core.trip.TripEvent
import app.napstop.core.trip.TripOutcome
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.TripSummary
import app.napstop.core.trip.VehicleKind
import app.napstop.core.trip.runtime.support.EngineStates
import app.napstop.core.trip.runtime.support.TestData
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** EffectPlanner (pure): L06–L08, L10–L11 (plan part), notices. */
class EffectPlannerTest {
    private val meta = TestData.meta()
    private val tracking = EngineStates.drive(meta, 1_000_000, 30_000.0, 30)
    private val now = tracking.state.nowMs
    private val dense = SamplingPolicy(SamplingTier.DENSE, 5, 2, AccuracyLevel.HIGH)
    private val alarm = Alarm(now, AlarmReason.DISTANCE, true, true, 900, 60, 50)

    private fun step(events: List<TripEvent>, phase: TripPhase = TripPhase.ALARMING) =
        Step(tracking.state, events, tracking.view.copy(phase = phase, alarmRinging = phase == TripPhase.ALARMING))

    private fun plan(s: Step, facts: RingFacts = RingFacts.NONE, scheduledWake: Long? = null, mode: TrackingMode = TrackingMode.TRACKING_FGS) =
        EffectPlanner.plan(PlanInput(tracking.view, s, meta, mode, facts, scheduledWake, EngineParams(), now + 1_000, now, canScheduleExact = true))

    private fun kinds(fx: List<Effect>) = fx.map { it.javaClass.simpleName }

    @Test
    fun l06_orderOfARingStep() {
        // Designer "sau test" G1: ArmRingGuard before PersistNow; SUPERSEDED has no OS effect any more.
        val fx = plan(step(listOf(alarm, SamplingPolicyChanged(now, dense), FallbackAlarmChanged(now, null, FallbackCause.SUPERSEDED))))
        assertEquals(
            listOf("ArmRingGuard", "PersistNow", "Ring", "ApplySampling", "ScheduleWake", "Tracking", "Persist", "Publish"),
            kinds(fx),
        )
        assertEquals(Effect.ArmRingGuard(now + 1_000 + EngineParams().fallbackLagS * 1000L), fx[0])
        assertEquals(Effect.PersistNow(300), fx[1])
        val ring = (fx[2] as Effect.Ring).request
        assertEquals(RingSource.ENGINE, ring.source)
        assertEquals(AlarmReason.DISTANCE, ring.reason)
        assertEquals("Ga Đông Hà", ring.destinationName)
        assertTrue(ring.snoozeAllowed)
        assertEquals(Effect.ApplySampling(FlpMapper.spec(dense, EngineParams())), fx[3])
        assertTrue(fx.none { it is Effect.CancelFallback }, "SUPERSEDED cancels no slot")
        // Same wake already scheduled: no ScheduleWake; HEADLESS: no ApplySampling.
        val fx2 = plan(step(listOf(alarm, SamplingPolicyChanged(now, dense))), scheduledWake = tracking.view.wakeAtMs, mode = TrackingMode.HEADLESS)
        assertEquals(listOf("ArmRingGuard", "PersistNow", "Ring", "Tracking", "Persist", "Publish"), kinds(fx2))
    }

    @Test
    fun l07_fallbackRingingNowBlocksTheRing() {
        val w = now + 1_000 - 20_000 // wall time the fallback started ringing (20 s ago)
        val facts = RingFacts(true, RingSource.FALLBACK, w, null, null)
        val fx = plan(step(listOf(alarm, FallbackAlarmChanged(now, null, FallbackCause.SUPERSEDED))), facts)
        assertTrue(fx.none { it is Effect.Ring })
        assertEquals(Effect.Feed(FallbackFired(now, now - 20_000)), fx[2])
    }

    @Test
    fun l08_fallbackThatStoppedRingingDoesNotBlock() {
        // Rang earlier and stopped by itself (not delivered yet): ring "now" (T10 obligation 3, second dash).
        val facts = RingFacts(false, null, null, null, now - 5_000)
        val fx = plan(step(listOf(alarm)), facts)
        assertTrue(fx.any { it is Effect.Ring })
        // An ENGINE ring of the trip on: no block either (the engine never asks twice, I1); the port updates content.
        val fx2 = plan(step(listOf(alarm)), RingFacts(true, RingSource.ENGINE, now, null, null))
        assertTrue(fx2.any { it is Effect.Ring })
    }

    @Test
    fun l10_snoozePlan() {
        val until = now + 60_000
        val s = Step(tracking.state, listOf(Snoozed(now, until), FallbackAlarmChanged(now, until + 30_000, FallbackCause.SNOOZE)), tracking.view.copy(phase = TripPhase.SNOOZED, snoozeCount = 1))
        val fx = plan(s)
        assertEquals(Effect.StopRinging(StopCause.SNOOZED), fx[0])
        assertEquals(Effect.ScheduleFallback(until + 30_000), fx[1])
        assertTrue(Effect.UpdateRingConfig(1) in fx)
    }

    @Test
    fun l11_tripEndedPlan() {
        val ended = TripEnded(now, TripOutcome.ON_TIME, EndReason.DISMISSED, TripSummary(1_000_000, now - 10, AlarmReason.DISTANCE, now, 0, 25_000, VehicleKind.TRAIN))
        val s = Step(tracking.state, listOf(FallbackAlarmChanged(now, null, FallbackCause.TRIP_ENDED), ended), tracking.view.copy(phase = TripPhase.ENDED, wakeAtMs = null))
        val fx = plan(s, scheduledWake = 5)
        assertEquals(
            listOf("CancelFallback", "Tracking", "Persist", "Publish", "StopRinging", "CancelFallback", "CancelWake", "ClearNotices", "Finish"),
            kinds(fx),
        )
        assertEquals(Effect.StopRinging(StopCause.TRIP_ENDED), fx[4])
        assertEquals(FinishedRecordBuilder.fromEvent(meta.tripId, ended), (fx.last() as Effect.Finish).record)
    }

    @Test
    fun noticesFollowGpsAndFallbackStatus() {
        val lost = plan(step(listOf(GpsLost(now, GpsLostCause.NEVER_ACQUIRED, null)), TripPhase.ACQUIRING))
        assertTrue(Effect.Notice(TripNotice.NoGpsYet, null) in lost)
        val revoked = plan(step(listOf(GpsLost(now, GpsLostCause.PERMISSION_REVOKED, 3)), TripPhase.TRACKING))
        assertTrue(Effect.Notice(TripNotice.PermissionRevoked, null) in revoked)
        val failed = Step(tracking.state, emptyList(), tracking.view.copy(fallbackStatus = FallbackStatus.FAILED))
        assertTrue(Effect.Notice(TripNotice.FallbackFailed, null) in plan(failed))
        val fixed =
            EffectPlanner.plan(
                PlanInput(tracking.view.copy(fallbackStatus = FallbackStatus.FAILED), Step(tracking.state, emptyList(), tracking.view.copy(fallbackStatus = FallbackStatus.CONFIRMED)), meta, TrackingMode.TRACKING_FGS, RingFacts.NONE, null, EngineParams(), now, now, true),
            )
        assertTrue(Effect.Notice(null, TripNotice.FallbackFailed) in fixed)
    }
}
