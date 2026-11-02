package app.napstop.core.trip.unit

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmMode
import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.FallbackAlarmChanged
import app.napstop.core.trip.FallbackCause
import app.napstop.core.trip.FallbackState
import app.napstop.core.trip.FallbackStatus
import app.napstop.core.trip.fallbackTarget
import app.napstop.core.trip.nextFallbackAt
import app.napstop.core.trip.support.EngineDriver
import app.napstop.core.trip.support.cfg
import app.napstop.core.trip.support.params
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class FallbackPlannerTest {
    private val p = EngineParams()
    private val old = params("{\"fallbackEarlyFrac\": 0.1, \"fallbackEarlyMaxS\": 1800, \"fallbackHintSpeedFactor\": 0}")
    private val now = 1_000_000_000L

    /** 10:00:00 of an arbitrary day, ms. */
    private val bigP = 36_000_000L + 86_400_000L * 20_000

    private fun hms(h: Int, m: Int, s: Int) = bigP - 36_000_000L + (h * 3600L + m * 60L + s) * 1000L

    @Test
    fun `U40 fallbackTarget by zone (T10_2 numbers) and old T10 numbers`() {
        fun t(tS: Long, q: EngineParams = p) = fallbackTarget(now, now + tS * 1000, now + tS * 1000, q)!!
        val cases = listOf(20_000L to -3570L, 3600L to -720L, 1000L to -70L, 600L to 30L, 300L to 30L, 60L to 30L)
        for ((tS, off) in cases) assertEquals(now + tS * 1000 + off * 1000, t(tS), "T=$tS")
        assertEquals(now + 30_000, t(0))
        assertEquals(now + 20_000, t(0, params("{\"fallbackLagS\": 10, \"fallbackMinLeadS\": 20}")))
        assertEquals(now + 20_000_000 - 1_770_000, t(20_000, old))
        assertEquals(now + 3_600_000 - 270_000, t(3600, old))
    }

    @Test
    fun `U41 quiet window 30 s before the fallback blocks any change`() {
        val fb = FallbackState(now + 25_000, now - 100_000, FallbackStatus.CONFIRMED, now - 99_000, false, false)
        for (pred in listOf(now + 2_000_000L, now + 300_000L)) {
            for (delta in listOf(-120_000L, 120_000L)) assertNull(nextFallbackAt(fb, fb.targetAtMs!! + delta, pred, now, p))
        }
    }

    @Test
    fun `U42 far zone min shift, earlier now, later at most once a minute, retry after FAILED`() {
        val pred = now + 2_000_000
        val x = now + 1_500_000
        fun fb(emittedAgoMs: Long, status: FallbackStatus = FallbackStatus.CONFIRMED) =
            FallbackState(x, now - emittedAgoMs, status, null, false, false)
        assertNull(nextFallbackAt(fb(600_000), x + 20_000, pred, now, p))
        assertEquals(x - 40_000, nextFallbackAt(fb(1_000), x - 40_000, pred, now, p))
        assertNull(nextFallbackAt(fb(30_000), x + 40_000, pred, now, p))
        assertEquals(x + 40_000, nextFallbackAt(fb(61_000), x + 40_000, pred, now, p))
        assertNull(nextFallbackAt(fb(59_000, FallbackStatus.FAILED), x, pred, now, p))
        assertEquals(x, nextFallbackAt(fb(60_000, FallbackStatus.FAILED), x, pred, now, p))
        val quiet = FallbackState(now + 10_000, now - 60_000, FallbackStatus.FAILED, null, false, false)
        assertEquals(now + 50_000, nextFallbackAt(quiet, now + 50_000, now + 20_000, now, p))
    }

    @Test
    fun `U43 engine alarm supersedes the fallback once, no ETA emission afterwards`() {
        val e = EngineDriver(cfg(AlarmMode.DISTANCE, thr = 1000))
        var t = 0
        var d = 6000.0
        while (d > 0) {
            e.fix(t, d, spd = 15.0)
            t += 5
            d -= 75
        }
        val alarmStep = e.steps.indexOfFirst { s -> s.events.any { it is Alarm } }
        val supers = e.all<FallbackAlarmChanged>().filter { it.cause == FallbackCause.SUPERSEDED }
        assertEquals(1, supers.size)
        assertTrue(e.steps[alarmStep].events.contains(supers[0]))
        assertTrue(e.steps.drop(alarmStep + 1).flatMap { it.events }.none { it is FallbackAlarmChanged })
    }

    @Test
    fun `U73 a and c stable ETA ends at P plus 30 s for every phase and start`() {
        for (phi in 0 until 20) {
            val sim = FallbackSim()
            sim.run(bigP - 3_600_000 + phi * 250L, bigP + 60_000) { bigP }
            assertEquals(bigP + 30_000, sim.fb.targetAtMs, "phi=$phi")
            assertTrue(sim.problems.isEmpty()) { sim.problems.toString() }
            assertNull(sim.fallbackRangMs)
            assertTrue(sim.engineAlarmMs!! >= bigP)
        }
        for (tS in listOf(700L, 600L, 300L, 100L, 40L, 31L, 30L, 20L)) {
            val sim = FallbackSim()
            sim.run(bigP - tS * 1000, bigP + 60_000) { bigP }
            assertEquals(bigP + 30_000, sim.fb.targetAtMs, "T=$tS")
            assertTrue(sim.problems.isEmpty()) { sim.problems.toString() }
            assertNull(sim.fallbackRangMs)
        }
    }

    @Test
    fun `U73 b table of section 4_10 from 09_30, T10_2 and old T10 parameters`() {
        val sim = FallbackSim()
        sim.run(hms(9, 30, 0), bigP + 60_000) { bigP }
        val want = (0..9).map { hms(9, 30 + 2 * it, 0) to bigP + (-270L + 30 * it) * 1000 } + (hms(9, 50, 0) to bigP + 30_000)
        assertEquals(want, sim.emissions.map { it.atMs to it.targetMs })
        val o = FallbackSim(old)
        o.run(hms(9, 30, 0), bigP + 60_000) { bigP }
        val wantOld = (0..4).map { hms(9, 30 + 5 * it, 0) to bigP + (-90L + 30 * it) * 1000 }
        assertEquals(wantOld, o.emissions.map { it.atMs to it.targetMs })
    }

    private fun f2(predicted: (Long) -> Long): FallbackSim {
        val sim = FallbackSim()
        sim.run(hms(9, 30, 0), bigP + 3_600_000, predicted = predicted)
        assertTrue(sim.problems.isEmpty()) { sim.problems.toString() }
        assertNull(sim.fallbackRangMs)
        val lowers = sim.emissions.filter { it.lowered }.map { it.atMs }
        for (i in 1 until lowers.size) assertTrue(lowers[i] - lowers[i - 1] >= 60_000)
        return sim
    }

    private fun alternating(amp: Long, from: Long = hms(9, 55, 0)): (Long) -> Long = { t ->
        if (t < from) bigP else if (((t - from) / 5000) % 2 == 0L) bigP + amp else bigP - amp
    }

    @Test
    fun `U74 near-zone hysteresis scenarios of the F1-F2 check table`() {
        val from = hms(9, 55, 0)
        val a = f2(alternating(20_000))
        assertEquals(listOf(from to bigP + 80_000), a.emissions.filter { it.atMs >= from }.map { it.atMs to it.targetMs })
        assertEquals(hms(9, 59, 45), a.engineAlarmMs)

        val b = f2(alternating(40_000))
        val wantB = listOf(0 to 100, 65 to 50, 70 to 100, 135 to 50, 140 to 100, 205 to 50, 210 to 100)
            .map { (s, off) -> from + s * 1000L to bigP + off * 1000L }
        assertEquals(wantB, b.emissions.filter { it.atMs >= from }.map { it.atMs to it.targetMs })
        assertEquals(hms(9, 59, 25), b.engineAlarmMs)

        val c = f2 { t -> if (t >= hms(9, 56, 0)) bigP - 100_000 else alternating(20_000)(t) }
        assertEquals(listOf(from to bigP + 80_000, hms(9, 56, 0) to bigP - 10_000), c.emissions.filter { it.atMs >= from }.map { it.atMs to it.targetMs })
        assertEquals(hms(9, 58, 20), c.engineAlarmMs)

        val lo = hms(9, 51, 40)
        val hi = hms(10, 1, 40)
        val d = f2 { t -> if (t < lo) bigP else if (t < hi) t + 500_000 else bigP + 600_000 }
        val inWin = d.emissions.filter { it.atMs in lo until hi }
        assertEquals((0 until 17).map { hms(9, 51, 45) + it * 35_000L }, inWin.map { it.atMs })
        assertEquals(bigP + 65_000, inWin.first().targetMs)
        assertEquals(bigP + 100_000, inWin[1].targetMs)
        assertEquals(bigP + 625_000, inWin.last().targetMs)
        assertEquals(listOf(hi to bigP + 660_000), d.emissions.filter { it.atMs >= hi }.map { it.atMs to it.targetMs })
        assertEquals(hms(10, 10, 0), d.engineAlarmMs)
    }

    @Test
    fun `U87 near zone raise, lower, hold`() {
        val pred = now + 300_000
        val x = pred + 30_000
        fun fb(target: Long, near: Boolean, emittedAgoMs: Long) = FallbackState(target, now - emittedAgoMs, FallbackStatus.CONFIRMED, null, false, near)
        assertEquals(x, nextFallbackAt(fb(x - 1, false, 600_000), x, pred, now, p))
        assertEquals(x + 30_000, nextFallbackAt(fb(x - 1, true, 600_000), x, pred, now, p))
        assertNull(nextFallbackAt(fb(x + 89_999, true, 600_000), x, pred, now, p))
        assertNull(nextFallbackAt(fb(x + 90_000, true, 59_999), x, pred, now, p))
        assertEquals(x + 60_000, nextFallbackAt(fb(x + 90_000, true, 60_000), x, pred, now, p))
        assertNull(nextFallbackAt(fb(x, true, 600_000), x, pred, now, p))
        assertNull(nextFallbackAt(fb(x + 60_000, true, 600_000), x, pred, now, p))
        val sim = FallbackSim()
        sim.step(now, now + 2_000_000)
        assertEquals(false, sim.fb.near)
        sim.step(now + 1_500_000, now + 2_000_000)
        assertEquals(true, sim.fb.near)
        assertEquals(false, FallbackState.CLEARED.near)
    }
}
