package app.napstop.core.trip.unit

import app.napstop.core.trip.FixRec
import app.napstop.core.trip.TMath
import app.napstop.core.trip.recentSpeed
import app.napstop.core.trip.support.trackingState
import app.napstop.core.trip.support.work
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

class MathUtilTest {
    private fun bits(x: Double) = java.lang.Double.doubleToRawLongBits(x)

    @Test
    fun `U09 blend first sample then EMA`() {
        val e1 = TMath.blend(null, 10.0, 5.0, 300)
        assertEquals(10.0, e1)
        assertEquals(10.0 + 10.0 * 5.0 / 305.0, TMath.blend(e1, 20.0, 5.0, 300))
    }

    @Test
    fun `U62 minOrNull`() {
        assertEquals(3L, TMath.minOrNull(null, 5L, 3L))
        assertNull(TMath.minOrNull(null, null))
    }

    @Test
    fun `U66 recentSpeed from medianHi of groundSample then ground then 0`() {
        fun rec(gs: Double?, i: Int) = FixRec(i * 1000L, 0.0, 106.0, 8.0, 1000.0, gs)
        val s = trackingState()
        assertEquals(5.0, recentSpeed(work(s.copy(recent = listOf(rec(null, 0), rec(3.0, 1), rec(5.0, 2))))))
        assertEquals(4.0, recentSpeed(work(s.copy(recent = listOf(rec(4.0, 0), rec(null, 1))))))
        assertEquals(2.0, recentSpeed(work(s.copy(recent = listOf(rec(null, 0), rec(null, 1)), ground = 2.0))))
        assertEquals(0.0, recentSpeed(work(s.copy(recent = listOf(rec(null, 0)), ground = null))))
    }

    @Test
    fun `U09 helpers min max signed zero, roundHalfUp, floorMs, medianHi`() {
        assertEquals(bits(0.0), bits(TMath.max(0.0, -0.0)))
        assertEquals(bits(-0.0), bits(TMath.min(-0.0, 0.0)))
        assertEquals(3, TMath.roundHalfUp(2.5))
        assertEquals(2, TMath.roundHalfUp(2.4999999))
        assertEquals(0L, TMath.floorMs(0.0009999))
        assertEquals(1L, TMath.floorMs(0.001))
        assertEquals(2000.0, TMath.medianHi(listOf(2000.0, 900.0)))
        assertEquals(1980.0, TMath.medianHi(listOf(2000.0, 900.0, 1980.0)))
        assertNull(TMath.medianHi(listOf(null, null)))
        assertEquals(5.0, TMath.clamp(7.0, 1.0, 5.0))
    }
}
