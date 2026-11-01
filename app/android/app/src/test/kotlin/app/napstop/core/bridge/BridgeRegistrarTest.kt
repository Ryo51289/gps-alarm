package app.napstop.core.bridge

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import java.nio.ByteBuffer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

/** Listener ownership across Flutter engines (review T14 M1), through the real Pigeon channels. */
class BridgeRegistrarTest {
    private companion object {
        const val UPDATES = "dev.flutter.pigeon.napstop.TripEventChannelApi.tripUpdates"
    }

    /** One engine's messenger: records handlers and what native sends to Dart. */
    private class FakeEngine : BinaryMessenger {
        val handlers = mutableMapOf<String, BinaryMessenger.BinaryMessageHandler>()
        private val sent = mutableListOf<Pair<String, ByteBuffer?>>()

        override fun send(channel: String, message: ByteBuffer?) {
            sent += channel to message
        }

        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) {
            sent += channel to message
        }

        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) {
            if (handler == null) handlers.remove(channel) else handlers[channel] = handler
        }

        /** Dart side starts / stops listening to `updates`. */
        fun listen() = call("listen")

        fun cancel() = call("cancel")

        private fun call(method: String) {
            val message = CoreApiPigeonMethodCodec.encodeMethodCall(MethodCall(method, null))
            message.rewind()
            handlers.getValue(UPDATES).onMessage(message) {}
        }

        /** Updates received on the event channel, decoded. */
        fun updates(): List<Any?> =
            sent.filter { it.first == UPDATES }.map { (_, message) ->
                CoreApiPigeonMethodCodec.decodeEnvelope(message!!.duplicate().apply { rewind() })
            }
    }

    /** Synchronous backend: keeps its listeners, [emit] sends to all of them. */
    private class FakeBackend : TripBackend {
        private val listeners = mutableListOf<(TripUpdateMsg) -> Unit>()
        val listenerCount get() = listeners.size

        fun emit(update: TripUpdateMsg) = listeners.toList().forEach { it(update) }

        override fun addListener(listener: (TripUpdateMsg) -> Unit): ListenerHandle {
            val entry: (TripUpdateMsg) -> Unit = { listener(it) }
            listeners += entry
            return ListenerHandle { listeners.remove(entry) }
        }

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

    private fun snoozed(atMs: Long) = SnoozedMsg(tripId = "t1", atMs = atMs, untilMs = atMs + 60_000)

    @Test
    fun destroyingOneEngineKeepsTheOtherEngineReceiving() {
        val backend = FakeBackend()
        val engineA = FakeEngine()
        val engineB = FakeEngine()
        val registrationA = BridgeRegistrar.register(engineA, backend)
        engineA.listen()
        val registrationB = BridgeRegistrar.register(engineB, backend)
        engineB.listen()
        assertEquals(2, backend.listenerCount)

        backend.emit(snoozed(1))
        assertEquals(listOf(snoozed(1)), engineA.updates())
        assertEquals(listOf(snoozed(1)), engineB.updates())

        // Engine B is destroyed (cleanUpFlutterEngine) while A stays alive.
        registrationB.unregister()
        assertNull(engineB.handlers[UPDATES])
        assertNotNull(engineA.handlers[UPDATES])
        assertEquals(1, backend.listenerCount)

        backend.emit(snoozed(2))
        assertEquals(listOf(snoozed(1), snoozed(2)), engineA.updates())
        assertEquals(listOf(snoozed(1)), engineB.updates())

        registrationA.unregister()
        assertEquals(0, backend.listenerCount)
    }

    @Test
    fun cancelAndRelistenTouchOnlyTheirOwnEngine() {
        val backend = FakeBackend()
        val engineA = FakeEngine()
        val engineB = FakeEngine()
        BridgeRegistrar.register(engineA, backend)
        BridgeRegistrar.register(engineB, backend)
        engineA.listen()
        engineB.listen()

        // A listens again (e.g. hot restart): its old listener is replaced, B's is kept.
        engineA.listen()
        assertEquals(2, backend.listenerCount)

        // A's Dart side stops listening; B still receives.
        engineA.cancel()
        assertEquals(1, backend.listenerCount)
        backend.emit(snoozed(3))
        assertEquals(emptyList<Any?>(), engineA.updates())
        assertEquals(listOf(snoozed(3)), engineB.updates())
    }
}
