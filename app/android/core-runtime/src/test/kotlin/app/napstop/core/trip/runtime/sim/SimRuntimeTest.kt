package app.napstop.core.trip.runtime.sim

import app.napstop.core.alarm.StopCause
import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.EndReason
import app.napstop.core.trip.GpsLost
import app.napstop.core.trip.GpsLostCause
import app.napstop.core.trip.TripOutcome
import app.napstop.core.trip.UserActionKind
import app.napstop.core.trip.runtime.BatteryReading
import app.napstop.core.trip.runtime.LocationAccess
import app.napstop.core.trip.runtime.RestoreCause
import app.napstop.core.trip.runtime.StartCodes
import app.napstop.core.trip.runtime.StartOutcome
import app.napstop.core.trip.runtime.TripNotice
import app.napstop.core.trip.runtime.TripMeta
import app.napstop.core.trip.runtime.support.ExpectReader
import app.napstop.core.trip.runtime.support.Geo
import app.napstop.core.trip.runtime.support.RecordingJournal
import app.napstop.core.trip.runtime.support.SimDriver
import app.napstop.core.trip.runtime.support.TestData
import app.napstop.core.trip.runtime.support.TraceCase
import app.napstop.core.trip.runtime.support.World
import app.napstop.core.trip.runtime.support.startTrip
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Runnable
import kotlinx.coroutines.async
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** T18 §6 lifecycle of a simulated trip in the runtime: SM12–SM14, SM16–SM18, SM23, SM24. */
@OptIn(ExperimentalCoroutinesApi::class)
class SimRuntimeTest {
    private val bus: TraceCase by lazy { ExpectReader.read("bus_hn_brt01") }

    private fun busMeta(speed: Double, tripId: String = "sim1"): TripMeta = SimDriver.simMeta(bus, bus.cases.single { it.id == "distance_1000" }, speed, tripId)

    private fun simWorld(scope: TestScope, journal: RecordingJournal = RecordingJournal()): World = World(scope, journal = journal).also { it.listen() }

    private fun World.osSets(): List<String> = log.ops.filter { it.startsWith("setWake") || it.startsWith("setFallback") }

    // ---------------------------------------------------------------- SM12 start failures

    /** Disk dispatcher that holds every task until [release] (a trace read that hangs, in virtual time). */
    private class StuckDispatcher(private val target: CoroutineDispatcher) : CoroutineDispatcher() {
        private val held = ArrayList<Runnable>()

        override fun dispatch(context: CoroutineContext, block: Runnable) {
            synchronized(held) { held += block }
        }

        fun release() {
            val q = synchronized(held) { held.toList().also { held.clear() } }
            q.forEach { target.dispatch(EmptyCoroutineContext, it) }
        }
    }

    private fun rejected(w: World, meta: TripMeta, advanceMs: Long = 0): StartOutcome {
        w.tracking.autoResult = app.napstop.core.trip.runtime.ForegroundResult.Started
        val d = w.scope.async { w.runtime.start(meta, bus.destLat, bus.destLng) }
        w.scope.runCurrent()
        if (advanceMs > 0) w.advance(advanceMs)
        return d.getCompleted()
    }

    private fun assertNothingStarted(w: World, where: String) {
        assertTrue(w.tracking.starts.isEmpty(), "$where: tracking.start")
        assertEquals(0, w.store.writeActiveCalls, "$where: snapshot written")
        assertTrue(w.osSets().isEmpty(), "$where: OS alarms")
        assertTrue(w.runtime.simTimers.pendingSlots.isEmpty() && !w.runtime.simTimers.wakePending, "$where: sim timers")
        assertTrue(w.keepAwake.holds.isEmpty(), "$where: wake lock")
        assertNull(w.runtime.liveTrip(), where)
    }

    @Test
    fun sm12_badTracesAndMissingConditionsRefuseTheStart() =
        runTest {
            for ((id, code) in listOf("stub/normal" to "TraceIdInvalid", "../x" to "TraceIdInvalid", "UPPER" to "TraceIdInvalid", "no_such_trace" to "TraceNotFound")) {
                val w = simWorld(this)
                val r = rejected(w, busMeta(60.0).copy(simulation = SimSpec(id, 60.0)))
                assertEquals(StartOutcome.Rejected(StartCodes.SIMULATION_UNAVAILABLE, code), r, id)
                assertNothingStarted(w, id)
            }
            // Broken GPX.
            val broken = simWorld(this)
            broken.traces.bytes["bus_hn_brt01"] = "<gpx><trk><trkseg><trkpt lat=\"1\"".toByteArray()
            assertEquals(StartOutcome.Rejected(StartCodes.SIMULATION_UNAVAILABLE, "TraceInvalid"), rejected(broken, busMeta(60.0)))
            assertNothingStarted(broken, "broken")
            // A read that hangs: TraceLoadTimeout after simTraceLoadBudgetMs (3 s), the start never waits longer.
            val stuckIo = StuckDispatcher(StandardTestDispatcher(testScheduler))
            val stuck = World(this, io = stuckIo, journal = RecordingJournal())
            val r = rejected(stuck, busMeta(60.0), advanceMs = 6_000)
            assertEquals(StartOutcome.Rejected(StartCodes.SIMULATION_UNAVAILABLE, "TraceLoadTimeout"), r)
            assertNothingStarted(stuck, "stuck")
            stuckIo.release()
            runCurrent()
            // Precise location missing: permission-missing, as a real trip (D6).
            val coarse = simWorld(this)
            coarse.env.access = LocationAccess(fineGranted = false, coarseGranted = true, servicesEnabled = true, playServicesAvailable = true)
            assertEquals(StartOutcome.Rejected(StartCodes.PERMISSION_MISSING, null, listOf("precise")), rejected(coarse, busMeta(60.0)))
            assertNothingStarted(coarse, "coarse")
            val hidden = simWorld(this)
            hidden.visibility.visible = false
            assertEquals(StartOutcome.Rejected(StartCodes.NOT_FOREGROUND), rejected(hidden, busMeta(60.0)))
            assertNothingStarted(hidden, "hidden")
            assertTrue(hidden.traces.opened.isEmpty(), "trace not read before the checks")
            // No Google Play services: a simulation does not need FLP.
            val noPlay = simWorld(this)
            noPlay.env.access = noPlay.env.access.copy(playServicesAvailable = false)
            assertEquals(StartOutcome.Started, rejected(noPlay, busMeta(60.0)))
            noPlay.kill()
            listOf(broken, stuck, coarse, hidden).forEach { it.kill() }
        }

    // ---------------------------------------------------------------- SM13 start

    @Test
    fun sm13_aSimulatedStartUsesTheSimulationSourceAndTimersOnly() =
        runTest {
            val w = simWorld(this)
            var seenAtReturn = -1
            val meta = busMeta(60.0)
            w.tracking.autoResult = app.napstop.core.trip.runtime.ForegroundResult.Started
            val started = async { w.runtime.start(meta, bus.destLat, bus.destLng).also { seenAtReturn = w.seen.size } }
            runCurrent()
            assertEquals(StartOutcome.Started, started.await())
            assertTrue(seenAtReturn >= 1, "TripStateUpdate (ACQUIRING) before start returned")
            assertEquals(app.napstop.core.trip.TripPhase.ACQUIRING, w.seen.first().view.phase)
            assertEquals(1, w.tracking.starts.size)
            assertTrue(w.location.requests.isEmpty(), "FLP not asked")
            assertTrue(w.osSets().isEmpty(), "no OS alarm: ${w.log.ops}")
            assertEquals(1, w.runtime.simTimers.pendingSlots.size, "one fallback timer")
            assertTrue(w.runtime.simTimers.wakePending, "one wake timer")
            assertEquals(listOf(6_600_000L), w.keepAwake.holds)
            assertTrue(w.store.ledger.activeSimulated)
            assertEquals("sim1", w.store.ledger.activeTripId)
            val (m, _) = w.now { w.runtime.current() }!!
            assertEquals(SimSpec("bus_hn_brt01", 60.0), m.simulation)
            // Fixes come from the trace (the ACQUIRING → TRACKING step happens without FLP).
            w.advance(2_000)
            assertTrue(w.seen.any { it.view.phase == app.napstop.core.trip.TripPhase.TRACKING })
            assertTrue(w.now { w.runtime.debugDump() }.contains("sim=bus_hn_brt01@60.0"))
            w.kill()
        }

    // ---------------------------------------------------------------- SM14 no battery / availability

    @Test
    fun sm14_aSimulatedTripGetsNoBatteryOrLocationState() =
        runTest {
            fun inputs(j: RecordingJournal) = j.lines.filter { it.ev == "step" }.mapNotNull { it.fields["input"] as String? }.toSet()
            val j = RecordingJournal()
            val w = simWorld(this, j)
            w.env.batteryReading = BatteryReading(80, false)
            assertEquals(StartOutcome.Started, SimDriver(w, busMeta(60.0)).start(bus.destLat, bus.destLng))
            w.advance(1_000)
            w.env.batteryReading = BatteryReading(4, false)
            w.env.access = LocationAccess(fineGranted = false, coarseGranted = false, servicesEnabled = false, playServicesAvailable = true)
            w.runtime.onDeviceStateChanged()
            w.advance(5_000)
            assertFalse("BatterySample" in inputs(j), "${inputs(j)}")
            assertFalse("LocationAvailability" in inputs(j), "${inputs(j)}")
            assertTrue("LocationFix" in inputs(j), "the trip goes on")
            w.kill()
            // The same with a real trip: both come in (L41).
            val jr = RecordingJournal()
            val real = World(this, journal = jr).also { it.listen() }
            real.env.batteryReading = BatteryReading(80, false)
            assertEquals(StartOutcome.Started, real.startTrip(TestData.meta("r1")))
            real.env.batteryReading = BatteryReading(4, false)
            real.env.access = LocationAccess(fineGranted = false, coarseGranted = false, servicesEnabled = false, playServicesAvailable = true)
            real.runtime.onDeviceStateChanged()
            real.advance(1_000)
            assertTrue("BatterySample" in inputs(jr), "${inputs(jr)}")
            assertTrue("LocationAvailability" in inputs(jr), "${inputs(jr)}")
            real.kill()
        }

    // ---------------------------------------------------------------- SM16, SM17 process death

    /** A simulated bus trip at 600× run until it rings; returns the world (alive). */
    private fun ringingSim(scope: TestScope): World {
        val w = simWorld(scope)
        val d = SimDriver(w, busMeta(600.0))
        assertEquals(StartOutcome.Started, d.start(bus.destLat, bus.destLng))
        d.runTo(bus.durationS) { w.alarm.ringNowCalls.isNotEmpty() }
        assertEquals(1, w.alarm.ringNowCalls.size)
        return w
    }

    @Test
    fun sm16_aSimulatedTripIsEndedWhenTheNextProcessLoadsIt() =
        runTest {
            for (cause in listOf(RestoreCause.PROCESS_START, RestoreCause.BOOT)) {
                val w = ringingSim(this)
                assertTrue(w.alarm.facts["sim1"]!!.ringing)
                assertTrue(w.store.active!!.meta.simulation != null)
                w.kill()
                val rings = w.alarm.ringNowCalls.size
                val stopsBefore = w.alarm.stops.size
                val w2 = World(this, store = w.store, scheduler = w.scheduler, alarm = w.alarm, journal = RecordingJournal())
                w2.listen()
                w2.now { w2.runtime.ensureLoaded(cause) }
                w2.advance(120_000)
                assertEquals(rings, w2.alarm.ringNowCalls.size, "$cause: no ring")
                assertTrue(w2.alarm.ringFallbackCalls.isEmpty(), "$cause: no fallback ring")
                assertTrue(w2.tracking.starts.isEmpty(), "$cause: no FGS")
                assertTrue(w.osSets().isEmpty() && w2.osSets().isEmpty(), "$cause: no OS alarm")
                assertTrue(w2.runtime.simTimers.pendingSlots.isEmpty() && !w2.runtime.simTimers.wakePending)
                assertEquals(listOf(StopCause.TRIP_ENDED), w2.alarm.stops.drop(stopsBefore), "$cause: the ring of :ring is stopped")
                assertEquals(listOf("sim1"), w2.alarm.cleared.filter { it == "sim1" }, "$cause: clearTrip once")
                val finished = w2.now { w2.runtime.pendingFinished() }.single()
                assertEquals(EndReason.USER_STOP, finished.endReason)
                assertEquals(TripOutcome.ON_TIME, finished.outcome, "$cause: it rang (T10 §3)")
                assertNull(w2.now { w2.runtime.current() })
                assertFalse(w2.notifier.history.any { it.contains("Interrupted") }, "$cause: ${w2.notifier.history}")
                assertNull(w2.store.ledger.activeTripId)
                assertFalse(w2.store.ledger.activeSimulated)
                assertTrue("sim1" in w2.store.ledger.endedTripIds)
                assertNull(w2.store.active, "$cause: snapshot gone")
                assertTrue((w2.journal as RecordingJournal).lines.any { it.ev == "sim_end" && it.fields["cause"] == cause.name })
                w2.kill()
            }
        }

    @Test
    fun sm17_aLostSnapshotOfASimulatedTripIsForgottenQuietly() =
        runTest {
            val w = ringingSim(this)
            w.kill()
            w.store.active = null
            assertTrue(w.store.ledger.activeSimulated)
            val w2 = World(this, store = w.store, scheduler = w.scheduler, alarm = w.alarm)
            w2.now { w2.runtime.ensureLoaded(RestoreCause.PROCESS_START) }
            w2.advance(60_000)
            assertTrue(w2.notifier.history.isEmpty(), "no Interrupted: ${w2.notifier.history}")
            assertNull(w2.store.ledger.activeTripId)
            assertFalse(w2.store.ledger.activeSimulated)
            assertTrue("sim1" in w2.store.ledger.endedTripIds)
            w2.kill()
        }

    // ---------------------------------------------------------------- SM18 end of a simulated trip

    @Test
    fun sm18_theEndOfASimulatedTripDetachesEverythingAndARealTripUsesTheOs() =
        runTest {
            val w = ringingSim(this)
            w.now { w.runtime.userAction("sim1", UserActionKind.DISMISS) }
            assertEquals(1, w.keepAwake.releases)
            assertFalse(w.keepAwake.held)
            assertTrue(w.runtime.simTimers.pendingSlots.isEmpty() && !w.runtime.simTimers.wakePending)
            assertFalse(w.store.ledger.activeSimulated)
            assertEquals(TripOutcome.ON_TIME, w.store.finished["sim1"]!!.outcome)
            val steps = w.seen.size
            w.advance(600_000)
            assertEquals(steps, w.seen.size, "the source and timers are gone")
            assertTrue(w.warnings.isEmpty(), "${w.warnings}")
            // A real trip next: FLP gets the request, the OS gets the alarms.
            assertEquals(StartOutcome.Started, w.startTrip(TestData.meta("r1"), Geo.latNorth(20_000.0)))
            assertTrue(w.location.requests.isNotEmpty(), "override removed")
            assertTrue(w.log.count("setFallback") >= 1, "router back to the OS: ${w.log.ops}")
            assertFalse(w.store.ledger.activeSimulated)
            assertEquals(1, w.keepAwake.holds.size, "no wake lock for a real trip")
            w.kill()
        }

    // ---------------------------------------------------------------- SM23 nothing after death

    @Test
    fun sm23_nothingRingsAfterTheProcessDied() =
        runTest {
            val w = simWorld(this)
            val d = SimDriver(w, busMeta(60.0))
            assertEquals(StartOutcome.Started, d.start(bus.destLat, bus.destLng))
            w.advance(10_000) // 600 s of the trace
            w.kill()
            val rings = w.alarm.ringNowCalls.size
            val pre = w.alarm.preAlerts.size
            w.advance(2 * 3_600_000L)
            assertEquals(rings, w.alarm.ringNowCalls.size)
            assertTrue(w.alarm.ringFallbackCalls.isEmpty())
            assertEquals(pre, w.alarm.preAlerts.size)
            assertTrue(w.alarm.overshoots.isEmpty())
            assertTrue(w.osSets().isEmpty())
            assertTrue(w.scheduler.slots.isEmpty() && w.scheduler.wake == null)
        }

    // ---------------------------------------------------------------- SM24 never acquired (replaces stub/no_fix K12)

    @Test
    fun sm24_aRealTripWithoutAnyFixLosesGpsThenTimesOut() =
        runTest(timeout = kotlin.time.Duration.parse("5m")) {
            val w = World(this).also { it.listen() }
            assertEquals(StartOutcome.Started, w.startTrip(TestData.meta("r1")))
            w.advance(130_000)
            val lost = w.events.map { it.second }.filterIsInstance<GpsLost>().firstOrNull()
            assertEquals(GpsLostCause.NEVER_ACQUIRED, lost?.cause)
            assertTrue(TripNotice.NoGpsYet in w.notifier.shown)
            var t = 130_000L
            while (t < 14_400_000L + 120_000L && w.firstAlarm() == null) {
                w.advance(60_000)
                t += 60_000
            }
            val alarm = w.events.map { it.second }.filterIsInstance<Alarm>().first()
            assertEquals(AlarmReason.TIMEOUT, alarm.reason)
            assertTrue(alarm.atMs - w.startWall in 14_400_000L..14_400_000L + 60_000L, "TIMEOUT at ${alarm.atMs - w.startWall}")
            w.kill()
        }
}
