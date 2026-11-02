package app.napstop.core.trip.unit

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmMode
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.Arrived
import app.napstop.core.trip.EndReason
import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.Overshoot
import app.napstop.core.trip.TripEnded
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.UserActionKind
import app.napstop.core.trip.support.DEST
import app.napstop.core.trip.support.EngineDriver
import app.napstop.core.trip.support.TestGeo
import app.napstop.core.trip.support.cfg
import app.napstop.core.trip.support.params
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class OvershootDetectorTest {
    private val v40 = 40 / 3.6

    /** Fixes every [step] s (one per smoothing window, so dSmooth = d). Returns the next t. */
    private fun seq(e: EngineDriver, t0: Int, ds: List<Double>, spd: Double, step: Int = 60): Int {
        var t = t0
        for (d in ds) {
            e.fix(t, d, spd = spd)
            t += step
        }
        return t
    }

    private fun d1000(p: EngineParams = EngineParams()) = EngineDriver(cfg(AlarmMode.DISTANCE, thr = 1000), p)

    private val approach = listOf(3000.0, 2300.0, 1600.0, 900.0, 300.0)

    @Test
    fun `U34 overshoot while ringing gives Overshoot without a new alarm`() {
        val e = d1000()
        val t = seq(e, 0, approach, v40)
        assertEquals(TripPhase.ALARMING, e.view.phase)
        seq(e, t, listOf(400.0, 800.0, 1350.0), v40)
        assertEquals(listOf(Overshoot(e.ms(t + 120), 1050)), e.all<Overshoot>())
        assertEquals(1, e.all<Alarm>().size)
        assertEquals(TripPhase.OVERSHOT, e.view.phase)
    }

    @Test
    fun `U34 b threshold 2000 widens the near radius`() {
        val e = EngineDriver(cfg(AlarmMode.DISTANCE, thr = 2000))
        val t = seq(e, 0, listOf(5000.0, 4000.0, 3000.0, 1900.0, 1500.0), v40)
        seq(e, t, listOf(1700.0, 2100.0, 2500.0), v40)
        assertEquals(1000, e.all<Overshoot>().single().pastM)
    }

    @Test
    fun `U35 slow or not strictly increasing gives no overshoot`() {
        val slow = d1000()
        seq(slow, seq(slow, 0, approach, 8 / 3.6), listOf(400.0, 800.0, 1350.0), 8 / 3.6)
        assertTrue(slow.all<Overshoot>().isEmpty())
        val osc = d1000()
        seq(osc, seq(osc, 0, approach, v40), listOf(400.0, 350.0, 1350.0), v40)
        assertTrue(osc.all<Overshoot>().isEmpty())
    }

    @Test
    fun `U35 b fast boundary is strict`() {
        val p = params("{\"overshootMinSpeedKmh\": 18}")
        val at = d1000(p)
        seq(at, seq(at, 0, approach, 5.0), listOf(400.0, 800.0, 1350.0), 5.0)
        assertTrue(at.all<Overshoot>().isEmpty())
        val above = d1000(p)
        seq(above, seq(above, 0, approach, 5.01), listOf(400.0, 800.0, 1350.0), 5.01)
        assertEquals(1, above.all<Overshoot>().size)
    }

    @Test
    fun `U35 c minD equal to the near radius is not near`() {
        val e = d1000()
        var t = seq(e, 0, listOf(3000.0, 2000.0), v40)
        e.fixAt(t, TestGeo.pointAtExactDistance(DEST, 1000.0), spd = v40)
        assertEquals(1000.0, e.state.minD)
        seq(e, t + 60, listOf(1500.0, 2000.0, 2100.0), v40)
        assertTrue(e.all<Overshoot>().isEmpty())
        val f = d1000()
        t = seq(f, 0, listOf(3000.0, 2000.0, 999.9), v40)
        seq(f, t, listOf(1500.0, 2000.0, 2100.0), v40)
        assertEquals(1, f.all<Overshoot>().size)
    }

    @Test
    fun `U36 after dismiss there is no overshoot`() {
        val e = d1000()
        val t = seq(e, 0, approach, v40)
        e.user(t, UserActionKind.DISMISS)
        seq(e, t + 60, listOf(400.0, 800.0, 1350.0), v40)
        assertEquals(TripPhase.ENDED, e.view.phase)
        assertTrue(e.all<Overshoot>().isEmpty())
    }

    @Test
    fun `U37 overshoot before any alarm wins over passed-closest in the same Step`() {
        val e = EngineDriver(cfg(AlarmMode.DISTANCE, thr = 500))
        seq(e, 0, listOf(900.0, 800.0, 1100.0, 2000.0), v40, step = 180)
        val last = e.last.events
        assertEquals(AlarmReason.OVERSHOOT, last.filterIsInstance<Alarm>().single().reason)
        assertEquals(1, last.filterIsInstance<Overshoot>().size)
        assertEquals(TripPhase.OVERSHOT, e.view.phase)
        assertEquals(1, e.all<Alarm>().size)
    }

    @Test
    fun `U38 arrived once, phase unchanged`() {
        val e = EngineDriver(cfg(AlarmMode.DISTANCE, thr = 200))
        seq(e, 0, listOf(1000.0, 700.0, 400.0, 290.0, 280.0), 5.0)
        assertEquals(290, e.all<Arrived>().single().distanceM)
        assertEquals(TripPhase.TRACKING, e.view.phase)
    }

    @Test
    fun `U77 passed-closest net and its negatives`() {
        fun run(ds: List<Double>, spd: Double = 5.0): EngineDriver = d1000().also { seq(it, 0, ds, spd) }
        val down = (0..9).map { 4000.0 - 300.0 * it } + 1200.0
        val pos = run(down + listOf(1300.0, 1600.0, 1850.0))
        assertEquals(listOf(AlarmReason.PASSED_CLOSEST), pos.all<Alarm>().map { it.reason })
        assertEquals(TripPhase.ALARMING, pos.view.phase)
        assertTrue(pos.last.events.any { it is Alarm })
        assertTrue(run((0..9).map { 6000.0 - 290.0 * it } + listOf(3100.0, 3200.0, 3700.0, 4700.0)).all<Alarm>().isEmpty())
        assertTrue(run(down + listOf(1300.0, 1600.0, 1850.0), spd = 8 / 3.6).all<Alarm>().isEmpty())
        assertTrue(run(down + listOf(1300.0, 1500.0, 1700.0)).all<Alarm>().isEmpty())
        assertTrue(run(down + listOf(1300.0, 1300.0, 1850.0)).all<Alarm>().isEmpty())
        val alarmed = d1000()
        val t = seq(alarmed, 0, down, 5.0)
        alarmed.fired(t, alarmed.ms(t))
        seq(alarmed, t + 60, listOf(1300.0, 1600.0, 1850.0), 5.0)
        assertEquals(listOf(AlarmReason.FALLBACK), alarmed.all<Alarm>().map { it.reason })

        val v24 = 24 / 3.6
        val r24 = d1000()
        var tt = seq(r24, 0, listOf(2500.0, 2600.0, 3000.0, 3400.0, 3800.0), v24)
        assertTrue(r24.all<Alarm>().isEmpty())
        tt = seq(r24, tt, listOf(3400.0, 3000.0, 2600.0, 2200.0, 1800.0, 2000.0, 2400.0), v24)
        assertTrue(r24.all<Alarm>().isEmpty())
        seq(r24, tt, listOf(2800.0), v24)
        assertEquals(AlarmReason.PASSED_CLOSEST, r24.last.events.filterIsInstance<Alarm>().single().reason)
    }

    @Test
    fun `U78 overshoot after the alarm stopped ringing rings again, then ends unanswered after 3600 s`() {
        val a = d1000()
        var t = seq(a, 0, approach, v40)
        a.silenced(t)
        t = seq(a, t + 5, listOf(400.0, 800.0, 1350.0), v40)
        val ov = a.last.events
        assertEquals(AlarmReason.OVERSHOOT, ov.filterIsInstance<Alarm>().single().reason)
        assertTrue(ov.filterIsInstance<Alarm>().single().ringNow)
        assertEquals(1, ov.filterIsInstance<Overshoot>().size)
        val ring = a.state.alarm.lastRingAtMs!!
        assertTrue(a.tickMs(ring + 3_599_000).events.none { it is TripEnded })
        assertEquals(EndReason.ALARM_UNANSWERED, a.tickMs(ring + 3_600_000).events.filterIsInstance<TripEnded>().single().endReason)

        val b = d1000()
        seq(b, seq(b, 0, approach, v40), listOf(400.0, 800.0, 1350.0), v40)
        assertEquals(1, b.all<Alarm>().size)
        assertEquals(1, b.all<Overshoot>().size)
    }
}
