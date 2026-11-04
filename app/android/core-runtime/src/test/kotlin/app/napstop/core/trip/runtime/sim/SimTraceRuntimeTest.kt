package app.napstop.core.trip.runtime.sim

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.GpsLost
import app.napstop.core.trip.TripEvent
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.UserActionKind
import app.napstop.core.trip.runtime.StartOutcome
import app.napstop.core.trip.runtime.support.ExpectCase
import app.napstop.core.trip.runtime.support.ExpectReader
import app.napstop.core.trip.runtime.support.RecordingJournal
import app.napstop.core.trip.runtime.support.SimDriver
import app.napstop.core.trip.runtime.support.TraceCase
import app.napstop.core.trip.runtime.support.World
import app.napstop.core.trip.runtime.support.eventName
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.currentTime
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestFactory

/**
 * T18 trace tests through the runtime in simulation mode (simulated source + in-process timers + FakeTraceStore over
 * fixtures/traces): SM19 (six bundled traces at 1×, 60×, 600×), SM20–SM22, SM15.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class SimTraceRuntimeTest {
    private val checked = setOf("alarm", "preAlert", "overshoot", "gpsLost", "arrived")

    /** Events compared across speeds (SM19): everything the user can see, not the sampling / fallback bookkeeping. */
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

    /** One run; returns (trace second, label) of the compared events. */
    private fun runCase(trace: TraceCase, c: ExpectCase, speed: Double): List<Pair<Double, String>> {
        var out: List<Pair<Double, String>>? = null
        runTest(timeout = kotlin.time.Duration.parse("10m")) {
            val world = World(this, journal = RecordingJournal())
            world.listen()
            val meta = SimDriver.simMeta(trace, c, speed)
            val d = SimDriver(world, meta, silenceAfterMs = c.osRingMaxS?.let { it * 1000L })
            assertEquals(StartOutcome.Started, d.start(trace.destLat, trace.destLng))
            var slotViolations = 0
            world.runtime.addListener { _, view, _, _ ->
                if ((view.phase == TripPhase.ACQUIRING || view.phase == TripPhase.TRACKING) && world.runtime.simTimers.pendingSlots.isEmpty()) slotViolations++
            }
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
            val ringNowEvents = events.count { (it.second as? Alarm)?.ringNow == true }
            assertEquals(ringNowEvents, world.alarm.ringNowCalls.size, "$where: one ringNow per Alarm(ringNow=true)")
            assertEquals(0, world.alarm.ringFallbackCalls.size, "$where: no fallback ring")
            assertEquals(0, world.alarm.doubleRings, "$where: one ring per trip")
            assertEquals(0, slotViolations, "$where: a fallback timer while ACQUIRING/TRACKING")
            val osSets = world.log.ops.filter { it.startsWith("setWake") || it.startsWith("setFallback") }
            assertTrue(osSets.isEmpty(), "$where: OS alarms $osSets")
            assertTrue(world.location.requests.isEmpty(), "$where: FLP asked for location")
            assertTrue(world.warnings.isEmpty(), "$where: warnings ${world.warnings}")
            assertEquals(1, world.keepAwake.holds.size)
            out = events.filter { eventName(it.second) in compared }.map { (it.second.atMs - d.simStart) / 1000.0 to label(it.second) }
            world.now { world.runtime.userAction(meta.tripId, UserActionKind.STOP_TRIP) }
            assertEquals(1, world.keepAwake.releases, "$where: wake lock released")
            world.kill()
        }
        return out!!
    }

    @TestFactory
    fun sm19_bundledTracesAtThreeSpeedsGiveTheSameEvents(): List<DynamicTest> =
        ExpectReader.BASE_TRACES.flatMap { id ->
            val trace = ExpectReader.read(id)
            trace.cases.filter { it.status == "final" && it.excludedKeys.isEmpty() }.map { c ->
                DynamicTest.dynamicTest("$id/${c.id}") {
                    val runs = listOf(1.0, 60.0, 600.0).associateWith { runCase(trace, c, it) }
                    val base = runs.getValue(1.0)
                    for ((speed, evs) in runs) {
                        assertEquals(base.map { it.second }, evs.map { it.second }, "$id/${c.id}: event sequence at $speed")
                        for ((a, b) in base.zip(evs)) {
                            assertTrue(kotlin.math.abs(a.first - b.first) <= 1.0, "$id/${c.id}@$speed: ${b.second} at ${b.first} vs ${a.first} at 1x")
                        }
                    }
                }
            }
        }

    @Test
    fun sm20_trainHanoiDongHoiAt60RingsOnTime() =
        runTest(timeout = kotlin.time.Duration.parse("10m")) {
            val trace = ExpectReader.read("train_hn_dh")
            val c = trace.cases.single { it.id == "distance_1000" }
            val world = World(this, journal = RecordingJournal())
            world.listen()
            val d = SimDriver(world, SimDriver.simMeta(trace, c, 60.0), maxStepRealMs = 500)
            val t0 = currentTime
            assertEquals(StartOutcome.Started, d.start(trace.destLat, trace.destLng))
            var ringRealMs: Long? = null
            d.runTo(trace.durationS) {
                if (ringRealMs == null && world.alarm.ringNowCalls.isNotEmpty()) ringRealMs = currentTime - t0
                ringRealMs != null
            }
            val pre = world.events.first { eventName(it.second) == "preAlert" }
            assertTrue(d.t(pre.second.atMs) in 33_435..33_470, "preAlert at ${d.t(pre.second.atMs)}")
            val alarm = world.events.first { (it.second as? Alarm)?.ringNow == true }.second as Alarm
            assertEquals(AlarmReason.DISTANCE, alarm.reason)
            val at = d.t(alarm.atMs)
            assertTrue(at in 33_680..33_715, "alarm at $at")
            // Real (test) time to the ring ≈ alarm trace second / 60, within the 1 s step of the driver.
            assertTrue(kotlin.math.abs(ringRealMs!! - at * 1000L / 60) <= 2_000, "rang after $ringRealMs ms real")
            world.kill()
        }

    @Test
    fun sm21_overshootAt60AfterTheAlarmRunsAtOneX() =
        runTest(timeout = kotlin.time.Duration.parse("10m")) {
            val trace = ExpectReader.read("coach_gb_phuly_overshoot")
            val c = trace.cases.single { it.id == "distance_1000_overshoot" }
            val world = World(this, journal = RecordingJournal())
            world.listen()
            val d = SimDriver(world, SimDriver.simMeta(trace, c, 60.0))
            assertEquals(StartOutcome.Started, d.start(trace.destLat, trace.destLng))
            d.runTo(trace.durationS)
            val alarms = world.events.map { it.second }.filterIsInstance<Alarm>()
            assertEquals(listOf(AlarmReason.DISTANCE), alarms.map { it.reason }, "OVERSHOOT adds no Alarm while ringing (I1)")
            assertTrue(d.t(alarms.single().atMs) in 2_335..2_360)
            val over = world.events.first { eventName(it.second) == "overshoot" }
            assertTrue(d.t(over.second.atMs) in 2_605..2_680, "overshoot at ${d.t(over.second.atMs)}")
            assertEquals(1, world.alarm.overshoots.size)
            assertEquals(1, world.alarm.ringNowCalls.size)
            world.kill()
        }

    @Test
    fun sm22_tunnelGpsLostAt60RingsFromTheInProcessTimers() =
        runTest(timeout = kotlin.time.Duration.parse("10m")) {
            val trace = ExpectReader.read("coach_dn_langco_tunnel")
            val c = trace.cases.single { it.id == "distance_1000_gps_lost" }
            val journal = RecordingJournal()
            val world = World(this, journal = journal)
            world.listen()
            val d = SimDriver(world, SimDriver.simMeta(trace, c, 60.0))
            assertEquals(StartOutcome.Started, d.start(trace.destLat, trace.destLng))
            d.runTo(1_400)
            val alarm = world.events.map { it.second }.filterIsInstance<Alarm>().first()
            assertEquals(AlarmReason.GPS_LOST, alarm.reason)
            assertTrue(d.t(alarm.atMs) in 1_175..1_265, "GPS_LOST alarm at ${d.t(alarm.atMs)}")
            // Inside the gap (no fix) Steps came from Ticks: awake Tick / in-process wake timer.
            val ticksInGap =
                journal.lines.count { it.ev == "step" && it.fields["input"] == "Tick" && it.tripMs != null && d.t(it.tripMs!!) in 1_175..1_265 }
            assertTrue(ticksInGap > 0, "ticks in the gap")
            assertTrue(world.log.ops.none { it.startsWith("setWake") || it.startsWith("setFallback") })
            world.kill()
        }

    @Test
    fun sm15_afterTheAlarmTimeRunsAtOneXSoSnoozeIsOneRealMinute() =
        runTest(timeout = kotlin.time.Duration.parse("10m")) {
            val trace = ExpectReader.read("coach_gb_phuly_overshoot")
            val c = trace.cases.single { it.id == "distance_1000_overshoot" }
            val journal = RecordingJournal()
            val world = World(this, journal = journal)
            world.listen()
            val meta = SimDriver.simMeta(trace, c, 60.0)
            val d = SimDriver(world, meta)
            assertEquals(StartOutcome.Started, d.start(trace.destLat, trace.destLng))
            d.runTo(trace.durationS) { world.alarm.ringNowCalls.isNotEmpty() }
            // The Alarm Step itself ran at 1×: sim_speed is logged before its step line and its ring.
            val iSpeed = journal.lines.indexOfFirst { it.ev == "sim_speed" }
            val iAlarmStep = journal.lines.indexOfFirst { it.ev == "step" && (it.fields["events"] as List<*>).contains("Alarm") }
            val iRing = journal.lines.indexOfFirst { it.ev == "ring" }
            assertTrue(iSpeed in 0 until iAlarmStep && iAlarmStep < iRing, "sim_speed $iSpeed, alarm step $iAlarmStep, ring $iRing")
            assertEquals(1.0, journal.lines[iSpeed].fields["to"])
            // Snooze right away.
            val snoozeWall = world.time.wallMs()
            val snoozeReal = currentTime
            world.now { world.runtime.userAction(meta.tripId, UserActionKind.SNOOZE) }
            val snoozed = world.tracking.notices.last { it.phase == TripPhase.SNOOZED }
            assertTrue(kotlin.math.abs(snoozed.snoozeUntilMs!! - (snoozeWall + 60_000)) <= 1_000, "notice shows wall time")
            assertTrue(snoozed.simulated)
            d.runTo(trace.durationS) { world.events.any { (it.second as? Alarm)?.reason == AlarmReason.SNOOZE_END } }
            val realToSnoozeEnd = currentTime - snoozeReal
            assertTrue(realToSnoozeEnd in 59_000L..61_000L, "SNOOZE_END after $realToSnoozeEnd ms real")
            world.kill()
        }
}
