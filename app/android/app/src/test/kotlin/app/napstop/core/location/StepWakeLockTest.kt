package app.napstop.core.location

import org.junit.Assert.assertEquals
import org.junit.Test

/** Review T15 #4: the per-fix wake lock is released as soon as the Steps in flight are done (5 s is only the cap). */
class StepWakeLockTest {
    @Test
    fun releasedWhenEveryFixInFlightIsDone() {
        val acquired = mutableListOf<Long>()
        var released = 0
        val lock = StepWakeLock(acquire = { acquired += it }, release = { released++ }, capMs = 5_000)
        val a = lock.begin()
        val b = lock.begin()
        assertEquals(listOf(5_000L, 5_000L), acquired)
        a()
        assertEquals("one fix still in flight", 0, released)
        a()
        assertEquals("done is idempotent", 0, released)
        b()
        assertEquals(1, released)
        assertEquals(0, lock.inFlight)
        lock.begin()()
        assertEquals(2, released)
    }

    @Test
    fun aFixInFlightAlwaysHoldsTheLock() {
        // Review T15 R2-5: a done() racing a begin() must never release the lock of the fix that just began.
        val held = java.util.concurrent.atomic.AtomicBoolean(false)
        val violations = java.util.concurrent.atomic.AtomicInteger(0)
        val lock = StepWakeLock(acquire = { held.set(true) }, release = { held.set(false) }, capMs = 5_000)
        val threads =
            List(8) {
                Thread {
                    repeat(2_000) {
                        val done = lock.begin()
                        if (!held.get()) violations.incrementAndGet()
                        done()
                    }
                }
            }
        threads.forEach { it.start() }
        threads.forEach { it.join() }
        assertEquals(0, violations.get())
        assertEquals(0, lock.inFlight)
        assertEquals(false, held.get())
    }
}
