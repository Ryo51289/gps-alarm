package app.napstop.core.trip.runtime

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.EndReason
import app.napstop.core.trip.TripEnded
import app.napstop.core.trip.TripEngine
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.UserAction
import app.napstop.core.trip.UserActionKind
import app.napstop.core.trip.runtime.T15TesterRestoreMatrixTest.HoldingDispatcher
import app.napstop.core.trip.runtime.support.EngineStates
import app.napstop.core.trip.runtime.support.FakeAlarmPort
import app.napstop.core.trip.runtime.support.FakeEnv
import app.napstop.core.trip.runtime.support.FakeLocationSource
import app.napstop.core.trip.runtime.support.FakeNotifier
import app.napstop.core.trip.runtime.support.FakeScheduler
import app.napstop.core.trip.runtime.support.FakeStore
import app.napstop.core.trip.runtime.support.FakeTracking
import app.napstop.core.trip.runtime.support.FakeVisibility
import app.napstop.core.trip.runtime.support.Geo
import app.napstop.core.trip.runtime.support.TestData
import app.napstop.core.trip.runtime.support.World
import app.napstop.core.trip.runtime.support.fixNorth
import app.napstop.core.trip.runtime.support.startTrip
import java.io.File
import java.util.concurrent.CountDownLatch
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Disabled
import org.junit.jupiter.api.Test

/**
 * Tester T15 — adversarial runtime tests outside the spec list: fallback A/B slot races, ring-before-persist on a hung
 * or failing disk, entries into a process whose runtime is not loaded, "Interrupted" alert-once across processes,
 * startTrip concurrency. Every case asks: is there an interleaving where the user is not woken, or woken twice?
 */
@OptIn(ExperimentalCoroutinesApi::class)
class T15TesterRuntimeTest {
    private val meta = TestData.meta()

    private fun World.approach(fromM: Double, toM: Double) {
        var m = fromM
        while (m >= toM) {
            fixNorth(m)
            advance(5_000)
            m -= 75.0
        }
    }

    private fun World.rings() = alarm.ringNowCalls.size + alarm.ringFallbackCalls.size

    private fun World.alarms() = events.map { it.second }.filterIsInstance<Alarm>()

    /** Runs [block] to completion, letting virtual time run (bounded disk calls may wait for their budget). */
    private fun <T> World.await(block: suspend () -> T): T {
        val d = scope.async { block() }
        var t = 0
        while (!d.isCompleted && t < 30_000) {
            advance(100)
            t += 100
        }
        check(d.isCompleted) { "call did not complete in 30 s virtual" }
        return d.getCompleted()
    }

    private fun outDir() = File(System.getProperty("napstop.outDir") ?: "build/napstop").apply { mkdirs() }

    // ============================================================ fallback A/B slot races (T10.5 §8, D7, D8)

    private enum class When { BEFORE_REARM, BETWEEN_SET_AND_CANCEL, AFTER_REARM_IN_FLIGHT }

    /**
     * Restored NEAR trip (fallback ≈ 50 s ahead, HEADLESS: no fixes), clock moved to [leadMs] before the fallback target,
     * then a re-arm (ACTION_TIME_CHANGED re-sets the same target in the other slot) races the old slot A firing.
     */
    @Test
    fun oldSlotFiringAroundARearmAtLeadTimes10s1s0sRingsExactlyOnce() =
        runTest {
            val report = StringBuilder("lead | when | action | rings | slots left | phase\n")
            for (leadMs in listOf(10_000L, 1_000L, 0L)) for (w0 in When.entries) {
                val w = World(this)
                w.visibility.visible = false
                val t0 = w.nowMs
                val step = EngineStates.drive(meta, t0 - 40_000, 1_900.0, 8)
                val fb = step.state.fallback.targetAtMs!!
                w.store.active = EngineStates.stored(meta, step, ClockAnchor(w.time.wallMs(), w.time.elapsedMs(), 7))
                w.store.ledger = FallbackLedger(1, meta.tripId, 3, FallbackSlotRec(0, 2, fb, t0), null, null)
                w.scheduler.slots[0] = FakeScheduler.Fallback(0, meta.tripId, 2, fb, fb, true)
                w.listen()
                w.now { w.runtime.ensureLoaded() }
                // ensureLoaded re-set the same target in slot 1 (PENDING). That slot is "A" now.
                val a = w.scheduler.slots.values.single()
                w.advance((a.triggerWallMs - leadMs - w.nowMs).coerceAtLeast(0))
                var action: FallbackFireAction? = null
                when (w0) {
                    When.BEFORE_REARM -> {
                        action = w.now { w.runtime.onFallbackFired(a.tripId, a.slot, a.generation, a.targetAtMs) }
                        w.scheduler.slots.remove(a.slot)
                        w.runtime.onTimeChanged()
                        w.settle()
                    }
                    When.BETWEEN_SET_AND_CANCEL -> {
                        w.scheduler.afterSetFallback = { b ->
                            w.scheduler.afterSetFallback = null
                            assertTrue(b.slot != a.slot)
                            launch { action = w.runtime.onFallbackFired(a.tripId, a.slot, a.generation, a.targetAtMs) }
                        }
                        w.runtime.onTimeChanged()
                        w.settle()
                    }
                    When.AFTER_REARM_IN_FLIGHT -> {
                        w.runtime.onTimeChanged()
                        w.settle()
                        assertFalse(w.scheduler.slots.containsKey(a.slot), "A cancelled by the re-arm")
                        // A's broadcast was already queued before the cancel (LM4 measures AlarmManager.cancel latency).
                        action = w.now { w.runtime.onFallbackFired(a.tripId, a.slot, a.generation, a.targetAtMs) }
                    }
                }
                val phase = w.seen.last().view.phase
                report.append("$leadMs | $w0 | $action | ${w.rings()} | ${w.scheduler.slots.keys} | $phase\n")
                // RANG, or ALREADY_RINGING when the re-arm Step itself rang "now" (P already passed): both are one ring.
                assertTrue(action == FallbackFireAction.RANG || action == FallbackFireAction.ALREADY_RINGING, "lead $leadMs $w0: $action")
                assertEquals(1, w.rings(), "lead $leadMs $w0: exactly one ring")
                assertEquals(0, w.alarm.doubleRings)
                assertTrue(w.scheduler.slots.isEmpty(), "lead $leadMs $w0: no slot left armed: ${w.scheduler.slots}")
                assertEquals(TripPhase.ALARMING, phase)
                // Nothing rings again in the next 10 minutes (no slot, engine ALARMING).
                repeat(10) {
                    w.advance(60_000)
                    w.deliverDue(null, null)
                }
                assertEquals(1, w.rings(), "lead $leadMs $w0: no second ring later")
            }
            File(outDir(), "T15-tester-slot-race.txt").writeText(report.toString())
        }

    @Test
    fun twoFallbackSlotsDeliveredTogetherRingOnce() =
        runTest {
            val w = World(this)
            w.listen()
            w.startTrip(meta)
            w.fixNorth(30_000.0)
            val a = w.scheduler.slots.values.single()
            // A second slot B exists too (the cancel of A was late): both broadcasts are queued at the same moment.
            w.scheduler.afterSetFallback = { w.scheduler.afterSetFallback = null }
            w.runtime.onTimeChanged()
            w.settle()
            val b = w.scheduler.slots.values.single()
            val r1 = async { w.runtime.onFallbackFired(a.tripId, a.slot, a.generation, a.targetAtMs) }
            val r2 = async { w.runtime.onFallbackFired(b.tripId, b.slot, b.generation, b.targetAtMs) }
            runCurrent()
            val actions = listOf(r1.await(), r2.await())
            assertEquals(listOf(FallbackFireAction.RANG, FallbackFireAction.ALREADY_RINGING), actions)
            assertEquals(1, w.rings())
            assertEquals(0, w.alarm.doubleRings)
            assertEquals(1, w.alarms().size, "one Alarm event")
            assertTrue(w.scheduler.slots.isEmpty())
        }

    @Test
    fun snoozeFallbackRacingADismissNeverRingsAfterTheTripEnded() =
        runTest {
            for (dismissFirst in listOf(true, false)) {
                val w = World(this)
                w.listen()
                w.startTrip(meta)
                w.approach(1_300.0, 900.0)
                w.now { w.runtime.userAction("t1", UserActionKind.SNOOZE) }
                val s = w.scheduler.slots.values.single()
                val ringsBefore = w.rings()
                if (dismissFirst) {
                    w.now { w.runtime.userAction("t1", UserActionKind.DISMISS) }
                    // The snooze fallback's broadcast was already in flight.
                    assertEquals(FallbackFireAction.IGNORED, w.now { w.runtime.onFallbackFired(s.tripId, s.slot, s.generation, s.targetAtMs) })
                    assertEquals(ringsBefore, w.rings(), "no ring after TripEnded")
                } else {
                    assertEquals(FallbackFireAction.RANG, w.now { w.runtime.onFallbackFired(s.tripId, s.slot, s.generation, s.targetAtMs) })
                    w.now { w.runtime.userAction("t1", UserActionKind.DISMISS) }
                    assertEquals(ringsBefore + 1, w.rings())
                    assertEquals(app.napstop.core.alarm.StopCause.TRIP_ENDED, w.alarm.stops.last())
                }
                assertEquals(1, w.events.count { it.second is TripEnded })
                assertTrue(w.scheduler.slots.isEmpty() && w.scheduler.wake == null)
            }
        }

    /**
     * Review R3-1 (follow-up T15.1, not counted as a T15 failure): the old trip's fallback broadcast arrives right after
     * a new trip took slot 0. The IGNORED branch cancels by slot number and removes the new trip's fallback.
     * Enable when T15.1 lands. Measured window (current code) in build/napstop/T15-tester-r31.txt via [r31Window].
     */
    @Test
    @Disabled("R3-1 -> T15.1: IGNORED cancels the new trip's slot")
    fun r31_staleFallbackOfThePreviousTripNeverCancelsTheNewTripsSlot() =
        runTest {
            val w = r31Setup(this)
            assertTrue(w.scheduler.slots.values.any { it.tripId == "t2" }, "t2 keeps a fallback slot: ${w.scheduler.slots}")
        }

    private fun r31Setup(scope: kotlinx.coroutines.test.TestScope): World {
        val w = World(scope)
        w.listen()
        w.startTrip(meta)
        w.fixNorth(30_000.0)
        var old = w.scheduler.slots.values.single()
        if (old.slot != 0) {
            w.runtime.onTimeChanged() // same target, other slot
            w.settle()
            old = w.scheduler.slots.values.single()
        }
        assertEquals(0, old.slot)
        w.now { w.runtime.userAction("t1", UserActionKind.STOP_TRIP) }
        w.startTrip(TestData.meta("t2"))
        // t2 just started: its deadline fallback is in slot 0 (no fix yet).
        assertEquals(0, w.scheduler.slots.values.single().slot)
        // t1's slot-0 broadcast was queued before its cancel.
        assertEquals(FallbackFireAction.IGNORED, w.now { w.runtime.onFallbackFired(old.tripId, old.slot, old.generation, old.targetAtMs) })
        return w
    }

    /** Numbers for R3-1 (no assertion on the bug): how long t2 runs without any fallback alarm, far and near. */
    @Test
    fun r31Window() =
        runTest {
            val w = r31Setup(this)
            val lostAt = w.nowMs
            var m = 29_000.0
            var guard = 0
            while (w.scheduler.slots.isEmpty() && guard++ < 2_000) {
                m -= 75.0
                w.fixNorth(m)
                w.advance(5_000)
            }
            File(outDir(), "T15-tester-r31.txt").writeText(
                "R3-1: t2 without a fallback alarm for ${(w.nowMs - lostAt) / 1000} s (steady 15 m/s fixes every 5 s from 29 km; " +
                    "slots after: ${w.scheduler.slots.values.map { it.tripId + "@" + it.slot }})\n",
            )
        }

    // ============================================================ ring before persist (D4, ARCH R2-1)

    @Test
    fun hungDiskDelaysTheNowRingByAtMostThePreRingBudget() =
        runTest {
            val holding = HoldingDispatcher(StandardTestDispatcher(testScheduler))
            val w = World(this, io = holding)
            w.listen()
            w.startTrip(meta)
            w.approach(1_300.0, 1_075.0)
            assertTrue(w.alarm.ringNowCalls.isEmpty())
            holding.hold = true // from now every disk call hangs (snapshot, ledger, ring config)
            var m = 1_000.0
            var guard = 0
            while (w.alarm.ringNowCalls.isEmpty() && guard++ < 40) {
                val before = testScheduler.currentTime
                w.location.emit(RawFix(Geo.latNorth(m), Geo.DEST_LNG, 8f, 15f, w.time.elapsedNanos()))
                runCurrent()
                if (w.alarm.ringNowCalls.isEmpty()) {
                    w.advance(299)
                    // Either no alarm in this Step, or still inside the 300 ms pre-ring budget.
                    if (w.alarm.ringNowCalls.isEmpty()) w.advance(1)
                    if (w.alarm.ringNowCalls.isNotEmpty()) {
                        assertTrue(testScheduler.currentTime - before <= 300, "rang ${testScheduler.currentTime - before} ms after the fix")
                    }
                }
                w.advance(5_000)
                m -= 75.0
            }
            assertEquals(1, w.alarm.ringNowCalls.size, "rang although the disk hangs")
            assertEquals(AlarmReason.DISTANCE, w.alarm.ringNowCalls.single().reason)
            assertTrue(w.warnings.any { it.contains("over budget") }, "${w.warnings}")
            holding.release()
            w.settle()
        }

    @Test
    fun everyDiskWriteFailingStillRingsAndStillEndsTheTrip() =
        runTest {
            val w = World(this)
            w.store.failWriteActive = { FakeStore.ioFailure() }
            w.store.failWriteLedger = FakeStore.ioFailure()
            w.store.failWriteFinished = FakeStore.ioFailure()
            w.listen()
            assertEquals(StartOutcome.Started, w.startTrip(meta))
            w.approach(1_300.0, 900.0)
            assertEquals(1, w.alarm.ringNowCalls.size)
            // The finished-record write waits ≤ ioBudgetMs for the writer (in its retry delay): virtual time must run.
            w.await { w.runtime.userAction("t1", UserActionKind.DISMISS) }
            assertEquals(1, w.events.count { it.second is TripEnded })
            assertTrue(w.scheduler.slots.isEmpty())
            assertEquals(1, w.await { w.runtime.pendingFinished() }.size, "record kept in memory")
            assertTrue(w.warnings.all { !it.contains("16.") })
        }

    /**
     * Real time: the whole disk hangs (ledger read/write, ring config, snapshot) in a new process; the fallback receiver
     * is the first entry, or a wake receiver loaded first. Spec L45 bounds only a hung snapshot (≤ 1.5 s); here every
     * file hangs, so each bounded disk call before the ring costs ioBudgetMs. Must ring within the receiver budget (8 s)
     * — after that goAsync() is finished and the process may be frozen. Numbers in T15-tester-hung-disk.txt.
     */
    @Test
    fun wholeDiskHungStillRingsWithinTheReceiverBudget() {
        val out = StringBuilder()
        for (wakeFirst in listOf(false, true)) {
            val r = HungDiskRuntime()
            try {
                val t0 = System.nanoTime() / 1_000_000L
                if (wakeFirst) {
                    r.scope.launch { r.runtime.onWake() }
                    Thread.sleep(20)
                }
                r.scope.launch { r.runtime.onFallbackFired("t1", 0, 2, r.time.wallMs()) }
                val d = r.ringDelayFrom(t0, 10_000)
                out.append("wakeFirst=$wakeFirst ring after ${d} ms; warnings=${r.warnings.toSet()}\n")
                assertNotNull(d, "never rang (wakeFirst=$wakeFirst)")
                assertTrue(d!! < RuntimeConstants().receiverBudgetMs, "rang after $d ms (wakeFirst=$wakeFirst)")
            } finally {
                r.close()
            }
        }
        File(outDir(), "T15-tester-hung-disk.txt").writeText(out.toString())
    }

    /** Store whose every call blocks on [gate]. */
    private class HungStore(val gate: CountDownLatch, val delegate: FakeStore) : RuntimeStore by delegate {
        override fun readActive(): StoredTrip? = gate.await().let { delegate.readActive() }

        override fun writeActive(t: StoredTrip) = gate.await().let { delegate.writeActive(t) }

        override fun readLedger(): FallbackLedger = gate.await().let { delegate.readLedger() }

        override fun writeLedger(l: FallbackLedger) = gate.await().let { delegate.writeLedger(l) }

        override fun readRingConfig(): RingConfig? = gate.await().let { delegate.readRingConfig() }

        override fun writeRingConfig(c: RingConfig) = gate.await().let { delegate.writeRingConfig(c) }
    }

    private class HungDiskRuntime {
        val gate = CountDownLatch(1)
        val fake = FakeStore()
        val alarm = FakeAlarmPort()
        val warnings: MutableList<String> = java.util.Collections.synchronizedList(ArrayList())
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val time =
            object : TimeSource {
                override fun wallMs() = System.currentTimeMillis()

                override fun elapsedMs() = System.nanoTime() / 1_000_000L

                override fun elapsedNanos() = System.nanoTime()

                override fun bootCount() = 7
            }
        val runtime: TripRuntime

        init {
            val m = TestData.meta()
            fake.active = EngineStates.stored(m, EngineStates.drive(m, time.wallMs() - 200_000, 30_000.0, 30), ClockAnchor(time.wallMs() - 200_000, time.elapsedMs() - 200_000, 7))
            fake.ledger = FallbackLedger(1, "t1", 3, FallbackSlotRec(0, 2, time.wallMs(), time.wallMs()), null, null)
            val ports =
                RuntimePorts(
                    time, FakeLocationSource(), FakeTracking(), FakeScheduler(), alarm, FakeNotifier(), HungStore(gate, fake),
                    FakeVisibility(false), FakeEnv(),
                )
            runtime = TripRuntime(ports, scope, Dispatchers.Default.limitedParallelism(1), Dispatchers.IO, Dispatchers.Default, RuntimeConstants(), warn = { warnings += it })
        }

        fun ringDelayFrom(t0: Long, maxMs: Long): Long? {
            while (System.nanoTime() / 1_000_000L - t0 < maxMs) {
                synchronized(alarm) { if (alarm.ringFallbackCalls.isNotEmpty()) return System.nanoTime() / 1_000_000L - t0 }
                Thread.sleep(5)
            }
            return null
        }

        fun close() {
            gate.countDown()
            scope.coroutineContext[kotlinx.coroutines.Job]?.cancel()
        }
    }

    // ============================================================ entries while the runtime is not loaded

    private fun World.seedNear(): app.napstop.core.trip.Step {
        val t0 = nowMs
        val step = EngineStates.drive(meta, t0 - 40_000, 1_900.0, 8)
        val fb = step.state.fallback.targetAtMs!!
        store.active = EngineStates.stored(meta, step, ClockAnchor(time.wallMs(), time.elapsedMs(), 7))
        store.ledger = FallbackLedger(1, meta.tripId, 3, FallbackSlotRec(0, 2, fb, t0), null, null)
        scheduler.slots[0] = FakeScheduler.Fallback(0, meta.tripId, 2, fb, fb, true)
        return step
    }

    @Test
    fun stopButtonInAFreshProcessEndsTheTripAndClearsEveryAlarm() =
        runTest {
            val w = World(this)
            w.visibility.visible = false
            w.seedNear()
            w.scheduler.wake = FakeScheduler.Wake(w.time.elapsedMs() + 10_000, WakeMechanism.EXACT_IDLE, w.nowMs + 10_000)
            w.listen()
            w.now { w.runtime.userAction("t1", UserActionKind.STOP_TRIP) } // TripActionReceiver is the first entry
            val ended = w.events.map { it.second }.filterIsInstance<TripEnded>().single()
            assertEquals(EndReason.USER_STOP, ended.endReason)
            assertTrue(w.scheduler.slots.isEmpty(), "${w.scheduler.slots}")
            assertNull(w.scheduler.wake)
            assertTrue(w.tracking.starts.isEmpty())
            assertEquals(0, w.rings())
            assertNull(w.store.active)
            assertTrue("t1" in w.store.ledger.endedTripIds)
        }

    @Test
    fun dismissFromTheAlarmNotificationInAFreshProcessEndsTheTripOnce() =
        runTest {
            // Fallback rang in a process that then died; the user taps "Tắt" on the interim notification: the port
            // records pendingDismiss, then RING_EVENT DISMISSED reaches a runtime that is not loaded.
            val w = World(this)
            w.visibility.visible = false
            val step = w.seedNear()
            val fb = step.state.fallback.targetAtMs!!
            w.advance(fb - w.nowMs)
            val first = World(this, store = w.store, scheduler = w.scheduler, alarm = w.alarm)
            first.visibility.visible = false
            assertEquals(FallbackFireAction.RANG, first.now { first.runtime.onFallbackFired("t1", 0, 2, fb) })
            // Process dies; user dismisses 20 s later.
            w.advance(20_000)
            w.alarm.facts["t1"]!!.apply {
                ringing = false
                pendingDismiss = w.nowMs
            }
            val second = World(this, store = w.store, scheduler = w.scheduler, alarm = w.alarm)
            second.visibility.visible = false
            second.listen()
            second.now { second.runtime.onRingEvent(RingEvent("t1", RingEventKind.DISMISSED, w.nowMs)) }
            val ends = second.events.map { it.second }.filterIsInstance<TripEnded>()
            assertEquals(1, ends.size, "${second.events}")
            assertEquals(app.napstop.core.trip.TripOutcome.ON_TIME, ends.single().outcome)
            assertTrue(second.scheduler.slots.isEmpty())
            assertEquals(1, w.alarm.ringFallbackCalls.size)
            assertEquals(0, w.alarm.ringNowCalls.size, "no second ring when the restored state is RANG/DISMISSED")
            assertEquals(1, second.now { second.runtime.pendingFinished() }.size)
        }

    @Test
    fun receiversOnAnEmptyDiskDoNothingAndDoNotThrow() =
        runTest {
            val w = World(this)
            w.visibility.visible = false
            w.listen()
            w.now { w.runtime.onWake() }
            w.now { w.runtime.ensureLoaded(RestoreCause.BOOT) }
            w.now { w.runtime.ensureLoaded(RestoreCause.PACKAGE_REPLACED) }
            w.now { w.runtime.onRingEvent(RingEvent("t1", RingEventKind.SILENCED, w.nowMs)) }
            w.now { w.runtime.userAction("t1", UserActionKind.STOP_TRIP) }
            w.now { w.runtime.onAppVisible() }
            w.advance(10_000)
            assertTrue(w.seen.isEmpty())
            assertTrue(w.notifier.history.isEmpty())
            assertTrue(w.tracking.starts.isEmpty())
            assertTrue(w.warnings.isEmpty(), "${w.warnings}")
            assertTrue(w.scheduler.slots.isEmpty())
        }

    @Test
    fun packageReplacedRestoreRearmsAndToldTheUserAtOnce() =
        runTest {
            val w = World(this)
            w.visibility.visible = false
            val step = EngineStates.drive(meta, w.nowMs - 150_000, 30_000.0, 30)
            val fb = step.state.fallback.targetAtMs!!
            w.store.active = EngineStates.stored(meta, step, ClockAnchor(w.time.wallMs(), w.time.elapsedMs(), 7))
            w.store.ledger = FallbackLedger(1, meta.tripId, 3, FallbackSlotRec(0, 2, fb, w.nowMs), null, null)
            w.scheduler.slots[0] = FakeScheduler.Fallback(0, meta.tripId, 2, fb, fb, true)
            w.listen()
            w.now { w.runtime.ensureLoaded(RestoreCause.PACKAGE_REPLACED) }
            assertEquals(1, w.scheduler.slots.size, "exactly one slot after RESYNC: ${w.scheduler.slots}")
            assertEquals(listOf(TripNotice.Interrupted to true), w.notifier.alerts.filter { it.first == TripNotice.Interrupted })
            assertEquals(TrackingMode.HEADLESS, w.runtime.mode.value)
            assertTrue(w.tracking.starts.isEmpty())
        }

    // ============================================================ "Interrupted" alert once across processes (R2-3)

    @Test
    fun failedStickyRestartInEveryProcessAlertsOnlyOnce() =
        runTest {
            val w = World(this)
            w.visibility.visible = false
            w.seedNear()
            var alerts = 0
            var shows = 0
            repeat(3) {
                val p = World(this, store = w.store, scheduler = w.scheduler, alarm = w.alarm)
                p.visibility.visible = false
                p.now { p.runtime.ensureLoaded() }
                p.runtime.onForegroundResult("t1", ForegroundResult.Failed("SecurityException"))
                p.advance(6_000)
                alerts += p.notifier.alerts.count { it.first == TripNotice.Interrupted && it.second }
                shows += p.notifier.alerts.count { it.first == TripNotice.Interrupted }
            }
            assertEquals(3, shows, "posted in every process (stays in the shade)")
            assertEquals(1, alerts, "sound / heads-up only once")
        }

    /**
     * Snapshot corrupt but the ledger still names the trip (§5.7): "Interrupted" is shown with no name. The orphan id is
     * never cleared, so the notice re-alerts in every new process (each wake-up / app open) forever — against the
     * "once per HEADLESS period" decision (R2-3). Tester finding F2 (minor).
     */
    @Test
    fun orphanInterruptedAlertsOnlyOnceAcrossProcesses() =
        runTest {
            val counts = orphanAlerts(this, 3)
            assertEquals(1, counts.first, "alerting posts over 3 processes")
        }

    /** Numbers for F2: (alerting posts, all posts) over [n] processes. */
    private fun orphanAlerts(scope: kotlinx.coroutines.test.TestScope, n: Int): Pair<Int, Int> {
        val w = World(scope)
        w.store.active = null // corrupt snapshot → deleted, null
        w.store.ledger = FallbackLedger(1, "X", 9, FallbackSlotRec(0, 8, 5, 5), null, null)
        var alerts = 0
        var shows = 0
        repeat(n) {
            val p = World(scope, store = w.store, scheduler = w.scheduler, alarm = w.alarm)
            p.visibility.visible = false
            p.now { p.runtime.ensureLoaded() }
            p.advance(6_000)
            alerts += p.notifier.alerts.count { it.first == TripNotice.Interrupted && it.second }
            shows += p.notifier.alerts.count { it.first == TripNotice.Interrupted }
        }
        return alerts to shows
    }

    @Test
    fun orphanInterruptedNumbers() =
        runTest {
            val (alerts, shows) = orphanAlerts(this, 3)
            File(outDir(), "T15-tester-orphan.txt").writeText("orphan ledger (corrupt snapshot), 3 processes: alerting posts=$alerts, posts=$shows\n")
            assertTrue(shows >= 1)
        }

    // ============================================================ startTrip concurrency (D12, §5.1)

    @Test
    fun callsWhileAStartWaitsForTheServiceDoNotDeadlock() =
        runTest {
            val w = World(this)
            w.tracking.autoResult = null
            val first = async { w.runtime.start(meta, Geo.DEST_LAT, Geo.DEST_LNG) }
            runCurrent()
            assertNull(w.now { w.runtime.current() }, "no trip yet; the actor is free while start waits for the FGS")
            assertTrue(w.now { w.runtime.pendingFinished() }.isEmpty())
            w.now { w.runtime.onWake() }
            assertEquals(StartOutcome.Rejected(StartCodes.TRIP_ACTIVE), w.now { w.runtime.start(TestData.meta("t2"), 1.0, 1.0) })
            w.tracking.isForeground = true
            w.runtime.onForegroundResult("t1", ForegroundResult.Started)
            runCurrent()
            assertEquals(StartOutcome.Started, first.await())
            assertEquals("t1", w.now { w.runtime.current() }?.first?.tripId)
        }

    @Test
    fun aStartedThatArrivesAfterTheTimeoutStopsTheServiceAndLeavesNoTrip() =
        runTest {
            val w = World(this)
            w.tracking.autoResult = null
            val r = async { w.runtime.start(meta, Geo.DEST_LAT, Geo.DEST_LNG) }
            w.advance(5_001)
            assertEquals(StartOutcome.Rejected(StartCodes.START_FAILED, "ForegroundTimeout"), r.await())
            assertEquals(1, w.tracking.stops)
            // The service finally runs onStartCommand → startForeground → Started.
            w.tracking.isForeground = true
            w.runtime.onForegroundResult("t1", ForegroundResult.Started)
            w.settle()
            assertEquals(2, w.tracking.stops, "late Started of a refused start stops the service")
            assertEquals(TrackingMode.IDLE, w.runtime.mode.value)
            assertTrue(w.scheduler.slots.isEmpty() && w.scheduler.wake == null)
            assertNull(w.now { w.runtime.current() })
            // The gate is free again: a new start works.
            w.listen()
            assertEquals(StartOutcome.Started, w.startTrip(meta))
            assertEquals(1, w.scheduler.slots.size)
        }

    @Test
    fun startWhileARestoredTripRunsHeadlessIsTripActive() =
        runTest {
            val w = World(this)
            w.seedNear()
            w.visibility.visible = true
            w.tracking.autoResult = null // the D11 resume does not answer
            w.now { w.runtime.ensureLoaded() }
            val r = w.now { w.runtime.start(TestData.meta("t2"), Geo.DEST_LAT, Geo.DEST_LNG) }
            assertEquals(StartOutcome.Rejected(StartCodes.TRIP_ACTIVE), r)
            assertEquals("t1", w.store.ledger.activeTripId)
            assertEquals(1, w.scheduler.slots.size)
        }

    @Test
    fun startPublishesTheFirstStateBeforeReturningEvenWithAHungDisk() =
        runTest {
            val holding = HoldingDispatcher(StandardTestDispatcher(testScheduler))
            val w = World(this, io = holding)
            val order = ArrayList<String>()
            w.runtime.addListener { _, v, _, _ -> order += "publish:${v.phase}" }
            holding.hold = true
            w.tracking.autoResult = ForegroundResult.Started
            val r = async { w.runtime.start(meta, Geo.DEST_LAT, Geo.DEST_LNG).also { order += "returned" } }
            var t = 0
            while (!r.isCompleted && t < 15_000) {
                w.advance(100)
                t += 100
            }
            assertEquals(StartOutcome.Started, r.getCompleted())
            assertTrue(t <= 15_000, "start answered within T25's 15 s")
            assertEquals("publish:ACQUIRING", order.first(), "$order")
            assertTrue(w.scheduler.slots.isNotEmpty(), "fallback set although the disk hangs")
            File(outDir(), "T15-tester-start-hung-disk.txt").writeText("startTrip with a hung disk answered after $t ms (virtual)\n")
            holding.release()
            w.settle()
        }

    // ============================================================ F1: boot restore on a slow disk

    /** Boot (alarms gone) with the disk stalled for [stallMs] at BOOT_COMPLETED; returns (slots armed, Interrupted posts). */
    private fun bootOnSlowDisk(scope: kotlinx.coroutines.test.TestScope, stallMs: Long): Pair<Int, Int> {
        val holding = HoldingDispatcher(StandardTestDispatcher(scope.testScheduler))
        val w = World(scope, io = holding)
        w.visibility.visible = false
        val step = EngineStates.drive(meta, w.nowMs - 150_000, 30_000.0, 30)
        val fb = step.state.fallback.targetAtMs!!
        w.store.active = EngineStates.stored(meta, step, ClockAnchor(w.time.wallMs(), w.time.elapsedMs(), 7))
        w.store.ledger = FallbackLedger(1, meta.tripId, 3, FallbackSlotRec(0, 2, fb, w.nowMs), null, null)
        w.time.bootCountValue = 8 // rebooted: every OS alarm is gone
        w.advance(60_000)
        holding.hold = true
        // BootReceiver: ensureLoaded(BOOT) + awaitNotices inside its 8 s goAsync budget.
        val job = scope.async { kotlinx.coroutines.withTimeoutOrNull(RuntimeConstants().receiverBudgetMs) { w.runtime.ensureLoaded(RestoreCause.BOOT); w.runtime.awaitNotices() } }
        w.advance(stallMs)
        holding.release()
        w.advance(10_000)
        check(job.isCompleted)
        return w.scheduler.slots.size to w.notifier.alerts.count { it.first == TripNotice.Interrupted }
    }

    /**
     * Finding F1 (tester, major): after a reboot the BootReceiver is the only entry (no alarm left, no FGS, app not
     * opened). If the disk stalls > 2 × ioBudgetMs at BOOT_COMPLETED (ledger read 1 s, then snapshot read 1 s), the
     * load is abandoned (`loaded` stays false), nothing retries it: no fallback re-armed, no "Interrupted" notice.
     */
    @Test
    fun f1_bootRestoreOnASlowDiskStillRearmsTheFallback() =
        runTest {
            val (slots, shows) = bootOnSlowDisk(this, 2_500)
            assertEquals(1, slots, "fallback re-armed after the disk came back within the receiver budget")
            assertEquals(1, shows, "'Interrupted' shown")
        }

    @Test
    fun f1Numbers() =
        runTest {
            val out = StringBuilder("disk stall at BOOT_COMPLETED (ms) | fallback slots after | Interrupted posts").append('\n')
            for (stall in listOf(500L, 1_500L, 2_100L, 2_500L, 5_000L)) {
                val (slots, shows) = bootOnSlowDisk(this, stall)
                out.append("$stall | $slots | $shows").append('\n')
                if (stall <= 1_500) assertEquals(1 to 1, slots to shows, "stall $stall ms is inside the budget")
            }
            File(outDir(), "T15-tester-f1-boot.txt").writeText(out.toString())
        }

    // ============================================================ F3: "now" ring fails → is the kept fallback near?

    /**
     * Spec §5.2 / L09 / RK-T15-8: when AlarmPort.ringNow throws, the runtime keeps the fallback slot, "≤ P + 30 s in the
     * near zone". The engine does not re-arm its fallback inside the quiet window (fallbackQuietBeforeS) and keeps the
     * start deadline when the first fix already shows P within 30 s (trip started near / inside the alarm zone). Measures
     * how long after the failed ring the user is first woken, for several start distances (15 m/s, fixes every 5 s, the
     * vehicle keeps going; ringNow fails once). Returns (seconds to first successful ring, reason, kept fallback - P s).
     */
    private fun ringFailureCase(scope: kotlinx.coroutines.test.TestScope, startM: Double, deathAfterPersist: Boolean): Triple<Long?, String, Long?> {
        val w = World(scope)
        w.listen()
        w.startTrip(meta)
        w.alarm.throwOnRingNow = IllegalStateException("cannot start the ring")
        var m = startM
        var failedAt: Long? = null
        var keptMinusP: Long? = null
        var guard = 0
        var world = w
        while (guard++ < 2_000) {
            if (failedAt == null) {
                world.fixNorth(m)
                if (world.log.count("ringNow") >= 1) {
                    failedAt = world.nowMs
                    world.alarm.throwOnRingNow = null
                    keptMinusP = world.scheduler.slots.values.minOfOrNull { it.triggerWallMs }?.let { (it - failedAt) / 1000 }
                    if (deathAfterPersist) {
                        // The process dies right after the Step (the pre-ring snapshot is on disk): new process, the app
                        // stays closed; the next OS alarm restores it.
                        world = World(scope, store = w.store.copy(), scheduler = w.scheduler.copy(), alarm = FakeAlarmPort())
                        world.visibility.visible = false
                        world.listen()
                        world.now { world.runtime.onWake() }
                    }
                }
            }
            if (failedAt != null && world.rings() > 0) break
            if (failedAt != null && deathAfterPersist) {
                // Headless: only OS alarms (no FGS, no fixes).
                val next = world.nextOsDeliveryMs(null, null) ?: break
                if (next - scope.testScheduler.currentTime > 4 * 3_600_000L) break
                if (next > scope.testScheduler.currentTime) world.advance(next - scope.testScheduler.currentTime)
                world.deliverDue(null, null)
                continue
            }
            world.advance(5_000)
            world.deliverDue(null, null)
            m -= 75.0
            if (failedAt != null) world.fixNorth(m)
        }
        val first = (world.alarm.ringFallbackCalls.map { it.atWallMs } + world.alarm.ringNowCalls.map { it.atWallMs }).minOrNull()
        val reason = world.alarm.ringNowCalls.firstOrNull()?.reason?.name ?: world.alarm.ringFallbackCalls.firstOrNull()?.let { "FALLBACK" } ?: "-"
        return Triple(first?.let { f -> failedAt?.let { (f - it) / 1000 } }, reason, keptMinusP)
    }

    @Test
    fun f3Numbers() =
        runTest {
            val out = StringBuilder("start (m) | process | woken after failed ring (s) | by | kept fallback - failed ring (s)").append('\n')
            for (death in listOf(false, true)) for (start in listOf(30_000.0, 3_000.0, 1_600.0, 1_300.0, 900.0)) {
                val (s, by, kept) = ringFailureCase(this, start, death)
                out.append("${start.toInt()} | ${if (death) "died after persist" else "alive"} | $s | $by | $kept").append('\n')
                // A trip started far away re-arms its fallback near P: the kept fallback catches a failed ring (L09 intent).
                if (start >= 30_000.0) assertTrue(s != null && s <= 31, "start $start death=$death: woken after $s s")
            }
            File(outDir(), "T15-tester-f3-ring-failure.txt").writeText(out.toString())
        }

    /** Spec §5.2 ("≤ P + 30 s in the near zone"): disabled until F3 is decided (see report). */
    @Test
    fun f3_failedNowRingIsCaughtWithinFallbackLag() =
        runTest {
            for (start in listOf(30_000.0, 1_300.0, 900.0)) for (death in listOf(false, true)) {
                val (s, by, _) = ringFailureCase(this, start, death)
                assertTrue(s != null && s <= 31, "start $start death=$death: woken after $s s by $by")
            }
        }
}
