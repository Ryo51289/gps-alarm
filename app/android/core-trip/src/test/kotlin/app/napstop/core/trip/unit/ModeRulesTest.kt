package app.napstop.core.trip.unit

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmMode
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.Tick
import app.napstop.core.trip.TripEngine
import app.napstop.core.trip.VehicleKind
import app.napstop.core.trip.modeReason
import app.napstop.core.trip.slowDistM
import app.napstop.core.trip.support.DEST
import app.napstop.core.trip.support.EngineDriver
import app.napstop.core.trip.support.TestGeo
import app.napstop.core.trip.support.cfg
import app.napstop.core.trip.support.est
import app.napstop.core.trip.support.params
import app.napstop.core.trip.support.trackingState
import app.napstop.core.trip.support.work
import app.napstop.core.trip.updateSlow
import app.napstop.core.trip.support.estimateOf
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class ModeRulesTest {
    private val p = EngineParams()

    @Test
    fun `U14 DISTANCE 1000 alarms at exactly 1000_0 and not at 1000_01`() {
        val a = EngineDriver(cfg(AlarmMode.DISTANCE, thr = 1000))
        a.fixAt(0, TestGeo.pointAtExactDistance(DEST, 1000.0))
        assertEquals(1000.0, a.state.dSmooth)
        assertEquals(AlarmReason.DISTANCE, a.last.events.filterIsInstance<Alarm>().single().reason)
        val b = EngineDriver(cfg(AlarmMode.DISTANCE, thr = 1000))
        b.fixAt(0, TestGeo.pointOnMeridian(DEST, 1000.01)) // no exactly representable point; |error| < 1e-6 m
        assertEquals(1000.01, b.state.dSmooth!!, 1e-6)
        assertTrue(b.state.dSmooth!! > 1000.0)
        assertTrue(b.all<Alarm>().isEmpty())
    }

    @Test
    fun `U15 TIME 15 alarms at etaS 900_0 and not at 900_5`() {
        val c = cfg(AlarmMode.TIME, thrMin = 15)
        // k = 1 (ground == closing), stopped so dNow = dSmooth: etaS = d / 10 + 20.
        val at = trackingState(c, d = 8800.0, ground = 10.0, closing = 10.0, inStop = true)
        assertEquals(900.0, estimateOf(at).etaS)
        assertEquals(AlarmReason.TIME, TripEngine.reduce(at, Tick(at.nowMs)).events.filterIsInstance<Alarm>().single().reason)
        val no = trackingState(c, d = 8805.0, ground = 10.0, closing = 10.0, inStop = true)
        assertEquals(900.5, estimateOf(no).etaS)
        assertTrue(TripEngine.reduce(no, Tick(no.nowMs)).events.none { it is Alarm })
    }

    @Test
    fun `U17 SMART time branch and floor branch`() {
        val c = cfg(AlarmMode.SMART)
        assertEquals(AlarmReason.SMART_TIME, modeReason(est(dNow = 9000.0, cvDr = 60 / 3.6 / 1.2, etaS = 599.0), c, false, p))
        val q = params("{\"smartTargetS\": 300, \"smartSlowSpeedKmh\": 5}")
        assertEquals(AlarmReason.SMART_DISTANCE, modeReason(est(dNow = 990.0, cvDr = 11 / 3.6 / 1.2, etaS = 400.0), c, false, q))
        assertNull(modeReason(est(dNow = 1010.0, cvDr = 11 / 3.6 / 1.2, etaS = 400.0), c, false, q))
    }

    @Test
    fun `U18 SMART slow branch, hysteresis, slowDistM floor`() {
        val c = cfg(AlarmMode.SMART)
        assertNull(modeReason(est(2600.0, 3.0, 1000.0), c, true, p))
        assertEquals(AlarmReason.SMART_SLOW_DISTANCE, modeReason(est(2500.0, 3.0, 1000.0), c, true, p))
        val w = work(trackingState(c, ground = 12 / 3.6, slow = false))
        updateSlow(w, estimateOf(w.toState()))
        assertTrue(w.slow)
        w.ground = 16 / 3.6
        updateSlow(w, estimateOf(w.toState()))
        assertTrue(w.slow)
        w.ground = 17.1 / 3.6
        updateSlow(w, estimateOf(w.toState()))
        assertFalse(w.slow)
        assertEquals(2500.0, slowDistM(p))
        assertEquals(3000.0, slowDistM(params("{\"smartFloorM\": 3000, \"smartTargetS\": 600}")))
    }

    @Test
    fun `U57 first fix already inside the alarm zone alarms at once`() {
        val e = EngineDriver(cfg(AlarmMode.DISTANCE, thr = 1000))
        e.fix(0, 800.0)
        assertEquals(AlarmReason.DISTANCE, e.last.events.filterIsInstance<Alarm>().single().reason)
    }

    @Test
    fun `U58 TIME 15 not established BUS hint 4 km alarms at once`() {
        val e = EngineDriver(cfg(AlarmMode.TIME, thrMin = 15, hint = VehicleKind.BUS))
        e.fix(0, 4000.0)
        assertEquals(884, e.view.etaS)
        assertEquals(AlarmReason.TIME, e.last.events.filterIsInstance<Alarm>().single().reason)
    }

    @Test
    fun `U81 TIME without ETA uses the arrival net at 300 m`() {
        val c = cfg(AlarmMode.TIME, thrMin = 15)
        val s301 = trackingState(c, d = 301.0, ground = 0.4, closing = -1.0)
        assertNull(estimateOf(s301).etaS)
        assertEquals(2.0, estimateOf(s301).k)
        assertTrue(TripEngine.reduce(s301, Tick(s301.nowMs)).events.none { it is Alarm })
        val s300 = trackingState(c, d = 300.0, ground = 0.4, closing = -1.0)
        assertEquals(AlarmReason.TIME, TripEngine.reduce(s300, Tick(s300.nowMs)).events.filterIsInstance<Alarm>().single().reason)
    }
}
