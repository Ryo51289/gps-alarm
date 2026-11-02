package app.napstop.core.trip.unit

import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.AlarmState
import app.napstop.core.trip.EndReason
import app.napstop.core.trip.EndedState
import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.FallbackState
import app.napstop.core.trip.FallbackStatus
import app.napstop.core.trip.GpsStatus
import app.napstop.core.trip.SamplingTier
import app.napstop.core.trip.TripOutcome
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.initialState
import app.napstop.core.trip.support.cfg
import app.napstop.core.trip.support.policy
import app.napstop.core.trip.support.trackingState
import app.napstop.core.trip.wakeAt
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

class WakePlannerTest {
    private val p = EngineParams()

    @Test
    fun `U70 wake-up candidates c1 to c7`() {
        val s0 = initialState(cfg(), p, 0).copy(policy = policy(SamplingTier.DENSE))
        assertEquals(120_000L, wakeAt(s0, 14_400_000))
        val sb = s0.copy(nowMs = 120_000, lostEmittedBeforeFirstFix = true)
        assertEquals(13_800_000L, wakeAt(sb, 14_400_000))
        val sc = trackingState(now = 1_000_000, startedAt = 0, lastFixAt = 1_000_000, tier = SamplingTier.DENSE)
        assertEquals(1_060_000L, wakeAt(sc, 2_000_000))
        val sd = trackingState(now = 1_500_000, startedAt = 0, lastFixAt = 1_000_000, gps = GpsStatus.LOST)
        assertEquals(2_100_000L, wakeAt(sd, 3_000_000))
        val alarm = AlarmState(900_000, AlarmReason.DISTANCE, null, 900_000, AlarmReason.DISTANCE, false, 1, 1_060_000, null)
        assertEquals(1_060_000L, wakeAt(sc.copy(phase = TripPhase.SNOOZED, alarm = alarm, gps = GpsStatus.LOST), null))
        val ringing = alarm.copy(ringing = true, lastRingAtMs = 990_000)
        assertEquals(990_000L + 3_600_000, wakeAt(sc.copy(phase = TripPhase.ALARMING, alarm = ringing, gps = GpsStatus.LOST), null))
        val failed = FallbackState(2_030_000, 980_000, FallbackStatus.FAILED, null, false, false)
        assertEquals(1_040_000L, wakeAt(sc.copy(fallback = failed), 2_000_000))
        assertNull(wakeAt(sc.copy(phase = TripPhase.ENDED, ended = EndedState(TripOutcome.ON_TIME, EndReason.DISMISSED, 1)), 2_000_000))
    }

    @Test
    fun `U70 i c7 still applies in SNOOZED with a FAILED snooze fallback (C13)`() {
        val alarm = AlarmState(900_000, AlarmReason.DISTANCE, null, 900_000, AlarmReason.DISTANCE, false, 1, 1_200_000, null)
        val fb = FallbackState(1_230_000, 1_100_000, FallbackStatus.FAILED, null, false, false)
        val s = trackingState(now = 1_150_000, startedAt = 0, gps = GpsStatus.LOST, phase = TripPhase.SNOOZED, alarm = alarm, fallback = fb)
        assertEquals(1_160_000L, wakeAt(s, null))
        assertEquals(1_160_000L, wakeAt(s.copy(alarm = alarm.copy(snoozeUntilMs = 1_400_000)), null))
    }

    @Test
    fun `U96 c8 wakes before the quiet window of a far-zone fallback while GPS is lost`() {
        val n = 10_000_000L
        val s = trackingState(now = n, startedAt = 0, lastFixAt = n - 600_000, gps = GpsStatus.LOST)
        val fb = FallbackState(n + 700_000, n - 10_000, FallbackStatus.CONFIRMED, n - 9_000, false, false)
        assertEquals(n + 610_000, wakeAt(s.copy(fallback = fb), n + 2_000_000))
        assertEquals(n + 1_100_000, wakeAt(s.copy(fallback = fb.copy(targetAtMs = n + 1_950_000)), n + 2_000_000))
        val alarm = AlarmState(n, AlarmReason.DISTANCE, null, n, AlarmReason.DISTANCE, true, 0, null, null)
        assertEquals(n + 3_600_000, wakeAt(s.copy(phase = TripPhase.ALARMING, alarm = alarm, fallback = fb), null))
    }
}
