package app.napstop.core.trip.runtime.sim

import app.napstop.core.alarm.AlarmConstants
import app.napstop.core.alarm.StopCause
import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.EndReason
import app.napstop.core.trip.GpsLost
import app.napstop.core.trip.Overshoot
import app.napstop.core.trip.TripEvent
import app.napstop.core.trip.TripOutcome
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.UserActionKind
import app.napstop.core.trip.runtime.ForegroundResult
import app.napstop.core.trip.runtime.RestoreCause
import app.napstop.core.trip.runtime.RuntimeConstants
import app.napstop.core.trip.runtime.StartCodes
import app.napstop.core.trip.runtime.StartOutcome
import app.napstop.core.trip.runtime.TrackingMode
import app.napstop.core.trip.runtime.TripMeta
import app.napstop.core.trip.runtime.support.ExpectCase
import app.napstop.core.trip.runtime.support.ExpectReader
import app.napstop.core.trip.runtime.support.Geo
import app.napstop.core.trip.runtime.support.RecordingJournal
import app.napstop.core.trip.runtime.support.SimDriver
import app.napstop.core.trip.runtime.support.TestData
import app.napstop.core.trip.runtime.support.TraceCase
import app.napstop.core.trip.runtime.support.World
import app.napstop.core.trip.runtime.support.eventName
import app.napstop.core.trip.runtime.support.startTrip
import java.io.ByteArrayInputStream
import java.io.File
import kotlin.random.Random
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.json.JSONObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.Tag
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestFactory
import org.junit.jupiter.api.assertThrows

/**
 * Tester T18, beyond the spec cases (risk areas of docs/reviews/T18.md "Ghi chú cho tester"):
 * - TS01: K11 (review minor #3) on the JVM with the T16 auto-stop of 300 s played: does an extra Alarm(OVERSHOOT) come?
 * - TS02: SM19 at the UI speed 10× (SM19 only runs 1/60/600) and at odd speeds (2.5×, 37×, 250×).
 * - TS03–TS05: wake lock (110 min cap): one hold for a 1× trace longer than the cap; UI speeds fit under the cap; FGS
 *   failing → nothing held.
 * - TS06–TS09: process death mid simulated trip (TRACKING, SNOOZED), then a real trip / a new simulated trip; FGS lost
 *   (HEADLESS) mid simulation.
 * - TS10–TS12: bad trace ids / broken GPX → simulation-unavailable; the start gate is free afterwards; XXE never resolved.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class T18TesterSimTest {
    private val checked = setOf("alarm", "preAlert", "overshoot", "gpsLost", "arrived")
    private val compared = setOf("alarm", "preAlert", "overshoot", "gpsLost", "gpsRecovered", "arrived", "snoozed", "lowBatteryRisk", "tripEnded")

    private fun matches(w: ExpectCase.Window, e: TripEvent): Boolean {
        if (eventName(e) != w.event) return false
        if (w.reason != null && (e as? Alarm)?.reason?.name != w.reason) return false
        if (w.ringNow != null && (e as? Alarm)?.ringNow != w.ringNow) return false
        if (w.cause != null && (e as? GpsLost)?.cause?.name != w.cause) return false
        return true
    }

    private fun label(e: TripEvent): String =
        eventName(e) + ((e as? Alarm)?.let { ":${it.reason}:${it.ringNow}" } ?: "") + ((e as? GpsLost)?.let { ":${it.cause}" } ?: "")

    /** One simulated run with every SM19 check; returns (trace second, label) of the compared events. */
    private fun runCase(trace: TraceCase, c: ExpectCase, speed: Double): List<Pair<Double, String>> {
        var out: List<Pair<Double, String>>? = null
        runTest(timeout = kotlin.time.Duration.parse("10m")) {
            val world = World(this, journal = RecordingJournal())
            world.listen()
            val meta = SimDriver.simMeta(trace, c, speed)
            val d = SimDriver(world, meta, silenceAfterMs = c.osRingMaxS?.let { it * 1000L })
            assertEquals(StartOutcome.Started, d.start(trace.destLat, trace.destLng))
            d.runTo(trace.durationS)
            val where = "${trace.traceId}/${c.id}@$speed"
            val events = world.events
            for (w in c.expect.filter { it.event in checked }) {
                val first = events.firstOrNull { matches(w, it.second) }
                assertNotNull(first, "$where: no ${w.event} ${w.reason ?: ""}")
                val at = d.t(first!!.second.atMs)
                assertTrue(at in w.notBefore..w.notAfter, "$where: ${w.event} ${w.reason ?: ""} at $at not in [${w.notBefore}, ${w.notAfter}]")
            }
            for (f in c.forbid) assertTrue(events.none { eventName(it.second) == f }, "$where: forbidden $f")
            assertEquals(events.count { (it.second as? Alarm)?.ringNow == true }, world.alarm.ringNowCalls.size, "$where: ringNow")
            assertEquals(0, world.alarm.ringFallbackCalls.size, "$where: no fallback ring")
            assertEquals(0, world.alarm.doubleRings, "$where: one ring per trip")
            assertTrue(world.log.ops.none { it.startsWith("setWake") || it.startsWith("setFallback") }, "$where: OS alarm")
            assertTrue(world.location.requests.isEmpty(), "$where: FLP asked")
            assertTrue(world.warnings.isEmpty(), "$where: warnings ${world.warnings}")
            out = events.filter { eventName(it.second) in compared }.map { (it.second.atMs - d.simStart) / 1000.0 to label(it.second) }
            world.now { world.runtime.userAction(meta.tripId, UserActionKind.STOP_TRIP) }
            assertEquals(1, world.keepAwake.releases, "$where: wake lock released")
            world.kill()
        }
        return out!!
    }

    // ---------------------------------------------------------------- TS01 K11 vs T16 auto-stop

    /** (alarm t, overshoot t, real ms from ring start to overshoot, Alarm reasons) of K11 with the ring stopping after [ringMaxMs]. */
    private data class K11(val alarmT: Int, val overshootT: Int, val realGapMs: Long, val reasons: List<AlarmReason>, val phaseAtOvershoot: TripPhase)

    private fun k11(ringMaxMs: Long): K11 {
        var r: K11? = null
        runTest(timeout = kotlin.time.Duration.parse("10m")) {
            val trace = ExpectReader.read("coach_gb_phuly_overshoot")
            val c = trace.cases.single { it.id == "distance_1000_overshoot" }
            val world = World(this, journal = RecordingJournal())
            world.listen()
            val meta = SimDriver.simMeta(trace, c, 60.0)
            val d = SimDriver(world, meta, silenceAfterMs = ringMaxMs, maxStepRealMs = 250)
            assertEquals(StartOutcome.Started, d.start(trace.destLat, trace.destLng))
            var overWall: Long? = null
            var phase: TripPhase? = null
            world.runtime.addListener { _, view, _, events ->
                if (overWall == null && events.any { it is Overshoot }) {
                    overWall = world.time.wallMs()
                    phase = view.phase
                }
            }
            d.runTo(trace.durationS)
            val alarms = world.events.map { it.second }.filterIsInstance<Alarm>()
            val over = world.events.first { it.second is Overshoot }.second
            val ringStart = world.alarm.ringNowCalls.first().atWallMs
            r = K11(d.t(alarms.first().atMs), d.t(over.atMs), overWall!! - ringStart, alarms.map { it.reason }, phase!!)
            world.kill()
        }
        return r!!
    }

    @Test
    fun ts01_k11OvershootComesBeforeTheT16AutoStop() {
        val ringMax = AlarmConstants().ringMaxMs
        assertEquals(300_000L, ringMax)
        val k = k11(ringMax)
        println("TS01 K11 at 60x, ringMax $ringMax: $k, margin ${ringMax - k.realGapMs} ms")
        assertTrue(k.alarmT in 2_335..2_360, "alarm at ${k.alarmT}")
        assertTrue(k.overshootT in 2_605..2_680, "overshoot at ${k.overshootT}")
        // After the alarm the trip runs at 1×: the real gap from the ring to the overshoot = trace gap.
        assertTrue(kotlin.math.abs(k.realGapMs - (k.overshootT - k.alarmT) * 1000L) <= 5_000, "real gap ${k.realGapMs}")
        if (k.realGapMs < ringMax) {
            assertEquals(listOf(AlarmReason.DISTANCE), k.reasons, "still ringing: no Alarm(OVERSHOOT)")
            assertEquals(TripPhase.OVERSHOT, k.phaseAtOvershoot)
        } else {
            assertEquals(listOf(AlarmReason.DISTANCE, AlarmReason.OVERSHOOT), k.reasons)
        }
        // Sensitivity: a ring that stops a little earlier than the gap (what a slower FGS start or a 1 s later
        // overshoot on a device could look like) gives the second alarm: K11's "one AlarmMsg" only holds with margin.
        val early = k11(k.realGapMs - 5_000)
        assertEquals(listOf(AlarmReason.DISTANCE, AlarmReason.OVERSHOOT), early.reasons, "ring stopped before the overshoot: $early")
    }

    // ---------------------------------------------------------------- TS02 SM19 at other speeds

    @Tag("slow")
    @TestFactory
    fun ts02_bundledTracesAtTheUiSpeed10xAndOddSpeeds(): List<DynamicTest> =
        ExpectReader.BASE_TRACES.flatMap { id ->
            val trace = ExpectReader.read(id)
            trace.cases.filter { it.status == "final" && it.excludedKeys.isEmpty() }.map { c ->
                DynamicTest.dynamicTest("$id/${c.id}") {
                    val base = runCase(trace, c, 1.0)
                    val speeds = if (c.id.startsWith("distance_1000")) listOf(10.0, 2.5, 37.0, 250.0) else listOf(10.0)
                    for (s in speeds) {
                        val evs = runCase(trace, c, s)
                        assertEquals(base.map { it.second }, evs.map { it.second }, "$id/${c.id}: event sequence at $s")
                        for ((a, b) in base.zip(evs)) {
                            assertTrue(kotlin.math.abs(a.first - b.first) <= 1.0, "$id/${c.id}@$s: ${b.second} at ${b.first} vs ${a.first} at 1x")
                        }
                    }
                }
            }
        }

    // ---------------------------------------------------------------- TS03–TS05 wake lock

    @Test
    fun ts03_aOneXTraceLongerThanTheCapHoldsOnceAndReleasesOnce() =
        runTest(timeout = kotlin.time.Duration.parse("10m")) {
            val trace = ExpectReader.read("coach_md_tb")
            assertTrue(trace.durationS * 1000L > RuntimeConstants().simWakelockCapMs, "trace longer than the 110 min cap at 1×")
            val c = trace.cases.single { it.id == "distance_1000" }
            val world = World(this, journal = RecordingJournal())
            world.listen()
            val meta = SimDriver.simMeta(trace, c, 1.0)
            val d = SimDriver(world, meta)
            assertEquals(StartOutcome.Started, d.start(trace.destLat, trace.destLng))
            d.runTo(trace.durationS)
            assertEquals(listOf(6_600_000L), world.keepAwake.holds, "held once with the cap, never renewed")
            assertTrue(world.alarm.ringNowCalls.isNotEmpty(), "rang (the JVM CPU never sleeps; on a device see protocol SMM1b)")
            world.now { world.runtime.userAction(meta.tripId, UserActionKind.DISMISS) }
            assertEquals(1, world.keepAwake.releases)
            assertFalse(world.keepAwake.held)
            world.kill()
        }

    @Test
    fun ts04_everyBundledTraceFitsUnderTheCapAtTheUiSpeeds10And60() {
        val cap = RuntimeConstants().simWakelockCapMs
        val catalog = File(ExpectReader.fixturesDir, "../../app/assets/sim/catalog.json").canonicalFile
        val traces = JSONObject(catalog.readText()).getJSONArray("traces")
        val overAt1x = ArrayList<String>()
        for (i in 0 until traces.length()) {
            val t = traces.getJSONObject(i)
            val ms = t.getInt("durationS") * 1000L
            assertTrue(ms / 10 < cap, "${t.getString("id")} at 10×: ${ms / 10} ms ≥ cap")
            assertTrue(ms / 60 < cap, "${t.getString("id")} at 60×")
            if (ms > cap) overAt1x += t.getString("id")
        }
        // Known (T18 R1): at 1× these run past the wake lock; with the screen off the simulation may stall on a device.
        assertEquals(listOf("train_hn_dh", "coach_md_tb"), overAt1x)
    }

    @Test
    fun ts05_foregroundServiceFailingLeavesNothingRunning() =
        runTest {
            val bus = ExpectReader.read("bus_hn_brt01")
            val world = World(this, journal = RecordingJournal()).also { it.listen() }
            world.tracking.autoResult = ForegroundResult.Failed("SecurityException")
            val meta = SimDriver.simMeta(bus, bus.cases.single { it.id == "distance_1000" }, 60.0, "simf")
            val r = world.now { world.runtime.start(meta, bus.destLat, bus.destLng) }
            assertEquals(StartOutcome.Rejected(StartCodes.START_FAILED, "SecurityException"), r)
            world.advance(600_000)
            assertTrue(world.keepAwake.holds.isEmpty())
            assertTrue(world.runtime.simTimers.pendingSlots.isEmpty() && !world.runtime.simTimers.wakePending)
            assertTrue(world.alarm.ringNowCalls.isEmpty() && world.alarm.preAlerts.isEmpty())
            assertTrue(world.seen.none { it.view.phase == TripPhase.TRACKING }, "no source playing")
            assertNull(world.runtime.liveTrip())
            // The gate is free: the same simulation starts once the FGS works.
            world.tracking.autoResult = ForegroundResult.Started
            assertEquals(StartOutcome.Started, world.now { world.runtime.start(meta.copy(tripId = "simf2"), bus.destLat, bus.destLng) })
            world.kill()
        }

    // ---------------------------------------------------------------- TS06–TS09 process death / FGS lost

    private val bus: TraceCase by lazy { ExpectReader.read("bus_hn_brt01") }

    private fun busMeta(speed: Double, tripId: String = "sim1"): TripMeta = SimDriver.simMeta(bus, bus.cases.single { it.id == "distance_1000" }, speed, tripId)

    private fun World.osSets(): List<String> = log.ops.filter { it.startsWith("setWake") || it.startsWith("setFallback") }

    private fun reload(scope: TestScope, w: World): World {
        w.kill()
        val w2 = World(scope, store = w.store, scheduler = w.scheduler, alarm = w.alarm, journal = RecordingJournal())
        w2.listen()
        return w2
    }

    @Test
    fun ts06_processDeathWhileTrackingEndsTheTripQuietlyAsCancelled() =
        runTest {
            val w = World(this, journal = RecordingJournal()).also { it.listen() }
            val d = SimDriver(w, busMeta(60.0))
            assertEquals(StartOutcome.Started, d.start(bus.destLat, bus.destLng))
            w.advance(20_000) // 1 200 s of the trace, before the alarm (~2 150 s)
            assertEquals(TripPhase.TRACKING, w.seen.last().view.phase)
            assertTrue(w.alarm.ringNowCalls.isEmpty())
            val w2 = reload(this, w)
            w2.now { w2.runtime.ensureLoaded(RestoreCause.PROCESS_START) }
            w2.advance(3_600_000)
            assertTrue(w2.alarm.ringNowCalls.isEmpty() && w2.alarm.ringFallbackCalls.isEmpty(), "nothing rings")
            assertTrue(w2.tracking.starts.isEmpty())
            assertTrue(w.osSets().isEmpty() && w2.osSets().isEmpty())
            val f = w2.now { w2.runtime.pendingFinished() }.single()
            assertEquals(TripOutcome.CANCELLED, f.outcome, "not rung yet (T10 §3)")
            assertEquals(EndReason.USER_STOP, f.endReason)
            assertFalse(w2.notifier.history.any { it.contains("Interrupted") }, "${w2.notifier.history}")
            assertNull(w2.now { w2.runtime.current() })
            assertTrue(w2.keepAwake.holds.isEmpty(), "no wake lock in the new process")
            // A real trip next: the router is on the OS, FLP is asked.
            assertEquals(StartOutcome.Started, w2.startTrip(TestData.meta("r1"), Geo.latNorth(20_000.0)))
            assertTrue(w2.location.requests.isNotEmpty())
            assertTrue(w2.log.count("setFallback") + w.log.count("setFallback") >= 1, "real trip uses OS alarms: ${w.log.ops}")
            w2.kill()
        }

    @Test
    fun ts07_processDeathWhileSnoozedNeverRingsTheSnoozeEnd() =
        runTest {
            val w = World(this, journal = RecordingJournal()).also { it.listen() }
            val d = SimDriver(w, busMeta(600.0))
            assertEquals(StartOutcome.Started, d.start(bus.destLat, bus.destLng))
            d.runTo(bus.durationS) { w.alarm.ringNowCalls.isNotEmpty() }
            w.now { w.runtime.userAction("sim1", UserActionKind.SNOOZE) }
            w.advance(10_000)
            assertEquals(TripPhase.SNOOZED, w.seen.last().view.phase)
            val rings = w.alarm.ringNowCalls.size
            val w2 = reload(this, w)
            w2.advance(5_000)
            w2.now { w2.runtime.ensureLoaded(RestoreCause.PROCESS_START) }
            w2.advance(600_000) // well past the 60 s snooze
            assertEquals(rings, w2.alarm.ringNowCalls.size, "no SNOOZE_END ring after the death")
            assertTrue(w2.alarm.ringFallbackCalls.isEmpty())
            val f = w2.now { w2.runtime.pendingFinished() }.single()
            assertEquals(EndReason.USER_STOP, f.endReason)
            assertEquals(1, f.snoozeCount)
            assertTrue(w2.alarm.stops.contains(StopCause.TRIP_ENDED))
            assertFalse(w2.notifier.history.any { it.contains("Interrupted") })
            w2.kill()
        }

    @Test
    fun ts08_aNewSimulatedStartAfterADeathEndsTheOldOneFirst() =
        runTest {
            val w = World(this, journal = RecordingJournal()).also { it.listen() }
            assertEquals(StartOutcome.Started, SimDriver(w, busMeta(60.0, "old")).start(bus.destLat, bus.destLng))
            w.advance(10_000)
            val w2 = reload(this, w)
            // No ensureLoaded: the user goes straight to "start" (start loads first, T15 R2-1).
            val d2 = SimDriver(w2, busMeta(600.0, "new"))
            assertEquals(StartOutcome.Started, d2.start(bus.destLat, bus.destLng))
            assertEquals("new", w2.runtime.liveTrip())
            val ended = w2.now { w2.runtime.pendingFinished() }.map { it.tripId }
            assertEquals(listOf("old"), ended)
            d2.runTo(bus.durationS) { w2.alarm.ringNowCalls.any { it.tripId == "new" } }
            assertEquals(1, w2.alarm.ringNowCalls.count { it.tripId == "new" }, "the new simulation rings")
            assertTrue(w2.alarm.ringNowCalls.none { it.tripId == "old" })
            assertEquals(listOf(6_600_000L), w2.keepAwake.holds)
            w2.kill()
        }

    /** FGS lost (OEM) at trace ~600 s; [reopenAfterMs] real ms later the app is opened (null = never). */
    private fun headless(scope: TestScope, reopenAfterMs: Long?): Triple<World, SimDriver, RecordingJournal> {
        val j = RecordingJournal()
        val w = World(scope, journal = j).also { it.listen() }
        val d = SimDriver(w, busMeta(60.0))
        assertEquals(StartOutcome.Started, d.start(bus.destLat, bus.destLng))
        w.advance(10_000) // trace ~600 s
        w.tracking.isForeground = false
        w.runtime.onForegroundLost()
        w.settle()
        assertEquals(TrackingMode.HEADLESS, w.runtime.mode.value)
        val fixesBefore = j.lines.count { it.ev == "fix" }
        assertTrue(w.runtime.simTimers.pendingSlots.isNotEmpty(), "the fallback timer still runs")
        if (reopenAfterMs != null) {
            w.advance(reopenAfterMs)
            assertEquals(fixesBefore, j.lines.count { it.ev == "fix" }, "no fix while HEADLESS")
            w.tracking.autoResult = ForegroundResult.Started
            w.now { w.runtime.onAppVisible() }
            assertEquals(TrackingMode.TRACKING_FGS, w.runtime.mode.value)
            w.advance(1_000) // > one 5 s sample at 60x
            assertTrue(j.lines.count { it.ev == "fix" } > fixesBefore, "the source goes on from the current trip time")
        }
        return Triple(w, d, j)
    }

    @Test
    fun ts09a_foregroundServiceLostBrieflyThenReopenedRingsOnDistance() =
        runTest(timeout = kotlin.time.Duration.parse("5m")) {
            // 1 s real HEADLESS = 60 s of the trace, shorter than the GPS-lost delay.
            val (w, d, _) = headless(this, reopenAfterMs = 1_000)
            d.runTo(bus.durationS) { w.alarm.ringNowCalls.isNotEmpty() || w.alarm.ringFallbackCalls.isNotEmpty() }
            val alarm = w.events.map { it.second }.filterIsInstance<Alarm>().first()
            assertEquals(AlarmReason.DISTANCE, alarm.reason)
            assertTrue(d.t(alarm.atMs) in 2_110..2_225, "DISTANCE window of bus distance_1000 at ${d.t(alarm.atMs)}")
            assertEquals(1, w.alarm.ringNowCalls.size + w.alarm.ringFallbackCalls.size, "rang once")
            w.kill()
        }

    @Test
    fun ts09b_foregroundServiceLostAndNeverReopenedStillWakesTheUser() =
        runTest(timeout = kotlin.time.Duration.parse("5m")) {
            // No FGS, no fix: the in-process timers keep the engine going; the user is woken (GPS_LOST, PRD §4) instead of
            // the trip going silent. In a simulation the HEADLESS gap runs at 60×, so it rings early (observation in report).
            val (w, d, j) = headless(this, reopenAfterMs = null)
            d.runTo(bus.durationS) { w.alarm.ringNowCalls.isNotEmpty() || w.alarm.ringFallbackCalls.isNotEmpty() }
            assertEquals(1, w.alarm.ringNowCalls.size + w.alarm.ringFallbackCalls.size, "woken once")
            val alarm = w.events.map { it.second }.filterIsInstance<Alarm>().first()
            println("TS09b HEADLESS from t~600 never reopened: ${alarm.reason} at t=${d.t(alarm.atMs)}; notices ${w.notifier.history}")
            assertTrue(alarm.reason == AlarmReason.GPS_LOST || alarm.reason == AlarmReason.FALLBACK, "${alarm.reason}")
            assertTrue(d.t(alarm.atMs) < bus.arrivalT, "before the arrival (${d.t(alarm.atMs)})")
            assertTrue(j.lines.any { it.ev == "sim_speed" }, "1x after the alarm")
            assertTrue(w.log.ops.none { it.startsWith("setWake") || it.startsWith("setFallback") }, "still no OS alarm")
            w.kill()
        }

    // ---------------------------------------------------------------- TS10–TS12 bad ids / broken GPX

    private fun rejected(w: World, meta: TripMeta): StartOutcome {
        w.tracking.autoResult = ForegroundResult.Started
        val d = w.scope.async { w.runtime.start(meta, bus.destLat, bus.destLng) }
        w.scope.runCurrent()
        return d.getCompleted()
    }

    private fun assertNothing(w: World, where: String) {
        assertTrue(w.tracking.starts.isEmpty(), "$where: FGS")
        assertEquals(0, w.store.writeActiveCalls, "$where: snapshot")
        assertTrue(w.keepAwake.holds.isEmpty(), "$where: wake lock")
        assertTrue(w.runtime.simTimers.pendingSlots.isEmpty() && !w.runtime.simTimers.wakePending, "$where: timers")
        assertNull(w.runtime.liveTrip(), where)
    }

    @Test
    fun ts10_badTraceIdsAreRefusedBeforeAnyRead() =
        runTest {
            val invalid = listOf("", "a".repeat(65), "train_hn_dh.gpx", "assets/sim/train_hn_dh", "a_", "_a", "a__b", "train-hn", "trаin", " train_hn_dh", "train_hn_dh\n", "..", "a/../b")
            for (id in invalid) {
                val w = World(this, journal = RecordingJournal())
                assertEquals(StartOutcome.Rejected(StartCodes.SIMULATION_UNAVAILABLE, "TraceIdInvalid"), rejected(w, busMeta(60.0).copy(simulation = SimSpec(id, 60.0))), "id '$id'")
                assertTrue(w.traces.opened.isEmpty(), "'$id' never reaches the store")
                assertNothing(w, id)
                w.kill()
            }
            // 64 chars, valid pattern, not bundled: not found (the store is asked).
            val w = World(this, journal = RecordingJournal())
            assertEquals(StartOutcome.Rejected(StartCodes.SIMULATION_UNAVAILABLE, "TraceNotFound"), rejected(w, busMeta(60.0).copy(simulation = SimSpec("a".repeat(64), 60.0))))
            // A trace that exists in fixtures but is not bundled in the app (FakeTraceStore.allowed = the six).
            val app = World(this, journal = RecordingJournal(), traces = app.napstop.core.trip.runtime.support.FakeTraceStore(allowed = ExpectReader.BASE_TRACES.toSet()))
            assertEquals(
                StartOutcome.Rejected(StartCodes.SIMULATION_UNAVAILABLE, "TraceNotFound"),
                rejected(app, busMeta(60.0).copy(simulation = SimSpec("train_longstop_nospd", 60.0))),
            )
            assertNothing(app, "not bundled")
            w.kill()
            app.kill()
        }

    private val header =
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?><gpx version=\"1.1\" xmlns=\"http://www.topografix.com/GPX/1/1\" " +
            "xmlns:napstop=\"https://napstop.app/xmlns/trace/1\"><trk><trkseg>"
    private val footer = "</trkseg></trk></gpx>"

    private fun pt(t: Int, acc: String = "8.0", spd: String? = "10.0", lat: String = "21.0", lon: String = "105.8", time: String? = null, accNs: String = "napstop:acc"): String {
        val ts = time ?: "2026-03-14T01:%02d:%02dZ".format(30 + t / 60, t % 60)
        val spdXml = spd?.let { "<napstop:spd>$it</napstop:spd>" } ?: ""
        return "<trkpt lat=\"$lat\" lon=\"$lon\"><time>$ts</time><extensions><$accNs>$acc</$accNs>$spdXml</extensions></trkpt>"
    }

    private fun gpx(vararg pts: String) = header + pts.joinToString("") + footer

    @TestFactory
    fun ts11_brokenGpxIsTraceInvalidAndTheGateIsFreeAfterwards(): List<DynamicTest> {
        val real = File(ExpectReader.fixturesDir, "train_hn_dh.gpx").readBytes()
        val cases =
            linkedMapOf(
                "empty" to ByteArray(0),
                "no trkpt" to gpx().toByteArray(),
                "acc missing" to (header + "<trkpt lat=\"21\" lon=\"105\"><time>2026-03-14T01:30:00Z</time></trkpt>" + footer).toByteArray(),
                "acc without namespace" to gpx(pt(0, accNs = "acc")).toByteArray(),
                "acc negative" to gpx(pt(0), pt(5, acc = "-1")).toByteArray(),
                "acc NaN" to gpx(pt(0, acc = "NaN")).toByteArray(),
                "spd negative" to gpx(pt(0), pt(5, spd = "-0.5")).toByteArray(),
                "lat 91" to gpx(pt(0, lat = "91")).toByteArray(),
                "lon garbage" to gpx(pt(0, lon = "abc")).toByteArray(),
                "time invalid" to gpx(pt(0, time = "2026-13-01T00:00:00Z")).toByteArray(),
                "time equal" to gpx(pt(0), pt(0)).toByteArray(),
                "time going back" to gpx(pt(0), pt(10), pt(5)).toByteArray(),
                "truncated real trace" to real.copyOf(real.size / 2),
                "binary garbage" to Random(18).nextBytes(4096),
                "UTF-16 BOM garbage" to byteArrayOf(0xFF.toByte(), 0xFE.toByte(), 0x3C, 0x00),
            )
        return cases.map { (name, bytes) ->
            DynamicTest.dynamicTest(name) {
                runTest {
                    val w = World(this, journal = RecordingJournal())
                    w.traces.bytes["bus_hn_brt01"] = bytes
                    assertEquals(StartOutcome.Rejected(StartCodes.SIMULATION_UNAVAILABLE, "TraceInvalid"), rejected(w, busMeta(60.0)), name)
                    assertNothing(w, name)
                    assertTrue(w.warnings.all { !it.contains("21.") && !it.contains("105.") }, "no coordinates in warnings: ${w.warnings}")
                    // The gate is free: a good trace starts right after.
                    w.traces.bytes.remove("bus_hn_brt01")
                    assertEquals(StartOutcome.Started, rejected(w, busMeta(60.0, "ok")), "$name: next start")
                    w.kill()
                }
            }
        }
    }

    @Test
    fun ts12_parserEdgeCases() {
        // A minimal valid trace parses (sanity of the builders above); a single sample is a usable trace.
        val ok = TraceGpx.parse(ByteArrayInputStream(gpx(pt(0), pt(5, spd = null), pt(10)).toByteArray()))
        assertEquals(listOf(0, 5, 10), ok.map { it.t })
        assertNull(ok[1].spdMps)
        assertEquals(1, TraceGpx.parse(ByteArrayInputStream(gpx(pt(0)).toByteArray())).size)
        // External entity (XXE): never resolved, whatever the file says.
        val secret = File.createTempFile("napstop-xxe", ".txt").apply { writeText("7.5"); deleteOnExit() }
        val xxe =
            "<?xml version=\"1.0\"?><!DOCTYPE gpx [<!ENTITY acc SYSTEM \"${secret.toURI()}\">]>" +
                header.removePrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>") +
                "<trkpt lat=\"21\" lon=\"105\"><time>2026-03-14T01:30:00Z</time><extensions><napstop:acc>&acc;</napstop:acc></extensions></trkpt>" + footer
        val e = assertThrows<TraceFormatException> { TraceGpx.parse(ByteArrayInputStream(xxe.toByteArray())) }
        assertFalse(e.message!!.contains("7.5"))
        // Messages name the rule only.
        val m = assertThrows<TraceFormatException> { TraceGpx.parse(ByteArrayInputStream(gpx(pt(0, lat = "91.123456")).toByteArray())) }.message!!
        assertFalse(Regex("\\d").containsMatchIn(m), m)
        // Sub-second timestamps (not produced by tracegen) keep strictly increasing time; t is floored seconds.
        val sub = TraceGpx.parse(ByteArrayInputStream(gpx(pt(0, time = "2026-03-14T01:30:00Z"), pt(0, time = "2026-03-14T01:30:00.500Z"), pt(0, time = "2026-03-14T01:30:01Z")).toByteArray()))
        assertEquals(listOf(0, 0, 1), sub.map { it.t })
    }
}
