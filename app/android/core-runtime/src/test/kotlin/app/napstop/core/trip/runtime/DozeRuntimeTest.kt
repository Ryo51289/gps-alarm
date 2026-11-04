package app.napstop.core.trip.runtime

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.runtime.support.ExpectCase
import app.napstop.core.trip.runtime.support.ExpectReader
import app.napstop.core.trip.runtime.support.FixFeed
import app.napstop.core.trip.runtime.support.RecordingJournal
import app.napstop.core.trip.runtime.support.TraceCase
import app.napstop.core.trip.runtime.support.TraceRun
import app.napstop.core.trip.runtime.support.World
import java.io.File
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory

/**
 * L32: Doze model in the fake AlarmManager — allow-while-idle alarms at most once per 540 s, setAlarmClock on time, no
 * in-process awake Tick (the CPU sleeps). Two fix models: (a) fixes per policy regardless of wake-ups, (b) fixes only
 * when an alarm wakes the app. Check: the first alarm is not later than the run without Doze (same input) by more than
 * fallbackLagS + 1 s, and never two rings. Statistics go to build/napstop/L32-doze.txt (not asserted).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class DozeRuntimeTest {
    private class Scenario(val name: String, val trace: TraceCase, val case: ExpectCase, val dropFromT: Int?, val endT: Int)

    /** [fbArmed] = view.fallbackAtMs of the Step just before the first alarm (the fallback alarm armed then). */
    private class RunOut(val alarm: Alarm?, val journal: RecordingJournal, val doubleRings: Int, val fallbackRings: Int, val fbArmed: Long?)

    private val stats = StringBuilder()

    private fun scenarios(): List<Scenario> {
        val near = ExpectReader.read("coach_dn_langco_neardest")
        val tunnel = ExpectReader.read("coach_dn_langco_tunnel")
        val slow = ExpectReader.read("bus_hn_slow")
        val slowCase =
            ExpectCase(
                "distance_1000_unknown_drop8km", "final", "distance", 1000, null, false, "unknown", emptyList(), null, emptyList(),
                emptyList(), null,
            )
        // GPS "lost" far out: no fix once ≤ 8 km remain (straight), and the run goes on ≥ 60 min after that.
        val drop = slow.gpx.samples.first { haversine(it.lat, it.lng, slow.destLat, slow.destLng) <= 8000.0 }.t
        return listOf(
            Scenario("neardest", near, near.cases.single { it.id == "distance_1000_neardest" }, null, near.durationS),
            Scenario("tunnel", tunnel, tunnel.cases.single { it.id == "distance_1000_gps_lost" }, null, tunnel.durationS),
            Scenario("bus_slow_far", slow, slowCase, drop, maxOf(slow.durationS, drop + 3600 + 600)),
            // Same with hint BUS (20 km/h floor): ETA > 20 min while lost, so the far-zone c8 wake-ups really happen.
            Scenario("bus_slow_far_bushint", slow, slowCase.copyHint("bus"), drop, maxOf(slow.durationS, drop + 3600 + 600)),
        )
    }

    @TestFactory
    fun l32_dozeModel(): List<DynamicTest> =
        scenarios().filter { System.getProperty("napstop.dozeOnly")?.let { o -> it.name == o } ?: true }.flatMap { s ->
            listOf(false, true).map { wakeOnly ->
                DynamicTest.dynamicTest("${s.name}/${if (wakeOnly) "b-fixWhenAwake" else "a-fixByPolicy"}") { check(s, wakeOnly) }
            }
        } + DynamicTest.dynamicTest("stats") { writeStats() }

    private fun check(s: Scenario, wakeOnly: Boolean) {
        val base = run(s, wakeOnly, doze = false)
        val doze = run(s, wakeOnly, doze = true)
        val where = "${s.name}/${if (wakeOnly) "b" else "a"}"
        val lateMs = if (doze.alarm != null && base.alarm != null) doze.alarm.atMs - base.alarm.atMs else null
        synchronized(stats) {
            stats.append(where).append(": base=").append(base.alarm?.reason).append('@').append(base.alarm?.let { t(s, it.atMs) })
                .append(" doze=").append(doze.alarm?.reason).append('@').append(doze.alarm?.let { t(s, it.atMs) })
                .append(" lateS=").append(lateMs?.let { it / 1000 })
                .append(" toArrivalS=").append(doze.alarm?.let { s.trace.arrivalT - t(s, it.atMs) })
                .append(" fbArmedT=").append(doze.fbArmed?.let { t(s, it) })
                .append(" firstIsFallback=").append(doze.alarm?.reason == AlarmReason.FALLBACK)
                .append(' ').append(c8Stats(doze.journal)).append('\n')
            if (System.getProperty("napstop.dumpDoze") != null) {
                for (l in doze.journal.lines) {
                    if (l.ev == "persist" || l.ev == "fix") continue
                    stats.append("   ").append(l.tripMs?.let { t(s, it) }).append(' ').append(l.ev).append(' ').append(l.fields).append('\n')
                }
            }
        }
        assertTrue(base.alarm != null, "$where: no alarm without Doze")
        assertTrue(doze.alarm != null, "$where: no alarm in Doze")
        // (i) never two rings.
        assertEquals(0, base.doubleRings + doze.doubleRings, "$where: double ring")
        // (ii) designer decision (a) ("T15 — sau hiện thực" §1): the first alarm in Doze is never later than the fallback
        // alarm armed then (+ 1 s), the D5/D6 guarantee. The comparison with the run without Doze is statistics only.
        val fbArmed = doze.fbArmed
        assertTrue(fbArmed != null, "$where: no fallback alarm armed before the first alarm")
        assertTrue(doze.alarm!!.atMs <= fbArmed!! + 1_000L, "$where: first alarm ${(doze.alarm.atMs - fbArmed) / 1000}s after the armed fallback")
        // (iii) for these 4 scenarios: woken before reaching the destination.
        assertTrue(t(s, doze.alarm.atMs) < s.trace.arrivalT, "$where: first alarm at ${t(s, doze.alarm.atMs)} not before arrivalT ${s.trace.arrivalT}")
    }

    private fun ExpectCase.copyHint(hint: String) =
        ExpectCase(id, status, mode, thresholdM, thresholdMin, preAlert, hint, excludedKeys, osRingMaxS, expect, forbid, expectOutcome)

    private fun t(s: Scenario, atMs: Long) = (atMs - s.trace.gpx.startMs) / 1000

    private fun run(s: Scenario, wakeOnly: Boolean, doze: Boolean): RunOut {
        var out: RunOut? = null
        runTest {
            val journal = RecordingJournal()
            // No in-process awake Tick in Doze (the CPU sleeps), nor in model (b) at all (the app is awake only on alarms).
            val constants = if (doze || wakeOnly) RuntimeConstants(awakeTickMaxMs = null) else RuntimeConstants()
            val world = World(this, startWall = s.trace.gpx.startMs, constants = constants, journal = journal)
            world.scheduler.doze = doze
            world.listen()
            val meta = ExpectReader.meta(s.trace, s.case)
            world.now { world.runtime.start(meta, s.trace.destLat, s.trace.destLng) }
            TraceRun(world, FixFeed(s.trace.gpx, s.trace.intervalS, s.dropFromT, wakeOnly), meta.tripId)
                .run(s.endT, stopAtFirstAlarm = true)
            val firstIdx = world.seen.indexOfFirst { st -> st.events.any { it is Alarm } }
            val fbArmed = if (firstIdx > 0) world.seen[firstIdx - 1].view.fallbackAtMs else null
            out = RunOut(world.firstAlarm(), journal, world.alarm.doubleRings, world.alarm.ringFallbackCalls.size, fbArmed)
        }
        return out!!
    }

    /** c8 = wake at fb − (fallbackQuietBeforeS + fallbackMinIntervalS) = fb − 90 s (T10.2). */
    private fun c8Stats(j: RecordingJournal): String {
        var fb: Long? = null
        var lastSetAt: Long? = null
        var lastSetIsC8 = false
        var c8 = 0
        var c8Late = ArrayList<Long>()
        var c8AfterQuiet = 0
        var movedLater = 0
        var prevFb: Long? = null
        for (l in j.lines) {
            when (l.ev) {
                "fb_set" -> {
                    val at = l.fields["at"] as Long
                    if (prevFb != null && at > prevFb) movedLater++
                    prevFb = at
                    fb = at
                }
                "wake_set" -> {
                    lastSetAt = l.fields["at"] as Long
                    lastSetIsC8 = fb != null && lastSetAt == fb - 90_000L
                }
                "wake_fire" -> {
                    val at = l.fields["at"] as Long?
                    val late = l.fields["lateMs"] as Long?
                    if (at != null && at == lastSetAt && lastSetIsC8) {
                        c8++
                        late?.let { c8Late += it }
                        if (fb != null && late != null && at + late > fb - 30_000L) c8AfterQuiet++
                    }
                }
            }
        }
        val wakes = j.lines.filter { it.ev == "wake_fire" }.mapNotNull { it.fields["lateMs"] as Long? }
        return "wakes=${wakes.size} maxWakeLateS=${(wakes.maxOrNull() ?: 0) / 1000} c8=$c8 c8MaxLateS=${(c8Late.maxOrNull() ?: 0) / 1000} " +
            "c8AfterFbMinus30=$c8AfterQuiet fbMovedLater=$movedLater"
    }

    private fun writeStats() {
        val dir = File(System.getProperty("napstop.outDir") ?: "build/napstop")
        dir.mkdirs()
        stats.append("Model applies Doze also while the vehicle moves: worst case (designer \"T15 - sau hien thuc\" §1).\n")
        File(dir, "L32-doze.txt").writeText(stats.toString())
        println(stats)
    }

    private companion object {
        fun haversine(lat1: Double, lng1: Double, lat2: Double, lng2: Double): Double {
            val r = 6_371_008.8
            val p1 = Math.toRadians(lat1)
            val p2 = Math.toRadians(lat2)
            val dp = p2 - p1
            val dl = Math.toRadians(lng2 - lng1)
            val a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
            return 2 * r * asin(sqrt(a))
        }
    }
}
