package app.napstop.core.trip.runtime

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.runtime.support.ExpectCase
import app.napstop.core.trip.runtime.support.ExpectReader
import app.napstop.core.trip.runtime.support.FakeAlarmPort
import app.napstop.core.trip.runtime.support.FakeScheduler
import app.napstop.core.trip.runtime.support.FakeStore
import app.napstop.core.trip.runtime.support.FixFeed
import app.napstop.core.trip.runtime.support.RecordingJournal
import app.napstop.core.trip.runtime.support.TraceCase
import app.napstop.core.trip.runtime.support.TraceRun
import app.napstop.core.trip.runtime.support.World
import java.io.File
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory

/**
 * L31: the L30 cases with a process death every 300 s up to the first alarm. Memory is lost; the store, the OS alarms
 * and the ring facts survive. The process comes back when the next OS alarm (wake or fallback) is delivered. Two
 * variants: (sticky) the system also restarts LocationService, which goes foreground on its own — never through
 * TrackingController.start (D9); (headless, review T15 #6) the sticky restart fails and the trip runs HEADLESS to the
 * end on wake-ups and the fallback alarm only (RK-T15-4).
 *
 * Criteria (designer "T15 — sau hiện thực" §2): first alarm ≤ the run without death + fallbackLagS + samplingDenseIntervalS
 * + WAKE_GUARD_MS (from the case params); a different reason only from {GPS_LOST, FALLBACK, FALLBACK_MISSED}; every run
 * rings, never twice, never starts the FGS from the background. Headless: first alarm ≤ the fallback alarm armed then + 1 s.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class KillSweepRuntimeTest {
    private class Capture(val k: Int, val store: FakeStore, val scheduler: FakeScheduler, val alarm: FakeAlarmPort, val feed: FixFeed)

    private class Outcome(val k: Int, val alarm: Alarm?, val trackingStarts: Int, val doubleRings: Int, val fbArmed: Long?)

    private val stats = StringBuilder()

    private companion object {
        /** FGS mode: the awake Tick (exact coroutine timer, ≤ 60 s) delivers wakeAtMs on time; coarse steps only speed up the sweep. */
        const val STEP_MS = 60_000L
        val DEATH_REASONS = setOf(AlarmReason.GPS_LOST, AlarmReason.FALLBACK, AlarmReason.FALLBACK_MISSED)
    }

    @TestFactory
    fun l31_killSweepEvery300s(): List<DynamicTest> =
        ExpectReader.BASE_TRACES.flatMap { id ->
            val trace = ExpectReader.read(id)
            trace.cases.filter { it.status == "final" && it.excludedKeys.isEmpty() }.map { c ->
                DynamicTest.dynamicTest("$id/${c.id}") { sweep(trace, c) }
            }
        } + DynamicTest.dynamicTest("stats") { writeStats() }

    private fun sweep(trace: TraceCase, c: ExpectCase) {
        val meta = ExpectReader.meta(trace, c)
        val captures = ArrayList<Capture>()
        var baseAlarm: Alarm? = null
        runTest {
            val world = World(this, startWall = trace.gpx.startMs)
            world.listen()
            world.now { world.runtime.start(meta, trace.destLat, trace.destLng) }
            val run = TraceRun(world, FixFeed(trace.gpx, trace.intervalS), meta.tripId, silenceAfterMs = c.osRingMaxS?.let { it * 1000L }, stepMs = STEP_MS)
            run.run(trace.durationS, stopAtFirstAlarm = true)
            baseAlarm = world.firstAlarm()
        }
        val base = baseAlarm!!
        val alarmT = ((base.atMs - trace.gpx.startMs) / 1000L).toInt()
        val kills = (300..alarmT step 300).toList()
        runTest {
            val world = World(this, startWall = trace.gpx.startMs)
            world.listen()
            world.now { world.runtime.start(meta, trace.destLat, trace.destLng) }
            val feed = FixFeed(trace.gpx, trace.intervalS)
            TraceRun(world, feed, meta.tripId, stepMs = STEP_MS).run(alarmT, captureAt = kills) { k ->
                captures += Capture(k, world.store.copy(), world.scheduler.copy(), world.alarm.copy(), feed.copy())
            }
        }
        val p = EngineParams() // the L30 cases carry no params
        val tolMs = (p.fallbackLagS + p.samplingDenseIntervalS) * 1000L + RuntimeConstants.WAKE_GUARD_MS
        val where = "${trace.traceId}/${c.id}"
        // (sticky)
        val sticky = captures.map { killRun(trace, c, meta, it.copyFresh(), sticky = true) }
        val pairs = LinkedHashMap<String, Int>()
        var maxEarlyS = 0L
        for (o in sticky) {
            checkCommon(where, "sticky", o)
            val a = o.alarm!!
            val lateMs = a.atMs - base.atMs
            assertTrue(lateMs <= tolMs, "$where sticky k=${o.k}: first alarm ${a.reason} ${lateMs / 1000}s after the run without death")
            if (a.reason != base.reason) {
                assertTrue(a.reason in DEATH_REASONS, "$where sticky k=${o.k}: reason ${base.reason} → ${a.reason}")
                pairs.merge("${base.reason}→${a.reason}", 1, Int::plus)
            }
            maxEarlyS = maxOf(maxEarlyS, -lateMs / 1000)
        }
        // (headless)
        val headless = captures.map { killRun(trace, c, meta, it.copyFresh(), sticky = false) }
        var headlessMaxOverFbMs = Long.MIN_VALUE
        for (o in headless) {
            checkCommon(where, "headless", o)
            val fb = o.fbArmed
            assertTrue(fb != null, "$where headless k=${o.k}: no fallback alarm armed")
            val over = o.alarm!!.atMs - fb!!
            headlessMaxOverFbMs = maxOf(headlessMaxOverFbMs, over)
            assertTrue(over <= 1_000L, "$where headless k=${o.k}: alarm ${o.alarm.reason} ${over / 1000}s after the armed fallback")
        }
        synchronized(stats) {
            stats.append("$where kills=${sticky.size} sticky: sameReason=${sticky.count { it.alarm!!.reason == base.reason }} ")
                .append("pairs=").append(pairs).append(" maxEarlyS=").append(maxEarlyS)
                .append(" | headless: reasons=").append(headless.groupingBy { it.alarm?.reason?.name }.eachCount())
                .append(" maxAfterBaseS=").append(headless.maxOf { (it.alarm!!.atMs - base.atMs) / 1000 })
                .append(" maxOverArmedFbS=").append(headlessMaxOverFbMs / 1000).append('\n')
        }
    }

    private fun Capture.copyFresh() = Capture(k, store.copy(), scheduler.copy(), alarm.copy(), feed.copy())

    private fun checkCommon(where: String, variant: String, o: Outcome) {
        assertEquals(0, o.trackingStarts, "$where $variant k=${o.k}: TrackingController.start after a restart (D9)")
        assertEquals(0, o.doubleRings, "$where $variant k=${o.k}: two rings in a row (I1)")
        assertTrue(o.alarm != null, "$where $variant k=${o.k}: no alarm after the process death")
    }

    private fun killRun(trace: TraceCase, c: ExpectCase, meta: TripMeta, cap: Capture, sticky: Boolean): Outcome {
        var out: Outcome? = null
        val armedAtDeath = cap.scheduler.slots.values.minOfOrNull { it.targetAtMs }
        runTest {
            val journal = RecordingJournal()
            val world =
                World(
                    this,
                    startWall = trace.gpx.startMs + cap.k * 1000L,
                    elapsedBase = 1_000_000L + cap.k * 1000L,
                    store = cap.store,
                    scheduler = cap.scheduler,
                    alarm = cap.alarm,
                    journal = journal,
                )
            world.listen()
            val run = TraceRun(world, cap.feed, meta.tripId, offsetS = cap.k, silenceAfterMs = c.osRingMaxS?.let { it * 1000L }, stepMs = STEP_MS)
            if (sticky) {
                run.afterFirstDelivery = {
                    // Sticky restart of LocationService: startForeground succeeds in the service itself.
                    world.runtime.liveTrip()?.let { id ->
                        world.tracking.isForeground = true
                        world.runtime.onForegroundResult(id, ForegroundResult.Started)
                    }
                }
            }
            // Headless: no fix after the death, so dead reckoning at the hint speed may put the fallback far past the
            // trace end; run until it rings.
            run.run(if (sticky) trace.durationS + 3600 else trace.durationS * 4 + 7200, stopAtFirstAlarm = true)
            val alarm = world.firstAlarm()
            // Fallback armed when the first alarm came: the last one set before it in this process, else the one that
            // survived the death.
            val fbArmed =
                alarm?.let { a ->
                    journal.lines.filter { it.ev == "fb_set" && (it.tripMs ?: Long.MAX_VALUE) <= a.atMs }.lastOrNull()?.fields?.get("at") as Long?
                } ?: armedAtDeath
            if (alarm == null && System.getProperty("napstop.dumpKill") != null) {
                println("NOALARM k=${cap.k} sticky=$sticky mode=${world.runtime.mode.value} wake=${world.scheduler.wake} slots=${world.scheduler.slots.values} warnings=${world.warnings} now=${world.scope.testScheduler.currentTime}")
                journal.lines.filter { it.ev != "persist" }.take(40).forEach { println("  ${it.tripMs} ${it.ev} ${it.fields}") }
            }
            out = Outcome(cap.k, alarm, world.tracking.starts.size, world.alarm.doubleRings, fbArmed)
        }
        return out!!
    }

    private fun writeStats() {
        val dir = File(System.getProperty("napstop.outDir") ?: "build/napstop")
        dir.mkdirs()
        File(dir, "L31-killsweep.txt").writeText(stats.toString())
        println(stats)
    }
}
