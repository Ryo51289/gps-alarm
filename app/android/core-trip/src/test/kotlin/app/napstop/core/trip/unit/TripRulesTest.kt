package app.napstop.core.trip.unit

import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.TripRules
import app.napstop.core.trip.VehicleKind
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class TripRulesTest {
    @Test
    fun `U16 shortDistanceWarning integer formula`() {
        val p = EngineParams()
        val cases = listOf(
            Triple(1000, VehicleKind.COACH, true), Triple(5000, VehicleKind.COACH, false), Triple(4000, VehicleKind.COACH, false),
            Triple(2000, VehicleKind.BUS, false), Triple(1000, VehicleKind.BUS, true), Triple(1333, VehicleKind.BUS, true),
            Triple(1334, VehicleKind.BUS, false), Triple(4000, VehicleKind.TRAIN, false), Triple(3600, VehicleKind.TRAIN, true),
            Triple(3667, VehicleKind.TRAIN, false),
        )
        for ((thr, v, want) in cases) assertEquals(want, TripRules.shortDistanceWarning(thr, v, p), "$thr $v")
        assertEquals(false, TripRules.shortDistanceWarning(3999, VehicleKind.UNKNOWN, p.copy(expectedSpeedKmhUnknown = 5)))
    }
}
