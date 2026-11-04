package app.napstop.core.trip.unit

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmMode
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.AvailabilityCause
import app.napstop.core.trip.GpsLost
import app.napstop.core.trip.GpsLostCause
import app.napstop.core.trip.GpsRecovered
import app.napstop.core.trip.GpsStatus
import app.napstop.core.trip.LocationAvailability
import app.napstop.core.trip.SamplingTier
import app.napstop.core.trip.alarmReason
import app.napstop.core.trip.support.DEST
import app.napstop.core.trip.support.EngineDriver
import app.napstop.core.trip.support.S
import app.napstop.core.trip.support.TestGeo
import app.napstop.core.trip.support.cfg
import app.napstop.core.trip.support.driverFrom
import app.napstop.core.trip.support.est
import app.napstop.core.trip.support.estimateOf
import app.napstop.core.trip.support.params
import app.napstop.core.trip.support.trackingState
import app.napstop.core.trip.support.work
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class GpsMonitorTest {
    @Test
    fun `U23 DENSE lost after 60 s`() {
        val e = EngineDriver(cfg(AlarmMode.DISTANCE, thr = 1000))
        e.fix(0, 6000.0, spd = 15.0)
        assertEquals(SamplingTier.DENSE, e.view.samplingPolicy!!.tier)
        assertTrue(e.tick(59).events.none { it is GpsLost })
        assertEquals(GpsLost(e.ms(60), GpsLostCause.NO_FIX_TIMEOUT, 60), e.tick(60).events.filterIsInstance<GpsLost>().single())
    }

    @Test
    fun `U24 just switched SPARSE to DENSE, no loss before 540 s after the last fix (C2)`() {
        // C2: the fix that triggers SPARSE -> DENSE records the interval it was requested with (180).
        val sparse = trackingState(cfg(), d = 5000.0, tier = SamplingTier.SPARSE)
        val e = driverFrom(sparse)
        e.fix(10, 4900.0, spd = 15.0)
        assertEquals(180, e.state.policyIntervalAtLastFixS)
        assertEquals(5, e.state.policy!!.intervalS)
        // Last fix 170 s ago when the policy became DENSE.
        val s = trackingState(cfg(), now = S + 170_000, lastFixAt = S, d = 20_000.0, ground = 15.0, closing = 15.0, tier = SamplingTier.DENSE, policyAtFix = 180)
        val d = driverFrom(s)
        assertTrue(d.tickMs(S + 539_000).events.none { it is GpsLost })
        assertEquals(1, d.tickMs(S + 540_000).events.filterIsInstance<GpsLost>().size)
    }

    @Test
    fun `U25 lost GPS alarms at the first tick with etaS below 1200 (65 s later)`() {
        val s = trackingState(cfg(AlarmMode.TIME, thrMin = 15), d = 18_600.0, ground = 18.0, closing = 15.0, tier = SamplingTier.DENSE)
        assertEquals(1260.0, estimateOf(s).etaS!!, 1e-9)
        val e = driverFrom(s)
        val hit = e.ticksUntil(5, 600, 5) { st -> st.events.any { it is Alarm } }!!
        assertEquals(65, hit.first)
        assertEquals(AlarmReason.GPS_LOST, hit.second.events.filterIsInstance<Alarm>().single().reason)
        assertEquals(GpsStatus.LOST, e.view.gps)
        assertTrue(e.state.cvGuard.isEmpty())
    }

    @Test
    fun `U26 lost for 120 s shows estimated distance and error`() {
        val s = trackingState(cfg(), now = S + 120_000, lastFixAt = S, d = 30_000.0, ground = 18.0, closing = 15.0, gps = GpsStatus.LOST)
        val e = driverFrom(s)
        val v = e.tickMs(S + 120_000).view
        assertTrue(v.isEstimated)
        assertEquals(458, v.distanceErrorM)
        assertEquals(28_200, v.distanceM)
    }

    @Test
    fun `U27 permission revoked with eta 900 gives GpsLost and GPS_LOST alarm in one Step`() {
        val s = trackingState(cfg(), d = 13_200.0, ground = 18.0, closing = 15.0)
        assertEquals(900.0, estimateOf(s).etaS!!, 1e-9)
        val st = driverFrom(s).feed(LocationAvailability(s.nowMs, AvailabilityCause.PERMISSION_REVOKED))
        assertEquals(GpsLostCause.PERMISSION_REVOKED, st.events.filterIsInstance<GpsLost>().single().cause)
        assertEquals(AlarmReason.GPS_LOST, st.events.filterIsInstance<Alarm>().single().reason)
    }

    @Test
    fun `U28 a rejected fix does not recover GPS, a good one does`() {
        val s = trackingState(cfg(), now = S + 100_000, lastFixAt = S, d = 50_000.0, gps = GpsStatus.LOST)
        val e = driverFrom(s)
        val jump = e.feed(app.napstop.core.trip.LocationFix(S + 105_000, S + 105_000, TestGeo.pointOnMeridian(DEST, 30_000.0).lat, DEST.lng, 8.0, null))
        assertTrue(jump.events.none { it is GpsRecovered })
        assertEquals(GpsStatus.LOST, jump.view.gps)
        val good = e.feed(app.napstop.core.trip.LocationFix(S + 110_000, S + 110_000, TestGeo.pointOnMeridian(DEST, 49_000.0).lat, DEST.lng, 8.0, null))
        assertEquals(GpsRecovered(S + 110_000, 110), good.events.filterIsInstance<GpsRecovered>().single())
    }

    @Test
    fun `U63 lost GPS alarm on mode condition or eta below 1200`() {
        val w = work(trackingState(cfg(), gps = GpsStatus.LOST))
        assertEquals(AlarmReason.GPS_LOST, alarmReason(w, est(5000.0, 10.0, 1100.0)))
        assertEquals(AlarmReason.GPS_LOST, alarmReason(w, est(900.0, 10.0, 1300.0)))
        assertNull(alarmReason(w, est(5000.0, 10.0, 1300.0)))
    }

    @Test
    fun `U71 lost while stopped keeps dead reckoning, prediction stays constant, alarm at tick 3660`() {
        // T10.6 §6 (not in the designer's list, see T12.md T12.3 notes): GPS lost 2 280 s before the alarm; this test checks dead
        // reckoning while stopped, not the "long loss" rule W (with W on the alarm is GPS_LOST at tick 2820, U119-U121).
        val s = trackingState(
            cfg(), p = params("{\"gpsLostLongS\": 0}"), d = 60_000.0, ground = 15.0, closing = 12.5, inStop = true,
            tier = SamplingTier.SPARSE, cvGuard = listOf(12.5, 12.5),
        )
        val e = driverFrom(s)
        var lostAt: Int? = null
        var pred: Long? = null
        var t = 60
        while (t <= 4000) {
            val st = e.tick(t)
            if (st.events.any { it is GpsLost }) lostAt = t
            if (lostAt != null && t > lostAt) {
                if (pred == null) pred = st.view.predictedAlarmAtMs
                if (st.events.none { it is Alarm }) assertTrue(kotlin.math.abs(st.view.predictedAlarmAtMs!! - pred!!) <= 1, "t=$t")
            }
            if (st.events.any { it is Alarm }) break
            t += 60
        }
        assertEquals(540, lostAt)
        assertEquals(3660, t)
        assertEquals(AlarmReason.GPS_LOST, e.view.alarmReason)
        assertTrue(e.state.cvGuard.all { it <= estimateOf(s).closingV })
    }

    @Test
    fun `U86 availability errors before and after the first fix, I7 alternation`() {
        val a = EngineDriver()
        a.avail(10, AvailabilityCause.SERVICES_OFF)
        a.avail(20, AvailabilityCause.SERVICES_OFF)
        a.fix(30, 50_000.0)
        assertEquals(listOf("L:SERVICES_OFF", "R"), a.events().mapNotNull { if (it is GpsLost) "L:${it.cause}" else if (it is GpsRecovered) "R" else null })
        val b = EngineDriver()
        b.fix(0, 50_000.0)
        b.avail(10, AvailabilityCause.PERMISSION_REVOKED)
        b.avail(20, AvailabilityCause.SERVICES_OFF)
        assertEquals(AvailabilityCause.SERVICES_OFF, b.view.locationCause)
        b.fix(30, 49_900.0)
        assertEquals(listOf("L:PERMISSION_REVOKED", "R"), b.events().mapNotNull { if (it is GpsLost) "L:${it.cause}" else if (it is GpsRecovered) "R" else null })
        assertEquals(AvailabilityCause.AVAILABLE, b.view.locationCause)
    }
}
