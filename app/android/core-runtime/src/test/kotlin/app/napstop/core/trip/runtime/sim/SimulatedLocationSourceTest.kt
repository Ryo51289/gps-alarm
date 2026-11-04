package app.napstop.core.trip.runtime.sim

import app.napstop.core.trip.runtime.ClockAnchor
import app.napstop.core.trip.runtime.FlpPriority
import app.napstop.core.trip.runtime.FlpRequestSpec
import app.napstop.core.trip.runtime.RawFix
import app.napstop.core.trip.runtime.TripClock
import app.napstop.core.trip.runtime.support.FakeTime
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** SM07, SM08: the simulated source plays a trace on the trip clock with the harness `policy` rule. */
@OptIn(ExperimentalCoroutinesApi::class)
class SimulatedLocationSourceTest {
    private fun spec(intervalMs: Long) = FlpRequestSpec(FlpPriority.HIGH_ACCURACY, intervalMs, intervalMs / 2, 0, intervalMs)

    private fun samples(ts: List<Int>) = ts.map { TraceSample(it, 16.0 + it / 1e5, 108.0, 8f, 10f) }

    private class Rig(scope: TestScope, speed: Double, ts: List<TraceSample>) {
        val time = FakeTime(wallBase = 1_700_000_000_000L, elapsedBase = 1_000_000L, virtual = { scope.testScheduler.currentTime })
        val clock = TripClock(ClockAnchor(time.wallMs(), time.elapsedMs(), 7, speed), time)
        val start = clock.now()
        val got = ArrayList<Pair<Long, RawFix>>()
        val source =
            SimulatedLocationSource(ts, start, clock.timeline, time, scope.backgroundScope, StandardTestDispatcher(scope.testScheduler), 250)
        val sink = app.napstop.core.trip.runtime.FixSink { raw, done -> got += scope.testScheduler.currentTime to raw; done() }

        fun tOf(raw: RawFix): Int = ((raw.simFixAtMs!! - start) / 1000L).toInt()
    }

    @Test
    fun sm07_policySamplingStopAndRequestAgain() =
        runTest {
            val r = Rig(this, 1.0, samples((0..55 step 5).toList()))
            r.source.request(spec(30_000), r.sink)
            runCurrent()
            advanceTimeBy(31_000)
            runCurrent()
            assertEquals(listOf(0, 30), r.got.map { r.tOf(it.second) })
            r.source.request(spec(5_000), r.sink)
            advanceTimeBy(10_000) // t = 41
            runCurrent()
            assertEquals(listOf(0, 30, 35, 40), r.got.map { r.tOf(it.second) })
            r.source.stop()
            advanceTimeBy(7_000) // t = 48: sample 45 skipped
            runCurrent()
            assertEquals(4, r.got.size)
            r.source.request(spec(5_000), r.sink)
            advanceTimeBy(20_000)
            runCurrent()
            assertEquals(listOf(0, 30, 35, 40, 50, 55), r.got.map { r.tOf(it.second) }, "no old sample delivered on a new request")
            for ((at, raw) in r.got) {
                assertEquals(r.start + r.tOf(raw) * 1000L, raw.simFixAtMs)
                assertEquals(r.tOf(raw) * 1000L, at, "delivered on time")
            }
            assertNull(r.source.lastKnown())
            // After the last sample nothing more; cancel stops everything.
            r.source.cancel()
            r.source.request(spec(5_000), r.sink)
            advanceTimeBy(60_000)
            runCurrent()
            assertEquals(6, r.got.size)
        }

    @Test
    fun sm08_rebaseToOneSlowsTheNextSamplesAtOnce() =
        runTest {
            val r = Rig(this, 60.0, samples(listOf(0, 600)))
            r.source.request(spec(5_000), r.sink)
            runCurrent()
            assertEquals(1, r.got.size)
            advanceTimeBy(5_000) // trip time 300 s
            runCurrent()
            assertEquals(r.start + 300_000, r.clock.now())
            r.clock.rebase(1.0)
            advanceTimeBy(299_000)
            runCurrent()
            assertEquals(1, r.got.size, "not 5 s after the rebase")
            advanceTimeBy(2_000)
            runCurrent()
            assertEquals(2, r.got.size)
            val realAfterRebase = r.got[1].first - 5_000
            assertTrue(realAfterRebase in 300_000L..300_250L, "sample 600 after $realAfterRebase ms real")
            assertEquals(r.start + 600_000, r.got[1].second.simFixAtMs)
        }
}
