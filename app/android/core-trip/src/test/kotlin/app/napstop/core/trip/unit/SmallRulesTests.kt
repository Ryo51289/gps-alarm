package app.napstop.core.trip.unit

import app.napstop.core.trip.AlarmMode
import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.GpsLost
import app.napstop.core.trip.Tick
import app.napstop.core.trip.TripEngine
import app.napstop.core.trip.VehicleKind
import app.napstop.core.trip.maxTripDurationFromFirstFix
import app.napstop.core.trip.support.DEST
import app.napstop.core.trip.support.EngineDriver
import app.napstop.core.trip.support.TestGeo
import app.napstop.core.trip.support.cfg
import app.napstop.core.trip.support.trackingState
import app.napstop.core.trip.vehicleGuess
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class ClockTest {
    @Test
    fun `U52 input time going back does not move now back nor fake a GPS loss`() {
        val e = EngineDriver()
        e.fix(100, 50_000.0)
        val s = e.tick(90)
        assertEquals(e.ms(100), s.state.nowMs)
        assertTrue(s.events.none { it is GpsLost })
        assertEquals(e.ms(100), s.view.atMs)
    }
}

class MaxTripDurationTest {
    @Test
    fun `U53 max trip duration from the first fix eta`() {
        val p = EngineParams()
        assertEquals(14_400, maxTripDurationFromFirstFix(3600.0, p))
        assertEquals(43_200, maxTripDurationFromFirstFix(6 * 3600.0, p))
        assertEquals(144_000, maxTripDurationFromFirstFix(20 * 3600.0, p))
        assertEquals(172_800, maxTripDurationFromFirstFix(30 * 3600.0, p))
        assertEquals(14_400, maxTripDurationFromFirstFix(null, p))
        assertEquals(14_400, EngineDriver().state.maxTripDurationS)
        // First fix 400 km away, train hint: etaS = 400000 * 1.2 / (55/3.6) + 20 = 31 438 s -> 62 876 s.
        val e = EngineDriver(cfg(hint = VehicleKind.TRAIN))
        e.fix(0, 400_000.0)
        assertEquals(TripEngineCheck.round2x(400_000.0 * 1.2 / (55 / 3.6) + 20), e.state.maxTripDurationS)
    }
}

private object TripEngineCheck {
    fun round2x(eta: Double): Int = kotlin.math.floor(2.0 * eta + 0.5).toInt()
}

class HistoryTest {
    @Test
    fun `U54 vehicle guess`() {
        val p = EngineParams()
        assertEquals(VehicleKind.BUS, vehicleGuess(1000.0, 22 / 3.6 * 1000, VehicleKind.COACH, p))
        assertEquals(VehicleKind.TRAIN, vehicleGuess(1000.0, 70 / 3.6 * 1000, VehicleKind.TRAIN, p))
        assertEquals(VehicleKind.UNKNOWN, vehicleGuess(1000.0, 70 / 3.6 * 1000, VehicleKind.UNKNOWN, p))
        assertEquals(VehicleKind.COACH, vehicleGuess(0.0, 0.0, VehicleKind.COACH, p))
    }

    private fun run15(): EngineDriver {
        val e = EngineDriver()
        for (t in 0..120 step 5) e.fix(t, 100_000.0 - 15.0 * t, spd = 15.0)
        return e
    }

    @Test
    fun `U55 jitter while stopped does not add distance`() {
        val a = run15()
        val stop = TestGeo.pointOnMeridian(DEST, 100_000.0 - 15.0 * 120 - 5)
        a.fixAt(125, stop, spd = 0.0)
        val m0 = a.view.travelledM
        val offs20 = listOf(0.0 to 0.0, 15.0 to 10.0, -12.0 to 15.0, 0.0 to -20.0, 18.0 to -5.0, -16.0 to -10.0)
        for (i in 1..120) {
            val (east, north) = offs20[i % offs20.size]
            a.fixAt(125 + 5 * i, TestGeo.jitter(stop, east, north))
        }
        assertEquals(m0, a.view.travelledM)

        val b = run15()
        val m1 = b.view.travelledM
        val stopB = TestGeo.pointOnMeridian(DEST, 100_000.0 - 15.0 * 120 - 3)
        val offs6 = listOf(0.0 to 0.0, 5.0 to 3.0, -4.0 to 4.0, 0.0 to -6.0, 6.0 to 0.0, -3.0 to -5.0)
        for (i in 1..120) {
            val (east, north) = offs6[i % offs6.size]
            b.fixAt(120 + 5 * i, TestGeo.jitter(stopB, east, north))
        }
        assertTrue(b.view.travelledM - m1 <= 50)
    }
}

class ViewTest {
    @Test
    fun `U85 progress, alarm marker, distance error`() {
        val s = trackingState(cfg(AlarmMode.DISTANCE, thr = 1000), d = 4000.0, dStart = 10_000.0, inStop = true, acc = 7.6)
        val v = TripEngine.reduce(s, Tick(s.nowMs)).view
        assertEquals(0.6, v.progress!!, 1e-12)
        assertEquals(0.9, v.alarmMarkerProgress!!, 1e-12)
        assertEquals(8, v.distanceErrorM)
        val t = trackingState(cfg(AlarmMode.TIME, thrMin = 15), d = 4000.0, dStart = 10_000.0, ground = 12.0, closing = 10.0, inStop = true)
        assertEquals(0.12, TripEngine.reduce(t, Tick(t.nowMs)).view.alarmMarkerProgress!!, 1e-12)
    }
}
