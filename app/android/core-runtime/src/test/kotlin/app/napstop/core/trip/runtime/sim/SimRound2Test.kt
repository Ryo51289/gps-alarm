package app.napstop.core.trip.runtime.sim

import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.runtime.FixMapper
import app.napstop.core.trip.runtime.RawFix
import app.napstop.core.trip.runtime.StartOutcome
import app.napstop.core.trip.runtime.support.ExpectReader
import app.napstop.core.trip.runtime.support.Geo
import app.napstop.core.trip.runtime.support.RecordingJournal
import app.napstop.core.trip.runtime.support.SimDriver
import app.napstop.core.trip.runtime.support.TestData
import app.napstop.core.trip.runtime.support.World
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** T18 after review: SM09b (Step time of a simulated fix) and SM15b (notification throttle at the current speed). */
@OptIn(ExperimentalCoroutinesApi::class)
class SimRound2Test {
    private val nanos = 10_000_000_000L

    private fun raw(simFixAtMs: Long?, ageMs: Long = 0) =
        RawFix(Geo.latNorth(20_000.0), Geo.DEST_LNG, 8f, 15f, nanos - ageMs * 1_000_000L, simFixAtMs = simFixAtMs)

    @Test
    fun sm09b_stepTimeIsTheSampleTimeClampedToTheLastStepAndNow() {
        val e = 1_000_000L
        val n = 1_060_000L
        // (a) E < F < N: the sample's own time.
        val fa = 1_030_000L
        assertEquals(fa, FixMapper.stepAtMs(raw(fa), e, n))
        assertEquals(fa, FixMapper.map(raw(fa), FixMapper.stepAtMs(raw(fa), e, n), nanos)!!.fixAtMs)
        // (b) F < E (a Tick came after the sample): the last Step's time, fixAtMs stays F.
        val fb = 990_000L
        assertEquals(e, FixMapper.stepAtMs(raw(fb), e, n))
        assertEquals(fb, FixMapper.map(raw(fb), FixMapper.stepAtMs(raw(fb), e, n), nanos)!!.fixAtMs)
        // (c) F > N: now, fixAtMs now.
        val fc = 1_070_000L
        assertEquals(n, FixMapper.stepAtMs(raw(fc), e, n))
        assertEquals(n, FixMapper.map(raw(fc), FixMapper.stepAtMs(raw(fc), e, n), nanos)!!.fixAtMs)
        // (d) FLP: now, fixAtMs = now - age (T15).
        assertEquals(n, FixMapper.stepAtMs(raw(null, ageMs = 3_000), e, n))
        assertEquals(n - 3_000, FixMapper.map(raw(null, ageMs = 3_000), n, nanos)!!.fixAtMs)
        for (f in listOf(fa, fb, fc)) assertTrue(FixMapper.stepAtMs(raw(f), e, n) >= e, "never before the last Step")
    }

    /** A one-sample trace: after t 0 nothing comes from the source, so the test controls the next fixes. */
    private val oneSample =
        """<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1" xmlns:napstop="https://napstop.app/xmlns/trace/1">
  <trk><trkseg>
<trkpt lat="${"%.7f".format(java.util.Locale.ROOT, Geo.latNorth(30_000.0))}" lon="${Geo.DEST_LNG}"><time>2026-03-14T02:00:00Z</time><extensions><napstop:acc>8.0</napstop:acc><napstop:spd>15.0</napstop:spd></extensions></trkpt>
  </trkseg></trk>
</gpx>
"""

    @Test
    fun sm09b_theRuntimeStampsASimulatedFixWithTheClampedTime() =
        runTest {
            val w = World(this, journal = RecordingJournal())
            w.listen()
            w.traces.bytes["one_sample"] = oneSample.toByteArray()
            val meta = TestData.meta("s1").copy(simulation = SimSpec("one_sample", 1.0))
            val d = SimDriver(w, meta)
            assertEquals(StartOutcome.Started, d.start(Geo.DEST_LAT, Geo.DEST_LNG))
            w.advance(1_000)
            val e1 = w.seen.last().view.atMs
            w.advance(10_000) // no Step meanwhile (awake Tick at 60 s)
            assertEquals(e1, w.seen.last().view.atMs)
            val n1 = d.tripNow()
            // (a) E < F < N.
            val fa = e1 + 5_000
            w.runtime.onRawFix(RawFix(Geo.latNorth(29_900.0), Geo.DEST_LNG, 8f, 15f, w.time.elapsedNanos(), simFixAtMs = fa))
            w.settle()
            assertEquals(fa, w.seen.last().view.atMs)
            // (b) F < E.
            w.advance(10_000)
            val e2 = w.seen.last().view.atMs
            val fb = fa - 1_000
            w.runtime.onRawFix(RawFix(Geo.latNorth(29_850.0), Geo.DEST_LNG, 8f, 15f, w.time.elapsedNanos(), simFixAtMs = fb))
            w.settle()
            assertEquals(e2, w.seen.last().view.atMs, "never before the last Step")
            // (c) F > N.
            val n2 = d.tripNow()
            w.runtime.onRawFix(RawFix(Geo.latNorth(29_800.0), Geo.DEST_LNG, 8f, 15f, w.time.elapsedNanos(), simFixAtMs = n2 + 30_000))
            w.settle()
            assertEquals(n2, w.seen.last().view.atMs)
            assertTrue(n1 < n2)
            assertTrue(w.warnings.isEmpty(), "${w.warnings}")
            w.kill()
        }

    @Test
    fun sm15b_notificationThrottleFollowsTheCurrentSpeed() =
        runTest(timeout = kotlin.time.Duration.parse("5m")) {
            val trace = ExpectReader.read("coach_gb_phuly_overshoot")
            val c = trace.cases.single { it.id == "distance_1000_overshoot" }
            val w = World(this, journal = RecordingJournal())
            w.listen()
            val d = SimDriver(w, SimDriver.simMeta(trace, c, 60.0), maxStepRealMs = 500)
            assertEquals(StartOutcome.Started, d.start(trace.destLat, trace.destLng))
            d.runTo(trace.durationS) { w.alarm.ringNowCalls.isNotEmpty() }
            val alarmAt = w.time.wallMs()
            d.runTo(2_620) // ~250 s real at 1× after the alarm
            val notices = w.tracking.notices
            val walls = w.tracking.noticeWallMs
            assertEquals(notices.size, walls.size)
            fun gaps(range: IntRange) = range.drop(1).filter { notices[it].phase == notices[it - 1].phase }.map { walls[it] - walls[it - 1] }
            // Before the alarm (60×): more often than a real trip, never closer than 1 s.
            val firstAlarming = notices.indexOfFirst { it.phase != TripPhase.ACQUIRING && it.phase != TripPhase.TRACKING }
            assertTrue(firstAlarming > 0)
            val preGaps = gaps(0 until firstAlarming)
            assertTrue(preGaps.isNotEmpty())
            assertTrue(preGaps.all { it >= 1_000 }, "pre $preGaps")
            assertTrue(preGaps.any { it < 15_000 }, "faster than a real trip before the alarm: $preGaps")
            // After the rebase to 1× (D3): as a real trip.
            val firstAfter = walls.indexOfFirst { it > alarmAt }
            assertTrue(firstAfter > 0)
            val postGaps = gaps(firstAfter until notices.size)
            assertTrue(postGaps.size >= 2, "updates after the alarm: $postGaps")
            assertTrue(postGaps.all { it >= 15_000 }, "post $postGaps")
            w.kill()
        }
}
