package app.napstop.core.alarm

import app.napstop.core.trip.AlarmReason
import java.nio.file.Files
import kotlin.concurrent.thread
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** T16 AA4: the ring book on disk — no lost update under the lock, always readable. */
class RingFactsStoreTest {
    private fun record(seq: Long = 1L, restarts: Int = 0) =
        RingFactsRecord(
            tripId = "t1", ringSeq = seq, ringing = true, mode = RingMode.SERVICE, source = RingSource.ENGINE, reason = AlarmReason.DISTANCE,
            startedAtWallMs = 1L, heartbeatElapsedMs = 2L, heartbeatWallMs = 3L, bootCount = 4, pendingDismissAtWallMs = null,
            snoozedAtWallMs = null, silencedAtWallMs = null, endedBy = null, stopSeq = null, restarts = restarts,
        )

    @Test
    fun aa4_concurrentUpdatesAreNeverLost() {
        val dir = Files.createTempDirectory("ringbook").toFile()
        val a = RingFactsStore(dir, syncWrites = false)
        val b = RingFactsStore(dir, syncWrites = false) // a second instance, as the other process would have
        a.update("t1") { record() }
        var unreadable = 0
        val threads =
            listOf(a, b).map { s ->
                thread {
                    repeat(500) {
                        s.update("t1") { r -> r!!.copy(restarts = r.restarts + 1) }
                        if (s.read("t1") == null) unreadable++
                    }
                }
            }
        threads.forEach { it.join() }
        assertEquals(1_000, a.read("t1")!!.restarts)
        assertEquals(0, unreadable)
        dir.deleteRecursively()
    }

    @Test
    fun readListDeleteAndBadFiles() {
        val dir = Files.createTempDirectory("ringbook").toFile()
        val s = RingFactsStore(dir)
        assertNull(s.read("t1"))
        s.update("t1") { record(seq = 5) }
        s.update("t2") { record(seq = 6).copy(tripId = "t2", ringing = false) }
        assertEquals(5L, s.read("t1")!!.ringSeq)
        assertEquals(listOf("t1"), s.listRinging().map { it.tripId })
        // The T15 interim file (no version) reads as "no ring".
        dir.resolve("t3.properties").writeText("ringing=true\nsource=ENGINE\nstartedAtWallMs=1\n")
        assertNull(s.read("t3"))
        dir.resolve("t4.properties").writeText("garbage")
        assertNull(s.read("t4"))
        s.update("t1") { null }
        assertNull(s.read("t1"))
        s.delete("t2")
        assertTrue(s.listRinging().isEmpty())
        assertTrue(runCatching { s.read("../x") }.isFailure)
        dir.deleteRecursively()
    }
}
