package app.napstop.core.bridge

import app.napstop.core.bridge.BridgeTestData.config
import app.napstop.core.bridge.BridgeTestData.expectFlutterError
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** T15 L35: routing of CompositeTripBackend (D14, §5.13). */
class CompositeTripBackendTest {
    /** Records calls; [active] = currentTrip() answer. */
    private class Fake(val name: String, val log: MutableList<String>) : TripBackend {
        var active: ActiveTripMsg? = null
        var finished: List<FinishedTripMsg> = emptyList()
        val listeners = mutableListOf<(TripUpdateMsg) -> Unit>()

        override suspend fun startTrip(config: TripConfigMsg, destLat: Double, destLng: Double, simulation: SimulationMsg?) {
            log += "$name.start(${simulation?.traceAsset})"
            active = ActiveTripMsg(config, MsgMapperTest.sampleState(), simulation)
        }

        override suspend fun stopTrip(tripId: String) {
            log += "$name.stop($tripId)"
        }

        override suspend fun currentTrip(): ActiveTripMsg? = active

        override suspend fun setBatteryChoice(tripId: String, choice: BatteryChoiceMsg) {
            log += "$name.battery"
        }

        override suspend fun dismiss(tripId: String) {
            log += "$name.dismiss($tripId)"
        }

        override suspend fun snooze(tripId: String) {
            log += "$name.snooze"
        }

        override suspend fun pendingFinishedTrips(): List<FinishedTripMsg> = finished

        override suspend fun ackFinishedTrips(tripIds: List<String>) {
            log += "$name.ack$tripIds"
        }

        override fun addListener(listener: (TripUpdateMsg) -> Unit): ListenerHandle {
            listeners += listener
            return ListenerHandle { listeners.remove(listener) }
        }
    }

    private val log = mutableListOf<String>()
    private val real = Fake("real", log)
    private val stub = Fake("stub", log)
    private val composite = CompositeTripBackend(real, stub)

    private fun finished(id: String, endedAt: Long) =
        FinishedTripMsg(id, TripOutcomeMsg.ON_TIME, EndReasonMsg.DISMISSED, endedAt, 0, null, null, null, 0, 0, VehicleKindMsg.UNKNOWN)

    @Test
    fun l35_routing() =
        runTest {
            composite.startTrip(config("s1"), 16.8, 107.1, SimulationMsg("stub/normal", 60.0))
            assertEquals(listOf("stub.start(stub/normal)"), log)
            // A stub trip runs: a real start is trip-active.
            assertEquals(BridgeErrors.TRIP_ACTIVE, expectFlutterError { kotlinx.coroutines.runBlocking { composite.startTrip(config("r1"), 16.8, 107.1, null) } }.code)
            composite.dismiss("s1")
            assertEquals("stub.dismiss(s1)", log.last())
            stub.active = null
            assertEquals(
                BridgeErrors.SIMULATION_UNAVAILABLE,
                expectFlutterError { kotlinx.coroutines.runBlocking { composite.startTrip(config("x"), 16.8, 107.1, SimulationMsg("train.gpx", 1.0)) } }.code,
            )
            composite.startTrip(config("r1"), 16.8, 107.1, null)
            assertEquals("real.start(null)", log.last())
            assertEquals("r1", composite.currentTrip()!!.config.tripId)
            composite.stopTrip("r1")
            assertEquals("real.stop(r1)", log.last())
        }

    @Test
    fun l35_finishedMergedByEndTimeAndListenersOnBoth() =
        runTest {
            real.finished = listOf(finished("a", 30), finished("c", 10))
            stub.finished = listOf(finished("b", 20))
            assertEquals(listOf("c", "b", "a"), composite.pendingFinishedTrips().map { it.tripId })
            composite.ackFinishedTrips(listOf("a", "b"))
            assertTrue(log.containsAll(listOf("real.ack[a, b]", "stub.ack[a, b]")))
            val h = composite.addListener {}
            assertEquals(1, real.listeners.size)
            assertEquals(1, stub.listeners.size)
            h.remove()
            assertEquals(0, real.listeners.size + stub.listeners.size)
        }

    @Test
    fun startsAreAtomicAcrossRealAndStub() =
        runTest {
            // Review T15 #8: a stub start while a real start still waits for its FGS is trip-active.
            val gate = kotlinx.coroutines.CompletableDeferred<Unit>()
            val slowReal =
                object : TripBackend by real {
                    override suspend fun startTrip(config: TripConfigMsg, destLat: Double, destLng: Double, simulation: SimulationMsg?) {
                        gate.await()
                        real.startTrip(config, destLat, destLng, simulation)
                    }
                }
            val c = CompositeTripBackend(slowReal, stub)
            val first = async { c.startTrip(config("r1"), 16.8, 107.1, null) }
            runCurrent()
            var code: String? = null
            try {
                c.startTrip(config("s1"), 16.8, 107.1, SimulationMsg("stub/normal", 60.0))
            } catch (e: FlutterError) {
                code = e.code
            }
            assertEquals(BridgeErrors.TRIP_ACTIVE, code)
            assertTrue(log.none { it.startsWith("stub.start") })
            gate.complete(Unit)
            first.await()
            assertEquals("r1", c.currentTrip()!!.config.tripId)
        }
}
