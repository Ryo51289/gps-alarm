package app.napstop.core.trip.runtime.sim

import app.napstop.core.trip.runtime.ClockAnchor
import app.napstop.core.trip.runtime.RestoreCause
import app.napstop.core.trip.runtime.SlotKind
import app.napstop.core.trip.runtime.TripClock
import app.napstop.core.trip.runtime.WakeMechanism
import app.napstop.core.trip.runtime.support.FakeScheduler
import app.napstop.core.trip.runtime.support.FakeTime
import app.napstop.core.trip.runtime.support.OpLog
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.currentTime
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows

/** SM10 (in-process timers on the trip clock), SM11 (routing between OS and simulation). */
@OptIn(ExperimentalCoroutinesApi::class)
class SimAlarmSchedulerTest {
    private class Rig(scope: TestScope, speed: Double) {
        val time = FakeTime(wallBase = 1_700_000_000_000L, elapsedBase = 1_000_000L, virtual = { scope.testScheduler.currentTime })
        val clock = TripClock(ClockAnchor(time.wallMs(), time.elapsedMs(), 7, speed), time)
        val wakes = ArrayList<Pair<Long, Long>>() // (wakeAtMs, trip time when it fired)
        val fallbacks = ArrayList<List<Any>>()
        val sim =
            SimAlarmScheduler(
                scope.backgroundScope, StandardTestDispatcher(scope.testScheduler), time, 250,
                onWake = { at, _ -> wakes += at to clock.timeline.tripNow() },
                onFallback = { tripId, slot, gen, target, kind -> fallbacks += listOf(tripId, slot, gen, target, kind, clock.timeline.tripNow()) },
            ).also { it.timeline = clock.timeline }
    }

    @Test
    fun sm10_timersFollowTheTripClockAndARebase() =
        runTest {
            val r = Rig(this, 60.0)
            val t0 = r.clock.now()
            val w = t0 + 120_000
            val w2 = t0 + 240_000
            r.sim.setWake(r.clock.toElapsed(w), WakeMechanism.EXACT_IDLE, r.clock.toWall(w), w)
            r.sim.setWake(r.clock.toElapsed(w2), WakeMechanism.EXACT_IDLE, r.clock.toWall(w2), w2) // replaces w
            val t1 = t0 + 60_000
            val t2 = t0 + 900_000
            r.sim.setFallback(0, "t1", 1, t1, r.clock.toWall(t1), true, SlotKind.ENGINE)
            r.sim.setFallback(1, "t1", 2, t2, r.clock.toWall(t2), true, SlotKind.GUARD)
            r.sim.cancelFallback(0)
            assertEquals(setOf(1), r.sim.pendingSlots)
            assertTrue(r.sim.wakePending)
            advanceTimeBy(4_500) // trip + 270 s
            runCurrent()
            assertEquals(listOf(w2), r.wakes.map { it.first }, "w replaced by w2, fired once")
            assertTrue(r.wakes.single().second >= w2 && r.wakes.single().second < w2 + 60 * 250)
            assertTrue(r.fallbacks.isEmpty())
            // Trip time 600 s: back to 1×; slot 1 (900 s) now needs 300 s real.
            advanceTimeBy(5_500)
            runCurrent()
            r.clock.rebase(1.0)
            val rebaseAt = currentTime
            advanceTimeBy(299_000)
            runCurrent()
            assertTrue(r.fallbacks.isEmpty(), "not before the trip time at 1×")
            advanceTimeBy(1_500)
            runCurrent()
            val f = r.fallbacks.single()
            assertEquals(listOf("t1", 1, 2L, t2, SlotKind.GUARD), f.subList(0, 5))
            assertTrue((f[5] as Long) >= t2)
            assertTrue(currentTime - rebaseAt in 300_000L..300_500L)
            assertFalse(r.sim.wakePending)
            assertTrue(r.sim.canScheduleExact())
            assertThrows<UnsupportedOperationException> { r.sim.setRestoreRetry(0, 0, RestoreCause.BOOT, 0, true) }
        }

    @Test
    fun sm10_cancelAllStopsEveryTimer() =
        runTest {
            val r = Rig(this, 60.0)
            val t0 = r.clock.now()
            r.sim.setWake(0, WakeMechanism.EXACT_IDLE, 0, t0 + 60_000)
            r.sim.setFallback(0, "t1", 1, t0 + 60_000, 0, true, SlotKind.ENGINE)
            r.sim.cancelAll()
            advanceTimeBy(10_000)
            runCurrent()
            assertTrue(r.wakes.isEmpty() && r.fallbacks.isEmpty())
            assertTrue(r.sim.pendingSlots.isEmpty())
        }

    @Test
    fun sm11_routingSendsSetsToOneSideAndCancelsToBoth() =
        runTest {
            val log = OpLog()
            val os = FakeScheduler(log)
            os.canExact = false
            val r = Rig(this, 60.0)
            val router = RoutingAlarmScheduler(os, r.sim)
            val t0 = r.clock.now()
            // Real trip.
            assertFalse(router.canScheduleExact())
            router.setWake(5, WakeMechanism.EXACT_IDLE, 6, t0 + 1_000)
            router.setFallback(0, "t1", 1, t0 + 1_000, 7, false, SlotKind.ENGINE)
            assertEquals(listOf("setWake(EXACT_IDLE)", "setFallback(0,${t0 + 1_000})"), log.ops)
            assertFalse(r.sim.wakePending)
            assertTrue(r.sim.pendingSlots.isEmpty())
            router.cancelWake()
            router.cancelFallback(0)
            // Simulated trip.
            log.ops.clear()
            router.simulated = true
            assertTrue(router.canScheduleExact(), "simulated: exact even when the OS says no")
            router.setWake(5, WakeMechanism.EXACT_IDLE, 6, t0 + 60_000)
            router.setFallback(1, "t1", 2, t0 + 60_000, 7, true, SlotKind.ENGINE)
            assertTrue(log.ops.isEmpty(), "nothing set at the OS: ${log.ops}")
            assertTrue(r.sim.wakePending)
            assertEquals(setOf(1), r.sim.pendingSlots)
            router.cancelFallback(1)
            router.cancelWake()
            assertEquals(listOf("cancelFallback(1)", "cancelWake"), log.ops, "cancels reach the OS too")
            assertTrue(r.sim.pendingSlots.isEmpty())
            assertFalse(r.sim.wakePending)
            router.setRestoreRetry(10, 1, RestoreCause.BOOT, 0, true)
            assertEquals(1, os.restoreRetries.size, "restore retries are the OS's")
            router.cancelRestoreRetry()
            assertEquals(null, os.restoreRetry)
        }
}
