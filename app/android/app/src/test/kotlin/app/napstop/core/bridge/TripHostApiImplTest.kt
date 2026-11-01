package app.napstop.core.bridge

import app.napstop.core.bridge.BridgeTestData.config
import app.napstop.core.bridge.BridgeTestData.expectFlutterError
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** K22 + error mapping of TripHostApiImpl (spec T14 §4, review T14 N1). */
class TripHostApiImplTest {
    private class ThrowingBackend(private val error: Throwable) : TripBackend {
        var startCalls = 0

        override suspend fun startTrip(config: TripConfigMsg, destLat: Double, destLng: Double, simulation: SimulationMsg?) {
            startCalls++
            throw error
        }

        override suspend fun stopTrip(tripId: String) = throw error

        override suspend fun currentTrip(): ActiveTripMsg? = throw error

        override suspend fun setBatteryChoice(tripId: String, choice: BatteryChoiceMsg) = throw error

        override suspend fun dismiss(tripId: String) = throw error

        override suspend fun snooze(tripId: String) = throw error

        override suspend fun pendingFinishedTrips(): List<FinishedTripMsg> = throw error

        override suspend fun ackFinishedTrips(tripIds: List<String>) = throw error

        override fun addListener(listener: (TripUpdateMsg) -> Unit): ListenerHandle = ListenerHandle {}
    }

    @Test
    fun k22_unexpectedExceptionBecomesInternalWithClassNameOnly() =
        runTest {
            val api = TripHostApiImpl(ThrowingBackend(IllegalStateException("secret 21.0,105.8")))
            val e = expectFlutterError { api.startTrip(config(), 21.0, 105.8, null) }
            assertEquals("internal", e.code)
            assertEquals("IllegalStateException", e.message)
            assertNull(e.details)
            assertFalse(e.toString().contains("21.0"))
        }

    @Test
    fun errorsAreInternalWithClassNameOnlyToo() =
        runTest {
            // A TODO() left in a backend branch, or any other Error: no message, no stack trace.
            val api = TripHostApiImpl(ThrowingBackend(NotImplementedError("secret 21.0,105.8")))
            val e = expectFlutterError { api.dismiss("t1") }
            assertEquals("internal", e.code)
            assertEquals("NotImplementedError", e.message)
            assertNull(e.details)
            val overflow = expectFlutterError { TripHostApiImpl(ThrowingBackend(StackOverflowError())).snooze("t1") }
            assertEquals("StackOverflowError", overflow.message)
        }

    @Test
    fun everyMethodIsGuarded() =
        runTest {
            val api = TripHostApiImpl(ThrowingBackend(IllegalArgumentException("x")))
            val calls: List<suspend () -> Unit> =
                listOf(
                    { api.stopTrip("t1") },
                    { api.currentTrip() },
                    { api.setBatteryChoice("t1", BatteryChoiceMsg.MAX_SAVING) },
                    { api.dismiss("t1") },
                    { api.snooze("t1") },
                    { api.pendingFinishedTrips() },
                    { api.ackFinishedTrips(listOf("t1")) },
                )
            for (call in calls) {
                val e = expectFlutterError { call() }
                assertEquals("internal", e.code)
                assertEquals("IllegalArgumentException", e.message)
            }
        }

    @Test
    fun flutterErrorsPassThroughUnchanged() =
        runTest {
            val api = TripHostApiImpl(ThrowingBackend(FlutterError("trip-active", null, null)))
            val e = expectFlutterError { api.startTrip(config(), 21.0, 105.8, null) }
            assertEquals("trip-active", e.code)
        }

    @Test
    fun invalidConfigNeverReachesTheBackend() =
        runTest {
            val backend = ThrowingBackend(IllegalStateException())
            val api = TripHostApiImpl(backend)
            val e = expectFlutterError { api.startTrip(config(), 91.5, 105.8, null) }
            assertEquals("invalid-config", e.code)
            assertEquals("destLat: out of range", e.message)
            assertEquals(0, backend.startCalls)
            assertTrue(BridgeErrors.ALL.contains(e.code))
        }
}
