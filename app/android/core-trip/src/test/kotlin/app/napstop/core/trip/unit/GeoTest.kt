package app.napstop.core.trip.unit

import app.napstop.core.trip.cosDeg
import app.napstop.core.trip.distanceM
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Test

class GeoTest {
    // Reference values printed by tools/tracegen distanceM (T02 §5.2) for the same pairs.
    private val pairs = listOf(
        doubleArrayOf(21.0242144, 105.8410943, 17.4689199, 106.5997285, 4.03273590386929631e+5),
        doubleArrayOf(16.0549823, 108.1733614, 16.2560000, 108.0700000, 2.49296713491753326e+4),
        doubleArrayOf(20.5384420, 105.9448818, 20.5484420, 105.9548818, 1.52335511979563171e+3),
        doubleArrayOf(21.0285123, 105.8000000, 21.0285123, 105.8000000, 0.0),
        doubleArrayOf(10.7769000, 106.7009000, 12.2388000, 109.1967000, 3.16823007430175960e+5),
        doubleArrayOf(-33.8688, 151.2093, -33.8650, 151.2200, 1.07449043461152996e+3),
    )

    @Test
    fun `U01 distanceM equals tracegen within 1e-6 m`() {
        for (p in pairs) assertEquals(p[4], distanceM(p[0], p[1], p[2], p[3]), 1e-6)
    }

    @Test
    fun `U01 distanceM is symmetric to the bit and cosDeg rejects angles beyond 90`() {
        for (p in pairs) {
            assertEquals(
                java.lang.Double.doubleToRawLongBits(distanceM(p[0], p[1], p[2], p[3])),
                java.lang.Double.doubleToRawLongBits(distanceM(p[2], p[3], p[0], p[1])),
            )
        }
        assertThrows(IllegalArgumentException::class.java) { cosDeg(90.0001) }
        assertThrows(IllegalArgumentException::class.java) { cosDeg(-90.0001) }
        assertThrows(IllegalArgumentException::class.java) { cosDeg(Double.NaN) }
        assertEquals(1.0, cosDeg(0.0))
    }
}
