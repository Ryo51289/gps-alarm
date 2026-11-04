package app.napstop.core.trip.runtime

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.UserActionKind
import app.napstop.core.trip.runtime.T15TesterRestoreMatrixTest.HoldingDispatcher
import app.napstop.core.trip.runtime.support.EngineStates
import app.napstop.core.trip.runtime.support.FakeAlarmPort
import app.napstop.core.trip.runtime.support.FakeEnv
import app.napstop.core.trip.runtime.support.FakeLocationSource
import app.napstop.core.trip.runtime.support.FakeNotifier
import app.napstop.core.trip.runtime.support.FakeScheduler
import app.napstop.core.trip.runtime.support.FakeStore
import app.napstop.core.trip.runtime.support.FakeVisibility
import app.napstop.core.trip.runtime.support.Geo
import app.napstop.core.trip.runtime.support.TestData
import app.napstop.core.trip.runtime.support.World
import app.napstop.core.trip.runtime.support.fixNorth
import app.napstop.core.trip.runtime.support.startTrip
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Tag
import org.junit.jupiter.api.Test

/**
 * Tester T15 — Lần 2 (designer "T15 — sau test"): adversarial cases around the ring guard slot (G1/G2), restoreRetry
 * (B3), "ring on restore if it never rang" (G3) and startTrip on a slow disk. Numbers go to
 * build/napstop/T15-tester2-*.txt.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class T15TesterRound2Test {
    private val meta = TestData.meta()

    private fun outDir() = File(System.getProperty("napstop.outDir") ?: "build/napstop").apply { mkdirs() }

    private fun World.approach(fromM: Double, toM: Double) {
        var m = fromM
        while (m >= toM) {
            fixNorth(m)
            advance(5_000)
            m -= 75.0
        }
    }

    private fun World.rings() = alarm.ringNowCalls.map { it.atWallMs } + alarm.ringFallbackCalls.map { it.atWallMs }

    private fun World.alarms() = events.map { it.second }.filterIsInstance<Alarm>()

    /** The trip rings "now" (DISTANCE 1 km); returns the ring wall time. */
    private fun World.ringingNow(): Long {
        listen()
        assertEquals(StartOutcome.Started, startTrip(meta))
        var m = 1_300.0
        while (alarm.ringNowCalls.isEmpty() && m > 0) {
            fixNorth(m)
            if (alarm.ringNowCalls.isEmpty()) advance(5_000)
            m -= 75.0
        }
        return alarm.ringNowCalls.single().atWallMs
    }

    /** Lets the fake OS deliver its alarms until [untilWall] (no fixes: the vehicle is parked / the phone pocketed). */
    private fun World.runOs(untilWall: Long) {
        var guard = 0
        while (guard++ < 500) {
            val next = nextOsDeliveryMs(null, null) ?: break
            if (startWall + next > untilWall) break
            val now = scope.testScheduler.currentTime
            if (next > now) advance(next - now)
            deliverDue(null, null)
        }
        val now = scope.testScheduler.currentTime
        if (untilWall - startWall > now) advance(untilWall - startWall - now)
    }

    private fun <T> World.await(maxMs: Long = 60_000, block: suspend () -> T): T {
        val d = scope.async { block() }
        var t = 0L
        while (!d.isCompleted && t < maxMs) {
            advance(100)
            t += 100
        }
        check(d.isCompleted) { "did not complete in $maxMs ms virtual" }
        return d.getCompleted()
    }

    // ============================================================ guard window (G1)

    @Test
    fun dismissInsideTheGuardWindowNeverRingsAgain() =
        runTest {
            val w = World(this)
            val t0 = w.ringingNow()
            val guard = w.scheduler.slots.values.single()
            assertEquals(SlotKind.GUARD, guard.kind)
            assertTrue(guard.triggerWallMs - t0 in 1..30_000, "guard ${guard.triggerWallMs - t0} ms after the ring")
            w.advance(10_000)
            w.now { w.runtime.userAction("t1", UserActionKind.DISMISS) }
            assertTrue(w.scheduler.slots.isEmpty(), "guard cancelled by TripEnded")
            // The guard broadcast was already in flight (cancel latency, LM4).
            assertEquals(FallbackFireAction.IGNORED, w.now { w.runtime.onFallbackFired("t1", guard.slot, guard.generation, guard.targetAtMs, SlotKind.GUARD) })
            w.runOs(t0 + 600_000)
            assertEquals(1, w.rings().size)
            File(outDir(), "T15-tester2-guard-dismiss.txt").writeText("dismiss at +10 s: rings=${w.rings().size}, slots=${w.scheduler.slots.size}; in-flight guard=IGNORED\n")
        }

    @Test
    fun snoozeInsideTheGuardWindowReplacesTheGuardAndRingsAtSnoozeEnd() =
        runTest {
            val w = World(this)
            val t0 = w.ringingNow()
            val guard = w.scheduler.slots.values.single()
            w.advance(10_000)
            w.now { w.runtime.userAction("t1", UserActionKind.SNOOZE) }
            val slot = w.scheduler.slots.values.single()
            assertEquals(SlotKind.ENGINE, slot.kind, "the snooze fallback replaced the guard")
            assertTrue(slot.triggerWallMs > guard.triggerWallMs)
            w.runOs(t0 + 600_000)
            val r = w.rings()
            assertEquals(2, r.size, "first ring + snooze end: $r")
            assertTrue(r[1] - t0 > 30_000, "nothing at the old guard time")
            assertEquals(AlarmReason.SNOOZE_END, w.alarms().last().reason)
            assertEquals(0, w.alarm.doubleRings)
            File(outDir(), "T15-tester2-guard-snooze.txt").writeText("snooze at +10 s: second ring at +${(r[1] - t0) / 1000} s (SNOOZE_END), guard was at +${(guard.triggerWallMs - t0) / 1000} s\n")
        }

    /**
     * Cancel latency: the guard's broadcast was already queued when the snooze replaced it. Records what happens (the
     * guard rings again right after the user snoozed — same class as the A/B in-flight race, never a missed alarm).
     */
    @Test
    fun guardInFlightRightAfterASnoozeNumbers() =
        runTest {
            val w = World(this)
            val t0 = w.ringingNow()
            val guard = w.scheduler.slots.values.single()
            w.advance(guard.triggerWallMs - w.nowMs)
            w.now { w.runtime.userAction("t1", UserActionKind.SNOOZE) }
            val a = w.now { w.runtime.onFallbackFired("t1", guard.slot, guard.generation, guard.targetAtMs, SlotKind.GUARD) }
            val phase = w.seen.last().view.phase
            w.runOs(t0 + 900_000)
            assertEquals(0, w.alarm.doubleRings)
            File(outDir(), "T15-tester2-guard-snooze-race.txt").writeText(
                "guard in flight right after snooze: action=$a phase=$phase rings at +${w.rings().map { (it - t0) / 1000 }} s doubles=${w.alarm.doubleRings}\n",
            )
        }

    /**
     * Reviewer round 4 note 2: swiping the interim alarm notification away (SILENCED, not Dismiss) inside the first 30 s
     * → the guard rings again ~30 s after the first ring, by design. Records it; checks it happens once and nothing more.
     */
    @Test
    fun swipingTheRingAwayInsideTheGuardWindowRingsOnceMoreAtTheGuard() =
        runTest {
            val w = World(this)
            val t0 = w.ringingNow()
            w.advance(5_000)
            w.alarm.silence("t1", w.nowMs)
            w.now { w.runtime.onRingEvent(RingEvent("t1", RingEventKind.SILENCED, w.nowMs)) }
            assertTrue(!w.seen.last().view.alarmRinging)
            w.runOs(t0 + 120_000)
            val r1 = w.rings()
            assertEquals(2, r1.size, "guard rang once more: $r1")
            assertTrue(r1[1] - t0 in 25_000..31_000, "second ring at +${r1[1] - t0} ms")
            assertTrue(w.scheduler.slots.isEmpty(), "no slot after the guard rang")
            // The user swipes it away again: nothing rings any more (until an overshoot).
            w.alarm.silence("t1", w.nowMs)
            w.now { w.runtime.onRingEvent(RingEvent("t1", RingEventKind.SILENCED, w.nowMs)) }
            w.runOs(t0 + 1_800_000)
            assertEquals(2, w.rings().size)
            assertEquals(0, w.alarm.doubleRings)
            File(outDir(), "T15-tester2-swipe.txt").writeText(
                "swipe at +5 s: second ring at +${(r1[1] - t0) / 1000} s via GUARD; swipe again: no more rings in 30 min\n",
            )
        }

    @Test
    fun swipingAfterTheGuardWasDroppedDoesNotRingAgain() =
        runTest {
            val w = World(this)
            val t0 = w.ringingNow()
            w.runOs(t0 + 35_000) // guard came while ringing → SUPPRESSED_LIVE
            assertTrue(w.scheduler.slots.isEmpty())
            w.alarm.silence("t1", w.nowMs)
            w.now { w.runtime.onRingEvent(RingEvent("t1", RingEventKind.SILENCED, w.nowMs)) }
            w.runOs(t0 + 1_800_000)
            assertEquals(1, w.rings().size)
        }

    // ============================================================ G2 / G3 combined

    /** Restore of "engine rang, speaker never did" (G3) where the restore ring fails too: the new guard catches it. */
    @Test
    fun g3RingThatFailsAgainIsCaughtByANewGuard() =
        runTest {
            val w = World(this)
            w.listen()
            w.startTrip(meta)
            var died: Pair<FakeStore, FakeScheduler>? = null
            var deathWall = 0L
            w.store.onWriteActive = { t ->
                if (died == null && t.engine.phase == TripPhase.ALARMING) {
                    died = w.store.copy() to w.scheduler.copy()
                    deathWall = w.nowMs
                }
            }
            w.approach(1_300.0, 600.0)
            val (store, sched) = died!!
            val p = World(this, startWall = w.startWall, store = store, scheduler = sched, alarm = FakeAlarmPort())
            p.visibility.visible = false
            p.alarm.throwOnRingNow = IllegalStateException("ring service refused")
            p.listen()
            // A sticky restart / wake brings the process back 5 s later; G3 rings now → fails → AlarmSilenced + guard.
            p.advance(5_000)
            p.await { p.runtime.ensureLoaded() }
            p.alarm.throwOnRingNow = null
            p.runOs(deathWall + 120_000)
            val first = p.rings().minOrNull()
            assertNotNull(first, "never woken")
            assertTrue(first!! - deathWall <= 36_000, "woken ${first - deathWall} ms after the death (restore +5 s, guard +30 s)")
            assertEquals(0, p.alarm.doubleRings)
            File(outDir(), "T15-tester2-g3-fail.txt").writeText("G3 ring failed at restore (+5 s): woken at +${(first - deathWall) / 1000} s via guard\n")
        }

    // ============================================================ restoreRetry (B3)

    private fun World.seedRebooted() {
        val step = EngineStates.drive(meta, nowMs - 150_000, 30_000.0, 30)
        val fb = step.state.fallback.targetAtMs!!
        store.active = EngineStates.stored(meta, step, ClockAnchor(time.wallMs(), time.elapsedMs(), 7))
        store.ledger = FallbackLedger(1, meta.tripId, 3, FallbackSlotRec(0, 2, fb, nowMs), null, null)
        time.bootCountValue = 8
        visibility.visible = false
    }

    @Test
    fun restoreRetryOnADiskHungForeverStopsAfter24h() =
        runTest {
            val holding = HoldingDispatcher(StandardTestDispatcher(testScheduler))
            val w = World(this, io = holding)
            w.seedRebooted()
            w.listen()
            holding.hold = true
            val since = w.nowMs
            w.await { w.runtime.ensureLoaded(RestoreCause.BOOT); w.runtime.awaitNotices() }
            var guard = 0
            while (w.scheduler.restoreRetry != null && guard++ < 1_000) {
                val rr = w.scheduler.restoreRetry!!
                w.advance(rr.triggerElapsedMs - w.time.elapsedMs())
                w.deliverDue(null, null)
                w.advance(9_000) // the RestoreLoop of this retry
            }
            val all = w.scheduler.restoreRetries
            val gaps = all.zipWithNext { a, b -> (b.triggerElapsedMs - a.triggerElapsedMs) / 1000 }
            File(outDir(), "T15-tester2-restore-retry-24h.txt").writeText(
                "hung disk forever after BOOT: ${all.size} restoreRetry alarms, last at +${(all.last().triggerElapsedMs - w.elapsedBase - (since - w.startWall)) / 3_600_000.0} h, " +
                    "first gaps (s) ${gaps.take(6)}, stopped at +${(w.nowMs - since) / 3_600_000.0} h; Interrupted posts=${w.notifier.alerts.count { it.first == TripNotice.Interrupted }}\n",
            )
            assertNull(w.scheduler.restoreRetry, "no retry left after the cap")
            assertTrue(all.size in 280..300, "about 290 retries in 24 h: ${all.size}")
            assertTrue(all.last().triggerElapsedMs - w.time.elapsedMs() <= 0)
            assertTrue((w.nowMs - since) in 86_400_000L..(86_400_000L + 600_000L), "stopped right after 24 h: ${(w.nowMs - since) / 1000} s")
            assertTrue(w.tracking.starts.isEmpty())
        }

    @Test
    fun restoreRetryIsCancelledWhenTheUserStartsANewTrip() =
        runTest {
            val holding = HoldingDispatcher(StandardTestDispatcher(testScheduler))
            val w = World(this, io = holding)
            w.seedRebooted()
            w.listen()
            holding.hold = true
            w.await { w.runtime.ensureLoaded(RestoreCause.BOOT) }
            assertNotNull(w.scheduler.restoreRetry)
            // The user opens the app and starts a new trip while the disk still hangs.
            w.visibility.visible = true
            w.tracking.autoResult = ForegroundResult.Started
            val r = w.await { w.runtime.start(TestData.meta("t2"), Geo.DEST_LAT, Geo.DEST_LNG) }
            assertEquals(StartOutcome.Started, r)
            assertNull(w.scheduler.restoreRetry, "restoreRetry cancelled by the new trip")
            holding.release()
            w.advance(10_000)
            assertEquals("t2", w.runtime.liveTrip())
            w.runOs(w.nowMs + 3_600_000)
            assertNull(w.scheduler.restoreRetry)
            assertEquals("t2", w.runtime.liveTrip(), "the late read of the old trip never replaced t2")
        }

    // ============================================================ startTrip on a slow disk (T25: 15 s)

    /** Store whose every call takes [ms] of real time (debug `slow_read` makes reads slow; here writes too: worse). */
    private class SlowStore(val ms: Long, val delegate: FakeStore) : RuntimeStore by delegate {
        private fun slow() = Thread.sleep(ms)

        override fun readActive(): StoredTrip? = slow().let { delegate.readActive() }

        override fun writeActive(t: StoredTrip) = slow().let { delegate.writeActive(t) }

        override fun readLedger(): FallbackLedger = slow().let { delegate.readLedger() }

        override fun writeLedger(l: FallbackLedger) = slow().let { delegate.writeLedger(l) }

        override fun readRingConfig(): RingConfig? = slow().let { delegate.readRingConfig() }

        override fun writeRingConfig(c: RingConfig) = slow().let { delegate.writeRingConfig(c) }

        override fun readFinished(): List<FinishedRecord> = slow().let { delegate.readFinished() }
    }

    /** Real time: Composite calls current() first, then start(); the FGS answers after [fgsMs]. Returns ms. */
    private fun startOnSlowDisk(diskMs: Long, fgsMs: Long): Long {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        try {
            val time =
                object : TimeSource {
                    override fun wallMs() = System.currentTimeMillis()

                    override fun elapsedMs() = System.nanoTime() / 1_000_000L

                    override fun elapsedNanos() = System.nanoTime()

                    override fun bootCount() = 7
                }
            lateinit var runtime: TripRuntime
            val tracking =
                object : TrackingController {
                    @Volatile override var isForeground = false

                    override fun start(tripId: String, reason: StartReason) {
                        Thread {
                            Thread.sleep(fgsMs)
                            isForeground = true
                            runtime.onForegroundResult(tripId, ForegroundResult.Started)
                        }.start()
                    }

                    override fun updateTrackingNotification(content: TrackingNotice) = Unit

                    override fun stop() {
                        isForeground = false
                    }
                }
            val ports =
                RuntimePorts(
                    time, FakeLocationSource(), tracking, FakeScheduler(), FakeAlarmPort(), FakeNotifier(), SlowStore(diskMs, FakeStore()),
                    FakeVisibility(true), FakeEnv(),
                )
            runtime = TripRuntime(ports, scope, Dispatchers.Default.limitedParallelism(1), Dispatchers.IO, Dispatchers.Default, RuntimeConstants(), warn = {})
            val t0 = System.nanoTime()
            val r =
                runBlocking {
                    runtime.current()
                    runtime.start(meta, Geo.DEST_LAT, Geo.DEST_LNG)
                }
            assertEquals(StartOutcome.Started, r)
            return (System.nanoTime() - t0) / 1_000_000L
        } finally {
            scope.coroutineContext[kotlinx.coroutines.Job]?.cancel()
        }
    }

    @Tag("slow")
    @Test
    fun startTripWithSlowRead2500AnswersWithin15s() {
        val fast = startOnSlowDisk(2_500, 100)
        val slowFgs = startOnSlowDisk(2_500, 4_800)
        File(outDir(), "T15-tester2-start-slow-disk.txt").writeText(
            "every disk call 2.5 s (reads and writes): current()+start() = $fast ms (FGS 0.1 s), $slowFgs ms (FGS 4.8 s); T25 budget 15 000 ms\n",
        )
        assertTrue(fast <= 15_000, "start took $fast ms")
        assertTrue(slowFgs <= 15_000, "start took $slowFgs ms with a slow FGS")
    }
}
