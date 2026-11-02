package app.napstop.core.trip.unit

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmMode
import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.PreAlert
import app.napstop.core.trip.inZone
import app.napstop.core.trip.support.EngineDriver
import app.napstop.core.trip.support.cfg
import app.napstop.core.trip.support.est
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class PreAlertRuleTest {
    private val p = EngineParams()

    @Test
    fun `U19 DISTANCE pre-alert zone 5x threshold, at least 3 km`() {
        for ((thr, zone) in listOf(500 to 3000.0, 1000 to 5000.0, 10_000 to 50_000.0)) {
            val c = cfg(AlarmMode.DISTANCE, thr = thr)
            assertTrue(inZone(est(zone, 10.0, 9999.0), c, p))
            assertFalse(inZone(est(zone + 0.001, 10.0, 9999.0), c, p))
        }
    }

    @Test
    fun `U20 TIME and SMART pre-alert at eta 1800, TIME 30 never`() {
        assertTrue(inZone(est(20_000.0, 10.0, 1800.0), cfg(AlarmMode.TIME, thrMin = 20), p))
        assertFalse(inZone(est(20_000.0, 10.0, 1800.5), cfg(AlarmMode.TIME, thrMin = 20), p))
        assertFalse(inZone(est(20_000.0, 10.0, 100.0), cfg(AlarmMode.TIME, thrMin = 30), p))
        assertTrue(inZone(est(20_000.0, 10.0, 1800.0), cfg(AlarmMode.SMART), p))
        assertFalse(inZone(est(20_000.0, 10.0, 1801.0), cfg(AlarmMode.SMART), p))
    }

    private fun approach(e: EngineDriver, from: Double, to: Double, t0: Int = 0, speed: Double = 15.0): Int {
        var t = t0
        var d = from
        while (d >= to) {
            e.fix(t, d, spd = speed)
            t += 5
            d -= speed * 5
        }
        return t
    }

    @Test
    fun `U21 start already in the zone or pre-alert disabled gives no pre-alert, alarm still comes`() {
        val a = EngineDriver(cfg(AlarmMode.DISTANCE, thr = 1000))
        approach(a, 4000.0, 800.0)
        assertTrue(a.all<PreAlert>().isEmpty())
        assertEquals(1, a.all<Alarm>().size)
        val b = EngineDriver(cfg(AlarmMode.DISTANCE, thr = 1000, preAlert = false))
        approach(b, 8000.0, 800.0)
        assertTrue(b.all<PreAlert>().isEmpty())
        assertEquals(1, b.all<Alarm>().size)
    }

    @Test
    fun `U22 pre-alert zone and alarm in the same Step gives only the alarm`() {
        val e = EngineDriver(cfg(AlarmMode.DISTANCE, thr = 1000))
        e.fix(0, 10_000.0)
        e.fix(300, 900.0)
        assertEquals(1, e.last.events.filterIsInstance<Alarm>().size)
        assertTrue(e.all<PreAlert>().isEmpty())
    }

    @Test
    fun `U64 armed only from the first fix`() {
        val a = EngineDriver(cfg(AlarmMode.DISTANCE, thr = 1000))
        var t = approach(a, 4000.0, 4000.0)
        var d = 4000.0
        while (d < 6000.0) { d += 75.0; a.fix(t, d, spd = 15.0); t += 5 }
        while (d > 4000.0) { d -= 75.0; a.fix(t, d, spd = 15.0); t += 5 }
        assertTrue(a.all<PreAlert>().isEmpty())
        val b = EngineDriver(cfg(AlarmMode.DISTANCE, thr = 1000))
        approach(b, 6000.0, 4700.0)
        val pre = b.all<PreAlert>().single()
        assertTrue(pre.distanceM <= 5000)
    }
}
