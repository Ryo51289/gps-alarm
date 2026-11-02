package app.napstop.core.trip.unit

import app.napstop.core.trip.AlarmMode
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.AlarmState
import app.napstop.core.trip.BatteryState
import app.napstop.core.trip.GpsStatus
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.initialState
import app.napstop.core.trip.predictedAlarmAt
import app.napstop.core.trip.support.S
import app.napstop.core.trip.support.cfg
import app.napstop.core.trip.support.est
import app.napstop.core.trip.support.estimateOf
import app.napstop.core.trip.support.params
import app.napstop.core.trip.support.trackingState
import app.napstop.core.trip.support.work
import app.napstop.core.trip.EngineParams
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

class PredictedAlarmAtTest {
    private val n = S + 1_000_000

    private fun pred(mode: AlarmMode, e: app.napstop.core.trip.Estimate, p: EngineParams = EngineParams(), slow: Boolean = false, thrMin: Int? = null) =
        predictedAlarmAt(work(trackingState(cfg(mode, thrMin = thrMin ?: if (mode == AlarmMode.TIME) 10 else null), p, now = n, slow = slow)), e)

    @Test
    fun `U82 a-e mode alarm times`() {
        assertEquals(n + 640_000, pred(AlarmMode.DISTANCE, est(9000.0, 12.5, 740.0)).withBattery)
        assertEquals(n + 140_000, pred(AlarmMode.TIME, est(9000.0, 12.5, 740.0), thrMin = 10).withBattery)
        assertEquals(n + 140_000, pred(AlarmMode.SMART, est(9000.0, 12.5, 740.0)).withBattery)
        val q = params("{\"smartTargetS\": 300, \"smartSlowSpeedKmh\": 5}")
        assertEquals(n + 500_000, pred(AlarmMode.SMART, est(2000.0, 2.0, 1020.0, k = 1.5), q).withBattery)
        assertEquals(n + 750_000, pred(AlarmMode.SMART, est(4000.0, 2.0, 2000.0), slow = true).withBattery)
    }

    @Test
    fun `U82 f lost GPS prediction does not drift`() {
        val l = S + 500_000
        for (dt in listOf(120_000L, 180_000L)) {
            val s = trackingState(cfg(), now = l + dt, lastFixAt = l, d = 30_000.0, ground = 15.0, closing = 12.5, gps = GpsStatus.LOST)
            assertEquals(l + 1_220_000, predictedAlarmAt(work(s), estimateOf(s)).withBattery)
        }
    }

    @Test
    fun `U82 g battery prediction, h no fix, alarmed, TIME without ETA`() {
        val b = BatteryState(20, false, n, 20, true, false, null, null)
        val w = work(trackingState(cfg(), now = n, battery = b))
        val e = est(406_000.0, 12.5, 32_000.0)
        val pr = predictedAlarmAt(w, e)
        assertEquals(n + 27_000_000, pr.withBattery)
        assertEquals(n + 32_400_000, pr.noBattery)

        val fresh = work(initialState(cfg(), EngineParams(), S))
        assertEquals(S + 14_400_000, predictedAlarmAt(fresh, null).withBattery)
        val alarmed = work(trackingState(now = n, phase = TripPhase.ALARMING, alarm = AlarmState.EMPTY.copy(atMs = n, reason = AlarmReason.DISTANCE)))
        assertNull(predictedAlarmAt(alarmed, est(9000.0, 12.5, 740.0)).withBattery)
        val t = trackingState(cfg(AlarmMode.TIME, thrMin = 15), now = n, d = 1300.0, ground = 0.4, closing = -1.0)
        val et = estimateOf(t)
        assertNull(et.etaS)
        assertEquals(n + 5_000_000, predictedAlarmAt(work(t), et).withBattery)
    }
}
