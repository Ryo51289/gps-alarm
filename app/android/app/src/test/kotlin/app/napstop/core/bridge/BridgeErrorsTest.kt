package app.napstop.core.bridge

import org.junit.Assert.assertEquals
import org.junit.Test

/** K21: the wire codes are shared with Dart BridgeErrorCode (spec T14 §4). */
class BridgeErrorsTest {
    @Test
    fun k21_codesMatchTheSpecTable() {
        assertEquals("invalid-config", BridgeErrors.INVALID_CONFIG)
        assertEquals("trip-active", BridgeErrors.TRIP_ACTIVE)
        assertEquals("simulation-unavailable", BridgeErrors.SIMULATION_UNAVAILABLE)
        assertEquals("permission-missing", BridgeErrors.PERMISSION_MISSING)
        assertEquals("not-foreground", BridgeErrors.NOT_FOREGROUND)
        assertEquals("start-failed", BridgeErrors.START_FAILED)
        assertEquals("request-in-progress", BridgeErrors.REQUEST_IN_PROGRESS)
        assertEquals("internal", BridgeErrors.INTERNAL)
        assertEquals(
            listOf(
                "invalid-config",
                "trip-active",
                "simulation-unavailable",
                "permission-missing",
                "not-foreground",
                "start-failed",
                "request-in-progress",
                "internal",
            ),
            BridgeErrors.ALL,
        )
    }
}
