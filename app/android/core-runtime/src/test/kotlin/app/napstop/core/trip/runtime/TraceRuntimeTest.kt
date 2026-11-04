package app.napstop.core.trip.runtime

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.GpsLost
import app.napstop.core.trip.TripEvent
import app.napstop.core.trip.runtime.support.ExpectCase
import app.napstop.core.trip.runtime.support.ExpectReader
import app.napstop.core.trip.runtime.support.FakeStore
import app.napstop.core.trip.runtime.support.FixFeed
import app.napstop.core.trip.runtime.support.RecordingJournal
import app.napstop.core.trip.runtime.support.TraceCase
import app.napstop.core.trip.runtime.support.TraceRun
import app.napstop.core.trip.runtime.support.World
import app.napstop.core.trip.runtime.support.eventName
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestFactory

/** L30, L14, L42: the six base traces of T02 through the runtime with a fake location source. */
@OptIn(ExperimentalCoroutinesApi::class)
class TraceRuntimeTest {
    private val checked = setOf("alarm", "preAlert", "overshoot", "gpsLost", "arrived")

    private fun matches(w: ExpectCase.Window, e: TripEvent): Boolean {
        if (eventName(e) != w.event) return false
        if (w.reason != null && (e as? Alarm)?.reason?.name != w.reason) return false
        if (w.ringNow != null && (e as? Alarm)?.ringNow != w.ringNow) return false
        if (w.cause != null && (e as? GpsLost)?.cause?.name != w.cause) return false
        return true
    }

    @TestFactory
    fun l30_baseTracesThroughTheRuntime(): List<DynamicTest> =
        ExpectReader.BASE_TRACES.flatMap { id ->
            val trace = ExpectReader.read(id)
            trace.cases.filter { it.status == "final" && it.excludedKeys.isEmpty() }.map { c ->
                DynamicTest.dynamicTest("$id/${c.id}") { runCase(trace, c) }
            }
        }

    private fun runCase(trace: TraceCase, c: ExpectCase) =
        runTest {
            val world = World(this, startWall = trace.gpx.startMs)
            world.checkSlots = true
            world.listen()
            val meta = ExpectReader.meta(trace, c)
            assertEquals(StartOutcome.Started, world.now { world.runtime.start(meta, trace.destLat, trace.destLng) })
            val run = TraceRun(world, FixFeed(trace.gpx, trace.intervalS), meta.tripId, silenceAfterMs = c.osRingMaxS?.let { it * 1000L })
            run.run(trace.durationS)
            val where = "${trace.traceId}/${c.id}"
            val events = world.events
            fun t(atMs: Long) = ((atMs - trace.gpx.startMs) / 1000L).toInt()
            for (w in c.expect.filter { it.event in checked }) {
                val first = events.firstOrNull { matches(w, it.second) }
                assertTrue(first != null, "$where: no ${w.event} ${w.reason ?: ""}")
                val at = t(first!!.second.atMs)
                assertTrue(at in w.notBefore..w.notAfter, "$where: ${w.event} ${w.reason ?: ""} at $at not in [${w.notBefore}, ${w.notAfter}]")
            }
            for (f in c.forbid) assertTrue(events.none { eventName(it.second) == f }, "$where: forbidden $f")
            // Runtime invariants.
            val ringNowEvents = events.count { (it.second as? Alarm)?.ringNow == true }
            assertEquals(ringNowEvents, world.alarm.ringNowCalls.size, "$where: one ringNow per Alarm(ringNow=true)")
            assertEquals(0, world.alarm.ringFallbackCalls.size, "$where: no fallback alarm without Doze")
            assertEquals(0, world.slotViolations, "$where: a fallback slot while ACQUIRING/TRACKING")
            assertEquals(0, world.alarm.doubleRings, "$where: one ring per trip")
            val ops = world.log.ops
            for ((i, op) in ops.withIndex()) {
                if (op.startsWith("ringNow")) {
                    val prevRing = ops.subList(0, i).indexOfLast { it.startsWith("ringNow") }
                    val persist = ops.subList(prevRing + 1, i).any { it == "writeActive" }
                    assertTrue(persist, "$where: PersistNow before ringNow #$i")
                }
            }
            assertTrue(world.warnings.isEmpty(), "$where: warnings ${world.warnings}")
            assertTrue(run.fixesDelivered > 0)
            c.expectOutcome?.let { expected ->
                assertEquals(expected, world.store.finished[meta.tripId]?.outcome?.name, "$where: outcome")
            }
            // L19 through the runtime: end the trip; the record equals TripEnded.summary.
            world.now { world.runtime.userAction(meta.tripId, app.napstop.core.trip.UserActionKind.STOP_TRIP) }
            val ended = world.events.map { it.second }.filterIsInstance<app.napstop.core.trip.TripEnded>().single()
            assertEquals(FinishedRecordBuilder.fromEvent(meta.tripId, ended), world.store.finished[meta.tripId])
            assertEquals(TrackingMode.IDLE, world.runtime.mode.value)
            assertTrue(world.scheduler.slots.isEmpty() && world.scheduler.wake == null, "$where: alarms left")
        }

    @Test
    fun l14_snapshotWritesFailingNeverDelayTheRing() {
        val trace = ExpectReader.read("coach_dn_langco_tunnel")
        val c = trace.cases.single { it.id == "distance_1000_gps_lost" }
        // Baseline: when does the alarm ring without disk errors?
        val base = alarmTimes(trace, c, failFromT = null)
        val alarmT = ((base.first - trace.gpx.startMs) / 1000).toInt()
        val failing = alarmTimes(trace, c, failFromT = alarmT - 60)
        assertEquals(base.first, failing.first, "ringNow at the same atMs")
        assertTrue(failing.second >= 2, "writer retried (${failing.second} failed attempts)")
    }

    /** (atMs of the first ringNow, failed write attempts) for the case, writes failing from trace second [failFromT]. */
    private fun alarmTimes(trace: TraceCase, c: ExpectCase, failFromT: Int?): Pair<Long, Int> {
        var result: Pair<Long, Int>? = null
        runTest {
            val world = World(this, startWall = trace.gpx.startMs)
            world.listen()
            var failed = 0
            world.store.failWriteActive = {
                val t = (world.scope.testScheduler.currentTime / 1000).toInt()
                if (failFromT != null && t >= failFromT) {
                    failed++
                    FakeStore.ioFailure()
                } else {
                    null
                }
            }
            val meta = ExpectReader.meta(trace, c)
            world.now { world.runtime.start(meta, trace.destLat, trace.destLng) }
            TraceRun(world, FixFeed(trace.gpx, trace.intervalS), meta.tripId).run(trace.durationS, stopAtFirstAlarm = true)
            // Keep going 30 s so the writer retries.
            world.advance(30_000)
            val alarm = world.events.first { (it.second as? Alarm)?.ringNow == true }
            assertEquals(AlarmReason.GPS_LOST, (alarm.second as Alarm).reason)
            assertEquals(1, world.alarm.ringNowCalls.size)
            // Listener got the AlarmMsg Step; no exception escaped (warnings only name the class).
            if (failFromT != null) {
                assertTrue(world.warnings.isNotEmpty())
                assertTrue(world.warnings.all { it == "snapshot write failed (IOException)" }, "${world.warnings}")
            }
            result = alarm.second.atMs to failed
        }
        return result!!
    }

    @Test
    fun l42_lowBatteryRingsOnceAndSamplesOnlyOnChange() =
        runTest {
            val trace = ExpectReader.read("train_hn_dh")
            val c = trace.cases.single { it.id == "distance_1000" }
            val journal = RecordingJournal()
            val world = World(this, startWall = trace.gpx.startMs, journal = journal)
            world.listen()
            world.env.batteryReading = BatteryReading(40, false)
            val meta = ExpectReader.meta(trace, c)
            world.now { world.runtime.start(meta, trace.destLat, trace.destLng) }
            val run = TraceRun(world, FixFeed(trace.gpx, trace.intervalS), meta.tripId)
            // 40 % for the first hour, then −1 % per minute from hour 2; read at every Tick / wake (§5.12).
            val levels = ArrayList<Int>()
            var t = 0
            while (t < 6 * 3600 && world.firstAlarm() == null) {
                t += 60
                run.run(t)
                val level = if (t < 3600) 40 else maxOf(0, 40 - (t - 3600) / 60)
                if (levels.lastOrNull() != level) levels += level
                world.env.batteryReading = BatteryReading(level, false)
            }
            val first = world.firstAlarm()
            assertEquals(AlarmReason.LOW_BATTERY, first?.reason, "first alarm")
            assertEquals(1, world.alarm.ringNowCalls.size, "ringNow exactly once")
            val samples = journal.lines.count { it.ev == "step" && it.fields["input"] == "BatterySample" }
            val seenLevels = world.seen.mapNotNull { it.view.batteryPct }.distinct()
            assertEquals(seenLevels.size, samples, "one BatterySample per level change")
            assertTrue(samples in 10..levels.size, "samples $samples, levels ${levels.size}")
        }

    @Test
    fun l43_journalHasNoCoordinatesNamesOrDistances() =
        runTest {
            val trace = ExpectReader.read("coach_dn_langco_tunnel")
            val c = trace.cases.single { it.id == "distance_1000_gps_lost" }
            val journal = RecordingJournal()
            val world = World(this, startWall = trace.gpx.startMs, journal = journal)
            world.listen()
            val meta = ExpectReader.meta(trace, c)
            world.now { world.runtime.start(meta, trace.destLat, trace.destLng) }
            TraceRun(world, FixFeed(trace.gpx, trace.intervalS), meta.tripId).run(trace.durationS)
            world.now { world.runtime.userAction(meta.tripId, app.napstop.core.trip.UserActionKind.DISMISS) }
            val evs = journal.lines.map { it.ev }.toSet()
            for (e in listOf("step", "fix", "wake_set", "fb_set", "ring", "persist", "mode")) assertTrue(e in evs, "journal has $e")
            val lat = "%.4f".format(trace.destLat)
            val lng = "%.4f".format(trace.destLng)
            for (line in journal.lines) {
                val allowed = RuntimeJournal.FIELDS[line.ev]
                assertTrue(allowed != null, "unknown event ${line.ev}")
                assertTrue(allowed!!.containsAll(line.fields.keys), "${line.ev} fields ${line.fields.keys}")
                val text = line.fields.toString()
                assertTrue(!text.contains(meta.destinationName) && !text.contains(lat) && !text.contains(lng), "${line.ev}: $text")
            }
        }
}
