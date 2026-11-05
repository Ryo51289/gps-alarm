package app.napstop.core.bridge

import app.napstop.core.alarm.LaunchActions
import app.napstop.core.alarm.SoundPreview
import io.flutter.plugin.common.BinaryMessenger
import java.nio.ByteBuffer
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** T16 AA1 (errors over the real Pigeon channel), AA3 (preview rules); T28 K03 (setAppLocale); T27 K03 (launch action, native alarm screen). */
@OptIn(ExperimentalCoroutinesApi::class)
class AlarmHostApiImplTest {
    private class FakePreview : SoundPreview {
        val plays = ArrayList<Triple<String, Float, Long>>()
        var stops = 0
        var throwOnPlay: Throwable? = null

        override fun play(soundId: String, volume: Float, maxMs: Long) {
            throwOnPlay?.let { throw it }
            plays += Triple(soundId, volume, maxMs)
        }

        override fun stop() {
            stops++
        }
    }

    private class FakeEngine : BinaryMessenger {
        val handlers = mutableMapOf<String, BinaryMessenger.BinaryMessageHandler>()

        override fun send(channel: String, message: ByteBuffer?) = Unit

        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) = Unit

        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) {
            if (handler == null) handlers.remove(channel) else handlers[channel] = handler
        }

        fun call(method: String, args: List<Any?>?): List<Any?>? {
            val message = args?.let { AlarmHostApi.codec.encodeMessage(it)!!.apply { rewind() } }
            var reply: List<Any?>? = null
            handlers.getValue("dev.flutter.pigeon.napstop.AlarmHostApi.$method").onMessage(message) { bytes ->
                @Suppress("UNCHECKED_CAST")
                reply = AlarmHostApi.codec.decodeMessage(bytes!!.duplicate().apply { rewind() }) as List<Any?>
            }
            return reply
        }
    }

    @Test
    fun aa1_errorsAreInternalWithTheClassNameOnly() {
        val p = FakePreview().apply { throwOnPlay = IllegalStateException("Ga Đồng Hới 21.0") }
        val api = AlarmHostApiImpl(p, ringActive = { false })
        val e = runCatching { api.previewSound("bell", 0.5) }.exceptionOrNull() as FlutterError
        assertEquals("internal", e.code)
        assertEquals("IllegalStateException", e.message)
        p.throwOnPlay = CancellationException("x")
        val c = runCatching { api.previewSound("bell", 0.5) }.exceptionOrNull() as FlutterError
        assertEquals("internal", c.code)
        assertEquals("CancellationException", c.message)

        // Through the generated handler and codec.
        val engine = FakeEngine()
        AlarmHostApi.setUp(engine, AlarmHostApiImpl(FakePreview().apply { throwOnPlay = IllegalStateException("Ga Đồng Hới 21.0") }, { false }))
        val reply = engine.call("previewSound", listOf("bell", 0.5))!!
        val text = reply.toString()
        assertEquals(listOf("internal", "IllegalStateException", null), reply)
        for (bad in listOf("Stacktrace", "21.0", "Ga", "Cause")) assertFalse(text, text.contains(bad))
        assertEquals(listOf(null), engine.call("stopPreview", null))
    }

    @Test
    fun aa3_previewRules() {
        val p = FakePreview()
        var ringing = true
        val api = AlarmHostApiImpl(p, ringActive = { ringing }, previewMaxMs = 10_000)
        api.previewSound("bell", 0.5)
        assertTrue("no preview over a ring", p.plays.isEmpty())
        ringing = false
        api.previewSound("bell", Double.NaN)
        assertEquals(Triple("bell", 1.0f, 10_000L), p.plays.last())
        api.previewSound("beep", -1.0)
        assertEquals(1, p.stops) // −1 → 0 → stop
        api.previewSound("beep", 2.0)
        assertEquals(1.0f, p.plays.last().second)
        api.previewSound("../x", 0.3)
        assertEquals("horn", p.plays.last().first)
        api.previewSound("bell", 0.0)
        assertEquals(2, p.stops)
        api.stopPreview()
        assertEquals(3, p.stops)
    }

    @Test
    fun k03_setAppLocaleParsesThenStores() {
        val stored = ArrayList<String?>()
        val api = AlarmHostApiImpl(FakePreview(), ringActive = { false }, setLocale = { stored += it })
        api.setAppLocale("en")
        api.setAppLocale("xx")
        api.setAppLocale(null)
        api.setAppLocale(" vi ")
        assertEquals(listOf("en", null, null, "vi"), stored)

        val failing = AlarmHostApiImpl(FakePreview(), ringActive = { false }, setLocale = { throw IllegalStateException("/data/x en") })
        val e = runCatching { failing.setAppLocale("en") }.exceptionOrNull() as FlutterError
        assertEquals("internal", e.code)
        assertEquals("IllegalStateException", e.message)

        // Through the generated handler and codec.
        val engine = FakeEngine()
        AlarmHostApi.setUp(engine, AlarmHostApiImpl(FakePreview(), ringActive = { false }, setLocale = { stored += it }))
        assertEquals(listOf(null), engine.call("setAppLocale", listOf("en")))
        assertEquals(listOf(null), engine.call("setAppLocale", listOf(null)))
        assertEquals(listOf("en", null, null, "vi", "en", null), stored)
        // The default (JVM registrar) does nothing and never throws.
        AlarmHostApiImpl(FakePreview(), ringActive = { false }).setAppLocale("en")
    }

    @Test
    fun k03_launchActionAndShowAlarmScreen() =
        runTest {
            var slot: LaunchActions.Action? = LaunchActions.parse(LaunchActions.OVERSHOOT_ROUTE, "t-1", 1200)
            val shown = ArrayList<String>()
            var answer: () -> Boolean = { true }
            val api =
                AlarmHostApiImpl(
                    FakePreview(),
                    ringActive = { false },
                    consumeLaunch = { slot.also { slot = null } },
                    showAlarm = { id ->
                        shown += id
                        answer()
                    },
                )
            assertEquals(LaunchActionMsg(LaunchActionKindMsg.OVERSHOOT_ROUTE, "t-1", 1200L), api.consumeLaunchAction())
            assertNull(api.consumeLaunchAction())
            slot = LaunchActions.parse(LaunchActions.OVERSHOOT_ROUTE, "t-2", null)
            assertEquals(LaunchActionMsg(LaunchActionKindMsg.OVERSHOOT_ROUTE, "t-2", null), api.consumeLaunchAction())

            assertTrue(api.showAlarmScreen("t-1"))
            answer = { false }
            assertFalse(api.showAlarmScreen("t-1"))
            answer = { throw IllegalStateException("Ga Đồng Hới") }
            assertFalse("a throwing start is false, not a Pigeon error", api.showAlarmScreen("t-1"))
            assertFalse(api.showAlarmScreen("bad/id"))
            assertFalse(api.showAlarmScreen(""))
            assertEquals("an invalid id never reaches showAlarm", listOf("t-1", "t-1", "t-1"), shown)

            // Defaults (registrar JVM tests): nothing.
            val bare = AlarmHostApiImpl(FakePreview(), ringActive = { false })
            assertNull(bare.consumeLaunchAction())
            assertFalse(bare.showAlarmScreen("t-1"))

            // A failing slot read: `internal` + class name only.
            val broken = AlarmHostApiImpl(FakePreview(), ringActive = { false }, consumeLaunch = { throw IllegalStateException("t-1 1200") })
            val e = runCatching { broken.consumeLaunchAction() }.exceptionOrNull() as FlutterError
            assertEquals("internal", e.code)
            assertEquals("IllegalStateException", e.message)
        }

    @Test
    fun k03_throughTheGeneratedHandlers() {
        Dispatchers.setMain(UnconfinedTestDispatcher())
        try {
            val engine = FakeEngine()
            var slot: LaunchActions.Action? = LaunchActions.parse(LaunchActions.OVERSHOOT_ROUTE, "t-1", 1500)
            AlarmHostApi.setUp(
                engine,
                AlarmHostApiImpl(
                    FakePreview(),
                    ringActive = { false },
                    consumeLaunch = { slot.also { slot = null } },
                    showAlarm = { throw IllegalStateException("Ga Đồng Hới 21.0") },
                ),
            )
            assertEquals(listOf(LaunchActionMsg(LaunchActionKindMsg.OVERSHOOT_ROUTE, "t-1", 1500L)), engine.call("consumeLaunchAction", null))
            assertEquals(listOf(null), engine.call("consumeLaunchAction", null))
            val reply = engine.call("showAlarmScreen", listOf("t-1"))!!
            assertEquals(listOf(false), reply)
            assertEquals(listOf(false), engine.call("showAlarmScreen", listOf("bad/id")))
        } finally {
            Dispatchers.resetMain()
        }
    }
}
