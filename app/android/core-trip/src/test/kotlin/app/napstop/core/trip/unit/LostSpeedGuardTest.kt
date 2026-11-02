package app.napstop.core.trip.unit

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.FallbackAlarmChanged
import app.napstop.core.trip.FallbackCause
import app.napstop.core.trip.GpsLost
import app.napstop.core.trip.GpsLostCause
import app.napstop.core.trip.Step
import app.napstop.core.trip.closingVOf
import app.napstop.core.trip.support.EngineDriver
import app.napstop.core.trip.support.cfg
import app.napstop.core.trip.support.estimateOf
import app.napstop.core.trip.support.params
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class LostSpeedGuardTest {
    private val u90Fixes = listOf(
        Triple(0, 100_000.0, 12.0), Triple(180, 97_840.0, 12.0), Triple(360, 95_680.0, 12.0),
        Triple(540, 93_520.0, 12.0), Triple(720, 91_360.0, 12.0), Triple(900, 89_400.0, 1.0),
    )

    private fun driver(p: EngineParams = EngineParams(), fixes: List<Triple<Int, Double, Double>> = u90Fixes): EngineDriver {
        val e = EngineDriver(cfg(), p)
        for ((t, d, v) in fixes) e.fix(t, d, spd = v)
        return e
    }

    private fun alarmTick(e: EngineDriver, from: Int, every: Int = 60): Pair<Int, Step> =
        e.ticksUntil(from, 40_000, every) { s -> s.events.any { it is Alarm } } ?: error("no alarm")

    @Test
    fun `U90 braking sample before GPS loss, guard lifts closing speed, override 0 is the old behaviour`() {
        val e = driver()
        assertEquals(7.875, e.state.ground!!, 1e-9)
        assertEquals(11.583333333333334, e.state.closing!!, 1e-6)
        val est = estimateOf(e.state)
        assertEquals(1.0, est.k)
        assertEquals(7.875, est.closingV, 1e-9)
        assertEquals(listOf(12.0, 12.0), e.state.cvGuard.map { Math.round(it * 1e9) / 1e9 })
        var t = 960
        while (t <= 1380) {
            assertTrue(e.tick(t).events.none { it is GpsLost }, "t=$t")
            t += 60
        }
        val s1440 = e.tick(1440)
        assertEquals(GpsLost(e.ms(1440), GpsLostCause.NO_FIX_TIMEOUT, 540), s1440.events.filterIsInstance<GpsLost>().single())
        assertEquals(82_920, s1440.view.distanceM)
        val pred = s1440.view.predictedAlarmAtMs!!
        assertTrue(kotlin.math.abs(pred - (e.startMs + 7_170_000)) <= 1)
        assertEquals(FallbackAlarmChanged(e.ms(1440), e.startMs + 5_619_742, FallbackCause.ETA), s1440.events.filterIsInstance<FallbackAlarmChanged>().single())
        t = 1500
        while (t < 7200) {
            val s = e.tick(t)
            assertTrue(s.events.none { it is Alarm }, "t=$t")
            assertTrue(kotlin.math.abs(s.view.predictedAlarmAtMs!! - pred) <= 1, "t=$t")
            t += 60
        }
        assertEquals(AlarmReason.GPS_LOST, e.tick(7200).events.filterIsInstance<Alarm>().single().reason)

        val old = driver(params("{\"fallbackEarlyFrac\": 0.1, \"fallbackEarlyMaxS\": 1800, \"fallbackHintSpeedFactor\": 0}"))
        val o1440 = old.ticksUntil(960, 1440, 60) { it.events.any { e2 -> e2 is GpsLost } }!!.second
        assertEquals(old.startMs + 6_687_000, o1440.events.filterIsInstance<FallbackAlarmChanged>().single().fallbackAtMs)

        val z = driver(params("{\"lostSpeedGuardUpdates\": 0}"))
        assertTrue(z.state.cvGuard.isEmpty())
        val z1440 = z.ticksUntil(960, 1440, 60) { it.events.any { e2 -> e2 is GpsLost } }!!
        assertEquals(1440, z1440.first)
        assertEquals(85_148, z1440.second.view.distanceM)
        assertTrue(kotlin.math.abs(z1440.second.view.predictedAlarmAtMs!! - (z.startMs + 11_072_380)) <= 1)
        val (tz, sz) = alarmTick(z, 1500)
        assertEquals(11_100, tz)
        assertEquals(AlarmReason.GPS_LOST, sz.events.filterIsInstance<Alarm>().single().reason)
        assertTrue(z.state.cvGuard.isEmpty())
    }

    private val u91Fixes = u90Fixes + listOf(Triple(1080, 89_398.0, 0.0), Triple(1260, 89_398.0, 0.0), Triple(1440, 89_000.0, 4.0))

    @Test
    fun `U91 restart sample after a station stop, N = 2, 1, 0`() {
        val e = driver(fixes = u91Fixes)
        assertEquals(listOf(12.0, 7.875), e.state.cvGuard.map { Math.round(it * 1e9) / 1e9 })
        assertEquals(6.421875, e.state.ground!!, 1e-9)
        assertEquals(8.06875, e.state.closing!!, 1e-6)
        assertEquals(6.421875, estimateOf(e.state).closingV, 1e-9)
        val lost = e.ticksUntil(1500, 3000, 60) { it.events.any { x -> x is GpsLost } }!!
        assertEquals(1980, lost.first)
        assertEquals(7680, alarmTick(e, 2040).first)
        assertEquals(AlarmReason.GPS_LOST, e.view.alarmReason)
        assertEquals(11_580, alarmTick(driver(params("{\"lostSpeedGuardUpdates\": 1}"), u91Fixes), 1500).first)
        assertEquals(14_160, alarmTick(driver(params("{\"lostSpeedGuardUpdates\": 0}"), u91Fixes), 1500).first)
    }

    private fun transcript(e: EngineDriver) = e.steps.map { it.events to it.view.copy(tripId = "") }

    @Test
    fun `U92 the guard never changes behaviour with GPS OK, before established, or when accelerating`() {
        val a = driver()
        assertEquals(88_613, a.tick(1000).view.distanceM)

        val b = driver(fixes = u90Fixes.take(3))
        val b0 = driver(params("{\"lostSpeedGuardUpdates\": 0}"), u90Fixes.take(3))
        assertTrue(b.state.cvGuard.isEmpty())
        for (t in 420..8000 step 60) { b.tick(t); b0.tick(t) }
        assertEquals(transcript(b0), transcript(b))

        val acc = (0..6).map { i -> 8.0 + i }
        var d = 100_000.0
        val cFixes = ArrayList<Triple<Int, Double, Double>>()
        for (i in acc.indices) {
            if (i > 0) d -= (acc[i - 1] + acc[i]) / 2 * 180
            cFixes += Triple(i * 180, d, acc[i])
        }
        val c = driver(fixes = cFixes)
        val c0 = driver(params("{\"lostSpeedGuardUpdates\": 0}"), cFixes)
        assertTrue(c.state.cvGuard.max() < estimateOf(c.state).closingV)
        for (t in 1140..12000 step 60) { c.tick(t); c0.tick(t) }
        assertEquals(transcript(c0), transcript(c))

        val dFixes = (0..9).map { i -> Triple(i * 180, 100_000.0 - 2160.0 * i, 12.0 + i % 2) }
        val dd = EngineDriver(cfg(), params("{\"lostSpeedGuardUpdates\": 3}"))
        val before = ArrayList<Double>()
        for ((t, dist, v) in dFixes) {
            dd.state.ground?.let { g -> before += closingVOf(g, dd.state.closing, dd.p) }
            dd.fix(t, dist, spd = v)
        }
        assertEquals(before.takeLast(3), dd.state.cvGuard)

        val ee = driver()
        val g0 = ee.state.cvGuard
        ee.fix(905, 89_390.0, spd = 0.0) // STATIONARY
        ee.fix(910, 89_385.0, spd = 3.0) // MOVING but inside the stop anchor
        ee.fix(1811, 80_000.0, spd = 10.0) // gap 901 s: UNKNOWN
        ee.fix(1816, 70_000.0) // DROP (jump)
        ee.fix(1831, 69_990.0)
        ee.fix(1846, 69_980.0) // REANCHOR
        assertEquals(1, ee.state.recent.size)
        assertEquals(g0, ee.state.cvGuard)

        val p = EngineParams()
        assertEquals(12.0, closingVOf(12.0, 12.0, p))
        assertEquals(7.875, closingVOf(7.875, 11.583333, p))
        assertEquals(12.5, closingVOf(15.0, 12.5, p), 1e-12)
        assertEquals(10.0 / 1.2, closingVOf(10.0, null, p))
        assertEquals(5.0, closingVOf(10.0, -1.0, p))
        assertNull(null)
    }
}
