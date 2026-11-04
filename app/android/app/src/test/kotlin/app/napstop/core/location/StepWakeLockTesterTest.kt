package app.napstop.core.location

import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Tester T15 (outside the spec list): StepWakeLock under concurrency (review T15 #4, R2-5). A leaked count keeps the
 * CPU awake (battery); a lost count releases the lock while a fix is still in flight. The failure branches (acquire /
 * release throwing) log through android.util.Log and cannot run in a plain JVM unit test (test hook: inject `warn`).
 */
class StepWakeLockTesterTest {
    @Test
    fun oneDoneCalledFromManyThreadsCountsOnce() {
        val released = AtomicInteger()
        val lock = StepWakeLock(acquire = {}, release = { released.incrementAndGet() }, capMs = 5_000)
        val keep = lock.begin() // another fix still in flight
        val done = lock.begin()
        val start = CountDownLatch(1)
        val threads = List(16) { Thread { start.await(); done() } }
        threads.forEach { it.start() }
        start.countDown()
        threads.forEach { it.join() }
        assertEquals("the other fix still holds the lock", 1, lock.inFlight)
        assertEquals(0, released.get())
        keep()
        assertEquals(1, released.get())
        assertEquals(0, lock.inFlight)
    }

    @Test
    fun batchOfFixesAcrossThreadsReleasesExactlyWhenTheLastIsDone() {
        // FLP batch on napstop-loc (begin) while the actor (done) finishes earlier fixes on other threads.
        val held = AtomicInteger(0) // 1 = held
        val violations = AtomicInteger()
        val lock = StepWakeLock(acquire = { held.set(1) }, release = { held.set(0) }, capMs = 5_000)
        val dones = java.util.concurrent.ConcurrentLinkedQueue<() -> Unit>()
        val producer =
            Thread {
                repeat(5_000) {
                    val d = lock.begin()
                    if (held.get() != 1) violations.incrementAndGet() // the fix just begun is not done yet
                    dones += d
                }
            }
        val consumers =
            List(4) {
                Thread {
                    var n = 0
                    while (n < 1_250) {
                        val d = dones.poll() ?: continue
                        d()
                        n++
                    }
                }
            }
        producer.start()
        consumers.forEach { it.start() }
        producer.join()
        consumers.forEach { it.join() }
        assertEquals(0, violations.get())
        assertEquals(0, lock.inFlight)
        assertEquals(0, held.get())
    }
}
