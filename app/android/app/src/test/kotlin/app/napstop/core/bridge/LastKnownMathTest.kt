package app.napstop.core.bridge

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/** T23 TK02: input check and freshest cached fix of distancesFromLastKnownM. */
class LastKnownMathTest {
    @Test
    fun validPairs() {
        assertFalse(LastKnownMath.validPairs(emptyList()))
        assertFalse(LastKnownMath.validPairs(listOf(1.0)))
        assertTrue(LastKnownMath.validPairs(listOf(21.0, 105.8)))
        assertFalse(LastKnownMath.validPairs(List(102) { 10.0 }))
        assertTrue(LastKnownMath.validPairs(List(100) { 10.0 }))
        assertFalse(LastKnownMath.validPairs(listOf(Double.NaN, 105.8)))
        assertFalse(LastKnownMath.validPairs(listOf(21.0, Double.POSITIVE_INFINITY)))
        assertFalse(LastKnownMath.validPairs(listOf(91.0, 105.8)))
        assertFalse(LastKnownMath.validPairs(listOf(21.0, 180.5)))
        assertTrue(LastKnownMath.validPairs(listOf(-90.0, -180.0, 90.0, 180.0)))
    }

    @Test
    fun roundForDisplayMatchesTheShownResolution() {
        assertEquals(0.0, LastKnownMath.roundForDisplay(0.0), 0.0)
        assertEquals(0.0, LastKnownMath.roundForDisplay(4.9), 0.0)
        assertEquals(10.0, LastKnownMath.roundForDisplay(5.0), 0.0)
        assertEquals(850.0, LastKnownMath.roundForDisplay(847.3), 0.0)
        assertEquals(990.0, LastKnownMath.roundForDisplay(994.9), 0.0)
        assertEquals(1000.0, LastKnownMath.roundForDisplay(995.0), 0.0)
        assertEquals(1000.0, LastKnownMath.roundForDisplay(1049.9), 0.0)
        assertEquals(1500.0, LastKnownMath.roundForDisplay(1450.0), 0.0)
        assertEquals(402000.0, LastKnownMath.roundForDisplay(402_031.7), 0.0)
        assertEquals(0.0, LastKnownMath.roundForDisplay(-3.0), 0.0)
        assertEquals(0.0, LastKnownMath.roundForDisplay(Double.NaN), 0.0)
        // Tester T23 (review nit #8): pin the 1 km step boundary. Exactly 1000 uses the
        // 100 m step; just below rounds up on the 10 m step; both show "1 km".
        assertEquals(1000.0, LastKnownMath.roundForDisplay(1000.0), 0.0)
        assertEquals(1000.0, LastKnownMath.roundForDisplay(999.4), 0.0)
        assertEquals(990.0, LastKnownMath.roundForDisplay(994.99), 0.0)
        assertEquals(1000.0, LastKnownMath.roundForDisplay(999.999), 0.0)
        assertEquals(1000.0, LastKnownMath.roundForDisplay(1000.001), 0.0)
        assertEquals(1100.0, LastKnownMath.roundForDisplay(1050.0), 0.0)
        assertEquals(0.0, LastKnownMath.roundForDisplay(Double.POSITIVE_INFINITY), 0.0)
        // Every result is a multiple of 10 (100 from 1 km).
        for (m in listOf(12.3, 333.3, 999.4, 1234.5, 98_765.4)) {
            val r = LastKnownMath.roundForDisplay(m)
            assertEquals(0.0, r % (if (r < 1000.0) 10.0 else 100.0), 0.0)
        }
    }

    @Test
    fun freshestPicksTheNewestYoungEnough() {
        val minute = 60_000_000_000L
        val now = 100 * minute
        val tenMinutes = LastKnownMath.Candidate(now - 10 * minute, "a")
        val fortyMinutes = LastKnownMath.Candidate(now - 40 * minute, "b")
        val twentyMinutes = LastKnownMath.Candidate(now - 20 * minute, "c")
        val best = LastKnownMath.freshest(listOf(fortyMinutes, tenMinutes, twentyMinutes), now, 30 * 60_000L)
        assertSame(tenMinutes, best)
        assertEquals("a", best?.payload)
    }

    @Test
    fun freshestIsNullWhenEverythingIsTooOld() {
        val minute = 60_000_000_000L
        val now = 100 * minute
        val old = listOf(
            LastKnownMath.Candidate(now - 40 * minute),
            LastKnownMath.Candidate(now - 31 * minute),
        )
        assertNull(LastKnownMath.freshest(old, now, 30 * 60_000L))
        assertNull(LastKnownMath.freshest(emptyList(), now, 30 * 60_000L))
    }

    @Test
    fun freshestAcceptsTheBoundary() {
        val now = 10_000_000_000_000L
        val exactly = LastKnownMath.Candidate(now - 30 * 60_000_000_000L)
        assertSame(exactly, LastKnownMath.freshest(listOf(exactly), now, 30 * 60_000L))
    }
}
