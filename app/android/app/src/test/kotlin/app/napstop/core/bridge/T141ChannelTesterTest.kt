package app.napstop.core.bridge

import app.napstop.core.bridge.BridgeTestData.config
import app.napstop.core.bridge.stub.StubStore
import app.napstop.core.bridge.stub.StubTripBackend
import io.flutter.plugin.common.BinaryMessenger
import java.io.File
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
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * Tester additions for T14.1 through the real generated Pigeon handlers and codec:
 * V11 on startTrip (validator -> wire error), engineParamsJson verbatim through the stub
 * snapshot and a simulated process death (fresh backend + fresh engine on the same
 * directory), and a snapshot written before T14.1 still loading.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class T141ChannelTesterTest {
    @get:Rule
    val tmp = TemporaryFolder()

    private val t0 = 1_700_000_000_000L
    private var nowMs = t0
    private val warnings = mutableListOf<String>()

    private companion object {
        const val BS = '\\'
    }

    @Before
    fun setUp() {
        // The generated handlers launch on Dispatchers.Main.
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    /** One engine's messenger: Dart -> native calls with the real codec. */
    private class FakeEngine : BinaryMessenger {
        val handlers = mutableMapOf<String, BinaryMessenger.BinaryMessageHandler>()

        override fun send(channel: String, message: ByteBuffer?) = Unit

        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) = Unit

        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) {
            if (handler == null) handlers.remove(channel) else handlers[channel] = handler
        }

        /** Sends [args] to TripHostApi.[method]; returns a slot filled when native replies. */
        fun call(method: String, args: List<Any?>?): () -> List<Any?>? {
            val message = args?.let { TripHostApi.codec.encodeMessage(it)!!.apply { rewind() } }
            var reply: List<Any?>? = null
            handlers.getValue("dev.flutter.pigeon.napstop.TripHostApi.$method").onMessage(message) { bytes ->
                @Suppress("UNCHECKED_CAST")
                reply = TripHostApi.codec.decodeMessage(bytes!!.duplicate().apply { rewind() }) as List<Any?>
            }
            return { reply }
        }
    }

    private fun TestScope.backend() =
        StubTripBackend(
            store = StubStore(tmp.root, warn = { warnings += it }),
            clock = { nowMs },
            scope = backgroundScope,
            io = StandardTestDispatcher(testScheduler),
            warn = { warnings += it },
        )

    private fun TestScope.engine(): FakeEngine = FakeEngine().also { BridgeRegistrar.register(it, backend()) }

    private fun TestScope.startTrip(engine: FakeEngine, cfg: TripConfigMsg): List<Any?> {
        val reply = engine.call("startTrip", listOf(cfg, 16.8163, 107.1003, null))
        runCurrent()
        return reply() ?: error("no reply")
    }

    private fun TestScope.currentTrip(engine: FakeEngine): ActiveTripMsg? {
        val reply = engine.call("currentTrip", null)
        runCurrent()
        val wrapped = reply() ?: error("no reply")
        assertEquals("success envelope", 1, wrapped.size)
        return wrapped.single() as ActiveTripMsg?
    }

    private val activeFile get() = File(tmp.root, StubStore.ACTIVE_FILE)

    /** Exactly [length] UTF-16 code units, with every character Properties escapes. */
    private fun awkwardJson(length: Int): String {
        val head = "{\"note\": \"Ga Đông Hà = a:b #c !d \\\\e\\n\\t 😴\", \"k\": \"\nconfig.tripId=hack\r\n\u0000\", \"pad\": \""
        val tail = "\"}\n"
        return head + "x".repeat(length - head.length - tail.length) + tail
    }

    private val tooLongValues =
        listOf(
            "x".repeat(16_385),
            // 8 192 emoji = 16 384 code units, plus one.
            "😴".repeat(8_192) + "x",
            awkwardJson(16_385),
        )

    @Test
    fun v11_limitIsAcceptedAndKeptVerbatim() =
        runTest {
            val params = awkwardJson(16_384)
            assertEquals(16_384, params.length)
            val engine = engine()
            assertEquals(listOf<Any?>(null), startTrip(engine, config("t1", engineParamsJson = params)))
            assertTrue(activeFile.exists())
            val trip = currentTrip(engine)
            assertNotNull(trip)
            assertEquals(params, trip!!.config.engineParamsJson)
            // The embedded "\nconfig.tripId=hack" did not become a key.
            assertEquals("t1", trip.config.tripId)
        }

    @Test
    fun v11_overTheLimitIsInvalidConfigAndStartsNothing() =
        runTest {
            val engine = engine()
            for (value in tooLongValues) {
                assertEquals(16_385, value.length)
                val reply = startTrip(engine, config("t1", engineParamsJson = value))
                assertEquals(listOf("invalid-config", "engineParamsJson: too long", null), reply)
                assertFalse("no snapshot", activeFile.exists())
                assertNull(currentTrip(engine))
            }
            // UTF-16 count: 8 192 emoji (16 384 code units, 8 192 code points) is accepted.
            assertEquals(listOf<Any?>(null), startTrip(engine, config("t2", engineParamsJson = "😴".repeat(8_192))))
            assertEquals("t2", currentTrip(engine)!!.config.tripId)
            assertTrue(warnings.isEmpty())
        }

    @Test
    fun v11_isReportedBeforeTripActiveAndLeavesTheRunningTripAlone() =
        runTest {
            val engine = engine()
            val params = "{\"smartTargetS\": 300.0}"
            assertEquals(listOf<Any?>(null), startTrip(engine, config("t1", engineParamsJson = params)))
            val before = activeFile.readText()

            val tooLong = startTrip(engine, config("t2", engineParamsJson = "x".repeat(16_385)))
            assertEquals("invalid-config", tooLong[0])
            val atLimit = startTrip(engine, config("t2", engineParamsJson = "x".repeat(16_384)))
            assertEquals("trip-active", atLimit[0])

            assertEquals(before, activeFile.readText())
            val trip = currentTrip(engine)!!
            assertEquals("t1", trip.config.tripId)
            assertEquals(params, trip.config.engineParamsJson)
        }

    @Test
    fun v11_comesAfterV1ToV10OverTheWireToo() =
        runTest {
            val engine = engine()
            val reply = startTrip(engine, config("bad id", engineParamsJson = "x".repeat(16_385)))
            assertEquals(listOf("invalid-config", "tripId: format", null), reply)
        }

    @Test
    fun engineParamsJsonSurvivesProcessDeathByteForByte() =
        runTest {
            val values =
                listOf(
                    awkwardJson(16_384),
                    "",
                    " ",
                    "{\"a\": 60.0}",
                    "\\",
                    "\\u0041 is not unescaped",
                    "#comment-like\n!bang\n",
                    "key = value : other",
                    "\t\r\n\u000c",
                    "ặ ẫ ở ữ đ Ư " + listOf(0x00a0, 0x2028, 0x2029, 0xfeff).map { it.toChar() }.joinToString(""),
                )
            for ((i, value) in values.withIndex()) {
                val tripId = "t$i"
                assertEquals(listOf<Any?>(null), startTrip(engine(), config(tripId, engineParamsJson = value)))

                // "New process": fresh backend + fresh engine on the same directory.
                nowMs += 1_000
                val revived = engine()
                val trip = currentTrip(revived)
                assertNotNull("value #$i", trip)
                assertEquals("value #$i", value, trip!!.config.engineParamsJson)
                assertEquals(config(tripId, engineParamsJson = value), trip.config)

                assertEquals(listOf<Any?>(null), revived.call("stopTrip", listOf(tripId)).also { runCurrent() }())
            }
            assertTrue(warnings.isEmpty())
        }

    @Test
    fun nullAndEmptyStayDistinctAfterProcessDeath() =
        runTest {
            startTrip(engine(), config("t1", engineParamsJson = null))
            assertFalse(activeFile.readText().contains("engineParamsJson"))
            assertNull(currentTrip(engine())!!.config.engineParamsJson)
            engine().call("stopTrip", listOf("t1")).also { runCurrent() }

            startTrip(engine(), config("t2", engineParamsJson = ""))
            assertTrue(activeFile.readText().contains("config.engineParamsJson="))
            assertEquals("", currentTrip(engine())!!.config.engineParamsJson)
        }

    /** "Ga Đông Hà" as Properties.store escapes it (ASCII only on disk). */
    private val NAME_ESCAPED = "Ga " + BS + "u0110" + BS + "u00f4ng H" + BS + "u00e0"

    /** Key set StubStore wrote before T14.1 (commit caa56a4), with a trip running. */
    private val preT141Snapshot =
        """
        #Mon Oct 26 10:00:00 ICT 2026
        version=1
        config.tripId=old1
        config.destinationName=@NAME@
        config.mode=DISTANCE
        config.distanceThresholdM=1000
        config.preAlertEnabled=true
        config.vehicleHint=TRAIN
        config.alarm.soundId=default
        config.alarm.volume=0.8
        config.alarm.rampUp=true
        config.alarm.vibration=MEDIUM
        config.alarm.flash=false
        config.alarm.preferHeadphones=true
        config.alarm.dismissMethod=SWIPE
        scenario=NORMAL
        speedFactor=1.0
        simulated=false
        startedAtMs=1700000000000
        nowMs=1700000000000
        phase=ACQUIRING
        gps=NO_FIX_YET
        preAlertFired=false
        arrivedFired=false
        lowBatteryEmitted=false
        neverAcquiredEmitted=false
        ringing=false
        snoozeCount=0
        overshot=false
        """.trimIndent().replace("@NAME@", NAME_ESCAPED) + "\n"

    @Test
    fun snapshotWrittenBeforeT141StillLoads() =
        runTest {
            activeFile.writeText(preT141Snapshot)
            nowMs = t0 + 1_000
            val engine = engine()
            val trip = currentTrip(engine)
            assertNotNull(trip)
            trip!!
            assertEquals("old1", trip.config.tripId)
            assertEquals("Ga Đông Hà", trip.config.destinationName)
            assertEquals(AlarmModeMsg.DISTANCE, trip.config.mode)
            assertEquals(1_000L, trip.config.distanceThresholdM)
            assertNull(trip.config.engineParamsJson)
            assertNull(trip.simulation)
            assertTrue(warnings.isEmpty())

            // The trip keeps working: a command rewrites the snapshot, still without the key.
            assertEquals(
                listOf<Any?>(null),
                engine.call("setBatteryChoice", listOf("old1", BatteryChoiceMsg.MAX_SAVING)).also { runCurrent() }(),
            )
            assertTrue(activeFile.exists())
            assertFalse(activeFile.readText().contains("engineParamsJson"))
            assertNull(currentTrip(engine())!!.config.engineParamsJson)

            // A trip started now with params writes the new key; the old trip is gone first.
            engine.call("stopTrip", listOf("old1")).also { runCurrent() }
            startTrip(engine, config("new1", engineParamsJson = "{}"))
            assertEquals("{}", currentTrip(engine())!!.config.engineParamsJson)
        }

    @Test
    fun snapshotKeysWithoutParamsAreExactlyThePreT141Ones() =
        runTest {
            // Same input as the literal above (default alarm, DISTANCE 1000, no simulation).
            startTrip(engine(), config("old1", mode = AlarmModeMsg.DISTANCE, distanceThresholdM = 1_000))
            fun keys(text: String) =
                text.lines().filter { it.isNotBlank() && !it.startsWith("#") }.map { it.substringBefore('=') }.toSet()
            assertEquals(keys(preT141Snapshot), keys(activeFile.readText()))
        }
}
