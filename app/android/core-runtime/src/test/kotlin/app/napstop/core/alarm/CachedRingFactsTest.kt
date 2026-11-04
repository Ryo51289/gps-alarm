package app.napstop.core.alarm

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** TASKS T16 / test report T15 O2: ringFacts never waits on the disk longer than the read budget. */
class CachedRingFactsTest {
    private var now = 0L
    private val warnings = ArrayList<String>()

    @Test
    fun freshReadsComeFromMemoryOlderOnesFromTheDisk() {
        val disk = MemoryFacts()
        val io = Executors.newSingleThreadExecutor()
        val c = CachedRingFacts(disk, io, { now }, { warnings += it })
        disk.records[AlarmData.TRIP] = AlarmData.record()
        assertEquals(AlarmData.record(), c.read(AlarmData.TRIP))
        val reads = disk.reads
        now += 500
        c.read(AlarmData.TRIP)
        assertEquals(reads, disk.reads, "fresh: memory")
        disk.records[AlarmData.TRIP] = AlarmData.record(ringing = false)
        now += 1_000
        assertEquals(false, c.read(AlarmData.TRIP)!!.ringing, "older than freshMs: disk")
        c.invalidate(AlarmData.TRIP)
        disk.records[AlarmData.TRIP] = AlarmData.record(ringSeq = 7)
        assertEquals(7L, c.read(AlarmData.TRIP)!!.ringSeq)
        io.shutdownNow()
    }

    @Test
    fun aHungDiskNeverHoldsTheCaller() {
        val gate = CountDownLatch(1)
        val disk =
            object : RingFactsSource by MemoryFacts() {
                override fun read(tripId: String): RingFactsRecord? {
                    gate.await(5, TimeUnit.SECONDS)
                    return AlarmData.record()
                }
            }
        val io = Executors.newSingleThreadExecutor()
        val c = CachedRingFacts(disk, io, { now }, { warnings += it }, readBudgetMs = 100)
        val t0 = System.nanoTime()
        assertNull(c.read(AlarmData.TRIP))
        assertTrue((System.nanoTime() - t0) / 1_000_000 < 1_000)
        assertTrue(warnings.any { it.contains("over budget") })
        gate.countDown()
        c.flush()
        assertEquals(AlarmData.record(), c.read(AlarmData.TRIP), "the late read filled the cache")
        io.shutdownNow()
    }

    @Test
    fun writesAreSeenAtOnceAndLandInOrder() {
        val disk = MemoryFacts()
        val io = Executors.newSingleThreadExecutor()
        val c = CachedRingFacts(disk, io, { now }, { warnings += it })
        c.update(AlarmData.TRIP) { AlarmData.record(ringSeq = 1) }
        c.update(AlarmData.TRIP) { it?.copy(ringSeq = it.ringSeq + 1) }
        assertEquals(2L, c.read(AlarmData.TRIP)!!.ringSeq)
        c.flush()
        assertEquals(2L, disk.records[AlarmData.TRIP]!!.ringSeq)
        c.delete(AlarmData.TRIP)
        assertNull(c.read(AlarmData.TRIP))
        c.flush()
        assertNull(disk.records[AlarmData.TRIP])
        io.shutdownNow()
    }

    /** Review T16 #7: a hung disk gets one read per trip, however often the actor asks. */
    @Test
    fun readsOfAHungDiskAreShared() {
        val gate = CountDownLatch(1)
        var diskReads = 0
        val disk =
            object : RingFactsSource by MemoryFacts() {
                override fun read(tripId: String): RingFactsRecord? {
                    diskReads++
                    gate.await(5, TimeUnit.SECONDS)
                    return null
                }
            }
        val io = Executors.newSingleThreadExecutor()
        val c = CachedRingFacts(disk, io, { now }, { warnings += it }, readBudgetMs = 20)
        repeat(5) { c.read(AlarmData.TRIP) }
        gate.countDown()
        c.flush()
        assertEquals(1, diskReads)
        io.shutdownNow()
    }
}
