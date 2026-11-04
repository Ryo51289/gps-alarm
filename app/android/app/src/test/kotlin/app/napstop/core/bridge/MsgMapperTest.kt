package app.napstop.core.bridge

import app.napstop.core.trip.AccuracyLevel
import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.Arrived
import app.napstop.core.trip.AvailabilityCause
import app.napstop.core.trip.EndReason
import app.napstop.core.trip.FallbackAlarmChanged
import app.napstop.core.trip.FallbackCause
import app.napstop.core.trip.FallbackStatus
import app.napstop.core.trip.GpsLost
import app.napstop.core.trip.GpsLostCause
import app.napstop.core.trip.GpsRecovered
import app.napstop.core.trip.GpsStatus
import app.napstop.core.trip.LowBatteryRisk
import app.napstop.core.trip.Overshoot
import app.napstop.core.trip.PreAlert
import app.napstop.core.trip.SamplingPolicy
import app.napstop.core.trip.SamplingPolicyChanged
import app.napstop.core.trip.SamplingTier
import app.napstop.core.trip.Snoozed
import app.napstop.core.trip.TripEnded
import app.napstop.core.trip.TripOutcome
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.TripSummary
import app.napstop.core.trip.TripView
import app.napstop.core.trip.UserActionKind
import app.napstop.core.trip.VehicleKind
import app.napstop.core.trip.runtime.FinishedRecord
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** T15 L34: engine view and events → Pigeon (T14 §3.3). */
class MsgMapperTest {
    companion object {
        val view =
            TripView(
                tripId = "t1", atMs = 1_000, phase = TripPhase.TRACKING, gps = GpsStatus.OK, locationCause = AvailabilityCause.AVAILABLE,
                distanceM = 12_345, routeDistanceEstM = 14_814, distanceErrorM = 12, isEstimated = false, etaS = 900, etaMinS = 810,
                etaMaxS = 990, speedKmh = 48.5, progress = 0.4, alarmMarkerProgress = 0.9, predictedAlarmAtMs = 900_000,
                samplingPolicy = SamplingPolicy(SamplingTier.MEDIUM, 30, 15, AccuracyLevel.HIGH), fallbackAtMs = 930_000,
                fallbackStatus = FallbackStatus.NONE, batteryPct = 55, batteryRisk = false, preAlertFired = true, alarmAtMs = null,
                alarmReason = null, alarmRinging = false, snoozeCount = 0, snoozeUntilMs = null, overshootPastM = null, outcome = null,
                vehicleGuess = VehicleKind.COACH, travelledM = 30_000, droppedFixes = 4, wakeAtMs = 777,
            )

        fun sampleState(): TripStateMsg = MsgMapper.state(view, null)
    }

    @Test
    fun l34_viewFields() {
        val s = MsgMapper.state(view, UserActionKind.BATTERY_ALARM_AT_5)
        assertEquals("t1", s.tripId)
        assertEquals(1_000L, s.atMs)
        assertEquals(TripPhaseMsg.TRACKING, s.phase)
        assertEquals(GpsStatusMsg.OK, s.gps)
        assertEquals(AvailabilityCauseMsg.AVAILABLE, s.locationCause)
        assertEquals(12_345L, s.distanceM)
        assertEquals(14_814L, s.routeDistanceEstM)
        assertEquals(12L, s.distanceErrorM)
        assertEquals(900L, s.etaS)
        assertEquals(810L, s.etaMinS)
        assertEquals(990L, s.etaMaxS)
        assertEquals(48.5, s.speedKmh!!, 0.0)
        assertEquals(0.4, s.progress!!, 0.0)
        assertEquals(0.9, s.alarmMarkerProgress!!, 0.0)
        assertEquals(900_000L, s.predictedAlarmAtMs)
        assertEquals(SamplingTierMsg.MEDIUM, s.samplingTier)
        assertEquals(930_000L, s.fallbackAtMs)
        assertEquals(FallbackStatusMsg.NOT_SET, s.fallbackStatus)
        assertEquals(55L, s.batteryPct)
        assertEquals(BatteryChoiceMsg.ALARM_AT5, s.batteryChoice)
        assertTrue(s.preAlertFired)
        assertEquals(VehicleKindMsg.COACH, s.vehicleGuess)
        assertEquals(30_000L, s.travelledM)
        assertNull(MsgMapper.state(view, null).batteryChoice)
        assertNull(MsgMapper.state(view, UserActionKind.DISMISS).batteryChoice)
    }

    @Test
    fun l34_everyEnumMaps() {
        for (p in TripPhase.entries) assertEquals(p.name, MsgMapper.phase(p).name)
        for (r in AlarmReason.entries) assertEquals(r.name, MsgMapper.reason(r).name)
        for (o in TripOutcome.entries) assertEquals(o.name, MsgMapper.outcome(o).name)
        for (e in EndReason.entries) assertEquals(e.name, MsgMapper.endReason(e).name)
        for (v in VehicleKind.entries) assertEquals(v.name, MsgMapper.vehicle(v).name)
        val statuses = FallbackStatus.entries.map { MsgMapper.state(view.copy(fallbackStatus = it), null).fallbackStatus }
        assertEquals(listOf(FallbackStatusMsg.NOT_SET, FallbackStatusMsg.REQUESTED, FallbackStatusMsg.CONFIRMED, FallbackStatusMsg.FAILED), statuses)
        for (g in GpsStatus.entries) assertEquals(g.name, MsgMapper.state(view.copy(gps = g), null).gps.name)
        for (c in AvailabilityCause.entries) assertEquals(c.name, MsgMapper.state(view.copy(locationCause = c), null).locationCause.name)
        for (t in SamplingTier.entries) {
            assertEquals(t.name, MsgMapper.state(view.copy(samplingPolicy = SamplingPolicy(t, 5, 2, AccuracyLevel.HIGH)), null).samplingTier!!.name)
        }
        for (c in BatteryChoiceMsg.entries) assertEquals(c, MsgMapper.batteryChoice(MsgMapper.batteryAction(c)))
    }

    @Test
    fun l34_eventsAndOrder() {
        val summary = TripSummary(10, 20, AlarmReason.DISTANCE, 30, 1, 1234, VehicleKind.TRAIN)
        val events =
            listOf(
                GpsRecovered(1, 60), GpsLost(1, GpsLostCause.NO_FIX_TIMEOUT, 70), Arrived(1, 250),
                Alarm(1, AlarmReason.GPS_LOST, true, false, 900, null, 40), Overshoot(1, 1100), PreAlert(1, 3000, 600),
                Snoozed(1, 61_000), LowBatteryRisk(1, 12, 30, 60),
                SamplingPolicyChanged(1, SamplingPolicy(SamplingTier.DENSE, 5, 2, AccuracyLevel.HIGH)),
                FallbackAlarmChanged(1, 99, FallbackCause.ETA),
                TripEnded(2, TripOutcome.SNOOZED, EndReason.DISMISSED, summary),
            )
        val out = MsgMapper.updates("t1", view, null, events)
        assertTrue(out.first() is TripStateUpdateMsg)
        assertEquals(
            listOf("TripStateUpdateMsg", "GpsRecoveredMsg", "GpsLostMsg", "ArrivedMsg", "AlarmMsg", "OvershootMsg", "PreAlertMsg", "SnoozedMsg", "LowBatteryRiskMsg", "TripEndedMsg"),
            out.map { it.javaClass.simpleName },
        )
        assertEquals(AlarmMsg("t1", 1, AlarmReasonMsg.GPS_LOST, true, false, 900, null, 40), out[4])
        assertEquals(GpsLostMsg("t1", 1, GpsLostCauseMsg.NO_FIX_TIMEOUT, 70), out[2])
        val ended = out.last() as TripEndedMsg
        assertEquals(FinishedTripMsg("t1", TripOutcomeMsg.SNOOZED, EndReasonMsg.DISMISSED, 2, 10, 20, AlarmReasonMsg.DISTANCE, 30, 1, 1234, VehicleKindMsg.TRAIN), ended.trip)
        val rec = FinishedRecord("t1", TripOutcome.SNOOZED, EndReason.DISMISSED, 2, 10, 20, AlarmReason.DISTANCE, 30, 1, 1234, VehicleKind.TRAIN)
        assertEquals(ended.trip, MsgMapper.finished(rec))
    }

    @Test
    fun configRoundTrip() {
        for (v in VibrationMsg.entries) for (d in DismissMethodMsg.entries) for (m in AlarmModeMsg.entries) {
            val c =
                BridgeTestData.config(mode = m, distanceThresholdM = 1000, timeThresholdMin = 15, engineParamsJson = "{\"a\":1}")
                    .copy(alarm = BridgeTestData.alarm().copy(vibration = v, dismissMethod = d))
            assertEquals(c, MsgMapper.config(MsgMapper.meta(c)))
        }
    }

    /** T18 SM30: the simulation goes into the meta and is echoed back; a real trip has none. */
    @Test
    fun sm30_simulationIntoTheMetaAndBack() {
        val c = BridgeTestData.config(mode = AlarmModeMsg.DISTANCE, distanceThresholdM = 1000)
        val meta = MsgMapper.meta(c, SimulationMsg("train_hn_dh", 60.0))
        assertEquals(app.napstop.core.trip.runtime.sim.SimSpec("train_hn_dh", 60.0), meta.simulation)
        assertEquals(SimulationMsg("train_hn_dh", 60.0), MsgMapper.simulation(meta))
        assertEquals(c, MsgMapper.config(meta))
        val real = MsgMapper.meta(c)
        assertEquals(null, real.simulation)
        assertEquals(null, MsgMapper.simulation(real))
    }
}
