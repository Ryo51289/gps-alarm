package app.napstop.core.trip.runtime

import app.napstop.core.alarm.StopCause
import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.EndReason
import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.FallbackStatus
import app.napstop.core.trip.GpsLost
import app.napstop.core.trip.GpsLostCause
import app.napstop.core.trip.Overshoot
import app.napstop.core.trip.Snoozed
import app.napstop.core.trip.TripEnded
import app.napstop.core.trip.TripOutcome
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.UserActionKind
import app.napstop.core.trip.runtime.support.EngineStates
import app.napstop.core.trip.runtime.support.FakeStore
import app.napstop.core.trip.runtime.support.Geo
import app.napstop.core.trip.runtime.support.RecordingJournal
import app.napstop.core.trip.runtime.support.TestData
import app.napstop.core.trip.runtime.support.World
import app.napstop.core.trip.runtime.support.fixNorth
import app.napstop.core.trip.runtime.support.startTrip
import java.util.concurrent.CountDownLatch
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.currentTime
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** Runtime with fakes: L09–L11, L13, L15, L16, L18, L21, L22, L24–L27, L29, L36–L39, L41. */
@OptIn(ExperimentalCoroutinesApi::class)
class RuntimeUnitTest {
    private val meta = TestData.meta()

    /** South-bound fixes every 5 s at 15 m/s from [fromM] until [toM] metres north of the destination. */
    private fun World.approach(fromM: Double, toM: Double) {
        var m = fromM
        while (m >= toM) {
            fixNorth(m)
            advance(5_000)
            m -= 75.0
        }
    }

    /** The trip is ALARMING (DISTANCE 1 km): fixes from 1.3 km down to 0.9 km. */
    private fun World.alarming() {
        listen()
        assertEquals(StartOutcome.Started, startTrip(meta))
        approach(1_300.0, 900.0)
        assertEquals(TripPhase.ALARMING, seen.last().view.phase)
    }

    private fun alarms(w: World) = w.events.map { it.second }.filterIsInstance<Alarm>()

    // ---------------------------------------------------------------- start (L13, L15, L16)

    @Test
    fun l13_secondStartWhileTheFirstIsPendingIsRefused() =
        runTest {
            val w = World(this)
            w.tracking.autoResult = null
            val first = async { w.runtime.start(meta, Geo.DEST_LAT, Geo.DEST_LNG) }
            runCurrent()
            assertEquals(TrackingMode.STARTING, w.runtime.mode.value)
            val second = w.now { w.runtime.start(TestData.meta("t2"), Geo.DEST_LAT, Geo.DEST_LNG) }
            assertEquals(StartOutcome.Rejected(StartCodes.TRIP_ACTIVE), second)
            assertEquals(1, w.tracking.starts.size)
            w.tracking.isForeground = true
            w.runtime.onForegroundResult("t1", ForegroundResult.Started)
            runCurrent()
            assertEquals(StartOutcome.Started, first.await())
            // Started: a third start is trip-active too.
            assertEquals(StartOutcome.Rejected(StartCodes.TRIP_ACTIVE), w.now { w.runtime.start(TestData.meta("t3"), 1.0, 1.0) })
        }

    @Test
    fun l15_stateIsPublishedBeforeStartReturns() =
        runTest {
            val w = World(this)
            val order = ArrayList<String>()
            w.runtime.addListener { _, view, _, _ -> order += "publish:${view.phase}" }
            w.tracking.autoResult = ForegroundResult.Started
            launch {
                val r = w.runtime.start(meta, Geo.DEST_LAT, Geo.DEST_LNG)
                order += "returned:$r"
            }
            runCurrent()
            assertEquals("publish:ACQUIRING", order.first())
            assertTrue(order.indexOf("returned:Started") > 0)
            assertEquals("t1", w.store.ledger.activeTripId)
            assertEquals(1, w.log.count("setFallback"))
            assertEquals(1, w.log.count("setWake"))
            assertNotNull(w.store.active, "first snapshot written")
            assertEquals("Ga Đông Hà", w.store.ringConfig?.destinationName)
            assertEquals(TrackingMode.TRACKING_FGS, w.runtime.mode.value)
            assertNotNull(w.location.spec, "FLP requested (DENSE)")
        }

    private class ForegroundServiceStartNotAllowedException : IllegalStateException()

    private fun TestScope.refused(setup: (World) -> Unit): Pair<World, StartOutcome> {
        val w = World(this)
        setup(w)
        val r = w.now { w.runtime.start(meta, Geo.DEST_LAT, Geo.DEST_LNG) }
        return w to r
    }

    @Test
    fun l16_refusedStartsCommitNothing() =
        runTest {
            val cases =
                listOf<Pair<(World) -> Unit, StartOutcome>>(
                    { w: World -> w.env.access = w.env.access.copy(fineGranted = false, servicesEnabled = false) } to
                        StartOutcome.Rejected(StartCodes.PERMISSION_MISSING, null, listOf("precise", "locationServices")),
                    { w: World -> w.env.access = w.env.access.copy(fineGranted = false, coarseGranted = false) } to
                        StartOutcome.Rejected(StartCodes.PERMISSION_MISSING, null, listOf("location")),
                    { w: World -> w.visibility.visible = false } to StartOutcome.Rejected(StartCodes.NOT_FOREGROUND),
                    { w: World -> w.env.access = w.env.access.copy(playServicesAvailable = false) } to
                        StartOutcome.Rejected(StartCodes.START_FAILED, "PlayServicesUnavailable"),
                    { w: World -> w.tracking.throwOnStart = ForegroundServiceStartNotAllowedException() } to
                        StartOutcome.Rejected(StartCodes.START_FAILED, "ForegroundServiceStartNotAllowedException"),
                    { w: World -> w.tracking.autoResult = ForegroundResult.Failed("SecurityException") } to
                        StartOutcome.Rejected(StartCodes.START_FAILED, "SecurityException"),
                )
            for ((setup, expected) in cases) {
                val (w, r) = refused(setup)
                assertEquals(expected, r)
                assertNothingCommitted(w)
            }
            // Timeout: no answer from the service within 5 s.
            val w = World(this)
            w.tracking.autoResult = null
            val r = async { w.runtime.start(meta, Geo.DEST_LAT, Geo.DEST_LNG) }
            w.advance(5_001)
            assertEquals(StartOutcome.Rejected(StartCodes.START_FAILED, "ForegroundTimeout"), r.await())
            assertEquals(1, w.tracking.stops)
            assertNothingCommitted(w)
            // Invalid config caught by the engine (C11): field and rule only.
            val (w2, r2) = refused {}
            assertEquals(StartOutcome.Started, r2)
            val w3 = World(this)
            val bad = w3.now { w3.runtime.start(TestData.meta("t9", distanceM = 50), 1.0, 1.0) }
            assertEquals(StartOutcome.Rejected(StartCodes.INVALID_CONFIG, "distanceThresholdM: out of range"), bad)
            assertNothingCommitted(w3)
            assertNotNull(w2.store.active)
        }

    private fun assertNothingCommitted(w: World) {
        assertEquals(0, w.store.writeActiveCalls, "no snapshot")
        assertTrue(w.scheduler.slots.isEmpty() && w.scheduler.wake == null, "no alarm")
        assertEquals(TrackingMode.IDLE, w.runtime.mode.value)
        assertNull(w.store.ledger.activeTripId)
    }

    // ---------------------------------------------------------------- effects (L09–L11)

    @Test
    fun l09_ringFailureKeepsTheFallbackSlots() =
        runTest {
            val w = World(this)
            w.listen()
            w.startTrip(meta)
            w.approach(1_300.0, 1_075.0)
            assertTrue(w.scheduler.slots.isNotEmpty())
            w.alarm.throwOnRingNow = IllegalStateException("secret 16.0")
            w.approach(1_000.0, 900.0)
            val last = w.seen.first { s -> s.events.any { it is Alarm } }
            assertEquals(TripPhase.ALARMING, last.view.phase, "published anyway")
            assertTrue(last.events.any { it is Alarm && it.ringNow })
            // Designer "sau test" G1/G2: the slot left is the ring guard, ≤ now + fallbackLagS — not just "a slot".
            val ringWall = last.atMs
            val slot = w.scheduler.slots.values.minByOrNull { it.triggerWallMs }
            assertNotNull(slot, "fallback slot kept")
            assertTrue(slot!!.triggerWallMs <= ringWall + EngineParams().fallbackLagS * 1000L, "guard at ${slot.triggerWallMs - ringWall} ms after the failed ring")
            assertEquals(SlotKind.GUARD, slot.kind)
            assertTrue("ring failed (IllegalStateException)" in w.warnings, "${w.warnings}")
            assertTrue(w.warnings.none { it.contains("secret") })
        }

    @Test
    fun l10_snoozeStopsTheRingAndSetsTheSnoozeFallback() =
        runTest {
            val w = World(this)
            w.alarming()
            w.now { w.runtime.userAction("t1", UserActionKind.SNOOZE) }
            val sn = w.events.map { it.second }.filterIsInstance<Snoozed>().single()
            assertEquals(StopCause.SNOOZED, w.alarm.stops.last())
            val slot = w.scheduler.slots.values.single()
            assertEquals(sn.untilMs + EngineParams().fallbackLagS * 1000L, slot.targetAtMs)
            assertEquals(1, w.store.ringConfig!!.snoozeCount)
            // Snooze over: SNOOZE_END rings again (second ringNow, valid after Snoozed).
            w.advance(61_000)
            assertEquals(AlarmReason.SNOOZE_END, alarms(w).last().reason)
            assertEquals(2, w.alarm.ringNowCalls.size)
        }

    @Test
    fun l11_tripEndCleansUpInOrder() =
        runTest {
            val w = World(this)
            w.alarming()
            w.log.ops.clear()
            w.now { w.runtime.userAction("t1", UserActionKind.DISMISS) }
            val ended = w.events.map { it.second }.filterIsInstance<TripEnded>().single()
            assertEquals(TripOutcome.ON_TIME, ended.outcome)
            assertEquals(StopCause.TRIP_ENDED, w.alarm.stops.last())
            assertTrue(w.scheduler.slots.isEmpty() && w.scheduler.wake == null)
            val ops = w.log.ops
            assertTrue(ops.indexOf("writeFinished") in 0 until ops.indexOf("deleteActive"), "$ops")
            assertTrue("tracking.stop" in ops && "location.stop" in ops)
            assertEquals(TrackingMode.IDLE, w.runtime.mode.value)
            assertNull(w.store.active)
            assertNull(w.store.ringConfig)
            assertNull(w.store.ledger.activeTripId)
            assertEquals(listOf("t1"), w.alarm.cleared)
            assertEquals(ended.outcome, w.now { w.runtime.pendingFinished() }.single().outcome)
            // Nothing for the trip after TripEnded.
            val n = w.seen.size
            w.advance(120_000)
            w.runtime.requestReplay()
            w.settle()
            assertEquals(n, w.seen.size)
            assertNull(w.now { w.runtime.current() })
            w.now { w.runtime.ackFinished(listOf("t1")) }
            assertTrue(w.now { w.runtime.pendingFinished() }.isEmpty())
        }

    @Test
    fun finishedWriteFailureKeepsTheRecordInMemoryAndRetries() =
        runTest {
            val w = World(this)
            w.alarming()
            w.store.failWriteFinished = FakeStore.ioFailure()
            w.now { w.runtime.userAction("t1", UserActionKind.DISMISS) }
            assertEquals(1, w.now { w.runtime.pendingFinished() }.size, "in memory")
            w.store.failWriteFinished = null
            assertEquals(1, w.now { w.runtime.pendingFinished() }.size)
            assertEquals(1, w.store.finished.size, "written on retry")
        }

    // ---------------------------------------------------------------- writer (L18)

    @Test
    fun l18_persistNowIsBoundedAndTheWriteCompletesLater() =
        runTest {
            val store = FakeStore()
            store.writeGate = CountDownLatch(1)
            val warnings = ArrayList<String>()
            val writerScope = CoroutineScope(Dispatchers.IO)
            val writer = SnapshotWriter(writerScope, Dispatchers.IO, store, 5_000, { 0L }, { warnings += it })
            val trip = EngineStates.stored(meta, EngineStates.drive(meta, 1, 30_000.0, 3), ClockAnchor(1, 2, 3))
            val t0 = currentTime
            val ok = writer.persistNow(trip, 300)
            assertFalse(ok)
            assertEquals(300, currentTime - t0, "returned after the 300 ms budget (virtual time)")
            store.writeGate!!.countDown()
            withContext(Dispatchers.Default) { withTimeout(5_000) { while (store.writeActiveOk == 0) delay(10) } }
            assertNotNull(store.active, "the write finished after the budget")
            writerScope.coroutineContext[kotlinx.coroutines.Job]?.cancel()
        }

    // ---------------------------------------------------------------- restore (L21, L22, L37)

    private fun World.seedStored(step: app.napstop.core.trip.Step, anchor: ClockAnchor = ClockAnchor(startWall, elapsedBase, 7)) {
        store.active = EngineStates.stored(meta, step, anchor)
        store.ledger = FallbackLedger(1, meta.tripId, 3, step.state.fallback.targetAtMs?.let { FallbackSlotRec(0, 2, it, startWall) }, null, null)
        step.state.fallback.targetAtMs?.let { scheduler.slots[0] = app.napstop.core.trip.runtime.support.FakeScheduler.Fallback(0, meta.tripId, 2, it, it, true) }
    }

    @Test
    fun l21_pendingRestoreSetsTheSameFallbackAgain() =
        runTest {
            val w = World(this)
            val step = EngineStates.drive(meta, w.startWall, 30_000.0, 30)
            val fb = step.state.fallback.targetAtMs!!
            w.seedStored(step)
            w.listen()
            w.advance(10_000)
            w.now { w.runtime.ensureLoaded() }
            val ops = w.log.ops
            assertTrue(ops.indexOf("setFallback(1,$fb)") in 0 until ops.indexOf("cancelFallback(0)"), "$ops")
            assertEquals(FallbackStatus.CONFIRMED, w.seen.last().view.fallbackStatus)
            assertEquals(TrackingMode.HEADLESS, w.runtime.mode.value)
            // Review T15 #1: no "Interrupted" until FGS_START_TIMEOUT_MS passed without the service coming back.
            assertFalse("show:Interrupted" in w.notifier.history)
            w.advance(5_000)
            assertEquals(1, w.notifier.history.count { it == "show:Interrupted" })
        }

    @Test
    fun l22_restoreRingsWhenTheEngineRingNeverReachedTheSpeaker() =
        runTest {
            // G3: ALARMING, alarmRinging, and the port has no trace of any ring → ring now (no AlarmSilenced).
            val w = World(this)
            val near = EngineStates.drive(meta, w.startWall, 1_500.0, 10)
            w.seedStored(near)
            w.listen()
            w.advance(60_000)
            w.now { w.runtime.ensureLoaded() }
            assertEquals(1, w.alarm.ringNowCalls.size)
            assertEquals(near.state.alarm.lastReason, w.alarm.ringNowCalls.single().reason)
            assertTrue(w.seen.last().view.alarmRinging)
            assertTrue(w.scheduler.slots.values.any { it.kind == SlotKind.GUARD && it.triggerWallMs <= w.nowMs + 30_000 }, "with a guard")
        }

    @Test
    fun l22_restoreSendsAlarmSilencedWhenTheRingStoppedMeanwhile() =
        runTest {
            val w = World(this)
            val near = EngineStates.drive(meta, w.startWall, 1_500.0, 10)
            assertEquals(TripPhase.ALARMING, near.state.phase)
            assertTrue(near.view.alarmRinging)
            w.seedStored(near)
            val silencedWall = w.startWall + 55_000
            w.alarm.facts["t1"] = app.napstop.core.trip.runtime.support.FakeAlarmPort.Facts().apply { silencedAt = silencedWall }
            w.listen()
            w.advance(60_000)
            w.now { w.runtime.ensureLoaded() }
            assertTrue(w.alarm.ringNowCalls.isEmpty())
            assertFalse(w.seen.last().view.alarmRinging)
            assertFalse(TripNotice.Interrupted in w.notifier.shown, "ringing phase: no interrupted notice")
        }

    @Test
    fun l37_bootRestoreWithTheFallbackPassed() =
        runTest {
            // fb passed: FALLBACK_MISSED rings now; no "interrupted" (an alarm is on).
            val w = World(this)
            w.time.bootCountValue = 8
            val step = EngineStates.drive(meta, w.startWall, 30_000.0, 30)
            w.seedStored(step)
            w.scheduler.slots.clear() // a reboot cleared the alarms
            w.listen()
            w.advance(step.state.fallback.targetAtMs!! - w.startWall + 60_000)
            w.now { w.runtime.ensureLoaded(RestoreCause.BOOT) }
            assertEquals(AlarmReason.FALLBACK_MISSED, w.alarm.ringNowCalls.single().reason)
            assertFalse(TripNotice.Interrupted in w.notifier.shown)
        }

    @Test
    fun l37_bootRestoreWithTheFallbackAhead() =
        runTest {
            // fb ahead: RESYNC sets a new fallback; "interrupted"; anchor replaced (BOOT_COUNT 7 → 8).
            val w = World(this)
            w.time.bootCountValue = 8
            val step = EngineStates.drive(meta, w.startWall, 30_000.0, 30)
            w.seedStored(step)
            w.scheduler.slots.clear()
            w.listen()
            w.now { w.runtime.ensureLoaded(RestoreCause.PROCESS_START) } // BOOT from the anchor check
            assertTrue(w.alarm.ringNowCalls.isEmpty())
            assertEquals(1, w.log.count("setFallback"))
            assertTrue(TripNotice.Interrupted in w.notifier.shown)
            w.advance(61_000)
            assertEquals(8, w.store.active!!.anchor.bootCount)
        }

    // ---------------------------------------------------------------- fallback receiver (L24–L27)

    @Test
    fun l24_oldSlotFiringWhileReschedulingRingsOnce() =
        runTest {
            val w = World(this)
            w.listen()
            w.startTrip(meta)
            w.fixNorth(30_000.0)
            val a = w.scheduler.slots.values.single()
            // The old slot A fires between setFallback(B) and cancelFallback(A).
            w.scheduler.afterSetFallback = { b ->
                w.scheduler.afterSetFallback = null
                assertTrue(b.slot != a.slot)
                launch { w.runtime.onFallbackFired(a.tripId, a.slot, a.generation, a.targetAtMs) }
            }
            w.runtime.onTimeChanged() // re-sets the current fallback in the other slot
            w.settle()
            assertEquals(1, w.alarm.ringFallbackCalls.size)
            assertEquals(0, w.alarm.doubleRings)
            assertTrue(w.scheduler.slots.isEmpty(), "B cancelled by the receiver: ${w.scheduler.slots}")
            assertEquals(AlarmReason.FALLBACK, alarms(w).single().reason)
            assertFalse(alarms(w).single().ringNow)
            assertEquals(TripPhase.ALARMING, w.seen.last().view.phase)
        }

    @Test
    fun l25_fallbackWhileANowRingIsOnDoesNotRingAgain() =
        runTest {
            val w = World(this)
            w.alarming()
            val n = alarms(w).size
            // GUARD slot while live: dropped — no FallbackFired Step, no lastFired. (A slot already ≤ now + 30 s is kept
            // and relabelled GUARD in the ledger; the receiver takes the kind from there.)
            assertEquals(SlotKind.GUARD, w.store.ledger.current?.kind)
            val guard = w.scheduler.slots.values.single()
            val steps = w.seen.size
            val fired = w.store.ledger.lastFired
            w.scheduler.slots.remove(guard.slot)
            assertEquals(FallbackFireAction.SUPPRESSED_LIVE, w.now { w.runtime.onFallbackFired("t1", guard.slot, guard.generation, guard.targetAtMs) })
            assertEquals(steps, w.seen.size)
            assertEquals(fired, w.store.ledger.lastFired)
            // ENGINE slot while the "now" ring is live: FallbackFired as before (obligation 5), no sound.
            val r = w.now { w.runtime.onFallbackFired("t1", 5, 999, w.nowMs, SlotKind.ENGINE) }
            assertEquals(FallbackFireAction.ALREADY_RINGING, r)
            assertTrue(w.alarm.ringFallbackCalls.isEmpty())
            assertEquals(n, alarms(w).size, "no new Alarm in ALARMING")
            assertEquals(1, w.alarm.ringNowCalls.size)
        }

    @Test
    fun l26_alarmOfAnEndedTripIsIgnored() =
        runTest {
            // Orchestrator decision (review T15 #2): ignore only with evidence — the ledger lists the trip as ended.
            val w = World(this)
            w.store.ledger = FallbackLedger(1, null, 9, null, null, null, endedTripIds = listOf("x", "old"))
            val r = w.now { w.runtime.onFallbackFired("old", 1, 4, w.nowMs) }
            assertEquals(FallbackFireAction.IGNORED, r)
            assertTrue(w.alarm.ringFallbackCalls.isEmpty())
            assertEquals("cancelFallback(1)", w.log.ops.last())
        }

    @Test
    fun l26_alarmOfAnotherTripWhileATripRunsIsIgnored() =
        runTest {
            val w = World(this)
            w.listen()
            w.startTrip(meta)
            val r = w.now { w.runtime.onFallbackFired("old", 1, 4, w.nowMs) }
            assertEquals(FallbackFireAction.IGNORED, r)
            assertTrue(w.alarm.ringFallbackCalls.isEmpty())
        }

    @Test
    fun uncertainLedgerRings() =
        runTest {
            // activeTripId of another trip on disk (stale after a failed write), runtime not loaded: no evidence → ring.
            val w = World(this)
            w.store.ledger = FallbackLedger(1, "other", 9, null, null, null)
            assertEquals(FallbackFireAction.RANG, w.now { w.runtime.onFallbackFired("t7", 1, 4, w.nowMs) })
            // Unreadable ledger: ring.
            val w2 = World(this)
            w2.store.failReadLedger = FakeStore.ioFailure()
            assertEquals(FallbackFireAction.RANG, w2.now { w2.runtime.onFallbackFired("t7", 0, 1, w2.nowMs) })
            assertEquals(1, w2.alarm.ringFallbackCalls.size)
        }

    @Test
    fun ledgerWriteFailedAtStartThenProcessDiesThenFallbackRings() =
        runTest {
            val w = World(this)
            w.store.failWriteLedger = FakeStore.ioFailure()
            w.listen()
            w.startTrip(meta)
            w.fixNorth(30_000.0)
            w.advance(61_000)
            assertNull(w.store.ledger.activeTripId, "the ledger never got the trip")
            val slot = w.scheduler.slots.values.single()
            // Process death: a new runtime on the same disk and alarms.
            val w2 = World(this, store = w.store, scheduler = w.scheduler, alarm = w.alarm)
            w2.listen()
            val r = w2.now { w2.runtime.onFallbackFired(slot.tripId, slot.slot, slot.generation, slot.targetAtMs) }
            assertEquals(FallbackFireAction.RANG, r)
            assertEquals(1, w.alarm.ringFallbackCalls.size)
            assertEquals(TripPhase.ALARMING, w2.seen.last().view.phase, "the restored trip learnt that the fallback rang")
        }

    @Test
    fun l27_corruptSnapshotStillRingsWithGenericCopy() =
        runTest {
            val w = World(this)
            w.store.active = null // corrupt → deleted by the real store
            w.store.ledger = FallbackLedger(1, "X", 9, FallbackSlotRec(0, 8, 5, 5), null, null)
            val r = w.now { w.runtime.onFallbackFired("X", 0, 8, 5) }
            assertEquals(FallbackFireAction.RANG, r)
            assertNull(w.alarm.ringFallbackCalls.single().destinationName)
            assertTrue(TripNotice.Interrupted in w.notifier.shown)
            assertNull(w.notifier.names.last())
            assertEquals(8, w.store.ledger.lastFired!!.generation)
        }

    @Test
    fun fallbackWhenTheProcessWasDeadRestoresRang() =
        runTest {
            val w = World(this)
            val step = EngineStates.drive(meta, w.startWall, 30_000.0, 30)
            w.seedStored(step)
            w.listen()
            val fb = step.state.fallback.targetAtMs!!
            w.advance(fb - w.startWall)
            val r = w.now { w.runtime.onFallbackFired("t1", 0, 2, fb) }
            assertEquals(FallbackFireAction.RANG, r)
            assertEquals(1, w.alarm.ringFallbackCalls.size)
            val a = alarms(w).single()
            assertEquals(AlarmReason.FALLBACK, a.reason)
            assertFalse(a.ringNow)
            assertEquals(TripPhase.ALARMING, w.seen.last().view.phase)
            assertTrue(w.scheduler.slots.isEmpty())
        }

    // ---------------------------------------------------------------- wake (L29), ADR-001 (L36)

    @Test
    fun l29_tickCarriesTheDeliveryTime() =
        runTest {
            val journal = RecordingJournal()
            val w = World(this, constants = RuntimeConstants(awakeTickMaxMs = null), journal = journal)
            w.listen()
            w.startTrip(meta)
            val wake = w.scheduler.wake!!
            val wTrip = w.startWall + (wake.triggerElapsedMs - w.elapsedBase)
            w.advance(wake.triggerElapsedMs - w.elapsedBase + 3_000)
            w.scheduler.consumeWake(w.time.elapsedMs())
            // F5: the receiver passes the extras of the alarm that fired.
            w.now { w.runtime.onWake(wake.wakeAtMs, wake.triggerWallMs) }
            assertEquals(wTrip + 3_000, w.seen.last().view.atMs)
            assertEquals(3_000L, journal.lines.last { it.ev == "wake_fire" }.fields["lateMs"])
        }

    @Test
    fun l36_nothingStartsTheLocationServiceFromTheBackground() =
        runTest {
            val w = World(this)
            val step = EngineStates.drive(meta, w.startWall, 30_000.0, 30)
            w.seedStored(step)
            w.visibility.visible = false
            w.listen()
            w.now { w.runtime.ensureLoaded() }
            assertEquals(TrackingMode.HEADLESS, w.runtime.mode.value)
            w.now { w.runtime.onWake() }
            w.now { w.runtime.onFallbackFired("t1", 5, 99, w.nowMs + 1_000_000) }
            w.now { w.runtime.onRingEvent(RingEvent("t1", RingEventKind.SILENCED, w.nowMs)) }
            w.now { w.runtime.onAppVisible() } // not visible: no start
            assertTrue(w.tracking.starts.isEmpty())
            val boot = World(this, store = w.store.copy())
            boot.visibility.visible = false
            boot.now { boot.runtime.ensureLoaded(RestoreCause.BOOT) }
            assertTrue(boot.tracking.starts.isEmpty())
            // Visible: D11 resumes the FGS once.
            val w2 = World(this, store = w.store.copy())
            w2.listen()
            w2.visibility.visible = false
            w2.now { w2.runtime.ensureLoaded() }
            w2.visibility.visible = true
            w2.tracking.isForeground = false
            w2.now { w2.runtime.onAppVisible() }
            assertEquals(listOf("t1" to StartReason.APP_VISIBLE), w2.tracking.starts)
            assertEquals(TrackingMode.TRACKING_FGS, w2.runtime.mode.value)
            w2.advance(10_000)
            assertFalse("show:Interrupted" in w2.notifier.history, "app open resumed the FGS: no transient notice")
            assertNotNull(w2.location.spec)
            w2.now { w2.runtime.onAppVisible() }
            assertEquals(1, w2.tracking.starts.size)
        }

    @Test
    fun foregroundLostGoesHeadlessAndTapResumes() =
        runTest {
            val w = World(this)
            w.listen()
            w.startTrip(meta)
            w.fixNorth(30_000.0)
            w.runtime.onForegroundLost()
            w.settle()
            assertEquals(TrackingMode.HEADLESS, w.runtime.mode.value)
            assertNull(w.location.spec)
            assertFalse("show:Interrupted" in w.notifier.history, "deferred: a sticky restart may follow")
            w.advance(5_000)
            assertTrue(TripNotice.Interrupted in w.notifier.shown)
            w.tracking.isForeground = false
            w.now { w.runtime.onNotificationResume("t1") }
            assertEquals(StartReason.NOTIFICATION_TAP, w.tracking.starts.last().second)
            assertEquals(TrackingMode.TRACKING_FGS, w.runtime.mode.value)
        }

    // ---------------------------------------------------------------- ring events (L38, L39)

    @Test
    fun l38_ringEvents() =
        runTest {
            val w = World(this)
            w.alarming()
            val n = w.seen.size
            w.now { w.runtime.onRingEvent(RingEvent("other", RingEventKind.SILENCED, w.nowMs)) }
            assertEquals(n, w.seen.size, "wrong tripId: no-op")
            w.now { w.runtime.onRingEvent(RingEvent("t1", RingEventKind.SNOOZED, w.nowMs)) }
            assertTrue(w.seen.drop(n).any { s -> s.events.any { it is Snoozed } }, "SNOOZED → UserAction(SNOOZE)")
            w.advance(61_000) // SNOOZE_END rings again
            assertTrue(w.seen.last().view.alarmRinging)
            val m = w.seen.size
            w.now { w.runtime.onRingEvent(RingEvent("t1", RingEventKind.SILENCED, w.nowMs - 1_000)) }
            assertTrue(w.seen.size > m)
            assertFalse(w.seen.last().view.alarmRinging, "SILENCED → AlarmSilenced")
            w.now { w.runtime.onRingEvent(RingEvent("t1", RingEventKind.DISMISSED, w.nowMs)) }
            assertTrue(w.seen.last().events.any { it is TripEnded }, "DISMISSED → UserAction(DISMISS)")
            assertEquals(listOf("t1"), w.alarm.cleared)
        }

    @Test
    fun l39_overshootAfterTheAlarmStoppedRingsAgain() =
        runTest {
            val w = World(this)
            w.listen()
            w.startTrip(meta)
            // South-bound at 15 m/s through the destination, one fix per 5 s.
            var m = 4_000.0
            while (alarms(w).isEmpty()) {
                w.fixNorth(m)
                w.advance(5_000)
                m -= 75.0
            }
            assertEquals(AlarmReason.DISTANCE, alarms(w).single().reason)
            w.alarm.silence("t1", w.nowMs)
            w.now { w.runtime.onRingEvent(RingEvent("t1", RingEventKind.SILENCED, w.nowMs)) }
            var guard = 0
            while (w.events.none { it.second is Overshoot } && guard++ < 400) {
                w.fixNorth(m)
                w.advance(5_000)
                m -= 75.0
            }
            assertEquals(AlarmReason.OVERSHOOT, alarms(w).last().reason)
            assertTrue(alarms(w).last().ringNow)
            assertEquals(2, w.alarm.ringNowCalls.size)
            assertEquals(0, w.alarm.doubleRings)
        }

    // ---------------------------------------------------------------- device state (L41)

    @Test
    fun l41_batteryAndLocationInputsOnlyOnChange() =
        runTest {
            val journal = RecordingJournal()
            val w = World(this, journal = journal)
            w.env.batteryReading = BatteryReading(80, false)
            w.listen()
            w.startTrip(meta)
            fun inputs(name: String) = journal.lines.count { it.ev == "step" && it.fields["input"] == name }
            assertEquals(1, inputs("BatterySample"))
            w.env.batteryReading = BatteryReading(79, false)
            w.runtime.onDeviceStateChanged()
            w.settle()
            w.runtime.onDeviceStateChanged()
            w.settle()
            assertEquals(2, inputs("BatterySample"))
            assertEquals(79, w.seen.last().view.batteryPct)
            w.env.access = w.env.access.copy(servicesEnabled = false)
            w.runtime.onDeviceStateChanged()
            w.settle()
            assertTrue(w.events.any { (it.second as? GpsLost)?.cause == GpsLostCause.SERVICES_OFF })
            assertTrue(TripNotice.ServicesOff in w.notifier.shown)
            w.env.access = w.env.access.copy(servicesEnabled = true)
            w.runtime.onDeviceStateChanged()
            w.settle()
            assertEquals(2, inputs("LocationAvailability"))
            w.env.access = w.env.access.copy(fineGranted = false)
            w.runtime.onDeviceStateChanged()
            w.settle()
            assertEquals(2, inputs("LocationAvailability"), "coarse only: no PERMISSION_REVOKED")
            w.env.access = w.env.access.copy(fineGranted = false, coarseGranted = false)
            w.runtime.onDeviceStateChanged()
            w.settle()
            assertEquals(3, inputs("LocationAvailability"), "neither fine nor coarse: PERMISSION_REVOKED")
        }

    @Test
    fun listenerThrowingDoesNotFailTheCall() =
        runTest {
            val w = World(this)
            w.runtime.addListener { _, _, _, _ -> throw IllegalStateException("16.0,108.0") }
            w.listen()
            assertEquals(StartOutcome.Started, w.startTrip(meta))
            w.fixNorth(800.0)
            w.now { w.runtime.userAction("t1", UserActionKind.DISMISS) }
            assertTrue(w.seen.last().events.any { it is TripEnded }, "the other listener got everything")
            assertTrue(w.warnings.isNotEmpty() && w.warnings.all { it == "listener failed (IllegalStateException)" })
        }

    @Test
    fun trackingNotificationIsThrottled() =
        runTest {
            val w = World(this)
            w.listen()
            w.startTrip(meta)
            repeat(10) { i ->
                w.fixNorth(30_000.0 - i * 75.0)
                w.advance(5_000)
            }
            // 50 s of fixes every 5 s, distance changes every fix: ≤ 1 update per 15 s (+ the first).
            assertTrue(w.tracking.notices.size in 2..5, "${w.tracking.notices.size}")
        }

    // ---------------------------------------------------------------- round 2 (review T15 #1, #3, #4, #5; L20 b', L45)

    @Test
    fun stickyRestartThatSucceedsNeverPostsInterrupted() =
        runTest {
            val w = World(this)
            w.seedStored(EngineStates.drive(meta, w.startWall, 30_000.0, 30))
            w.listen()
            w.advance(10_000)
            w.now { w.runtime.ensureLoaded() } // LocationService.onStartCommand(null)
            assertEquals(TrackingMode.HEADLESS, w.runtime.mode.value)
            w.advance(400)
            w.tracking.isForeground = true
            w.runtime.onForegroundResult("t1", ForegroundResult.Started)
            w.advance(10_000)
            assertEquals(TrackingMode.TRACKING_FGS, w.runtime.mode.value)
            assertFalse("show:Interrupted" in w.notifier.history, "${w.notifier.history}")
        }

    @Test
    fun stickyRestartThatFailsPostsInterruptedAtOnceAndOnlyOnce() =
        runTest {
            val w = World(this)
            w.seedStored(EngineStates.drive(meta, w.startWall, 30_000.0, 30))
            w.listen()
            w.now { w.runtime.ensureLoaded() }
            w.runtime.onForegroundResult("t1", ForegroundResult.Failed("SecurityException"))
            w.settle()
            assertEquals(1, w.notifier.history.count { it == "show:Interrupted" })
            w.advance(10_000)
            w.now { w.runtime.onWake() }
            assertEquals(1, w.notifier.history.count { it == "show:Interrupted" })
        }

    @Test
    fun receiverOnlyProcessShowsInterruptedAfterTheTimeout() =
        runTest {
            val w = World(this)
            w.seedStored(EngineStates.drive(meta, w.startWall, 30_000.0, 30))
            w.listen()
            val waited = async { w.runtime.onWake(); w.runtime.awaitNotices() }
            runCurrent()
            assertFalse("show:Interrupted" in w.notifier.history)
            w.advance(5_000)
            waited.await()
            assertEquals(1, w.notifier.history.count { it == "show:Interrupted" })
        }

    @Test
    fun failedFallbackRingIsNotReportedAsRingingAndIsRetried() =
        runTest {
            // Process alive (trip loaded): the fallback ring fails → engine told it is silent, guard + in-process retry.
            val w = World(this)
            val step = EngineStates.drive(meta, w.startWall, 30_000.0, 30)
            w.seedStored(step)
            w.listen()
            w.now { w.runtime.ensureLoaded() }
            val fb = step.state.fallback.targetAtMs!!
            w.advance(fb - w.startWall)
            w.alarm.ringFallbackFailures = 1
            val r = w.now { w.runtime.onFallbackFired("t1", 0, 2, fb) }
            assertEquals(FallbackFireAction.RING_FAILED, r)
            assertEquals(TripPhase.ALARMING, w.seen.last().view.phase)
            assertFalse(w.seen.last().view.alarmRinging, "nothing sounds: the engine must not think it rings")
            val guard = w.scheduler.slots.values.single()
            assertEquals(SlotKind.GUARD, guard.kind)
            assertTrue(guard.triggerWallMs <= w.nowMs + 30_000, "G2: a guard slot ≤ now + fallbackLagS")
            // In-process retry at a later Step, ≥ 30 s on (the guard slot is the path when the process sleeps).
            w.advance(31_000)
            w.now { w.runtime.onWake() }
            assertEquals(1, w.alarm.ringFallbackCalls.size, "retried and rang")
            assertTrue(w.seen.last().view.alarmRinging)
            assertEquals(0, w.alarm.doubleRings, "${w.log.ops}")
        }

    @Test
    fun failedFallbackRingInAFreshProcessIsRungAgainByTheRestore() =
        runTest {
            // Process dead: the receiver's ring fails, the load that follows sees "ALARMING, never rang" → G3 rings now.
            val w = World(this)
            val step = EngineStates.drive(meta, w.startWall, 30_000.0, 30)
            w.seedStored(step)
            w.listen()
            val fb = step.state.fallback.targetAtMs!!
            w.advance(fb - w.startWall)
            w.alarm.ringFallbackFailures = 1
            assertEquals(FallbackFireAction.RING_FAILED, w.now { w.runtime.onFallbackFired("t1", 0, 2, fb) })
            assertEquals(1, w.alarm.ringNowCalls.size, "G3 ring at restore")
            assertTrue(w.seen.last().view.alarmRinging)
            assertEquals(0, w.alarm.doubleRings)
        }

    @Test
    fun everyFixIsReportedProcessed() =
        runTest {
            val w = World(this)
            w.listen()
            w.startTrip(meta)
            repeat(5) {
                w.fixNorth(30_000.0 - it * 75.0)
                w.advance(5_000)
            }
            w.location.emit(RawFix(Geo.DEST_LAT, Geo.DEST_LNG, null, null, w.time.elapsedNanos())) // dropped fix
            w.settle()
            assertEquals(w.location.emitted, w.location.processed)
            assertEquals(6, w.location.processed)
        }

    @Test
    fun l20b_firedRecordWithoutTripTimeUsesItsWallTime() {
        val base = EngineStates.drive(meta, 1_000_000, 30_000.0, 30).state
        val s = base.copy(fallback = app.napstop.core.trip.FallbackState(base.nowMs + 600_000, base.nowMs, app.napstop.core.trip.FallbackStatus.CONFIRMED, base.nowMs, false, false))
        val toTrip = { wall: Long -> wall - 1_000L }
        fun plan(firedWall: Long) =
            RestorePlanner.plan(
                s, FallbackLedger.EMPTY.copy(lastFired = FiredRec(3, 9, null, firedWall)), app.napstop.core.alarm.RingFacts.NONE,
                RestoreCause.PROCESS_START, base.nowMs + 60_000, toTrip,
            ).status
        assertEquals(app.napstop.core.trip.FallbackRestoreStatus.RANG, plan(base.nowMs + 1_000 + 5_000), "after the last Step")
        assertEquals(app.napstop.core.trip.FallbackRestoreStatus.PENDING, plan(base.nowMs + 1_000 - 5_000), "before the last Step")
    }

    /**
     * L45 runs in real time (runBlocking, real dispatchers): with virtual time, runTest would jump the clock while the
     * test waits for the real IO lane and every bounded disk call would "time out". Real time is the stricter check.
     */
    private class RealRuntime(blockRead: Boolean, blockWrite: Boolean) {
        val gate = CountDownLatch(1)
        val store = FakeStore()
        val alarm = app.napstop.core.trip.runtime.support.FakeAlarmPort()
        val warnings = java.util.Collections.synchronizedList(ArrayList<String>())
        val scope = CoroutineScope(kotlinx.coroutines.SupervisorJob() + Dispatchers.Default)
        val time = object : TimeSource {
            override fun wallMs() = System.currentTimeMillis()
            override fun elapsedMs() = System.nanoTime() / 1_000_000L
            override fun elapsedNanos() = System.nanoTime()
            override fun bootCount() = 7
        }
        val runtime: TripRuntime

        init {
            val m = TestData.meta()
            store.active = EngineStates.stored(m, EngineStates.drive(m, time.wallMs() - 200_000, 30_000.0, 30), ClockAnchor(time.wallMs() - 200_000, time.elapsedMs() - 200_000, 7))
            store.ledger = FallbackLedger(1, "t1", 3, FallbackSlotRec(0, 2, time.wallMs(), time.wallMs()), null, null)
            if (blockRead) store.readGate = gate
            if (blockWrite) store.writeGate = gate
            val ports =
                RuntimePorts(
                    time, app.napstop.core.trip.runtime.support.FakeLocationSource(), app.napstop.core.trip.runtime.support.FakeTracking(),
                    app.napstop.core.trip.runtime.support.FakeScheduler(), alarm, app.napstop.core.trip.runtime.support.FakeNotifier(), store,
                    app.napstop.core.trip.runtime.support.FakeVisibility(false), app.napstop.core.trip.runtime.support.FakeEnv(),
                )
            @OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
            val actor = Dispatchers.Default.limitedParallelism(1)
            runtime = TripRuntime(ports, scope, actor, Dispatchers.IO, Dispatchers.Default, RuntimeConstants(), warn = { warnings += it })
        }

        /** Real ms from [t0] until ringFallback was called (≤ 5 s polled). */
        fun ringDelayFrom(t0: Long): Long? {
            while (System.nanoTime() / 1_000_000L - t0 < 5_000) {
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

    @Test
    fun l45_hungDiskNeverDelaysTheFallbackRing() {
        // New process, the fallback receiver is the first entry; snapshot read and write hang forever.
        val r = RealRuntime(blockRead = true, blockWrite = true)
        try {
            val t0 = System.nanoTime() / 1_000_000L
            r.scope.launch { r.runtime.onFallbackFired("t1", 0, 2, r.time.wallMs()) }
            val d = r.ringDelayFrom(t0)
            assertNotNull(d, "rang; warnings=${r.warnings}")
            assertTrue(d!! <= 1_500, "rang after $d ms")
            assertNotNull(r.store.ledger.lastFired?.firedAtWallMs)
        } finally {
            r.close()
        }
    }

    @Test
    fun l45_anotherEntryLoadingFirstOnAHungDiskDelaysTheRingByAtMostTheIoBudget() {
        // A sticky restart / WakeAlarmReceiver loaded first and its snapshot read hangs (review T15 #5).
        val r = RealRuntime(blockRead = true, blockWrite = false)
        try {
            val t0 = System.nanoTime() / 1_000_000L
            r.scope.launch { r.runtime.onWake() }
            Thread.sleep(20)
            r.scope.launch { r.runtime.onFallbackFired("t1", 0, 2, r.time.wallMs()) }
            val d = r.ringDelayFrom(t0)
            assertNotNull(d, "rang; warnings=${r.warnings}")
            assertTrue(d!! <= 1_500, "rang after $d ms")
            assertTrue(r.warnings.any { it == "snapshot read over budget" }, "${r.warnings}")
        } finally {
            r.close()
        }
    }

    // ---------------------------------------------------------------- round 3 (review T15 R2-1, R2-2, R2-3)

    /** Disk dispatcher that holds every task while [hold] (a hung disk in virtual time), then runs them on release. */
    private class HoldingDispatcher(private val target: kotlinx.coroutines.CoroutineDispatcher) : kotlinx.coroutines.CoroutineDispatcher() {
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

    @Test
    fun r21_tripStartedAfterATimedOutLoadIsNeverReplacedByTheOldSnapshot() =
        runTest {
            // Reviewer's scenario: slow disk after boot, an old unfinished trip on disk, the user starts a new trip.
            val holding = HoldingDispatcher(kotlinx.coroutines.test.StandardTestDispatcher(testScheduler))
            val w = World(this, io = holding)
            val old = TestData.meta("old")
            w.store.active = EngineStates.stored(old, EngineStates.drive(old, w.startWall, 30_000.0, 30), ClockAnchor(w.startWall, w.elapsedBase, 7))
            w.store.ledger = FallbackLedger(1, "old", 3, FallbackSlotRec(0, 2, w.startWall + 900_000, w.startWall), null, null)
            w.scheduler.slots[0] = app.napstop.core.trip.runtime.support.FakeScheduler.Fallback(0, "old", 2, w.startWall + 900_000, w.startWall + 900_000, true)
            w.listen()
            holding.hold = true
            val first = async { w.runtime.current() } // app opens: the load times out → null
            w.advance(3_000)
            assertNull(first.await())
            assertTrue("snapshot read over budget" in w.warnings)
            w.tracking.autoResult = ForegroundResult.Started
            val started = async { w.runtime.start(meta, Geo.DEST_LAT, Geo.DEST_LNG) }
            w.advance(30_000)
            assertEquals(StartOutcome.Started, started.await())
            // The disk comes back: the old read (and every queued write) completes now.
            holding.release()
            w.advance(5_000)
            // Later calls must not restore the old snapshot over the running trip.
            assertEquals("t1", w.now { w.runtime.current() }?.first?.tripId)
            w.now { w.runtime.onWake() }
            w.now { w.runtime.userAction("t1", UserActionKind.STOP_TRIP) }
            assertTrue(w.seen.last().events.any { it is TripEnded }, "the new trip is the one that ended")
            assertEquals("t1", w.now { w.runtime.pendingFinished() }.single().tripId)
            assertFalse(w.scheduler.slots.values.any { it.tripId == "old" }, "the superseded trip's fallback was cancelled")
            // Ledger unreadable at start: the old id is unknown, so both slots were cancelled before the new trip set its own.
            val ops = w.log.ops
            assertTrue(ops.indexOf("cancelFallback(0)") in 0 until ops.indexOfFirst { it.startsWith("setFallback") }, "$ops")
            assertTrue("t1" in w.store.ledger.endedTripIds)
            assertEquals(null, w.store.ledger.activeTripId)
        }

    @Test
    fun r22_aReusedTripIdIsNotSuppressedByEndedTripIds() =
        runTest {
            val w = World(this)
            w.store.ledger = FallbackLedger(1, null, 9, null, null, null, endedTripIds = listOf("t1"))
            w.listen()
            w.startTrip(meta) // "t1" again
            w.fixNorth(30_000.0)
            assertFalse("t1" in w.store.ledger.endedTripIds)
            val slot = w.scheduler.slots.values.single()
            assertEquals(FallbackFireAction.RANG, w.now { w.runtime.onFallbackFired("t1", slot.slot, slot.generation, slot.targetAtMs) })
            // Even with the id still listed (old ledger), the running trip's own alarm rings.
            val w2 = World(this)
            w2.listen()
            w2.startTrip(meta)
            w2.fixNorth(30_000.0)
            w2.store.ledger = w2.store.ledger.copy(endedTripIds = listOf("t1"))
            assertEquals(FallbackFireAction.RANG, w2.now { w2.runtime.onFallbackFired("t1", 0, 1, w2.nowMs) })
        }

    @Test
    fun r23_interruptedAlertsOncePerHeadlessPeriodAcrossProcesses() =
        runTest {
            fun World.headlessProcess(): List<Pair<TripNotice, Boolean>> {
                listen()
                now { runtime.ensureLoaded() }
                advance(6_000)
                return notifier.alerts.filter { it.first == TripNotice.Interrupted }
            }
            val w = World(this)
            w.seedStored(EngineStates.drive(meta, w.startWall, 30_000.0, 30))
            assertEquals(listOf(TripNotice.Interrupted to true), w.headlessProcess(), "first process: alerts")
            assertTrue(w.store.ledger.interruptedAlerted)
            // Process killed after each wake-up (OEM): later processes re-post silently.
            val w2 = World(this, store = w.store, scheduler = w.scheduler, alarm = w.alarm)
            assertEquals(listOf(TripNotice.Interrupted to false), w2.headlessProcess(), "second process: silent")
            val w3 = World(this, store = w.store, scheduler = w.scheduler, alarm = w.alarm)
            assertEquals(listOf(TripNotice.Interrupted to false), w3.headlessProcess(), "third process: silent")
            // The FGS comes back: notice cleared, flag reset.
            w3.tracking.isForeground = true
            w3.runtime.onForegroundResult("t1", ForegroundResult.Started)
            w3.settle()
            assertTrue("clear:Interrupted" in w3.notifier.history)
            assertFalse(w.store.ledger.interruptedAlerted)
            // A new HEADLESS period alerts again, once.
            val w4 = World(this, store = w.store, scheduler = w.scheduler, alarm = w.alarm)
            assertEquals(listOf(TripNotice.Interrupted to true), w4.headlessProcess(), "new HEADLESS period: alerts once")
        }

    // ---------------------------------------------------------------- round 4: designer "T15 — sau test" (L46–L55)

    /** Runs [block] to completion, letting virtual time run (bounded disk calls / RestoreLoop back-off). */
    private fun <T> World.await(maxMs: Long = 60_000, block: suspend () -> T): T {
        val d = scope.async { block() }
        var t = 0L
        while (!d.isCompleted && t < maxMs) {
            advance(100)
            t += 100
        }
        check(d.isCompleted) { "did not complete in $maxMs ms virtual" }
        @OptIn(ExperimentalCoroutinesApi::class)
        return d.getCompleted()
    }

    /** A FAR trip on disk as a dead process left it, then a reboot (OS alarms gone, BOOT_COUNT 7 → 8). */
    private fun World.seedRebooted(): Long {
        val step = EngineStates.drive(meta, nowMs - 150_000, 30_000.0, 30)
        val fb = step.state.fallback.targetAtMs!!
        store.active = EngineStates.stored(meta, step, ClockAnchor(time.wallMs(), time.elapsedMs(), 7))
        store.ledger = FallbackLedger(1, meta.tripId, 3, FallbackSlotRec(0, 2, fb, nowMs), null, null)
        time.bootCountValue = 8
        visibility.visible = false
        return fb
    }

    @Test
    fun l46_bootOnASlowDiskArmsASafetySlotThenRestores() =
        runTest {
            val snapshotIo = HoldingDispatcher(kotlinx.coroutines.test.StandardTestDispatcher(testScheduler))
            val ledgerIo = HoldingDispatcher(kotlinx.coroutines.test.StandardTestDispatcher(testScheduler))
            val w = World(this, io = snapshotIo, ledgerIo = ledgerIo)
            val fb = w.seedRebooted()
            w.listen()
            w.advance(60_000)
            snapshotIo.hold = true
            ledgerIo.hold = true
            val boot = async { w.runtime.ensureLoaded(RestoreCause.BOOT); w.runtime.awaitNotices() }
            w.advance(300)
            ledgerIo.release() // ledger: 300 ms
            // Snapshot reads stay slow for the first 3 attempts (≈ 2.5 s each, beyond the 1 s budget).
            var safety: app.napstop.core.trip.runtime.support.FakeScheduler.Fallback? = null
            var armedAt = 0L
            // Snapshot reads stay slower than the 1 s budget for 3 attempts (≈ 1.3 s, 2.55 s, 4.05 s).
            while (testScheduler.currentTime < 60_000 + 4_200) {
                w.advance(50)
                if (safety == null) {
                    safety = w.scheduler.slots.values.firstOrNull { it.kind == SlotKind.SAFETY }
                    armedAt = w.nowMs
                }
            }
            assertNotNull(safety, "SAFETY slot after the first ledger read")
            val expected = maxOf(fb, armedAt + 30_000)
            assertTrue(kotlin.math.abs(safety!!.triggerWallMs - expected) <= 100, "SAFETY at max(ledger fallback, now + 30 s)")
            assertTrue(w.warnings.count { it == "snapshot read over budget" } >= 3, "${w.warnings}")
            snapshotIo.release()
            w.advance(3_000)
            w.await { boot.await() }
            assertEquals("t1", w.runtime.liveTrip(), "loaded within the receiver budget")
            assertEquals(1, w.scheduler.slots.size, "the engine fallback (RESYNC) replaced the SAFETY slot")
            assertEquals(SlotKind.ENGINE, w.scheduler.slots.values.single().kind)
            assertEquals(1, w.notifier.alerts.count { it.first == TripNotice.Interrupted && it.second }, "Interrupted alerted once")
            assertTrue(w.scheduler.restoreRetries.isEmpty(), "no retry needed")
        }

    @Test
    fun l47_hungDiskBeyondTheReceiverBudgetIsRetriedByAlarm() =
        runTest {
            val holding = HoldingDispatcher(kotlinx.coroutines.test.StandardTestDispatcher(testScheduler))
            val w = World(this, io = holding)
            w.seedRebooted()
            w.listen()
            w.advance(60_000)
            holding.hold = true
            w.await { w.runtime.ensureLoaded(RestoreCause.BOOT); w.runtime.awaitNotices() }
            val first = w.scheduler.restoreRetry!!
            assertEquals(0, first.attempt)
            assertTrue(first.triggerElapsedMs - w.time.elapsedMs() in 29_000..30_000, "first retry in 30 s")
            // Retry 1: still hung → next in 60 s.
            w.advance(first.triggerElapsedMs - w.time.elapsedMs())
            w.deliverDue(null, null)
            w.advance(9_000)
            val second = w.scheduler.restoreRetry!!
            assertEquals(1, second.attempt)
            assertEquals(RestoreCause.BOOT, second.cause)
            assertTrue(second.triggerElapsedMs - w.time.elapsedMs() in 50_000..60_000, "second retry in 60 s")
            // The disk comes back; the next retry restores everything.
            holding.release()
            w.advance(second.triggerElapsedMs - w.time.elapsedMs())
            w.deliverDue(null, null)
            w.advance(9_000)
            assertEquals("t1", w.runtime.liveTrip())
            assertNull(w.scheduler.restoreRetry, "no more retries once loaded")
            assertEquals(1, w.scheduler.slots.size, "fallback re-armed")
            assertTrue(w.tracking.starts.isEmpty(), "never the FGS from the background")
            assertEquals(1, w.notifier.alerts.count { it.first == TripNotice.Interrupted && it.second })
        }

    @Test
    fun l48_failedNowRingIsCaughtByTheRingGuard() =
        runTest {
            val w = World(this)
            w.listen()
            w.startTrip(meta)
            w.alarm.throwOnRingNow = IllegalStateException("cannot start the ring")
            var m = 1_600.0
            while (w.log.count("ringNow") == 0) {
                w.fixNorth(m)
                w.advance(5_000)
                m -= 75.0
            }
            w.alarm.throwOnRingNow = null
            val ops = w.log.ops
            val ringIdx = ops.indexOfFirst { it.startsWith("ringNow") }
            val persistIdx = ops.subList(0, ringIdx).indexOfLast { it == "writeActive" }
            val guardIdx = ops.subList(0, persistIdx).indexOfLast { it.startsWith("setFallback") }
            assertTrue(guardIdx in 0 until persistIdx, "ArmRingGuard before PersistNow: $ops")
            val failedAt = alarms(w).first { it.ringNow }.atMs
            val guard = w.scheduler.slots.values.single()
            assertEquals(SlotKind.GUARD, guard.kind)
            assertTrue(guard.triggerWallMs <= failedAt + 30_000)
            // The process sleeps: only the OS delivers.
            w.advance(guard.triggerWallMs - w.nowMs)
            w.deliverDue(null, null)
            val rings = w.alarm.ringFallbackCalls.map { it.atWallMs } + w.alarm.ringNowCalls.map { it.atWallMs }
            assertEquals(1, rings.size, "exactly one sound")
            assertTrue(rings.single() - failedAt <= 31_000)
            assertEquals(0, w.alarm.doubleRings)
        }

    @Test
    fun l49_guardWhileTheRingIsLiveIsDropped() =
        runTest {
            val journal = RecordingJournal()
            val w = World(this, journal = journal)
            w.alarming()
            val guard = w.scheduler.slots.values.single()
            assertEquals(SlotKind.GUARD, guard.kind)
            val steps = w.seen.size
            val fired = w.store.ledger.lastFired
            w.advance(guard.triggerWallMs - w.nowMs)
            w.deliverDue(null, null)
            assertEquals(steps, w.seen.size, "no FallbackFired")
            assertEquals(fired, w.store.ledger.lastFired, "no lastFired")
            assertTrue(w.scheduler.slots.isEmpty(), "slot gone")
            assertEquals(1, w.alarm.ringNowCalls.size)
            assertTrue(w.alarm.ringFallbackCalls.isEmpty())
            assertEquals("SUPPRESSED_LIVE", journal.lines.last { it.ev == "fb_fire" }.fields["action"])
            assertEquals("GUARD", journal.lines.last { it.ev == "fb_fire" }.fields["kind"])
        }

    @Test
    fun l50_eachFailedRingArmsANewGuardUntilOneRings() =
        runTest {
            val w = World(this)
            w.listen()
            w.startTrip(meta)
            w.alarm.throwOnRingNow = IllegalStateException("x")
            w.alarm.ringFallbackFailures = 2
            var m = 1_300.0
            while (w.log.count("ringNow") == 0) {
                w.fixNorth(m)
                w.advance(5_000)
                m -= 75.0
            }
            // No more fixes: the process sleeps, the guards carry the retries.
            val guardTimes = ArrayList<Long>()
            var n = 0
            while (w.alarm.ringFallbackCalls.isEmpty() && n++ < 10) {
                val g = w.scheduler.slots.values.single { it.kind == SlotKind.GUARD }
                guardTimes += g.triggerWallMs
                w.advance(g.triggerWallMs - w.nowMs)
                w.deliverDue(null, null)
            }
            assertEquals(1, w.alarm.ringFallbackCalls.size, "rang at the third guard")
            assertEquals(3, guardTimes.size, "$guardTimes")
            guardTimes.zipWithNext().forEach { (a, b) -> assertTrue(b - a in 29_000..31_000, "guards 30 s apart: $guardTimes") }
            assertTrue(w.seen.last().view.alarmRinging)
            // Afterwards no stray guard rings: one that comes due while the ring is live is dropped.
            w.advance(120_000)
            w.deliverDue(null, null)
            assertTrue(w.scheduler.slots.values.none { it.kind == SlotKind.GUARD }, "${w.scheduler.slots}")
            assertEquals(1, w.alarm.ringFallbackCalls.size)
            assertEquals(0, w.alarm.doubleRings)
        }

    @Test
    fun l51_processDiesRightAfterPersistNow() =
        runTest {
            val w = World(this)
            w.listen()
            w.startTrip(meta)
            var died: Triple<FakeStore, app.napstop.core.trip.runtime.support.FakeScheduler, Long>? = null
            w.store.onWriteActive = { t ->
                if (died == null && t.engine.phase == TripPhase.ALARMING) died = Triple(w.store.copy(), w.scheduler.copy(), w.nowMs)
            }
            var m = 1_300.0
            while (died == null && m > 0) {
                w.fixNorth(m)
                w.advance(5_000)
                m -= 75.0
            }
            val (store, scheduler, deathWall) = died!!
            assertTrue(scheduler.slots.values.any { it.kind == SlotKind.GUARD && it.triggerWallMs <= deathWall + 30_000 }, "guard set before the write")
            // New process (no ring ever happened in it); the first OS alarm brings it back.
            val p = World(this, startWall = w.startWall, store = store, scheduler = scheduler, alarm = app.napstop.core.trip.runtime.support.FakeAlarmPort())
            p.visibility.visible = false
            p.listen()
            var guardLoop = 0
            while (p.alarm.ringNowCalls.isEmpty() && p.alarm.ringFallbackCalls.isEmpty() && guardLoop++ < 20) {
                val next = p.nextOsDeliveryMs(null, null) ?: break
                if (next > testScheduler.currentTime) p.advance(next - testScheduler.currentTime)
                p.deliverDue(null, null)
            }
            val first = (p.alarm.ringNowCalls.map { it.atWallMs } + p.alarm.ringFallbackCalls.map { it.atWallMs }).minOrNull()
            assertNotNull(first)
            assertTrue(first!! - deathWall <= 31_000, "rang ${first - deathWall} ms after the death")
            assertTrue(p.seen.isEmpty() || p.seen.last().view.alarmRinging, "no AlarmSilenced before the ring")
            assertEquals(0, p.alarm.doubleRings)
        }

    private fun World.ringingThenDead(pending: (app.napstop.core.trip.runtime.support.FakeAlarmPort.Facts, Long) -> Unit): Pair<World, app.napstop.core.trip.runtime.support.FakeScheduler.Fallback> {
        alarming()
        val guard = scheduler.slots.values.single { it.kind == SlotKind.GUARD }
        // Process dies; in the alarm UI process the user acts before RING_EVENT reaches the main process.
        val alarmCopy = alarm.copy()
        alarmCopy.facts.getValue("t1").also {
            it.ringing = false
            pending(it, nowMs)
        }
        val p = World(scope, startWall = startWall, store = store.copy(), scheduler = scheduler.copy(), alarm = alarmCopy)
        p.visibility.visible = false
        p.listen()
        return p to guard
    }

    @Test
    fun l52_guardAfterADismissInTheAlarmUiDoesNotRing() =
        runTest {
            val (p, guard) = World(this).ringingThenDead { f, now -> f.pendingDismiss = now }
            p.advance(guard.triggerWallMs - p.nowMs)
            p.scheduler.slots.remove(guard.slot)
            assertEquals(FallbackFireAction.SUPPRESSED_DISMISS, p.now { p.runtime.onFallbackFired("t1", guard.slot, guard.generation, guard.targetAtMs, guard.kind) })
            assertTrue(p.alarm.ringFallbackCalls.isEmpty() && p.alarm.ringNowCalls.isEmpty())
            p.now { p.runtime.ensureLoaded() }
            assertTrue(p.events.any { it.second is TripEnded }, "restored DISMISSED → TripEnded")
            assertEquals(EndReason.DISMISSED, p.events.map { it.second }.filterIsInstance<TripEnded>().single().endReason)
        }

    @Test
    fun l53_guardAfterASnoozeInTheAlarmUiDoesNotRing() =
        runTest {
            val (p, guard) = World(this).ringingThenDead { f, now -> f.pendingSnooze = now }
            p.advance(guard.triggerWallMs - p.nowMs)
            p.scheduler.slots.remove(guard.slot)
            assertEquals(FallbackFireAction.SUPPRESSED_SNOOZE, p.now { p.runtime.onFallbackFired("t1", guard.slot, guard.generation, guard.targetAtMs, guard.kind) })
            assertTrue(p.alarm.ringFallbackCalls.isEmpty() && p.alarm.ringNowCalls.isEmpty())
            p.now { p.runtime.onRingEvent(RingEvent("t1", RingEventKind.SNOOZED, p.nowMs)) }
            assertTrue(p.alarm.ringNowCalls.isEmpty(), "no ring on restore while a snooze is pending")
            val sn = p.events.map { it.second }.filterIsInstance<Snoozed>().single()
            val slot = p.scheduler.slots.values.single()
            assertEquals(SlotKind.ENGINE, slot.kind)
            assertEquals(sn.untilMs + EngineParams().fallbackLagS * 1000L, slot.targetAtMs)
        }

    @Test
    fun l54_orphanLedgerTripAlertsOnceKeepsItsSlotAndEndsOnDismiss() =
        runTest {
            val w = World(this)
            w.store.active = null
            w.store.ledger = FallbackLedger(1, "X", 9, FallbackSlotRec(0, 8, w.nowMs + 600_000, w.nowMs), null, null)
            w.scheduler.slots[0] = app.napstop.core.trip.runtime.support.FakeScheduler.Fallback(0, "X", 8, w.nowMs + 600_000, w.nowMs + 600_000, true)
            var alerts = 0
            repeat(3) {
                val p = World(this, store = w.store, scheduler = w.scheduler, alarm = w.alarm)
                p.visibility.visible = false
                p.now { p.runtime.ensureLoaded() }
                p.advance(6_000)
                alerts += p.notifier.alerts.count { it.first == TripNotice.Interrupted && it.second }
            }
            assertEquals(1, alerts)
            assertNull(w.store.ledger.activeTripId)
            assertEquals("X", w.scheduler.slots.values.single().tripId, "the orphan's slot is kept")
            // It rings ("uncertain → ring"), the user dismisses it.
            val p = World(this, store = w.store, scheduler = w.scheduler, alarm = w.alarm)
            p.advance(w.scheduler.slots.values.single().triggerWallMs - p.nowMs)
            p.deliverDue(null, null)
            assertEquals(1, p.alarm.ringFallbackCalls.size)
            p.now { p.runtime.onRingEvent(RingEvent("X", RingEventKind.DISMISSED, p.nowMs)) }
            assertTrue("X" in p.store.ledger.endedTripIds)
            assertTrue(p.scheduler.slots.isEmpty())
            assertTrue("X" in p.alarm.cleared)
        }

    @Test
    fun l55_wakeFireLogsTheAlarmThatFired() =
        runTest {
            val journal = RecordingJournal()
            val w = World(this)
            w.seedStored(EngineStates.drive(meta, w.startWall, 30_000.0, 30))
            val wakeAt = w.nowMs + 10_000
            // A new process (journal of its own); the alarm set by the old one is delivered 456 ms late.
            val p = World(this, store = w.store, scheduler = w.scheduler, alarm = w.alarm, journal = journal)
            p.advance(10_456)
            p.now { p.runtime.onWake(wakeAt, wakeAt) }
            val fire = journal.lines.first { it.ev == "wake_fire" }
            assertEquals(wakeAt, fire.fields["at"])
            assertEquals(456L, fire.fields["lateMs"])
            assertEquals("WAKE", fire.fields["kind"])
            assertTrue(journal.lines.indexOf(fire) < journal.lines.indexOfFirst { it.ev == "restore" }, "logged before the restore")
            val text =
                JournalAnalyzer.analyze(
                    listOf(
                        """{"t":0,"w":0,"ev":"step","phase":"TRACKING","gps":"OK","tier":"SPARSE","predicted":${wakeAt - 1_000},"fb":null,"fbStatus":"CONFIRMED","wake":$wakeAt,"events":[],"input":"Tick"}""",
                        """{"t":0,"w":0,"ev":"wake_set","at":$wakeAt,"mech":"EXACT_IDLE"}""",
                        """{"t":null,"w":0,"ev":"wake_fire","at":$wakeAt,"lateMs":456,"kind":"WAKE"}""",
                        """{"t":null,"w":0,"ev":"wake_fire","at":null,"lateMs":null,"kind":"RESTORE_RETRY"}""",
                    ),
                )
            assertTrue(text.contains("at=$wakeAt late=0.456s label=c3"), text)
            assertTrue(text.contains("wake-ups (1)"), "the line without `at` is left out: $text")
        }

    /** Disk dispatcher where every task runs [ms] of virtual time after it was dispatched (a constantly slow disk). */
    private class SlowDispatcher(private val scope: CoroutineScope, private val ms: Long) : kotlinx.coroutines.CoroutineDispatcher() {
        override fun dispatch(context: kotlin.coroutines.CoroutineContext, block: Runnable) {
            scope.launch {
                delay(ms)
                block.run()
            }
        }
    }

    @Test
    fun l46b_aDiskConstantlySlowerThanTheBudgetStillLoads() =
        runTest {
            // Every read / write takes 2.5 s (> ioBudgetMs 1 s): attempts reuse the read in flight instead of restarting it.
            val w = World(this, io = SlowDispatcher(backgroundScope, 2_500), ledgerIo = SlowDispatcher(backgroundScope, 2_500))
            w.seedRebooted()
            w.listen()
            w.advance(60_000)
            w.await { w.runtime.ensureLoaded(RestoreCause.BOOT); w.runtime.awaitNotices() }
            assertEquals("t1", w.runtime.liveTrip(), "loaded within the receiver budget")
            assertTrue(w.scheduler.slots.isNotEmpty(), "fallback re-armed")
            assertTrue(w.scheduler.restoreRetries.isEmpty(), "no retry alarm needed")
            assertEquals(1, w.notifier.alerts.count { it.first == TripNotice.Interrupted && it.second })
        }
}
