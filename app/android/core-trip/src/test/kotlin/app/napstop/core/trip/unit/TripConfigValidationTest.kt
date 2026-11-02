package app.napstop.core.trip.unit

import app.napstop.core.trip.AlarmMode
import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.TripConfig
import app.napstop.core.trip.TripEngine
import app.napstop.core.trip.support.S
import app.napstop.core.trip.support.cfg
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Test

class TripConfigValidationTest {
    private fun err(c: TripConfig): String =
        assertThrows(IllegalArgumentException::class.java) { TripEngine.start(c, EngineParams(), S) }.message!!

    private fun ok(c: TripConfig) {
        TripEngine.start(c, EngineParams(), S)
    }

    @Test
    fun `U03 thresholds out of range or missing are rejected, bounds accepted`() {
        assertEquals("distanceThresholdM: out of range", err(cfg(AlarmMode.DISTANCE, thr = 150)))
        assertEquals("distanceThresholdM: out of range", err(cfg(AlarmMode.DISTANCE, thr = 10001)))
        assertEquals("timeThresholdMin: out of range", err(cfg(AlarmMode.TIME, thrMin = 4)))
        assertEquals("timeThresholdMin: required", err(cfg(AlarmMode.TIME, thrMin = null)))
        ok(cfg(AlarmMode.DISTANCE, thr = 200))
        ok(cfg(AlarmMode.DISTANCE, thr = 10000))
    }

    @Test
    fun `U03 test report 4 TIME bounds, SMART with bad threshold, C11 order and messages`() {
        ok(cfg(AlarmMode.TIME, thrMin = 60))
        ok(cfg(AlarmMode.TIME, thrMin = 5))
        assertEquals("timeThresholdMin: out of range", err(cfg(AlarmMode.TIME, thrMin = 61)))
        assertEquals("distanceThresholdM: out of range", err(cfg(AlarmMode.SMART, thr = 150)))
        ok(cfg(AlarmMode.SMART))
        assertEquals("distanceThresholdM: required", err(cfg(AlarmMode.DISTANCE, thr = null)))
        val base = cfg(AlarmMode.DISTANCE, thr = 1)
        assertEquals("tripId: empty", err(base.copy(tripId = "", destLat = 95.0)))
        assertEquals("destLat: out of range", err(base.copy(destLat = 95.0, destLng = 200.0)))
        assertEquals("destLat: out of range", err(base.copy(destLat = Double.NaN)))
        assertEquals("destLng: out of range", err(base.copy(destLng = 180.0)))
        assertEquals("destLng: out of range", err(base.copy(destLng = Double.POSITIVE_INFINITY)))
        assertEquals("distanceThresholdM: out of range", err(base))
        ok(base.copy(destLng = -180.0, distanceThresholdM = 1000))
        assertEquals("timeThresholdMin: out of range", err(cfg(AlarmMode.DISTANCE, thr = 1000, thrMin = 4)))
    }
}
