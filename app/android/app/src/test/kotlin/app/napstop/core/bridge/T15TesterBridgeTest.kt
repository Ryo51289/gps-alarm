package app.napstop.core.bridge

import app.napstop.core.bridge.BridgeTestData.config
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Tester T15 (outside the spec list): startTrip concurrency through the real bridge stack (RealTripBackend →
 * TripRuntime on fakes), D12, §5.1. T18 D13: the CompositeTripBackend cases (stub routing) went with the composite.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class T15TesterBridgeTest {
    private val warnings = mutableListOf<String>()

    /** Error code of [block] (null = success). Suspends: the runtime actor runs on the test dispatcher. */
    private suspend fun codeOf(block: suspend () -> Unit): String? =
        try {
            block()
            null
        } catch (e: FlutterError) {
            e.code
        }

    @Test
    fun twoConcurrentRealStartsOneWinsOneIsTripActiveAndStateComesFirst() =
        runTest {
            val fakes = RuntimeFakes(this)
            val hub = ListenerHub { warnings += it }
            val backend = RealTripBackend(fakes.runtime, hub)
            val got = mutableListOf<String>()
            backend.addListener { got += it.javaClass.simpleName }
            val first =
                async {
                    backend.startTrip(config("r1", mode = AlarmModeMsg.DISTANCE, distanceThresholdM = 1000), 16.0, 108.0, null)
                    got += "returned:r1"
                }
            val second =
                async {
                    try {
                        backend.startTrip(config("r2", mode = AlarmModeMsg.DISTANCE, distanceThresholdM = 1000), 16.0, 108.0, null)
                        "started"
                    } catch (e: FlutterError) {
                        e.code
                    }
                }
            runCurrent()
            first.await()
            assertEquals(BridgeErrors.TRIP_ACTIVE, second.await())
            assertEquals("r1", backend.currentTrip()!!.config.tripId)
            val idxState = got.indexOf("TripStateUpdateMsg")
            assertTrue("TripStateUpdateMsg before startTrip returned: $got", idxState in 0 until got.indexOf("returned:r1"))
            // A third start after the first succeeded: trip-active (D12), from the runtime this time.
            assertEquals(BridgeErrors.TRIP_ACTIVE, codeOf { backend.startTrip(config("r3"), 16.0, 108.0, null) })
            // A simulation while a real trip runs: trip-active as well (one trip at a time, T18 §11).
            assertEquals(BridgeErrors.TRIP_ACTIVE, codeOf { backend.startTrip(config("s1"), 16.0, 108.0, SimulationMsg("bus_hn_brt01", 60.0)) })
        }

    @Test
    fun aRejectedRealStartReleasesTheGateForTheNextStart() =
        runTest {
            val fakes = RuntimeFakes(this)
            val backend = RealTripBackend(fakes.runtime, ListenerHub { warnings += it })
            // Distance 50 m: the engine refuses it (invalid-config) after the bridge validator (not run here).
            val bad = async { runCatching { backend.startTrip(config("r1", mode = AlarmModeMsg.DISTANCE, distanceThresholdM = 50), 16.0, 108.0, null) } }
            runCurrent()
            assertEquals(BridgeErrors.INVALID_CONFIG, (bad.await().exceptionOrNull() as FlutterError).code)
            assertNull(backend.currentTrip())
            val ok = async { backend.startTrip(config("r2", mode = AlarmModeMsg.DISTANCE, distanceThresholdM = 1000), 16.0, 108.0, null) }
            runCurrent()
            ok.await()
            assertEquals("r2", backend.currentTrip()!!.config.tripId)
        }
}
