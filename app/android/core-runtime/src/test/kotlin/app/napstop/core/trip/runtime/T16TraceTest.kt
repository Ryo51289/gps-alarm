package app.napstop.core.trip.runtime

import app.napstop.core.alarm.AlarmConstants
import app.napstop.core.alarm.RingCommand
import app.napstop.core.alarm.RingPhase
import app.napstop.core.alarm.RingSource
import app.napstop.core.alarm.RingVariant
import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.Snoozed
import app.napstop.core.trip.TripEnded
import app.napstop.core.trip.TripEvent
import app.napstop.core.trip.TripOutcome
import app.napstop.core.trip.runtime.support.ExpectCase
import app.napstop.core.trip.runtime.support.ExpectReader
import app.napstop.core.trip.runtime.support.FakeScheduler
import app.napstop.core.trip.runtime.support.FakeTime
import app.napstop.core.trip.runtime.support.FixFeed
import app.napstop.core.trip.runtime.support.SimRing
import app.napstop.core.trip.runtime.support.SimRingProcess
import app.napstop.core.trip.runtime.support.TraceCase
import app.napstop.core.trip.runtime.support.TraceRun
import app.napstop.core.trip.runtime.support.World
import java.util.Locale
import kotlin.math.abs
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestFactory

/**
 * T16 trace tests (spec "Test cases" AT1–AT6) through the T15 runtime with the real AlarmControllerCore and ring session
 * machine in memory ([SimRing] = main process, [SimRingProcess] = `:ring`), plus the review T16 #1 regression (reboot
 * during a snooze).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class T16TraceTest {
    private class Rig(val world: World, val sim: SimRing) {
        val proc: SimRingProcess get() = sim.proc
    }

    /** A world whose alarm port is a SimRing on [proc] (a new `:ring` process when null). */
    private fun TestScope.rig(
        startWall: Long,
        c: AlarmConstants = AlarmConstants(),
        proc: SimRingProcess? = null,
        elapsedBase: Long = 1_000_000L,
        store: app.napstop.core.trip.runtime.support.FakeStore? = null,
        scheduler: FakeScheduler? = null,
        boot: Int = 7,
    ): Rig {
        var sim: SimRing? = null
        val scope = this
        val world =
            World(
                scope, startWall = startWall, elapsedBase = elapsedBase,
                store = store ?: app.napstop.core.trip.runtime.support.FakeStore(),
                scheduler = scheduler,
                ringPort = { w ->
                    w.time.bootCountValue = boot
                    SimRing(w, proc ?: SimRingProcess(scope, w.time, c)).also { sim = it }
                },
            )
        world.listen()
        return Rig(world, sim!!)
    }

    private fun t(trace: TraceCase, atMs: Long) = ((atMs - trace.gpx.startMs) / 1000L).toInt()

    private fun window(c: ExpectCase, reason: String) = c.expect.firstOrNull { it.event == "alarm" && it.reason == reason }

    private fun ringNowEvents(w: World): List<Alarm> = w.events.map { it.second }.filterIsInstance<Alarm>().filter { it.ringNow }

    /** Every Alarm(ringNow) of [w] reached the port, and each one is a new start, an update of the ring on, or a backup. */
    private fun assertStartOrUpdate(where: String, w: World, r: Rig) {
        assertEquals(ringNowEvents(w).size, r.sim.ringCalls.count { it.source == RingSource.ENGINE }, "$where: ringNow calls")
        val updates = r.sim.transport.commands.count { it is RingCommand.Update }
        assertEquals(r.sim.ringCalls.size, r.sim.transport.started.size + updates + r.sim.transport.backups.size + r.sim.denied, "$where: start or update")
        assertEquals(0, r.proc.overlaps, "$where: two sessions at once")
    }

    // ------------------------------------------------------------------ AT1

    private fun at1Case(trace: TraceCase, c: ExpectCase) =
        runTest {
            val r = rig(trace.gpx.startMs)
            val world = r.world
            val meta = ExpectReader.meta(trace, c)
            assertEquals(StartOutcome.Started, world.now { world.runtime.start(meta, trace.destLat, trace.destLng) })
            TraceRun(world, FixFeed(trace.gpx, trace.intervalS), meta.tripId).run(trace.durationS)
            world.advance(60_000)
            val where = "${trace.traceId}/${c.id}"
            val first = ringNowEvents(world).firstOrNull()
            c.expect.firstOrNull { it.event == "alarm" }?.let { w ->
                assertNotNull(first, "$where: no alarm")
                assertTrue(t(trace, first!!.atMs) in w.notBefore..w.notAfter, "$where: alarm at ${t(trace, first.atMs)} not in [${w.notBefore}, ${w.notAfter}]")
            }
            assertStartOrUpdate(where, world, r)
            if (first != null) {
                assertTrue(r.proc.sessions.isNotEmpty(), "$where: a session rang")
                // Dismissed in the native UI 30 s later → the trip ended, the book is cleared, nothing rings.
                assertTrue(world.events.any { it.second is TripEnded }, "$where: trip ended")
                assertTrue(r.proc.facts.records.isEmpty(), "$where: book cleared ${r.proc.facts.records.keys}")
                assertTrue(r.proc.ring.state.phase != RingPhase.RINGING, "$where: still ringing")
                assertNotNull(world.store.finished[meta.tripId]?.outcome, "$where: finished record")
            }
            assertTrue(r.sim.warnings.none { it.contains("failed") }, "$where: ${r.sim.warnings}")
        }

    @TestFactory
    fun at1_baseTracesWithTheRealAlarmCore(): List<DynamicTest> =
        ExpectReader.BASE_TRACES.flatMap { id ->
            val trace = ExpectReader.read(id)
            trace.cases.filter { it.status == "final" && it.excludedKeys.isEmpty() }.map { c ->
                DynamicTest.dynamicTest("$id/${c.id}") { at1Case(trace, c) }
            }
        }

    // ------------------------------------------------------------------ AT2

    @Test
    fun at2_silencedRingThenTheOvershootRingsOnce() =
        runTest {
            val trace = ExpectReader.read("coach_gb_phuly_overshoot")
            val c = trace.cases.single { it.id == "distance_1000_overshoot_silenced" }
            val r = rig(trace.gpx.startMs, AlarmConstants(ringMaxMs = 60_000L))
            r.proc.dismissAfterMs = null // nobody wakes up
            val world = r.world
            val meta = ExpectReader.meta(trace, c)
            world.now { world.runtime.start(meta, trace.destLat, trace.destLng) }
            TraceRun(world, FixFeed(trace.gpx, trace.intervalS), meta.tripId).run(trace.durationS)
            val rings = ringNowEvents(world)
            val distance = rings.first { it.reason == AlarmReason.DISTANCE }
            val over = rings.single { it.reason == AlarmReason.OVERSHOOT }
            val w = window(c, "OVERSHOOT")!!
            assertTrue(t(trace, over.atMs) in w.notBefore..w.notAfter, "overshoot alarm at ${t(trace, over.atMs)}")
            // Session 1 stopped by itself at +60 s (SILENCED), session 2 is the overshoot screen with its "past" line.
            assertEquals(2, r.proc.sessions.size, "sessions ${r.proc.sessions.map { it.second.request.reason }}")
            val silenced = r.proc.ring.events.first { it.kind == RingEventKind.SILENCED }
            assertEquals(r.proc.sessions[0].first + 60_000L, silenced.atWallMs)
            assertTrue(silenced.atWallMs < trace.gpx.startMs + (over.atMs - trace.gpx.startMs), "silenced before the overshoot ring")
            assertEquals(AlarmReason.OVERSHOOT, r.proc.sessions[1].second.request.reason)
            assertEquals(RingVariant.OVERSHOOT, r.proc.sessionContent[1]?.variant)
            assertNotNull(r.proc.sessionContent[1]?.pastLine, "overshoot screen shows how far past")
            assertTrue(distance.atMs < over.atMs)
            assertStartOrUpdate("AT2", world, r)
        }

    // ------------------------------------------------------------------ AT3 (+ review #1)

    private fun at3World(scope: TestScope, trace: TraceCase, c: ExpectCase) =
        scope.rig(trace.gpx.startMs).also {
            it.proc.snoozeFirstAfterMs = 20_000L
            it.proc.dismissAfterMs = 30_000L
        }

    @Test
    fun at3_snoozeRingsOnceMoreAtTheSnoozeEnd() =
        runTest {
            val trace = ExpectReader.read("coach_md_tb")
            val c = trace.cases.single { it.id == "distance_1000" }
            val r = at3World(this, trace, c)
            val world = r.world
            val meta = ExpectReader.meta(trace, c)
            world.now { world.runtime.start(meta, trace.destLat, trace.destLng) }
            TraceRun(world, FixFeed(trace.gpx, trace.intervalS), meta.tripId).run(trace.durationS)
            world.advance(60_000)
            val snoozed = world.events.map { it.second }.filterIsInstance<Snoozed>().single()
            assertTrue(r.proc.sessions.size >= 2, "sessions ${r.proc.sessions.size}")
            val (secondAt, second) = r.proc.sessions[1]
            assertEquals(AlarmReason.SNOOZE_END, second.request.reason)
            assertFalse(second.request.snoozeAllowed, "no snooze button on the second ring")
            // The user snoozed 20 s into the first session; the second session starts at the snooze end (± 1 s + confirm).
            val snoozeEndWall = r.proc.sessions[0].first + 20_000L + (snoozed.untilMs - snoozed.atMs)
            assertTrue(abs(secondAt - snoozeEndWall) <= 1_500, "second at $secondAt, snooze end $snoozeEndWall")
            assertEquals(TripOutcome.SNOOZED.name, world.store.finished[meta.tripId]?.outcome?.name)
            assertEquals(0, r.proc.overlaps)
            assertTrue(r.proc.facts.records.isEmpty())
        }

    /**
     * Review T16 #1: the phone reboots while snoozed. The book keeps the stopSeq of the old boot (elapsed time far above
     * the new boot's); the snooze-end ring of the new boot must still sound.
     */
    @Test
    fun at3b_rebootDuringTheSnoozeStillRingsTheSnoozeEnd() {
        val trace = ExpectReader.read("coach_md_tb")
        val c = trace.cases.single { it.id == "distance_1000" }
        val meta = ExpectReader.meta(trace, c)
        var store: app.napstop.core.trip.runtime.support.FakeStore? = null
        var facts: app.napstop.core.alarm.MemoryFacts? = null
        var feed: FixFeed? = null
        var atS = 0
        runTest {
            val r = at3World(this, trace, c)
            val world = r.world
            world.now { world.runtime.start(meta, trace.destLat, trace.destLng) }
            val f = FixFeed(trace.gpx, trace.intervalS)
            val run = TraceRun(world, f, meta.tripId)
            run.run(trace.durationS, stopAtFirstAlarm = true)
            // 20 s: snooze; 25 s: the trip is SNOOZED, the book has the old boot's stopSeq.
            world.advance(25_000)
            assertTrue(world.events.any { it.second is Snoozed })
            val rec = r.proc.facts.records[meta.tripId]!!
            assertTrue(rec.stopSeq != null && rec.stopSeq!! >= rec.ringSeq, "book after the snooze: $rec")
            store = world.store.copy()
            facts = app.napstop.core.alarm.MemoryFacts().also { it.records.putAll(r.proc.facts.records) }
            feed = f.copy()
            atS = t(trace, world.time.wallMs())
        }
        runTest {
            // Rebooted 5 s later: other boot count, elapsed time restarts small, every OS alarm is gone.
            val bootTime = FakeTime(wallBase = trace.gpx.startMs + (atS + 5) * 1000L, elapsedBase = 20_000L, bootCountValue = 8)
            val proc = SimRingProcess(this, bootTime, facts = facts!!)
            proc.dismissAfterMs = 30_000L
            val r = rig(trace.gpx.startMs + (atS + 5) * 1000L, proc = proc, elapsedBase = 20_000L, store = store, boot = 8)
            proc.reboot(r.world.time)
            val world = r.world
            world.now { world.runtime.ensureLoaded(RestoreCause.BOOT) }
            // The user opens the app after the reboot: the trip goes back to the location service (D11).
            world.tracking.autoResult = ForegroundResult.Started
            world.visibility.visible = true
            world.now { world.runtime.onAppVisible() }
            TraceRun(world, feed!!, meta.tripId, offsetS = atS + 5).run(trace.durationS)
            world.advance(60_000)
            val rings = r.sim.ringCalls
            assertTrue(rings.isNotEmpty(), "a ring after the reboot")
            assertTrue(proc.sessions.isNotEmpty(), "the ring after the reboot sounded (calls ${rings.map { it.reason }})")
            assertEquals(r.sim.ringCalls.size, r.sim.transport.started.size + r.sim.transport.commands.count { it is RingCommand.Update } + r.sim.transport.backups.size)
            assertTrue(world.events.any { it.second is TripEnded }, "dismissed → trip over")
        }
    }

    // ------------------------------------------------------------------ AT4 (RK14: main process dies while ringing)

    @Test
    fun at4_mainProcessDiesWhileRingingAndTheDismissIsRestored() =
        runTest {
            val trace = ExpectReader.read("train_hn_dh")
            val c = trace.cases.single { it.id == "distance_1000" }
            val a = rig(trace.gpx.startMs)
            val proc = a.proc
            proc.dismissAfterMs = 30_000L
            val meta = ExpectReader.meta(trace, c)
            a.world.now { a.world.runtime.start(meta, trace.destLat, trace.destLng) }
            TraceRun(a.world, FixFeed(trace.gpx, trace.intervalS), meta.tripId).run(trace.durationS, stopAtFirstAlarm = true)
            a.world.advance(5_000)
            assertEquals(1, proc.sessions.size)
            // The main process dies: runtime, controller, watchdog gone; the ring book, :ring and the OS alarms stay.
            a.world.kill()
            val b = rig(trace.gpx.startMs, proc = proc, store = a.world.store.copy(), scheduler = a.world.scheduler)
            // :ring keeps ringing, then the user dismisses at +30 s: RING_EVENT starts the new main process (B).
            var ringingWhileDead = 0
            repeat(40) {
                b.world.advance(1_000)
                b.world.deliverDue(null, null)
                if (proc.ring.state.phase == RingPhase.RINGING) ringingWhileDead++
            }
            assertTrue(ringingWhileDead >= 24, "rang on after the death: $ringingWhileDead s")
            assertEquals(1, proc.sessions.size, "no second ring (RK14)")
            val ended = b.world.events.map { it.second }.filterIsInstance<TripEnded>().singleOrNull()
            assertNotNull(ended, "the new main process ended the trip from the dismiss")
            val rec = b.world.store.finished[meta.tripId]!!
            assertEquals(TripOutcome.ON_TIME, rec.outcome)
            assertTrue(abs(rec.dismissedAtMs!! - proc.userAt.single()) <= 1_000, "dismissedAt ${rec.dismissedAtMs} vs press ${proc.userAt}")
            assertTrue(b.sim.ringCalls.isEmpty(), "the new process never rang again")
            assertTrue(proc.facts.records.isEmpty())
        }

    // ------------------------------------------------------------------ AT5 (RK14: :ring dies)

    @Test
    fun at5_ringProcessDiesRestartsBackupSilenceThenTheOvershootRings() =
        runTest {
            val trace = ExpectReader.read("coach_gb_phuly_overshoot")
            val c = trace.cases.single { it.id == "distance_1000_overshoot_silenced" }
            val r = rig(trace.gpx.startMs, AlarmConstants(ringMaxMs = 60_000L))
            val proc = r.proc
            proc.dismissAfterMs = null
            val world = r.world
            val meta = ExpectReader.meta(trace, c)
            world.now { world.runtime.start(meta, trace.destLat, trace.destLng) }
            val run = TraceRun(world, FixFeed(trace.gpx, trace.intervalS), meta.tripId)
            run.run(trace.durationS, stopAtFirstAlarm = true)
            world.advance(1_000)
            val firstStart = proc.sessions.single().first
            world.advance(19_000)
            // :ring dies at +20 s, and again at every restart (it never confirms).
            proc.kill()
            proc.dead = true
            var silencedAt: Long? = null
            while (silencedAt == null && world.time.wallMs() < firstStart + 120_000L) {
                run.run(t(trace, world.time.wallMs()) + 1)
                silencedAt = r.sim.lost.firstOrNull()?.second
            }
            // Watchdog restarts keep the first start time (a GUARD slot of T15 may add a plain ring attempt meanwhile).
            val restarts = r.sim.transport.started.drop(1).filter { it.resumeStartedAtWallMs == firstStart }
            assertEquals(2, restarts.size, "Restart ×2: ${r.sim.transport.started.map { it.resumeStartedAtWallMs }}")
            assertTrue(r.sim.transport.backups.isNotEmpty(), "then the backup notification")
            assertEquals(firstStart, r.sim.transport.backups.first().first.resumeStartedAtWallMs)
            assertEquals(firstStart + 60_000L, silencedAt, "silenced at RING_MAX of the first start")
            // :ring works again; the engine got AlarmSilenced and rings again at the overshoot.
            proc.dead = false
            run.run(trace.durationS)
            val over = ringNowEvents(world).single { it.reason == AlarmReason.OVERSHOOT }
            val w = window(c, "OVERSHOOT")!!
            assertTrue(t(trace, over.atMs) in w.notBefore..w.notAfter)
            assertEquals(AlarmReason.OVERSHOOT, proc.sessions.last().second.request.reason)
            assertEquals(2, proc.sessions.size)
        }

    // ------------------------------------------------------------------ AT6 (headless: FGS start rules)

    private fun at6Case(trace: TraceCase, c: ExpectCase) {
        val meta = ExpectReader.meta(trace, c)
        var alarmT = 0
        runTest {
            val r = rig(trace.gpx.startMs)
            r.world.now { r.world.runtime.start(meta, trace.destLat, trace.destLng) }
            TraceRun(r.world, FixFeed(trace.gpx, trace.intervalS), meta.tripId).run(trace.durationS, stopAtFirstAlarm = true)
            alarmT = t(trace, r.world.firstAlarm()?.atMs ?: return@runTest)
        }
        if (alarmT == 0) return
        val k = maxOf(60, alarmT - 900)
        var store: app.napstop.core.trip.runtime.support.FakeStore? = null
        var scheduler: FakeScheduler? = null
        var feed: FixFeed? = null
        runTest {
            val r = rig(trace.gpx.startMs)
            r.world.now { r.world.runtime.start(meta, trace.destLat, trace.destLng) }
            val f = FixFeed(trace.gpx, trace.intervalS)
            TraceRun(r.world, f, meta.tripId).run(k)
            store = r.world.store.copy()
            scheduler = r.world.scheduler.copy()
            feed = f.copy()
        }
        runTest {
            // The process died at k and the location service never came back (sticky failed): HEADLESS. Only alarm
            // receivers run it; starting the ring service is allowed there (exact alarm exemption), not elsewhere.
            val r = rig(trace.gpx.startMs + k * 1000L, elapsedBase = 1_000_000L + k * 1000L, store = store, scheduler = scheduler)
            val world = r.world
            world.visibility.visible = false
            var inReceiver = false
            world.deliveryHook = { inReceiver = it }
            r.sim.allowStart = { inReceiver || world.tracking.isForeground }
            r.proc.dismissAfterMs = 30_000L
            TraceRun(world, feed!!, meta.tripId, offsetS = k).run(trace.durationS * 4 + 7200, stopAtFirstAlarm = true)
            world.advance(60_000)
            val where = "${trace.traceId}/${c.id} k=$k"
            assertTrue(r.sim.ringCalls.isNotEmpty(), "$where: a ring")
            for (call in r.sim.ringCalls) assertTrue(call.tripId == meta.tripId)
            assertEquals(0, r.sim.denied, "$where: every ring came from a receiver (exempt)")
            assertTrue(r.proc.sessions.isNotEmpty() || r.sim.transport.backups.isNotEmpty(), "$where: something rang")
            assertTrue(world.warnings.none { it.contains("RingStartException") }, "$where: ${world.warnings}")
            assertEquals(0, r.proc.overlaps)
        }
    }

    @TestFactory
    fun at6_headlessRingsStartFromReceivers(): List<DynamicTest> =
        ExpectReader.BASE_TRACES.flatMap { id ->
            val trace = ExpectReader.read(id)
            trace.cases.filter { it.status == "final" && it.excludedKeys.isEmpty() && it.expect.any { e -> e.event == "alarm" } }.map { c ->
                DynamicTest.dynamicTest("$id/${c.id}") { at6Case(trace, c) }
            }
        }

    @Test
    fun at6_outsideAReceiverTheBackupRings() =
        runTest {
            val r = rig(1_700_000_000_000L)
            r.sim.allowStart = { false }
            r.sim.ringNow(app.napstop.core.alarm.AlarmData.request())
            assertEquals(1, r.sim.denied)
            assertEquals(1, r.sim.transport.backups.size)
            assertTrue(r.sim.ringFacts(app.napstop.core.alarm.AlarmData.TRIP).ringingNow)
            assertEquals(Locale.ENGLISH, Locale.ENGLISH)
        }

    @Suppress("unused")
    private fun events(w: World): List<TripEvent> = w.events.map { it.second }
}
