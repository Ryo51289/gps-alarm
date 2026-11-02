package app.napstop.core.trip.unit

import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.FixRec
import app.napstop.core.trip.TMath
import app.napstop.core.trip.updateRecent
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class DistanceSmootherTest {
    private fun rec(tS: Int, d: Double) = FixRec(tS * 1000L, 0.0, 106.0, 8.0, d, null)

    @Test
    fun `U08 median of the window, two elements take the larger`() {
        val p = EngineParams()
        var r = updateRecent(emptyList(), rec(0, 2000.0), p)
        r = updateRecent(r, rec(6, 900.0), p)
        assertEquals(2000.0, TMath.medianHi(r.map { it.d }))
        r = updateRecent(r, rec(12, 1980.0), p)
        assertEquals(3, r.size)
        assertEquals(1980.0, TMath.medianHi(r.map { it.d }))
        r = updateRecent(r, rec(25, 1900.0), p) // older than 12 s are dropped
        assertEquals(listOf(1900.0), r.map { it.d })
    }
}
