package app.napstop.core.alarm

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** T27 K01 (slot, TTL), K02 (parse, privacy of toString), K04/K05 (replayed or stale intents, review T27 #1). */
class LaunchActionsTest {
    private var now = 1_000_000L
    private val original = LaunchActions.elapsed

    @Before
    fun setUp() {
        LaunchActions.elapsed = { now }
        LaunchActions.consume()
    }

    @After
    fun tearDown() {
        LaunchActions.consume()
        LaunchActions.elapsed = original
    }

    private fun action(trip: String = "t-1", pastM: Int? = 1200) = LaunchActions.parse(LaunchActions.OVERSHOOT_ROUTE, trip, pastM)!!

    @Test
    fun k01_consumedOnceExpiresAfterTtlLastWins() {
        assertNull(LaunchActions.consume())

        LaunchActions.set(action())
        now += 5_000
        val a = LaunchActions.consume()
        assertNotNull(a)
        assertEquals("t-1", a!!.tripId)
        assertEquals(1200, a.pastM)
        assertNull("taken once", LaunchActions.consume())

        LaunchActions.set(action())
        now += LaunchActions.TTL_MS
        assertNotNull("exactly 10 min is still valid", LaunchActions.consume())

        LaunchActions.set(action())
        now += 600_001
        assertNull("expired", LaunchActions.consume())
        assertNull("an expired action is cleared too", LaunchActions.consume())

        LaunchActions.set(action(trip = "t-1"))
        now += 10
        LaunchActions.set(action(trip = "t-2", pastM = null))
        val last = LaunchActions.consume()!!
        assertEquals("t-2", last.tripId)
        assertNull(last.pastM)
        assertNull(LaunchActions.consume())

        // The age counts from set(), whatever the action carried.
        LaunchActions.set(action().copy(atElapsedMs = 0L))
        assertNotNull(LaunchActions.consume())

        // A clock that went backwards (should not happen with elapsedRealtime): dropped.
        LaunchActions.set(action())
        now -= 1
        assertNull(LaunchActions.consume())
    }

    @Test
    fun k02_parse() {
        val ok = LaunchActions.parse("overshootRoute", "t-1", 1200)!!
        assertEquals(LaunchActions.OVERSHOOT_ROUTE, ok.action)
        assertEquals("t-1", ok.tripId)
        assertEquals(1200, ok.pastM)

        assertNull(LaunchActions.parse("x", "t-1", 1))
        assertNull(LaunchActions.parse(null, "t-1", 1))
        assertNull(LaunchActions.parse("overshootRoute", "a b", 1))
        assertNull(LaunchActions.parse("overshootRoute", "a/b", 1))
        assertNull(LaunchActions.parse("overshootRoute", "", 1))
        assertNull(LaunchActions.parse("overshootRoute", null, 1))
        assertNull(LaunchActions.parse("overshootRoute", "x".repeat(65), 1))

        assertNull(LaunchActions.parse("overshootRoute", "t-1", -1)!!.pastM)
        assertNull(LaunchActions.parse("overshootRoute", "t-1", 2_000_000)!!.pastM)
        assertNull(LaunchActions.parse("overshootRoute", "t-1", null)!!.pastM)
        assertEquals(0, LaunchActions.parse("overshootRoute", "t-1", 0)!!.pastM)
        assertEquals(1_000_000, LaunchActions.parse("overshootRoute", "t-1", 1_000_000)!!.pastM)

        val text = LaunchActions.parse("overshootRoute", "trip123", 1200).toString()
        assertFalse(text, text.contains("1200"))
        assertFalse(text, text.contains("trip123"))
        assertFalse(text, Regex("\\d").containsMatchIn(text))
    }

    /** Review T27 #1, layer 1: an intent given back by the system (activity restored, launched from Recents) is ignored. */
    @Test
    fun k04_replayedTaskIntentIsIgnored() {
        val now = 1_800_000_000_000L
        fun gate(restored: Boolean, flags: Int) =
            LaunchActions.fromIntent("overshootRoute", "t-1", 900, now - 1_000, now, restored = restored, intentFlags = flags)

        assertEquals(android.content.Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY, LaunchActions.FLAG_LAUNCHED_FROM_HISTORY)
        assertNotNull("a fresh intent", gate(restored = false, flags = 0x10000000))
        assertNull("process death: savedInstanceState != null", gate(restored = true, flags = 0))
        assertNull("from Recents", gate(restored = false, flags = LaunchActions.FLAG_LAUNCHED_FROM_HISTORY or 0x10000000))
        assertTrue(LaunchActions.isReplay(restored = true, intentFlags = 0))
        assertFalse(LaunchActions.isReplay(restored = false, intentFlags = 0x10000000))
    }

    /** Review T27 #1, layer 2: the tap time must be present and at most 10 min old (wall clock). */
    @Test
    fun k05_tapTimeMustBeRecent() {
        val now = 1_800_000_000_000L
        fun gate(at: Long?) = LaunchActions.fromIntent("overshootRoute", "t-1", 900, at, now, restored = false, intentFlags = 0)

        assertEquals(900, gate(now)!!.pastM)
        assertNotNull(gate(now - LaunchActions.TTL_MS))
        assertNull("older than 10 min (e.g. the task intent hours later)", gate(now - LaunchActions.TTL_MS - 1))
        assertNull("hours later", gate(now - 3 * 3_600_000L))
        assertNull("no tap time (old build, hand-made intent)", gate(null))
        assertNull("in the future", gate(now + 1))
        // The other checks of parse still apply.
        assertNull(LaunchActions.fromIntent("x", "t-1", 900, now, now, restored = false, intentFlags = 0))
        assertNull(LaunchActions.fromIntent("overshootRoute", "a/b", 900, now, now, restored = false, intentFlags = 0))
    }
}
