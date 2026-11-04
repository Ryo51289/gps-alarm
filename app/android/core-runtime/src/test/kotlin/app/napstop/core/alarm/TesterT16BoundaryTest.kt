package app.napstop.core.alarm

import app.napstop.core.alarm.AlarmData.record
import app.napstop.core.alarm.AlarmData.request
import app.napstop.core.alarm.AlarmData.start
import app.napstop.core.trip.runtime.RingEventKind
import java.util.Locale
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Tester T16 (out of spec): boundaries of liveness / watchdog / session timeout / boot detection / codec / shake, and the
 * "a dead ring in the book must not block the next ring" case (RK-T16-8). Values from spec T16 §5.2, §5.3, §5.5, §6.
 */
class TesterT16BoundaryTest {
    private val c = AlarmConstants()
    private val wall0 = 1_700_000_000_000L
    private val el0 = 5_000_000L
    private val vi = Locale.forLanguageTag("vi-VN")

    private fun env(dtMs: Long = 0, boot: Int? = 7, backup: Boolean = false) = LivenessEnv(wall0 + dtMs, el0 + dtMs, boot, backup)

    // ------------------------------------------------------------------ §5.2 liveness

    @Test
    fun heartbeatAgeExactlyStaleIsAliveOneMsLaterIsDead() {
        val r = record(heartbeatElapsed = el0, heartbeatWall = wall0)
        assertTrue(RingLiveness.alive(r, env(c.heartbeatStaleMs), c), "age == HEARTBEAT_STALE_MS (6 000) counts as alive (≤)")
        assertFalse(RingLiveness.alive(r, env(c.heartbeatStaleMs + 1), c), "age 6 001 ms: dead")
        // Heartbeat "from the future" (elapsed went back without a boot count): never alive.
        assertFalse(RingLiveness.alive(record(heartbeatElapsed = el0 + 1, bootCount = null), env(0, boot = null), c))
    }

    @Test
    fun stuckRingBoundaryIsRingMaxPlusGrace() {
        val edge = c.ringMaxMs + c.livenessGraceMs
        // Heartbeat always fresh: only the wall-clock cap decides.
        val atEdge = record(heartbeatElapsed = el0 + edge, heartbeatWall = wall0 + edge)
        assertTrue(RingLiveness.alive(atEdge, env(edge), c), "nowWall == startedAt + RING_MAX + grace: still alive (>)")
        val past = record(heartbeatElapsed = el0 + edge + 1, heartbeatWall = wall0 + edge + 1)
        assertFalse(RingLiveness.alive(past, env(edge + 1), c))
    }

    @Test
    fun startingMarkerCountsForExactlyRingConfirmMs() {
        val st = StartingMarker(AlarmData.TRIP, 200L, RingSource.ENGINE, el0, wall0)
        assertTrue(RingLiveness.facts(null, st, env(c.ringConfirmMs), c).ringingNow, "3 000 ms after ringNow: still STARTING")
        assertFalse(RingLiveness.facts(null, st, env(c.ringConfirmMs + 1), c).ringingNow)
        // A marker of another trip never counts for this trip's book.
        val other = record(tripId = "t2", ringing = false, ringSeq = 1)
        assertFalse(RingLiveness.pendingStart(other, st, env(1_000), c))
        // stopSeq == ringSeq: the stop covers this ring (≥).
        assertFalse(RingLiveness.facts(record(ringing = false, ringSeq = 50, stopSeq = 200), st, env(1_000), c).ringingNow)
        assertTrue(RingLiveness.facts(record(ringing = false, ringSeq = 50, stopSeq = 199), st, env(1_000), c).ringingNow)
    }

    // ------------------------------------------------------------------ §5.3 watchdog

    @Test
    fun watchdogSilencesExactlyAtRingMaxAndRestartsJustBefore() {
        // Dead ring (heartbeat 7 s old), restarts left.
        fun deadAt(dt: Long) = record(heartbeatElapsed = el0 + dt - 7_000, heartbeatWall = wall0 + dt - 7_000)
        assertEquals(WatchAction.Restart(1), RingWatchdogPolicy.decide(deadAt(c.ringMaxMs - 1), null, env(c.ringMaxMs - 1), c))
        assertEquals(WatchAction.Silence(wall0 + c.ringMaxMs), RingWatchdogPolicy.decide(deadAt(c.ringMaxMs), null, env(c.ringMaxMs), c))
        // Unconfirmed start: exactly RING_CONFIRM_MS → wait; +1 → restart (first), then backup when restarts are used up.
        val st = StartingMarker(AlarmData.TRIP, 200L, RingSource.ENGINE, el0, wall0)
        assertEquals(WatchAction.None, RingWatchdogPolicy.decide(null, st, env(c.ringConfirmMs), c))
        assertEquals(WatchAction.Restart(1), RingWatchdogPolicy.decide(null, st, env(c.ringConfirmMs + 1), c))
        val used = record(ringing = false, ringSeq = 100, restarts = c.ringRestartMax)
        assertEquals(WatchAction.Backup, RingWatchdogPolicy.decide(used, st, env(c.ringConfirmMs + 1), c))
    }

    // ------------------------------------------------------------------ §5.5 session timeout

    @Test
    fun resumeAtExactlyRingMaxEndsSilencedOneMsEarlierStillRings() {
        val now = wall0 + 1_000_000
        val (ended, fx) =
            RingSessionMachine.reduce(RingState(), RingInput.Start(start(resume = now - c.ringMaxMs), false, null, now, el0, 7), c, vi)
        assertEquals(RingPhase.ENDED, ended.phase)
        assertEquals(RingFx.SendEvent(RingEventKind.SILENCED, now), fx.filterIsInstance<RingFx.SendEvent>().single())
        assertTrue(fx.none { it is RingFx.StartAudio }, "a ring past RING_MAX never sounds again")

        val (ringing, fx2) =
            RingSessionMachine.reduce(RingState(), RingInput.Start(start(resume = now - c.ringMaxMs + 1), false, null, now, el0, 7), c, vi)
        assertEquals(RingPhase.RINGING, ringing.phase)
        assertEquals(RingFx.ScheduleTimeout(1), fx2.filterIsInstance<RingFx.ScheduleTimeout>().single())
        assertNotNull(fx2.filterIsInstance<RingFx.StartAudio>().singleOrNull())
    }

    @Test
    fun aStartInTheFutureOfTheWallClockRingsTheFullTime() {
        // Wall clock moved back after the ring started (user / network time): elapsed is clamped to 0, the ring is not cut.
        val now = wall0
        val (s, fx) = RingSessionMachine.reduce(RingState(), RingInput.Start(start(resume = now + 3_600_000), false, null, now, el0, 7), c, vi)
        assertEquals(RingPhase.RINGING, s.phase)
        assertEquals(RingFx.ScheduleTimeout(c.ringMaxMs), fx.filterIsInstance<RingFx.ScheduleTimeout>().single())
        assertEquals(0L, fx.filterIsInstance<RingFx.StartAudio>().single().elapsedMs)
    }

    // ------------------------------------------------------------------ RingBoot

    @Test
    fun bootDetectionBoundaries() {
        val now = 2_000_000_000L
        assertFalse(RingBoot.fromOtherBoot(record(ringSeq = now, bootCount = null), null, now), "seq == now: this boot")
        assertTrue(RingBoot.fromOtherBoot(record(ringSeq = now + 1, bootCount = null), null, now))
        assertTrue(RingBoot.fromOtherBoot(record(ringSeq = 1, stopSeq = now + 1, bootCount = null), null, now))
        assertTrue(RingBoot.fromOtherBoot(record(ringSeq = 1, bootCount = 6), 7, now))
        assertFalse(RingBoot.fromOtherBoot(record(ringSeq = 1, bootCount = 7), 7, now))
        // Unknown boot on one side only: seqs alone decide.
        assertFalse(RingBoot.fromOtherBoot(record(ringSeq = 1, bootCount = 6), null, now))
        assertEquals(1_999_999L, RingBoot.nanosBound(1))
        // A sanitized book keeps the user facts and never blocks a ring.
        val old = record(ringSeq = now + 5, stopSeq = now + 5, ringing = false, snoozedAt = 42L, endedBy = RingEnd.SNOOZED, bootCount = 6)
        val s = RingBoot.sanitize(old, 7, now)!!
        assertNull(s.stopSeq)
        assertEquals(42L, s.snoozedAtWallMs)
        assertEquals(7, s.bootCount)
        assertFalse(s.ringing)
    }

    // ------------------------------------------------------------------ RK-T16-8 / missed alarm

    @Test
    fun aDeadRingInTheBookDoesNotBlockTheNextRing() {
        val clock = FakeRingClock(wall = wall0, elapsed = el0)
        val facts = MemoryFacts()
        val transport = FakeTransport()
        val core = AlarmControllerCore(transport, facts, clock, { AlarmData.ringConfig(it) }, { _, _ -> }, { }, c, { }, { vi })
        // :ring died 7 s ago while ringing (book still says ringing, heartbeat stale), no watchdog ran.
        facts.records[AlarmData.TRIP] = record(ringSeq = el0 * 1_000_000L - 10_000_000_000L, heartbeatElapsed = el0 - 7_000, heartbeatWall = wall0 - 7_000)
        assertFalse(core.ringFacts(AlarmData.TRIP).ringingNow)
        core.ringNow(request())
        assertEquals(1, transport.started.size, "a fresh ring service start, not just an Update to a dead :ring")
        assertTrue(transport.commands.none { it is RingCommand.Update })
        assertTrue(core.ringFacts(AlarmData.TRIP).ringingNow)
    }

    @Test
    fun aRingOfAnotherTripDoesNotCountAsRingingForThisTrip() {
        val clock = FakeRingClock(wall = wall0, elapsed = el0)
        val facts = MemoryFacts()
        val transport = FakeTransport()
        val core = AlarmControllerCore(transport, facts, clock, { AlarmData.ringConfig(it) }, { _, _ -> }, { }, c, { }, { vi })
        core.ringNow(request(tripId = "t2"))
        assertFalse(core.ringFacts(AlarmData.TRIP).ringingNow)
        core.ringNow(request())
        assertEquals(listOf("t2", AlarmData.TRIP), transport.started.map { it.request.tripId })
    }

    // ------------------------------------------------------------------ codec / dismiss rules

    @Test
    fun tripIdLengthAndCharsetAtTheEdge() {
        val ok = "a".repeat(64)
        val map = RingStartCodec.toMap(start(req = request(tripId = ok)))
        assertEquals(ok, RingStartCodec.fromMap(map)!!.request.tripId)
        for (bad in listOf("a".repeat(65), "", "a/b", "../x", "t 1", "ga-đích")) {
            assertNull(RingStartCodec.fromMap(map + ("tripId" to bad)), bad)
        }
    }

    @Test
    fun shakePeakExactlyAtThresholdAndGapCount() {
        val g = AlarmConstants.G * c.shakeG
        val d = ShakeDetector(c)
        var t = 0L
        // Peak exactly at 2.2 g, then back to rest, every SHAKE_MIN_GAP_MS exactly: every peak counts.
        repeat(c.shakePeaksRequired) {
            d.onSample(0f, 0f, g, t)
            d.onSample(0f, 0f, AlarmConstants.G, t + 20)
            t += c.shakeMinGapMs
        }
        assertTrue(d.onSample(0f, 0f, AlarmConstants.G, t).done, "20 peaks ≥ 2.2 g, ≥ 120 ms apart → dismissed")
        // Just below the threshold: never counts.
        val d2 = ShakeDetector(c)
        var t2 = 0L
        repeat(100) {
            d2.onSample(0f, 0f, g * 0.999f, t2)
            d2.onSample(0f, 0f, AlarmConstants.G, t2 + 20)
            t2 += 200
        }
        assertEquals(0, d2.onSample(0f, 0f, AlarmConstants.G, t2).count)
        // Peaks 119 ms apart: only every other one counts.
        val d3 = ShakeDetector(c)
        var t3 = 0L
        repeat(10) {
            d3.onSample(0f, 0f, g, t3)
            d3.onSample(0f, 0f, AlarmConstants.G, t3 + 20)
            t3 += c.shakeMinGapMs - 1
        }
        assertEquals(5, d3.onSample(0f, 0f, AlarmConstants.G, t3).count)
    }

    @Test
    fun swipeEdgeWithZeroWidthTrackNeverCompletes() {
        // Degenerate layout (track not measured yet): no accidental dismiss.
        assertEquals(0f, SwipeRule.fraction(10f, 72f, 72f))
        assertEquals(0f, SwipeRule.fraction(500f, 0f, 72f))
        assertEquals(0f, SwipeRule.fraction(Float.NaN, 300f, 72f))
        assertFalse(SwipeRule.isComplete(SwipeRule.fraction(10f, 72f, 72f)))
        // 95 % of a 228 px travel = 216.6 px: 216 is not enough, 217 is.
        assertFalse(SwipeRule.isComplete(SwipeRule.fraction(216f, 300f, 72f)))
        assertTrue(SwipeRule.isComplete(SwipeRule.fraction(217f, 300f, 72f)))
    }
}
