package app.napstop.core.trip.unit

import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.FixRec
import app.napstop.core.trip.Motion
import app.napstop.core.trip.TMath
import app.napstop.core.trip.speedSample
import app.napstop.core.trip.support.DEST
import app.napstop.core.trip.support.EngineDriver
import app.napstop.core.trip.support.TestGeo
import app.napstop.core.trip.support.estimateOf
import app.napstop.core.trip.support.trackingState
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class SpeedEstimatorTest {
    private val p = EngineParams()

    /** Runs at 15 m/s (Doppler) every 5 s for t = 0..60, d = 100000 − 15 t. */
    private fun running(): EngineDriver {
        val e = EngineDriver()
        for (t in 0..60 step 5) e.fix(t, 100_000.0 - 15.0 * t, spd = 15.0)
        return e
    }

    @Test
    fun `U10 short stop of 25 s is blended into the EMA`() {
        val e = running()
        for (t in 65..90 step 5) e.fix(t, 99_100.0, spd = 0.0)
        val g0 = e.state.ground!!
        val c0 = e.state.closing!!
        assertEquals(15.0, g0)
        e.fix(95, 99_025.0, spd = 15.0)
        assertNull(e.state.stopStartMs)
        assertEquals(TMath.blend(TMath.blend(g0, 0.0, 25.0, 300), 15.0, 5.0, 300), e.state.ground!!)
        assertEquals(TMath.blend(TMath.blend(c0, 0.0, 25.0, 300), 15.0, 5.0, 300), e.state.closing!!, 1e-6)
    }

    @Test
    fun `U11 long stop of 300 s is skipped, EMA and ETA unchanged`() {
        val e = running()
        val etaBefore = e.view.etaS!!
        for (t in 65..365 step 5) e.fix(t, 99_100.0, spd = 0.0)
        val g0 = e.state.ground!!
        val c0 = e.state.closing!!
        e.fix(370, 99_100.0 - 75.0, spd = 15.0)
        assertEquals(g0, e.state.ground!!)
        assertEquals(c0, e.state.closing!!, 1e-6)
        // Same EMA and k: 75 m less to go = 75 · k / v = 5 s less (route factor learnt = 1).
        assertTrue(kotlin.math.abs(etaBefore - 5 - e.view.etaS!!) <= 1)
    }

    @Test
    fun `U12 route factor k`() {
        assertEquals(1.25, estimateOf(trackingState(ground = 20.0, closing = 16.0)).k)
        assertEquals(1.0, estimateOf(trackingState(ground = 20.0, closing = 25.0)).k)
        assertEquals(2.0, estimateOf(trackingState(ground = 20.0, closing = -1.0)).k)
        assertEquals(1.2, estimateOf(trackingState(ground = 20.0, closing = 16.0, established = false)).k)
    }

    @Test
    fun `U13 etaS and minimum speed`() {
        assertEquals(740.0, estimateOf(trackingState(d = 9000.0, ground = 15.0, closing = 12.5, inStop = true)).etaS!!, 1e-9)
        assertNull(estimateOf(trackingState(d = 9000.0, ground = 0.4, closing = 0.4 / 1.2, inStop = true)).etaS)
    }

    @Test
    fun `U60 sample gap 900 s updates the EMA, 901 s does not, in both branches`() {
        val a = FixRec(0, 0.0, 106.0, 8.0, 20_000.0, null)
        val pt900 = TestGeo.pointOnMeridian(DEST, 11_000.0)
        for (gap in listOf(900_000L, 901_000L)) {
            val f = FixRec(gap, pt900.lat, pt900.lng, 8.0, 11_000.0, null)
            val doppler = speedSample(a, f, 10.0, p)
            val disp = speedSample(a, f, null, p)
            if (gap == 900_000L) {
                assertEquals(Motion.MOVING, doppler.raw)
                assertEquals(Motion.MOVING, disp.raw)
                assertEquals(900.0, doppler.dt)
            } else {
                assertEquals(Motion.UNKNOWN, doppler.raw)
                assertEquals(Motion.UNKNOWN, disp.raw)
                assertNull(doppler.groundSample)
                assertNull(disp.closingSample)
            }
        }
        val e = EngineDriver()
        e.fix(0, 20_000.0, spd = 10.0)
        e.fix(900, 11_000.0, spd = 10.0)
        assertEquals(10.0, e.state.ground)
        assertEquals(900.0, e.state.movingTimeS)
        val u = EngineDriver()
        u.fix(0, 20_000.0, spd = 10.0)
        u.fix(901, 11_000.0, spd = 10.0)
        assertNull(u.state.ground)
    }

    @Test
    fun `U61 established by Doppler without closing samples uses the prior route factor`() {
        val e = EngineDriver()
        for (i in 0 until 10) e.fix(i * 30, 50_000.0 - 300.0 * i, acc = if (i % 2 == 0) 60.0 else 40.0, spd = 10.0)
        assertTrue(e.state.movingSamples >= 3 && e.state.movingTimeS >= 120.0)
        assertNull(e.state.closing)
        assertEquals(1.2, estimateOf(e.state).k)
    }

    @Test
    fun `U72 one long stop with noisy no-speed fixes, EMA unchanged, exit beyond 50 m`() {
        val e = running()
        val stopPt = TestGeo.pointOnMeridian(DEST, 99_090.0) // 10 m from the last moving fix
        e.fixAt(65, stopPt)
        val offsets = listOf(0.0 to 0.0, 18.0 to 0.0, 0.0 to 0.0, -18.0 to 0.0, 0.0 to 18.0, 12.0 to -12.0, 0.0 to -18.0, 0.0 to 0.0)
        var starts = 0
        var wasStopped = e.state.stopStartMs != null
        if (wasStopped) starts++
        var i = 0
        for (t in 70..665 step 5) {
            val (east, north) = offsets[i++ % offsets.size]
            e.fixAt(t, TestGeo.jitter(stopPt, east, north))
            val stopped = e.state.stopStartMs != null
            if (stopped && !wasStopped) starts++
            wasStopped = stopped
            assertTrue(stopped, "stopped at $t")
            assertEquals(15.0, e.state.ground)
        }
        e.fixAt(670, TestGeo.pointOnMeridian(DEST, 99_090.0 - 60.0), spd = 15.0)
        assertNull(e.state.stopStartMs)
        assertEquals(1, starts)
        assertEquals(15.0, e.state.ground)
        assertNotNull(e.state.closing)
    }
}
