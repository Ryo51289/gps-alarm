package app.napstop.core.trip.runtime

import app.napstop.core.trip.TripEngine
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.UserAction
import app.napstop.core.trip.UserActionKind
import app.napstop.core.trip.runtime.support.EngineStates
import app.napstop.core.trip.runtime.support.FakeScheduler
import app.napstop.core.trip.runtime.support.FakeStore
import app.napstop.core.trip.runtime.support.TestData
import app.napstop.core.trip.runtime.support.World
import java.io.File
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory

/**
 * Tester T15 (outside the spec list): restore matrix "where the process died" × ledger (readable / unreadable / stale)
 * × snapshot (ok / corrupt / disk hung) × first entry of the new process (fallback alarm, wake alarm, sticky restart,
 * boot, package replaced). The app is never visible (nothing may start the FGS from the background, D9).
 *
 * Safety property asked by the tester question "is there a case where the user is not woken in time?":
 * - while the OS still holds the trip's fallback alarm (process death, not reboot), the user is woken no later than
 *   that fallback alarm + 1 s, whatever the state of the disk, and exactly once;
 * - after a reboot / app update (OS alarms gone) with a readable snapshot, the same holds (RESYNC / FALLBACK_MISSED).
 * A corrupt snapshot after a reboot cannot ring (nothing left to know the trip); then "Interrupted" must be shown if the
 * ledger names the trip. Results also go to build/napstop/T15-tester-restore-matrix.txt.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class T15TesterRestoreMatrixTest {
    enum class Phase { ACQUIRING, FAR, NEAR, SNOOZED }

    enum class LedgerV { OK, UNREADABLE, STALE }

    enum class SnapV { OK, CORRUPT, HUNG }

    enum class Entry { FALLBACK, WAKE, STICKY, BOOT, REPLACED }

    /** Disk dispatcher that parks every task while [hold] (a hung disk in virtual time). */
    class HoldingDispatcher(private val target: CoroutineDispatcher) : CoroutineDispatcher() {
        @Volatile
        var hold = false
        private val queued = ArrayList<Runnable>()

        override fun dispatch(context: kotlin.coroutines.CoroutineContext, block: Runnable) {
            if (hold) synchronized(queued) { queued += block } else target.dispatch(context, block)
        }

        fun release() {
            hold = false
            val q = synchronized(queued) { queued.toList().also { queued.clear() } }
            q.forEach { target.dispatch(kotlin.coroutines.EmptyCoroutineContext, it) }
        }
    }

    private class Result(
        val firstRingWall: Long?,
        val rings: Int,
        val doubles: Int,
        val ignored: Int,
        val starts: Int,
        val interruptedAlerts: Int,
        val interruptedShows: Int,
        val fbWall: Long?,
        val phaseAfter: TripPhase?,
    )

    private val meta = TestData.meta()
    private val lines = ArrayList<String>()

    @TestFactory
    fun restoreMatrix(): List<DynamicTest> {
        val tests = ArrayList<DynamicTest>()
        for (phase in Phase.entries) for (ledger in LedgerV.entries) for (snap in SnapV.entries) for (entry in Entry.entries) {
            tests += DynamicTest.dynamicTest("$phase/$ledger/$snap/$entry") { runCell(phase, ledger, snap, entry) }
        }
        tests += DynamicTest.dynamicTest("write table") { writeTable() }
        return tests
    }

    private fun writeTable() {
        val dir = File(System.getProperty("napstop.outDir") ?: "build/napstop").apply { mkdirs() }
        File(dir, "T15-tester-restore-matrix.txt").writeText(
            "phase/ledger/snapshot/entry | fb (s after death) | first ring (s after death) | rings | doubles | ignored | FGS starts | " +
                "Interrupted shows (alerting) | phase after\n" + lines.joinToString("\n") + "\n",
        )
    }

    /** The engine state on disk when the process died, and the fallback target of that state. */
    private fun stateFor(phase: Phase, t0Wall: Long): app.napstop.core.trip.Step =
        when (phase) {
            Phase.ACQUIRING -> EngineStates.drive(meta, t0Wall, 30_000.0, 0)
            Phase.FAR -> EngineStates.drive(meta, t0Wall - 150_000, 30_000.0, 30)
            Phase.NEAR -> EngineStates.drive(meta, t0Wall - 40_000, 1_900.0, 8)
            Phase.SNOOZED -> {
                val ringing = EngineStates.drive(meta, t0Wall - 51_000, 1_500.0, 10)
                check(ringing.state.phase == TripPhase.ALARMING)
                TripEngine.reduce(ringing.state, UserAction(ringing.state.nowMs + 1_000, UserActionKind.SNOOZE))
            }
        }

    private fun runCell(phase: Phase, ledgerV: LedgerV, snapV: SnapV, entry: Entry) =
        runTest {
            val holding = HoldingDispatcher(StandardTestDispatcher(testScheduler))
            val w = World(this, io = holding)
            w.visibility.visible = false
            val death = w.nowMs
            val step = stateFor(phase, death)
            val fb = step.state.fallback.targetAtMs
            val anchor = ClockAnchor(w.time.wallMs(), w.time.elapsedMs(), 7)
            // Disk as the dead process left it.
            if (snapV != SnapV.CORRUPT) w.store.active = EngineStates.stored(meta, step, anchor)
            val slot = if (ledgerV == LedgerV.STALE) 1 else 0
            when (ledgerV) {
                LedgerV.OK -> w.store.ledger = FallbackLedger(1, meta.tripId, 3, fb?.let { FallbackSlotRec(slot, 2, it, death) }, null, null)
                LedgerV.UNREADABLE -> w.store.failReadLedger = FakeStore.ioFailure()
                LedgerV.STALE -> w.store.ledger = FallbackLedger(1, "old", 9, null, null, null, endedTripIds = listOf("older"))
            }
            // OS alarms the dead process left (trip clock == wall clock here).
            val bootLike = entry == Entry.BOOT
            if (fb != null && !bootLike) w.scheduler.slots[slot] = FakeScheduler.Fallback(slot, meta.tripId, 2, fb, fb, true)
            val wakeAt = step.view.wakeAtMs
            if (wakeAt != null && !bootLike) {
                w.scheduler.wake = FakeScheduler.Wake(w.time.elapsedMs() + (wakeAt - death).coerceAtLeast(0), app.napstop.core.trip.runtime.WakeMechanism.EXACT_IDLE, wakeAt)
            }
            if (bootLike) w.time.bootCountValue = 8
            w.listen()
            if (snapV == SnapV.HUNG) holding.hold = true
            w.advance(1_000)
            var ignored = 0
            val first: suspend () -> Unit =
                when (entry) {
                    Entry.FALLBACK -> {
                        { /* delivered by the OS loop below at its time */ }
                    }
                    Entry.WAKE -> {
                        { w.runtime.onWake(); w.runtime.awaitNotices() }
                    }
                    Entry.STICKY -> {
                        {
                            w.runtime.ensureLoaded()
                            // LocationService: goes foreground only if a trip was loaded, else stopSelf.
                            if (w.runtime.liveTrip() != null) {
                                w.tracking.isForeground = true
                                w.runtime.onForegroundResult(meta.tripId, ForegroundResult.Started)
                            }
                        }
                    }
                    Entry.BOOT -> {
                        { w.runtime.ensureLoaded(RestoreCause.BOOT); w.runtime.awaitNotices() }
                    }
                    Entry.REPLACED -> {
                        { w.runtime.ensureLoaded(RestoreCause.PACKAGE_REPLACED); w.runtime.awaitNotices() }
                    }
                }
            if (entry != Entry.FALLBACK) awaitDone(w) { first() }
            // A hung disk recovers after 20 s.
            if (snapV == SnapV.HUNG) {
                w.advance(20_000)
                holding.release()
                w.settle()
            }
            // The OS from then on: deliver wake-ups and fallback alarms until 3 min after the fallback target.
            val horizon = (fb ?: (death + 3_600_000)) + 180_000
            var guard = 0
            while (guard++ < 2_000) {
                val next = w.nextOsDeliveryMs(null, null) ?: break
                val nextWall = w.startWall + next
                if (nextWall > horizon) break
                val nowV = testScheduler.currentTime
                if (next > nowV) w.advance(next - nowV)
                val f = w.scheduler.nextFallback()
                if (f != null && f.triggerWallMs <= w.time.wallMs()) {
                    w.scheduler.slots.remove(f.slot)
                    val r = awaitDone(w) { w.runtime.onFallbackFired(f.tripId, f.slot, f.generation, f.targetAtMs) }
                    if (r == FallbackFireAction.IGNORED) ignored++
                    continue
                }
                w.deliverDue(null, null)
            }
            val rings = w.alarm.ringNowCalls.map { it.atWallMs } + w.alarm.ringFallbackCalls.map { it.atWallMs }
            val res =
                Result(
                    firstRingWall = rings.minOrNull(),
                    rings = rings.size,
                    doubles = w.alarm.doubleRings,
                    ignored = ignored,
                    starts = w.tracking.starts.size,
                    interruptedAlerts = w.notifier.alerts.count { it.first == TripNotice.Interrupted && it.second },
                    interruptedShows = w.notifier.alerts.count { it.first == TripNotice.Interrupted },
                    fbWall = fb,
                    phaseAfter = w.seen.lastOrNull()?.view?.phase,
                )
            lines +=
                "$phase/$ledgerV/$snapV/$entry | ${fb?.let { (it - death) / 1000 }} | ${res.firstRingWall?.let { (it - death) / 1000 }} | " +
                "${res.rings} | ${res.doubles} | ${res.ignored} | ${res.starts} | ${res.interruptedShows} (${res.interruptedAlerts}) | ${res.phaseAfter}"
            check(phase, ledgerV, snapV, entry, res, w)
        }

    private fun check(phase: Phase, ledgerV: LedgerV, snapV: SnapV, entry: Entry, r: Result, w: World) {
        val cell = "$phase/$ledgerV/$snapV/$entry"
        assertEquals(0, r.starts, "$cell: FGS started from the background (D9)")
        assertEquals(0, r.doubles, "$cell: second sound while ringing")
        assertEquals(0, r.ignored, "$cell: fallback ignored without evidence the trip ended")
        val fb = r.fbWall ?: return
        val osKeptAlarm = entry != Entry.BOOT
        val canKnowTrip = snapV != SnapV.CORRUPT
        if (phase == Phase.ACQUIRING && canKnowTrip) {
            // No fix ever: the engine keeps moving its deadline fallback while it runs (T10, "Chưa có GPS — báo thức chưa
            // hoạt động"); the runtime must keep an OS fallback armed for it.
            assertTrue(w.scheduler.slots.values.any { it.tripId == meta.tripId } || r.rings == 1, "$cell: no fallback armed: ${w.scheduler.slots}")
            return
        }
        if (osKeptAlarm || canKnowTrip) {
            val ring = r.firstRingWall
            assertTrue(ring != null && ring <= fb + 1_000, "$cell: first ring ${ring?.let { it - fb }} ms vs fallback $fb (must be ≤ +1 s)")
            assertEquals(1, r.rings, "$cell: exactly one ring")
        } else if (ledgerV == LedgerV.OK) {
            // Reboot + corrupt snapshot: nothing can ring; the user must at least be told.
            assertTrue(r.interruptedShows >= 1, "$cell: no 'Interrupted' notice although the ledger names the trip")
        }
        if (r.interruptedAlerts > 1) error("$cell: 'Interrupted' alerted ${r.interruptedAlerts} times")
        w.warnings.forEach { assertTrue(!it.contains("16.") && !it.contains("Ga "), "$cell: warning leaks data: $it") }
    }

    /** Runs [block] to completion in virtual time (disk calls may wait for their 1 s budget). */
    private fun <T> awaitDone(w: World, block: suspend () -> T): T {
        val scope: TestScope = w.scope
        val d = scope.async { block() }
        var t = 0
        while (!d.isCompleted && t < 30_000) {
            w.advance(100)
            t += 100
        }
        check(d.isCompleted) { "entry did not complete in 30 s virtual" }
        @OptIn(ExperimentalCoroutinesApi::class)
        return d.getCompleted()
    }
}
