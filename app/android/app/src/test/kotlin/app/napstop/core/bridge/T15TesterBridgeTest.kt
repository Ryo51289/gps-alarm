package app.napstop.core.bridge

import app.napstop.core.bridge.BridgeTestData.config
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Tester T15 (outside the spec list): startTrip concurrency through the real bridge stack (CompositeTripBackend →
 * RealTripBackend → TripRuntime on fakes), and stub routing while a real trip runs (D12, D14, §5.1, §5.13).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class T15TesterBridgeTest {
    /** Minimal stub backend: records calls, holds one trip. */
    private class StubFake(val log: MutableList<String>) : TripBackend {
        var active: ActiveTripMsg? = null
        var finished: List<FinishedTripMsg> = emptyList()

        override suspend fun startTrip(config: TripConfigMsg, destLat: Double, destLng: Double, simulation: SimulationMsg?) {
            log += "stub.start(${config.tripId})"
            active = ActiveTripMsg(config, MsgMapperTest.sampleState(), simulation)
        }

        override suspend fun stopTrip(tripId: String) {
            log += "stub.stop($tripId)"
            if (active?.config?.tripId == tripId) active = null
        }

        override suspend fun currentTrip(): ActiveTripMsg? = active

        override suspend fun setBatteryChoice(tripId: String, choice: BatteryChoiceMsg) {
            log += "stub.battery($tripId)"
        }

        override suspend fun dismiss(tripId: String) {
            log += "stub.dismiss($tripId)"
        }

        override suspend fun snooze(tripId: String) {
            log += "stub.snooze($tripId)"
        }

        override suspend fun pendingFinishedTrips(): List<FinishedTripMsg> = finished

        override suspend fun ackFinishedTrips(tripIds: List<String>) {
            log += "stub.ack$tripIds"
        }

        override fun addListener(listener: (TripUpdateMsg) -> Unit): ListenerHandle = ListenerHandle {}
    }

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
            val log = mutableListOf<String>()
            val composite = CompositeTripBackend(RealTripBackend(fakes.runtime, hub), StubFake(log))
            val got = mutableListOf<String>()
            composite.addListener { got += it.javaClass.simpleName }
            val first =
                async {
                    composite.startTrip(config("r1", mode = AlarmModeMsg.DISTANCE, distanceThresholdM = 1000), 16.0, 108.0, null)
                    got += "returned:r1"
                }
            val second =
                async {
                    try {
                        composite.startTrip(config("r2", mode = AlarmModeMsg.DISTANCE, distanceThresholdM = 1000), 16.0, 108.0, null)
                        "started"
                    } catch (e: FlutterError) {
                        e.code
                    }
                }
            runCurrent()
            first.await()
            assertEquals(BridgeErrors.TRIP_ACTIVE, second.await())
            assertEquals("r1", composite.currentTrip()!!.config.tripId)
            val idxState = got.indexOf("TripStateUpdateMsg")
            assertTrue("TripStateUpdateMsg before startTrip returned: $got", idxState in 0 until got.indexOf("returned:r1"))
            // A third start after the first succeeded: trip-active (D12), from the runtime this time.
            assertEquals(BridgeErrors.TRIP_ACTIVE, codeOf { composite.startTrip(config("r3"), 16.0, 108.0, null) })
            // Stub start while a real trip runs: trip-active, stub untouched.
            assertEquals(BridgeErrors.TRIP_ACTIVE, codeOf { composite.startTrip(config("s1"), 16.0, 108.0, SimulationMsg("stub/normal", 60.0)) })
            assertTrue(log.none { it.startsWith("stub.start") })
        }

    @Test
    fun aRejectedRealStartReleasesTheGateForTheNextStart() =
        runTest {
            val fakes = RuntimeFakes(this)
            val composite = CompositeTripBackend(RealTripBackend(fakes.runtime, ListenerHub { warnings += it }), StubFake(mutableListOf()))
            // Distance 50 m: the engine refuses it (invalid-config) after the bridge validator (not run here).
            val bad = async { runCatching { composite.startTrip(config("r1", mode = AlarmModeMsg.DISTANCE, distanceThresholdM = 50), 16.0, 108.0, null) } }
            runCurrent()
            assertEquals(BridgeErrors.INVALID_CONFIG, (bad.await().exceptionOrNull() as FlutterError).code)
            assertNull(composite.currentTrip())
            val ok = async { composite.startTrip(config("r2", mode = AlarmModeMsg.DISTANCE, distanceThresholdM = 1000), 16.0, 108.0, null) }
            runCurrent()
            ok.await()
            assertEquals("r2", composite.currentTrip()!!.config.tripId)
        }

    @Test
    fun commandsWhileARealTripRunsNeverReachTheStubAndUnknownIdsAreNoOps() =
        runTest {
            val fakes = RuntimeFakes(this)
            val log = mutableListOf<String>()
            val stub = StubFake(log)
            val composite = CompositeTripBackend(RealTripBackend(fakes.runtime, ListenerHub { warnings += it }), stub)
            composite.startTrip(config("r1", mode = AlarmModeMsg.DISTANCE, distanceThresholdM = 1000), 16.0, 108.0, null)
            composite.dismiss("s-old")
            composite.snooze("s-old")
            composite.stopTrip("s-old")
            composite.setBatteryChoice("s-old", BatteryChoiceMsg.MAX_SAVING)
            assertTrue("stub got nothing: $log", log.isEmpty())
            assertEquals("unknown id: no-op on the real trip", "r1", composite.currentTrip()!!.config.tripId)
            composite.stopTrip("r1")
            runCurrent()
            assertNull(composite.currentTrip())
            // The stub is reachable again once the real trip ended.
            composite.startTrip(config("s1"), 16.0, 108.0, SimulationMsg("stub/normal", 60.0))
            assertEquals("stub.start(s1)", log.last())
            assertEquals(BridgeErrors.TRIP_ACTIVE, codeOf { composite.startTrip(config("r2"), 16.0, 108.0, null) })
            composite.dismiss("s1")
            assertEquals("stub.dismiss(s1)", log.last())
        }

    @Test
    fun finishedTripsOfBothBackendsAreMergedAndAcknowledgedOnBoth() =
        runTest {
            val fakes = RuntimeFakes(this)
            val log = mutableListOf<String>()
            val stub = StubFake(log)
            val composite = CompositeTripBackend(RealTripBackend(fakes.runtime, ListenerHub { warnings += it }), stub)
            composite.startTrip(config("r1", mode = AlarmModeMsg.DISTANCE, distanceThresholdM = 1000), 16.0, 108.0, null)
            advanceTimeBy(10_000)
            composite.stopTrip("r1")
            runCurrent()
            val realEnd = composite.pendingFinishedTrips().single().endedAtMs
            stub.finished = listOf(FinishedTripMsg("s0", TripOutcomeMsg.ON_TIME, EndReasonMsg.DISMISSED, realEnd - 1, 0, null, null, null, 0, 0, VehicleKindMsg.UNKNOWN))
            assertEquals(listOf("s0", "r1"), composite.pendingFinishedTrips().map { it.tripId })
            composite.ackFinishedTrips(listOf("s0", "r1"))
            assertTrue(log.contains("stub.ack[s0, r1]"))
            stub.finished = emptyList()
            assertTrue(composite.pendingFinishedTrips().isEmpty())
        }
}
