package app.napstop.core.alarm

import app.napstop.core.alarm.AlarmData.record
import java.util.Properties
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** T16 A08 (codec), A09 (liveness), A10 (watchdog policy). */
class RingFactsTest {
    private val c = AlarmConstants()
    private val wall0 = 1_700_000_000_000L
    private val el0 = 5_000_000L

    private fun env(dtMs: Long = 0, boot: Int? = 7, backup: Boolean = false) = LivenessEnv(wall0 + dtMs, el0 + dtMs, boot, backup)

    @Test
    fun a08_codecRoundTripAndRejects() {
        val full =
            record(pendingDismiss = 1L, snoozedAt = 2L, silencedAt = 3L, endedBy = RingEnd.SNOOZED, stopSeq = 99L, restarts = 2, mode = RingMode.BACKUP)
        assertEquals(full, RingFactsCodec.decode(RingFactsCodec.encode(full)))
        val bare = record(heartbeatElapsed = null, heartbeatWall = null, bootCount = null)
        val back = RingFactsCodec.decode(RingFactsCodec.encode(bare))!!
        assertEquals(bare, back)
        assertNull(back.heartbeatElapsedMs)
        assertNull(back.stopSeq)
        assertNull(back.endedBy)

        // Broken number, other version, interim T15 file (no version), bad trip id.
        val broken = RingFactsCodec.encode(full).apply { setProperty("ringSeq", "x") }
        assertNull(RingFactsCodec.decode(broken))
        val brokenOpt = RingFactsCodec.encode(full).apply { setProperty("stopSeq", "abc") }
        assertNull(RingFactsCodec.decode(brokenOpt))
        assertNull(RingFactsCodec.decode(RingFactsCodec.encode(full).apply { setProperty("version", "2") }))
        val interim = Properties().apply {
            setProperty("ringing", "true")
            setProperty("source", "ENGINE")
            setProperty("startedAtWallMs", "123")
        }
        assertNull(RingFactsCodec.decode(interim))
        assertNull(RingFactsCodec.decode(RingFactsCodec.encode(full).apply { setProperty("tripId", "../x") }))
        assertNull(RingFactsCodec.decode(RingFactsCodec.encode(full).apply { setProperty("mode", "LOUD") }))
    }

    @Test
    fun a09_liveness() {
        // (a) no record
        assertFalse(RingLiveness.facts(null, null, env(), c).ringingNow)
        // (b) heartbeat 1 s ago
        val r = record(heartbeatElapsed = el0, heartbeatWall = wall0)
        val b = RingLiveness.facts(r, null, env(1_000), c)
        assertTrue(b.ringingNow)
        assertEquals(RingSource.ENGINE, b.ringingSource)
        // (c) 7 s ago: dead, silencedAt = last heartbeat
        val cc = RingLiveness.facts(r, null, env(7_000), c)
        assertFalse(cc.ringingNow)
        assertEquals(wall0, cc.silencedAtWallMs)
        assertEquals(wall0, cc.ringStartedAtWallMs) // G3 needs it after the ring stopped
        // (d) other boot
        assertFalse(RingLiveness.facts(r, null, env(1_000, boot = 8), c).ringingNow)
        // (e) stuck beyond RING_MAX + grace
        val stuck = record(heartbeatElapsed = el0 + c.ringMaxMs + 61_000)
        assertFalse(RingLiveness.facts(stuck, null, env(c.ringMaxMs + 61_000), c).ringingNow)
        // (f) backup follows the notification
        val bk = record(mode = RingMode.BACKUP, heartbeatElapsed = null)
        assertTrue(RingLiveness.facts(bk, null, env(30_000, backup = true), c).ringingNow)
        assertFalse(RingLiveness.facts(bk, null, env(30_000, backup = false), c).ringingNow)
        // (g) STARTING 1 s, no record
        val st = StartingMarker(AlarmData.TRIP, 200L, RingSource.FALLBACK, el0, wall0)
        val g = RingLiveness.facts(null, st, env(1_000), c)
        assertTrue(g.ringingNow)
        assertEquals(RingSource.FALLBACK, g.ringingSource)
        assertEquals(wall0, g.ringStartedAtWallMs)
        // (h) STARTING 4 s
        assertFalse(RingLiveness.facts(null, st, env(4_000), c).ringingNow)
        // (i) stop overtook the start
        val stopped = record(ringing = false, ringSeq = 50, stopSeq = 200)
        assertFalse(RingLiveness.facts(stopped, st, env(1_000), c).ringingNow)
        // (j) no boot count, elapsed went back
        val j = record(heartbeatElapsed = el0 + 5_000, bootCount = null)
        assertFalse(RingLiveness.facts(j, null, env(0, boot = null), c).ringingNow)
        // (k) pending dismiss carried
        val k = record(ringing = false, pendingDismiss = wall0 + 9)
        assertEquals(wall0 + 9, RingLiveness.facts(k, null, env(), c).pendingDismissAtWallMs)
        // pending snooze carried (T15 G1)
        assertEquals(wall0 + 5, RingLiveness.facts(record(ringing = false, snoozedAt = wall0 + 5), null, env(), c).pendingSnoozeAtWallMs)
    }

    @Test
    fun a10_watchdogPolicy() {
        val st = StartingMarker(AlarmData.TRIP, 200L, RingSource.ENGINE, el0, wall0)
        assertEquals(WatchAction.None, RingWatchdogPolicy.decide(null, st, env(2_000), c))
        assertEquals(WatchAction.Restart(1), RingWatchdogPolicy.decide(null, st, env(3_500), c))
        assertEquals(WatchAction.Backup, RingWatchdogPolicy.decide(record(ringSeq = 10, ringing = false, restarts = 2), st, env(3_500), c))
        // Confirmed and alive.
        val alive = record(ringSeq = 200, heartbeatElapsed = el0 + 18_000)
        assertEquals(WatchAction.None, RingWatchdogPolicy.decide(alive, st, env(19_000), c))
        // Dead at 20 s (heartbeat stopped at 13 s).
        for ((n, want) in listOf(0 to WatchAction.Restart(1), 1 to WatchAction.Restart(2), 2 to WatchAction.Backup)) {
            val dead = record(ringSeq = 200, heartbeatElapsed = el0 + 13_000, restarts = n)
            assertEquals(want, RingWatchdogPolicy.decide(dead, null, env(20_000), c))
        }
        // Dead after RING_MAX.
        val late = record(heartbeatElapsed = el0 + c.ringMaxMs - 10_000)
        assertEquals(WatchAction.Silence(wall0 + c.ringMaxMs), RingWatchdogPolicy.decide(late, null, env(c.ringMaxMs + 1_000), c))
        // Backup notification gone.
        val bk = record(mode = RingMode.BACKUP, heartbeatElapsed = null)
        assertEquals(WatchAction.Silence(wall0 + 30_000), RingWatchdogPolicy.decide(bk, null, env(30_000, backup = false), c))
        assertEquals(WatchAction.StopWatching, RingWatchdogPolicy.decide(record(pendingDismiss = wall0), null, env(1_000), c))
        assertEquals(WatchAction.StopWatching, RingWatchdogPolicy.decide(record(ringing = false), null, env(1_000), c))
        assertEquals(WatchAction.StopWatching, RingWatchdogPolicy.decide(record(ringing = false, ringSeq = 1, stopSeq = 200), st, env(1_000), c))
    }

    /** Review T16 #1: seqs of another boot never compare with this boot's. */
    @Test
    fun bookOfAnotherBootLosesItsSeqs() {
        val old = record(ringSeq = 900_000_000_000_000L, stopSeq = 900_000_000_000_000L, ringing = false, snoozedAt = 5L, bootCount = 1)
        val now = 5_000_000_000_000L
        val s = RingBoot.sanitize(old, 7, now)!!
        assertEquals(Long.MIN_VALUE, s.ringSeq)
        assertNull(s.stopSeq)
        assertEquals(5L, s.snoozedAtWallMs, "user facts stay")
        assertEquals(7, s.bootCount)
        // Same boot count unknown, but a seq later than "now" cannot be of this boot.
        assertNull(RingBoot.sanitize(old.copy(bootCount = null), null, now)!!.stopSeq)
        assertNull(RingBoot.sanitize(old.copy(bootCount = null), 7, now)!!.stopSeq)
        // This boot: untouched.
        val mine = record(ringSeq = 10L, stopSeq = 20L)
        assertEquals(mine, RingBoot.sanitize(mine, 7, now))
        assertNull(RingBoot.sanitize(null, 7, now))
        // A live-looking record of another boot is not ringing.
        assertFalse(RingBoot.sanitize(record(bootCount = 1), 7, now)!!.ringing)
    }
}
