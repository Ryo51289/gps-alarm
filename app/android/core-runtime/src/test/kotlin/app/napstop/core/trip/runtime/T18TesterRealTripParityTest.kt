package app.napstop.core.trip.runtime

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.UserActionKind
import app.napstop.core.trip.runtime.support.ExpectCase
import app.napstop.core.trip.runtime.support.ExpectReader
import app.napstop.core.trip.runtime.support.FixFeed
import app.napstop.core.trip.runtime.support.TraceCase
import app.napstop.core.trip.runtime.support.TraceRun
import app.napstop.core.trip.runtime.support.World
import java.io.File
import java.security.MessageDigest
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory

/**
 * Tester T18 (beyond spec, "a real trip at 1x is the same as T15 to the ms"): every L30 case of the six base traces,
 * plus a snooze + process death + restore scenario, run as a **real** trip (fake FLP, fake OS scheduler) and dumped
 * as text: each Step (trip time, phase, events), every OS alarm the runtime set (trigger elapsed/wall, target), every
 * ring, the tracking notices and the finished record. The dump is written to `build/core-runtime/napstop/t18-parity/`
 * and its SHA-256 compared with `src/test/resources/t18/real_trip_parity.sha256`, produced by this same file on the
 * pre-T18 tree (HEAD 6f56349, T16). Only APIs that exist before T18 are used, so the file compiles on both trees.
 * The line `coach_gb_phuly_overshoot/distance_1000_overshoot_ringing` (TR44, a case added by T11.5) was added by tester T12.5
 * from the T10.8 tree after reading the dump: DISTANCE 2 341.289, Overshoot 2 625 without a ring, Alarm(OVERSHOOT, ringNow) at
 * 2 941.289 = the auto-stop (osRingMaxS 600) of the first ring, no TripEnded before the user stop.
 *
 * A mismatch means a real trip now behaves differently from T15/T16: compare the dump with one made on the old tree.
 * If the change is intended (a later task), delete the golden file; the next run writes a new one and fails once.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class T18TesterRealTripParityTest {
    private val outDir: File = File(System.getProperty("napstop.outDir") ?: "build/napstop", "t18-parity")

    private fun goldenFile(): File? =
        System.getProperty("napstop.mainSrcDir")?.let { File(it).parentFile.parentFile.resolve("test/resources/t18/real_trip_parity.sha256") }

    @TestFactory
    fun t18p_realTripsBehaveAsBeforeT18(): List<DynamicTest> {
        val runs = ArrayList<Pair<String, () -> String>>()
        for (id in ExpectReader.BASE_TRACES) {
            val trace = ExpectReader.read(id)
            for (c in trace.cases.filter { it.status == "final" && it.excludedKeys.isEmpty() }) {
                runs += "$id/${c.id}" to { dumpCase(trace, c) }
            }
        }
        runs += "bus_hn_brt01/snooze_kill_restore" to { dumpSnoozeKillRestore() }
        val golden = loadGolden()
        val fresh = LinkedHashMap<String, String>()
        val tests =
            runs.map { (name, run) ->
                DynamicTest.dynamicTest(name) {
                    val text = run()
                    val f = File(outDir, name.replace("/", "__") + ".txt")
                    f.parentFile.mkdirs()
                    f.writeText(text)
                    val sha = sha256(text)
                    synchronized(fresh) { fresh[name] = sha }
                    if (golden != null) {
                        assertEquals(golden[name], sha, "$name: real-trip behaviour differs from T15/T16, dump in ${f.absolutePath}")
                    }
                }
            }
        val writeGolden =
            DynamicTest.dynamicTest("golden") {
                val g = goldenFile()
                if (golden == null && g != null && fresh.size == runs.size) {
                    g.parentFile.mkdirs()
                    g.writeText(fresh.entries.joinToString("") { "${it.value}  ${it.key}\n" })
                    File(outDir, "real_trip_parity.sha256").writeText(g.readText())
                    error("golden written to ${g.absolutePath}: run again")
                }
                File(outDir, "real_trip_parity.sha256").writeText(fresh.entries.joinToString("") { "${it.value}  ${it.key}\n" })
                assertTrue(golden != null)
            }
        return tests + writeGolden
    }

    private fun loadGolden(): Map<String, String>? {
        val g = goldenFile() ?: return null
        if (!g.isFile) return null
        return g.readLines().filter { it.isNotBlank() }.associate { line ->
            val (sha, name) = line.split("  ", limit = 2)
            name to sha
        }
    }

    private fun sha256(s: String): String = MessageDigest.getInstance("SHA-256").digest(s.toByteArray()).joinToString("") { "%02x".format(it) }

    /** Recorder over a world: Steps, OS alarms, rings. */
    private class Recorder(val w: World, val label: String) {
        val out = StringBuilder()

        fun line(s: String) {
            out.append("[$label v=${w.scope.testScheduler.currentTime}] ").append(s).append('\n')
        }

        fun attach() {
            w.scheduler.afterSetFallback = { f -> line("setFallback $f") }
            w.runtime.addListener { tripId, view, choice, events ->
                line(
                    "step $tripId at=${view.atMs} phase=${view.phase} choice=$choice wakeAt=${view.wakeAtMs} fb=${view.fallbackStatus} " +
                        "events=$events osWake=${w.scheduler.wake}",
                )
            }
        }

        fun finish() {
            line("ops ${w.log.ops}")
            line("rings ${w.alarm.ringNowCalls} fallbackRings ${w.alarm.ringFallbackCalls} stops ${w.alarm.stops} pre ${w.alarm.preAlerts} over ${w.alarm.overshoots}")
            for (n in w.tracking.notices) line("notice ${n.tripId} ${n.phase} d=${n.distanceM} eta=${n.etaS} est=${n.isEstimated} snooze=${n.snoozeUntilMs}")
            line("notifier ${w.notifier.history}")
            line("finished ${w.store.finished.values.toList()}")
            line("slots ${w.scheduler.slots} wake ${w.scheduler.wake} mode ${w.runtime.mode.value} warnings ${w.warnings}")
        }
    }

    private fun dumpCase(trace: TraceCase, c: ExpectCase): String {
        var text = ""
        runTest {
            val world = World(this, startWall = trace.gpx.startMs)
            val rec = Recorder(world, "p1").also { it.attach() }
            val meta = ExpectReader.meta(trace, c)
            assertEquals(StartOutcome.Started, world.now { world.runtime.start(meta, trace.destLat, trace.destLng) })
            TraceRun(world, FixFeed(trace.gpx, trace.intervalS), meta.tripId, silenceAfterMs = c.osRingMaxS?.let { it * 1000L }).run(trace.durationS)
            world.now { world.runtime.userAction(meta.tripId, UserActionKind.STOP_TRIP) }
            rec.finish()
            text = rec.out.toString()
            world.kill()
        }
        return text
    }

    /** Real bus trip: alarm, snooze, process death while SNOOZED, restore 90 s later, run to the end. */
    private fun dumpSnoozeKillRestore(): String {
        var text = ""
        runTest {
            val trace = ExpectReader.read("bus_hn_brt01")
            val c = trace.cases.single { it.id == "distance_1000" }
            text = snoozeKillRestore(this, trace, c)
        }
        return text
    }

    private fun snoozeKillRestore(scope: TestScope, trace: TraceCase, c: ExpectCase): String {
        val w1 = World(scope, startWall = trace.gpx.startMs)
        val r1 = Recorder(w1, "p1").also { it.attach() }
        w1.listen()
        val meta = ExpectReader.meta(trace, c)
        assertEquals(StartOutcome.Started, w1.now { w1.runtime.start(meta, trace.destLat, trace.destLng) })
        val feed = FixFeed(trace.gpx, trace.intervalS)
        TraceRun(w1, feed, meta.tripId).run(trace.durationS, stopAtFirstAlarm = true)
        val alarm = w1.events.map { it.second }.filterIsInstance<Alarm>().first()
        r1.line("first alarm $alarm")
        w1.advance(10_000)
        w1.now { w1.runtime.userAction(meta.tripId, UserActionKind.SNOOZE) }
        w1.advance(20_000)
        r1.finish()
        w1.kill()
        scope.testScheduler.advanceTimeBy(90_000)
        scope.testScheduler.runCurrent()
        val w2 = World(scope, startWall = trace.gpx.startMs, store = w1.store, scheduler = w1.scheduler, alarm = w1.alarm)
        val r2 = Recorder(w2, "p2").also { it.attach() }
        w2.listen()
        w2.now { w2.runtime.ensureLoaded(RestoreCause.PROCESS_START) }
        val offsetS = (scope.testScheduler.currentTime / 1000L).toInt()
        val feed2 = feed.copy().also { f -> f.lastDelivered = null }
        TraceRun(w2, feed2, meta.tripId, offsetS = 0).run(trace.durationS)
        r2.line("restored at offset $offsetS")
        w2.now { w2.runtime.userAction(meta.tripId, UserActionKind.STOP_TRIP) }
        r2.finish()
        w2.kill()
        return r1.out.toString() + r2.out.toString()
    }
}
