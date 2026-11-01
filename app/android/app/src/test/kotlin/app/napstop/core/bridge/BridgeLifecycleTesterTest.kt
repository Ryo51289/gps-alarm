package app.napstop.core.bridge

import app.napstop.core.bridge.BridgeTestData.config
import app.napstop.core.bridge.stub.StubStore
import app.napstop.core.bridge.stub.StubTripBackend
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import java.nio.ByteBuffer
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * Tester additions for T14 (review M1): engine attach/detach orders against the real
 * StubTripBackend, through the generated Pigeon event channel. An engine whose Dart side
 * listens must keep receiving ticks whatever the other engine does.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class BridgeLifecycleTesterTest {
    @get:Rule
    val tmp = TemporaryFolder()

    private companion object {
        const val UPDATES = "dev.flutter.pigeon.napstop.TripEventChannelApi.tripUpdates"
        const val T0 = 1_700_000_000_000L
    }

    /** One engine's messenger: handlers registered on it and what native sent to Dart. */
    private class FakeEngine(val name: String) : BinaryMessenger {
        val handlers = mutableMapOf<String, BinaryMessenger.BinaryMessageHandler>()
        private val sent = mutableListOf<ByteBuffer?>()

        override fun send(channel: String, message: ByteBuffer?) {
            if (channel == UPDATES) sent += message
        }

        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) {
            send(channel, message)
        }

        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) {
            if (handler == null) handlers.remove(channel) else handlers[channel] = handler
        }

        fun listen() = call("listen")

        fun cancel() = call("cancel")

        private fun call(method: String) {
            val message = CoreApiPigeonMethodCodec.encodeMethodCall(MethodCall(method, null))
            message.rewind()
            handlers.getValue(UPDATES).onMessage(message) {}
        }

        fun updates(): List<TripUpdateMsg> =
            sent.map { CoreApiPigeonMethodCodec.decodeEnvelope(it!!.duplicate().apply { rewind() }) as TripUpdateMsg }

        val count get() = sent.size

        override fun toString() = name
    }

    private fun TestScope.stubBackend(dirName: String) =
        StubTripBackend(
            store = StubStore(tmp.newFolder(dirName), warn = {}),
            clock = { T0 + testScheduler.currentTime },
            scope = backgroundScope,
            io = StandardTestDispatcher(testScheduler),
            warn = {},
        )

    /** All 6 interleavings of (A listens < A detaches) and (B listens < B detaches). */
    private val orders =
        listOf(
            "AL BL AU BU",
            "AL BL BU AU",
            "AL AU BL BU",
            "BL AL AU BU",
            "BL AL BU AU",
            "BL BU AL AU",
        )

    private suspend fun TestScope.checkOrder(order: String, detach: String) {
        val backend = stubBackend("o${order.replace(" ", "")}$detach")
        backend.startTrip(config("t1"), 16.8, 107.1, null)
        val a = FakeEngine("A")
        val b = FakeEngine("B")
        val registrations = mapOf(a to BridgeRegistrar.register(a, backend), b to BridgeRegistrar.register(b, backend))
        val listening = mutableSetOf<FakeEngine>()
        for (op in order.split(" ")) {
            val engine = if (op[0] == 'A') a else b
            if (op[1] == 'L') {
                engine.listen()
                listening += engine
            } else {
                // Engine destroyed (cleanUpFlutterEngine) or Dart cancelled its subscription.
                if (detach == "unregister") registrations.getValue(engine).unregister() else engine.cancel()
                listening -= engine
            }
            runCurrent()
            val before = mapOf(a to a.count, b to b.count)
            advanceTimeBy(1_000)
            runCurrent()
            for (e in listOf(a, b)) {
                val got = e.count - before.getValue(e)
                if (e in listening) {
                    assertTrue("$order/$detach after $op: $e listening, got $got", got in 1..2)
                } else {
                    assertEquals("$order/$detach after $op: $e detached", 0, got)
                }
            }
        }
        // Nobody listens: no tick, nothing sent; the trip itself survives in the process.
        val total = a.count + b.count
        advanceTimeBy(5_000)
        runCurrent()
        assertEquals("$order/$detach: silent once nobody listens", total, a.count + b.count)
        assertTrue(a.updates().all { it is TripStateUpdateMsg } && b.updates().all { it is TripStateUpdateMsg })
        assertNotNull(backend.currentTrip())
        registrations.values.forEach { it.unregister() }
    }

    @Test
    fun everyAttachDetachOrderOfTwoEnginesKeepsTheListeningOneTicking() =
        runTest {
            for (order in orders) checkOrder(order, detach = "unregister")
        }

    @Test
    fun everyListenCancelOrderOfTwoEnginesKeepsTheListeningOneTicking() =
        runTest {
            for (order in orders) checkOrder(order, detach = "cancel")
        }

    @Test
    fun activityRecreatedGetsTheReplayImmediately() =
        runTest {
            // "Don't keep activities": every time the app is left the engine is destroyed,
            // reopening creates a new one in the same process.
            val backend = stubBackend("recreate")
            backend.startTrip(config("t1"), 16.8, 107.1, SimulationMsg("stub/normal", 60.0))
            var engine = FakeEngine("A0")
            var registration = BridgeRegistrar.register(engine, backend)
            engine.listen()
            runCurrent()
            for (round in 1..3) {
                registration.unregister()
                advanceTimeBy(4_000) // away from the app; no listener, no tick
                runCurrent()
                engine = FakeEngine("A$round")
                registration = BridgeRegistrar.register(engine, backend)
                engine.listen()
                runCurrent()
                // The replay is one Step computed now: its state first, then only events this
                // very Step produced (round 1: the PreAlert nobody computed while away).
                val replay = engine.updates()
                assertTrue("round $round: replay right away", replay.isNotEmpty())
                val state = (replay.first() as TripStateUpdateMsg).state
                assertEquals(1, replay.count { it is TripStateUpdateMsg })
                assertEquals(T0 + testScheduler.currentTime, state.atMs)
                val afterReplay = engine.count
                advanceTimeBy(1_000)
                runCurrent()
                assertTrue("round $round: ticking again", engine.count > afterReplay)
            }
            // 1 + 3 * 5 s = 16 s at 60x: past the alarm (~12.3 s); the reopened UI sees it.
            val last = (engine.updates().last { it is TripStateUpdateMsg } as TripStateUpdateMsg).state
            assertEquals(TripPhaseMsg.ALARMING, last.phase)
            assertTrue(last.alarmRinging)
            registration.unregister()
        }

    @Test
    fun listenTwiceOnOneEngineIsStillOneListener() =
        runTest {
            val backend = stubBackend("twice")
            backend.startTrip(config("t1"), 16.8, 107.1, null)
            val a = FakeEngine("A")
            val registration = BridgeRegistrar.register(a, backend)
            a.listen()
            a.listen() // hot restart: Dart listens again without a cancel
            runCurrent()
            val before = a.count
            advanceTimeBy(3_000)
            runCurrent()
            assertEquals("one update per tick, not two", 3, a.count - before)
            registration.unregister()
            registration.unregister() // idempotent
            val after = a.count
            advanceTimeBy(3_000)
            runCurrent()
            assertEquals(after, a.count)
        }

    @Test
    fun unregisteringAnEngineThatNeverListenedLeavesTheOtherAlone() =
        runTest {
            val backend = stubBackend("never")
            backend.startTrip(config("t1"), 16.8, 107.1, null)
            val a = FakeEngine("A")
            val b = FakeEngine("B")
            val registrationA = BridgeRegistrar.register(a, backend)
            BridgeRegistrar.register(b, backend).also { b.listen() }
            runCurrent()
            registrationA.unregister()
            registrationA.unregister()
            val before = b.count
            advanceTimeBy(2_000)
            runCurrent()
            assertEquals(2, b.count - before)
            assertEquals(0, a.count)
        }
}
