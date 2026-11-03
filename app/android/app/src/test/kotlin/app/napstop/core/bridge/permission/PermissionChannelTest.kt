package app.napstop.core.bridge.permission

import app.napstop.core.bridge.ActiveTripMsg
import app.napstop.core.bridge.BatteryChoiceMsg
import app.napstop.core.bridge.BridgeRegistrar
import app.napstop.core.bridge.FinishedTripMsg
import app.napstop.core.bridge.ListenerHandle
import app.napstop.core.bridge.PermissionHostApi
import app.napstop.core.bridge.PermissionHostApiStub
import app.napstop.core.bridge.PermissionKindMsg
import app.napstop.core.bridge.SettingsTargetMsg
import app.napstop.core.bridge.SimulationMsg
import app.napstop.core.bridge.TripBackend
import app.napstop.core.bridge.TripConfigMsg
import app.napstop.core.bridge.TripUpdateMsg
import io.flutter.plugin.common.BinaryMessenger
import java.nio.ByteBuffer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

/**
 * K07, K09: the real PermissionHostApiImpl behind the generated Pigeon handlers and codec.
 * Errors reach Dart as code + class name only (T14 F3); the registrar wires the real or
 * the stub API (spec T21 §4.7).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class PermissionChannelTest {
    private val dispatcher = StandardTestDispatcher()

    @Before
    fun setUp() {
        // The generated async handlers launch on Dispatchers.Main.
        Dispatchers.setMain(dispatcher)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private class FakeEngine : BinaryMessenger {
        val handlers = mutableMapOf<String, BinaryMessenger.BinaryMessageHandler>()

        override fun send(channel: String, message: ByteBuffer?) = Unit

        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) = Unit

        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) {
            if (handler == null) handlers.remove(channel) else handlers[channel] = handler
        }

        fun has(method: String) = handlers.containsKey("$PREFIX$method")

        /** Sends [args] to PermissionHostApi.[method]; the reply slot fills when native answers. */
        fun call(method: String, args: List<Any?>?): () -> List<Any?>? {
            val message = args?.let { PermissionHostApi.codec.encodeMessage(it)!!.apply { rewind() } }
            var reply: List<Any?>? = null
            handlers.getValue("$PREFIX$method").onMessage(message) { bytes ->
                @Suppress("UNCHECKED_CAST")
                reply = PermissionHostApi.codec.decodeMessage(bytes!!.duplicate().apply { rewind() }) as List<Any?>
            }
            return { reply }
        }

        companion object {
            const val PREFIX = "dev.flutter.pigeon.napstop.PermissionHostApi."
        }
    }

    private class NoTrips : TripBackend {
        override fun addListener(listener: (TripUpdateMsg) -> Unit): ListenerHandle = ListenerHandle {}

        override suspend fun startTrip(config: TripConfigMsg, destLat: Double, destLng: Double, simulation: SimulationMsg?) =
            Unit

        override suspend fun stopTrip(tripId: String) = Unit

        override suspend fun currentTrip(): ActiveTripMsg? = null

        override suspend fun setBatteryChoice(tripId: String, choice: BatteryChoiceMsg) = Unit

        override suspend fun dismiss(tripId: String) = Unit

        override suspend fun snooze(tripId: String) = Unit

        override suspend fun pendingFinishedTrips(): List<FinishedTripMsg> = emptyList()

        override suspend fun ackFinishedTrips(tripIds: List<String>) = Unit
    }

    private fun TestScope.reply(engine: FakeEngine, method: String, args: List<Any?>?): List<Any?> {
        val slot = engine.call(method, args)
        runCurrent()
        return slot() ?: error("no reply to $method")
    }

    @Test
    fun k07ErrorsCarryOnlyTheCodeAndTheClassName() =
        runTest(dispatcher) {
            val fakes = PermissionFakes().apply { failure = { IllegalArgumentException("lat 21.0") } }
            val engine = FakeEngine()
            BridgeRegistrar.register(engine, NoTrips(), permissionApi = fakes.impl())
            val calls =
                mapOf(
                    "status" to null,
                    "request" to listOf(PermissionKindMsg.LOCATION),
                    "openSettings" to listOf(SettingsTargetMsg.APP_DETAILS),
                    "deviceInfo" to null,
                    "startBackgroundCheck" to listOf(30_000L),
                )
            for ((method, args) in calls) {
                val r = reply(engine, method, args)
                assertEquals(method, listOf("internal", "IllegalArgumentException", null), r)
                val text = r.toString()
                for (leak in listOf("Stacktrace", "Cause:", "21.0", "lat")) {
                    assertFalse("$method leaks $leak", text.contains(leak))
                }
            }
        }

    @Test
    fun k07SuccessGoesThroughTheCodec() =
        runTest(dispatcher) {
            val engine = FakeEngine()
            BridgeRegistrar.register(engine, NoTrips(), permissionApi = PermissionFakes().impl())
            val status = reply(engine, "status", null)
            assertEquals(1, status.size)
            val check = reply(engine, "startBackgroundCheck", listOf(30_000L)).single()
            assertEquals(31_000L, (check as app.napstop.core.bridge.BackgroundCheckMsg).dueAtMs)
            assertEquals(listOf(check), reply(engine, "backgroundCheck", null))
            assertEquals(listOf(null), reply(engine, "cancelBackgroundCheck", null))
            assertEquals(listOf(null), reply(engine, "backgroundCheck", null))
            assertEquals(
                listOf("invalid-config", "delayMs: out of range", null),
                reply(engine, "startBackgroundCheck", listOf(4_999L)),
            )
        }

    @Test
    fun k09RegistrarWiresTheGivenApiAndUnregisters() =
        runTest(dispatcher) {
            val fakes = PermissionFakes().apply { sources.granted.clear() }
            val engine = FakeEngine()
            val registration = BridgeRegistrar.register(engine, NoTrips(), permissionApi = fakes.impl())
            val status = reply(engine, "status", null).single() as app.napstop.core.bridge.PermissionStatusMsg
            assertEquals(app.napstop.core.bridge.LocationAccessMsg.NOT_DETERMINED, status.location)
            registration.unregister()
            for (method in listOf("status", "request", "openSettings", "deviceInfo", "startBackgroundCheck")) {
                assertFalse(method, engine.has(method))
            }
            assertFalse(registration.onRequestPermissionsResult(ActivityPermissionPrompter.REQUEST_CODE))
        }

    @Test
    fun k09OldOverloadStillUsesTheStub() =
        runTest(dispatcher) {
            val engine = FakeEngine()
            BridgeRegistrar.register(engine, NoTrips())
            assertEquals(listOf(PermissionHostApiStub.FIXED_STATUS), reply(engine, "status", null))
            assertEquals(listOf("internal", "unsupported", null), reply(engine, "startBackgroundCheck", listOf(30_000L)))
            assertEquals(listOf(null), reply(engine, "backgroundCheck", null))
            assertNull(reply(engine, "cancelBackgroundCheck", null).single())
        }
}
