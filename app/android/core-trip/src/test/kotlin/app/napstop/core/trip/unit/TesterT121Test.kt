package app.napstop.core.trip.unit

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmMode
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.BatterySample
import app.napstop.core.trip.EngineInput
import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.EngineState
import app.napstop.core.trip.FallbackAlarmChanged
import app.napstop.core.trip.FallbackCause
import app.napstop.core.trip.FallbackFired
import app.napstop.core.trip.FallbackRestoreStatus
import app.napstop.core.trip.FallbackScheduled
import app.napstop.core.trip.FallbackStatus
import app.napstop.core.trip.GpsLost
import app.napstop.core.trip.GpsLostCause
import app.napstop.core.trip.GpsStatus
import app.napstop.core.trip.LocationFix
import app.napstop.core.trip.Overshoot
import app.napstop.core.trip.PreAlert
import app.napstop.core.trip.RestoreInfo
import app.napstop.core.trip.SamplingTier
import app.napstop.core.trip.Step
import app.napstop.core.trip.Tick
import app.napstop.core.trip.TripConfig
import app.napstop.core.trip.TripEngine
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.VehicleKind
import app.napstop.core.trip.WAKE_GUARD_MS
import app.napstop.core.trip.harness.Checks
import app.napstop.core.trip.harness.GapProbe
import app.napstop.core.trip.lostAfterS
import app.napstop.core.trip.support.DEST
import app.napstop.core.trip.support.S
import app.napstop.core.trip.support.TestGeo
import app.napstop.core.trip.support.cfg
import app.napstop.core.trip.support.driverFrom
import app.napstop.core.trip.support.params
import app.napstop.core.trip.support.trackingState
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

/**
 * Tester additions for T12.1 (T10.4: wakeGuardMs, lostAfterS monotone between fixes; docs/test-reports/T12.1.md), turned into
 * T10.5 tests by T12.2 (U106 a/b, U107, U111; T10 mục T10.5 §6).
 * Question: "is there any situation where the engine does not wake the user on time?"
 *  - U107 (A10): pre-alert (nhắc nhẹ) for TIME/SMART during GPS loss lands on the near-zone wake-up within the T10.5 §2.2 scope.
 *  - Early wake-up delivery (T10.4 §3.1 (2)): a Tick up to 998 ms before wakeAtMs still rings.
 *  - U111 Doze platform fuzz: longer trips, fixes only while "awake" (or never), only wake-up Ticks + OS fallback, random
 *    FallbackScheduled failures, random kill/restart (RANG/PENDING/MISSING/UNKNOWN); I4 (T10.5 wording), I13, I14, "Tick at
 *    wakeAtMs rings or re-arms strictly later", liveness, "the first alarm never comes from the OS fallback when it was
 *    scheduled OK and nothing new was learnt after it was planned", and (T10.5) "an early fallback the urgent later shift
 *    could rescue was rescued".
 *  - U106 a/b: no wake-up storm with GPS OK + stopped (before T10.5: one wake-up every T − B + 1 s).
 */
class TesterT121Test {
    private val outDir = File(System.getProperty("napstop.outDir") ?: "build/napstop").also { it.mkdirs() }

    private class Rng(seed: Long) {
        private var x = seed * -0x61c8864680b583ebL + 0x1234567L

        fun next(): Long {
            x += -0x61c8864680b583ebL
            var z = x
            z = (z xor (z ushr 30)) * -0x40a7b892e31b1a47L
            z = (z xor (z ushr 27)) * -0x6b2fb644ecceee15L
            return z xor (z ushr 31)
        }

        fun int(n: Int): Int = ((next() ushr 1) % n).toInt()

        fun dbl(): Double = (next() ushr 11).toDouble() / (1L shl 53).toDouble()

        fun dbl(lo: Double, hi: Double): Double = lo + (hi - lo) * dbl()

        fun chance(p: Double): Boolean = dbl() < p
    }

    private fun i13(s: Step): String? {
        val w = s.view.wakeAtMs
        return if (s.view.phase == TripPhase.ENDED) {
            if (w == null) null else "I13 ENDED with wakeAt"
        } else if (w == null) {
            "I13 wakeAt null in ${s.view.phase}"
        } else if (w <= s.state.nowMs) {
            "I13 wakeAt ${w - s.state.nowMs} ms <= now in ${s.view.phase}"
        } else {
            null
        }
    }

    private fun i14(s: Step): String? {
        if (s.view.phase == TripPhase.ENDED) return null
        val again = TripEngine.reduce(s.state, Tick(s.state.nowMs))
        if (again.events.isNotEmpty()) return "I14 Tick(now) emitted ${again.events.map { it.javaClass.simpleName }}"
        if (again.state != s.state) return "I14 Tick(now) changed the state"
        if (again.view != s.view) return "I14 Tick(now) changed the view"
        return null
    }

    // ================================================================ A10: pre-alert during GPS loss (TIME / SMART)

    /**
     * TRACKING, established, closing [closing] m/s (k = ground/closing), one fix at S, DENSE (lostAfterS 60 s), etaS at the fix =
     * [eta0]. Tick at lostAfterS → GpsLost; then only Tick(view.wakeAtMs) until the Alarm. Returns the trace.
     */
    private class DozeRun(val lost: Step, val wakes: List<Step>)

    private fun lostDoze(config: TripConfig, eta0: Double, ground: Double, closing: Double, slow: Boolean): DozeRun {
        val cvDr = closing // k = ground/closing, vDr = ground → etaS = dNow/closing + 20
        val d = (eta0 - 20.0) * cvDr
        // T10.6 §6: U107 loses GPS >= gpsLostLongS before the alarm and checks the A10 pre-alert rule, so W is off (U120 d: W on).
        val st = trackingState(config, p = params("{\"gpsLostLongS\": 0}"), d = d, ground = ground, closing = closing, slow = slow)
        val e = driverFrom(st)
        val lost = e.tickMs(S + lostAfterS(st.params, st.policyIntervalAtLastFixS, st.policy) * 1000L)
        assertTrue(lost.events.any { it is GpsLost })
        val wakes = ArrayList<Step>()
        var prev = lost
        var guard = 0
        while (prev.events.none { it is Alarm }) {
            assertEquals(null, i13(prev))
            val w = prev.view.wakeAtMs!!
            prev = e.tickMs(w)
            wakes += prev
            check(++guard < 500)
        }
        // I5: at most one PreAlert over the trip, never at or after the Alarm.
        val all = e.steps
        val preIdx = all.indices.filter { i -> all[i].events.any { it is PreAlert } }
        val alarmIdx = all.indexOfFirst { s -> s.events.any { it is Alarm } }
        assertTrue(preIdx.size <= 1 && preIdx.all { it < alarmIdx }) { "I5: pre-alerts at $preIdx, alarm at $alarmIdx" }
        return DozeRun(lost, wakes)
    }

    @Test
    fun `U107 a A10 TIME and SMART pre-alert during GPS loss rings at the near-zone wake-up (etaS about 1799)`() {
        val rng = Rng(10)
        val modes = listOf(
            Triple("TIME 5", cfg(AlarmMode.TIME, thrMin = 5), false),
            Triple("TIME 15", cfg(AlarmMode.TIME, thrMin = 15), false),
            Triple("TIME 20", cfg(AlarmMode.TIME, thrMin = 20), false),
            Triple("SMART", cfg(AlarmMode.SMART), false),
            Triple("SMART slow", cfg(AlarmMode.SMART), true),
        )
        val log = StringBuilder()
        var sets = 0
        for ((name, config, slow) in modes) {
            val sets0 = ArrayList<Triple<Double, Double, Double>>()
            sets0 += if (slow) Triple(5_000.0, 3.0, 2.5) else Triple(5_000.0, 15.0, 12.5)
            repeat(30) {
                // SMART slow: closing > 2.12 m/s so slowDistM (2 500 m) is reached after etaS 1200 (P = lostAt, the A10 claim).
                val g = if (slow) rng.dbl(2.6, 4.1) else rng.dbl(5.0, 30.0)
                sets0 += Triple(rng.dbl(2_000.0, 20_000.0), g, rng.dbl(if (slow) maxOf(0.6 * g, 2.2) else 0.6 * g, g))
            }
            for ((eta0, g, c) in sets0) {
                val tag = "$name eta0=$eta0 ground=$g closing=$c"
                val r = lostDoze(config, eta0, g, c, slow)
                val p0 = r.lost.view.predictedAlarmAtMs!!
                val pre = r.wakes.filter { s -> s.events.any { it is PreAlert } }
                assertEquals(1, pre.size, "$tag: pre-alert count")
                val preStep = pre.single()
                val alarmStep = r.wakes.last()
                val a = alarmStep.events.filterIsInstance<Alarm>().single()
                assertEquals(AlarmReason.GPS_LOST, a.reason, tag)
                assertTrue(a.ringNow, tag)
                assertTrue(preStep.state.nowMs < alarmStep.state.nowMs, "$tag: pre-alert not before the alarm")
                // Near-zone wake-up of c3: P − fallbackNearS·1000 + wakeGuardMs (P stable to ±1 ms while lost).
                val expect = p0 - 600_000L + WAKE_GUARD_MS
                assertTrue(preStep.state.nowMs in (expect - 1)..(expect + 1), "$tag: pre-alert at ${preStep.state.nowMs - p0} ms vs P0")
                val eta = preStep.events.filterIsInstance<PreAlert>().single().etaS!!
                assertTrue(eta in 1799..1800, "$tag: pre-alert etaS $eta")
                // P is lostAt (etaS 1200) for TIME <= 20 and SMART (slow distance 2 500 m comes after etaS 1200 at <= 4 m/s).
                assertTrue(a.atMs - p0 in 999L..1001L, "$tag: alarm ${a.atMs - p0} ms after P0")
                log.append("$tag lead=${(a.atMs - preStep.state.nowMs) / 1000} s etaS=$eta\n")
                sets++
            }
        }
        assertEquals(155, sets)
        File(outDir, "t121-a10.txt").writeText("sets=$sets\n$log")
    }

    /**
     * U107 b–d, outside the A10 scope of T10.5 §2.2 (pinned numbers of the T12.1 tester): TIME 21–25 min (mode boundary before
     * lostAt, pre-alert allowed since 1800 − thr >= 300), SMART slow closing < 2.12 m/s and DISTANCE (no wake-up candidate for
     * the pre-alert, T10.4 §3.4). The pre-alert comes at the c8 wake-up 61 s before the alarm, or not at all (I5 allows).
     */
    @Test
    fun `U107 b c d A10 outside the scope TIME 21 and 25, SMART slow below 2_12 m per s, DISTANCE pre-alert lead in Doze`() {
        val out = StringBuilder()
        fun measure(name: String, config: TripConfig, ground: Double, closing: Double, slow: Boolean): List<Double> {
            val r = lostDoze(config, 5_000.0, ground, closing, slow)
            val alarm = r.wakes.last()
            val a = alarm.events.filterIsInstance<Alarm>().single()
            assertTrue(a.ringNow && a.reason == AlarmReason.GPS_LOST, name)
            val leads = r.wakes.filter { s -> s.events.any { it is PreAlert } }.map { (alarm.state.nowMs - it.state.nowMs) / 1000.0 }
            out.append("$name: alarm ${a.reason} at etaS ${alarm.view.etaS}; pre-alert lead $leads s; wake-ups ${r.wakes.size}\n")
            return leads
        }
        measure("TIME 20 (claim, reference)", cfg(AlarmMode.TIME, thrMin = 20), 15.0, 12.5, false)
        val t21 = measure("TIME 21", cfg(AlarmMode.TIME, thrMin = 21), 15.0, 12.5, false)
        val t25 = measure("TIME 25", cfg(AlarmMode.TIME, thrMin = 25), 15.0, 12.5, false)
        val slow15 = measure("SMART slow closing 1.5", cfg(AlarmMode.SMART), 1.8, 1.5, true)
        val slow141 = measure("SMART slow closing 1.41", cfg(AlarmMode.SMART), 1.69, 1.41, true)
        val dist = measure("DISTANCE 1000", cfg(AlarmMode.DISTANCE, thr = 1000), 15.0, 12.5, false)
        File(outDir, "t121-a10-outside.txt").writeText(out.toString())
        // Pinned (outside the A10 scope, I5 allows): the pre-alert comes at the c8 wake-up 61 s before the alarm, or not at all.
        assertEquals(listOf(61.0), t21)
        assertEquals(listOf(61.0), t25)
        assertEquals(listOf(61.0), slow15)
        assertEquals(emptyList<Double>(), slow141)
        assertEquals(emptyList<Double>(), dist)
    }

    // ================================================================ early wake-up delivery (T10.4 §3.1 (2))

    @Test
    fun `T121 a Tick delivered up to 998 ms before wakeAtMs still rings when GPS is lost (every mode, random sets)`() {
        val rng = Rng(31)
        val modes = listOf(
            cfg(AlarmMode.DISTANCE, thr = 200), cfg(AlarmMode.DISTANCE, thr = 1000), cfg(AlarmMode.DISTANCE, thr = 10_000),
            cfg(AlarmMode.TIME, thrMin = 5), cfg(AlarmMode.TIME, thrMin = 20), cfg(AlarmMode.TIME, thrMin = 60),
            cfg(AlarmMode.SMART),
        )
        var probes = 0
        for (config in modes) for (slow in listOf(false, true)) {
            if (slow && config.mode != AlarmMode.SMART) continue
            repeat(60) { i ->
                val g = if (slow) rng.dbl(0.8, 4.0) else rng.dbl(3.0, 35.0)
                val c = rng.dbl(0.5 * g, g)
                val d = rng.dbl(1_500.0, 150_000.0)
                val guard = if (rng.chance(0.3)) listOf(c * rng.dbl(1.0, 1.6)) else emptyList()
                val st = trackingState(config, d = d, ground = g, closing = c, slow = slow, cvGuard = guard)
                val e = driverFrom(st)
                var s = e.tickMs(S + lostAfterS(st.params, st.policyIntervalAtLastFixS, st.policy) * 1000L)
                val tag = "${config.mode} thr=${config.distanceThresholdM}/${config.timeThresholdMin} slow=$slow #$i"
                var n = 0
                while (s.events.none { it is Alarm }) {
                    val p = s.view.predictedAlarmAtMs!!
                    // Early delivery: anything in [P + 2 ms, P + 1 000 ms] rings (≥ 1 ms past the true boundary).
                    for (early in listOf(998L, rng.int(999).toLong(), 0L)) {
                        val at = p + WAKE_GUARD_MS - early
                        if (at < s.state.nowMs) continue
                        val r = TripEngine.reduce(s.state, Tick(at))
                        val a = r.events.filterIsInstance<Alarm>().singleOrNull()
                        assertNotNull(a, "$tag: Tick ${early} ms early (P + ${WAKE_GUARD_MS - early} ms) did not ring")
                        assertTrue(a!!.ringNow && a.reason != AlarmReason.FALLBACK, tag)
                        probes++
                    }
                    s = e.tickMs(s.view.wakeAtMs!!)
                    check(++n < 500)
                }
            }
        }
        assertTrue(probes > 1_000)
        File(outDir, "t121-early.txt").writeText("probes=$probes\n")
    }

    @Test
    fun `T121 GPS OK and no new fix (dead reckoning) the wake-up at P + 1 s rings the mode alarm before c2`() {
        // A1–A5 with gps OK: the platform delivers no fix (Doze) but the boundary comes before the lost timeout.
        val rng = Rng(32)
        var n = 0
        for (config in listOf(cfg(AlarmMode.DISTANCE, thr = 500), cfg(AlarmMode.TIME, thrMin = 10), cfg(AlarmMode.SMART))) {
            repeat(80) {
                val g = rng.dbl(5.0, 35.0)
                val c = rng.dbl(0.6 * g, g)
                // Boundary 5–55 s after the fix (DENSE: lostAfterS = 60 s).
                val x = rng.dbl(5.0, 55.0)
                val d = when (config.mode) {
                    AlarmMode.DISTANCE -> 500.0 + c * x
                    AlarmMode.TIME -> (600.0 - 20.0 + x) * c
                    AlarmMode.SMART -> TMathMax(1000.0 + c * x, (600.0 - 20.0 + x) * c)
                }
                val e = driverFrom(trackingState(config, d = d, ground = g, closing = c))
                var s = e.tickMs(S + 1_000)
                assertEquals(GpsStatus.OK, s.view.gps)
                var wakes = 0
                while (s.events.none { it is Alarm }) {
                    s = e.tickMs(s.view.wakeAtMs!!)
                    check(++wakes < 50)
                }
                val a = s.events.filterIsInstance<Alarm>().single()
                assertTrue(a.reason != AlarmReason.GPS_LOST && a.reason != AlarmReason.FALLBACK && a.ringNow, "${a.reason}")
                assertEquals(GpsStatus.OK, s.view.gps, "rang before c2")
                assertTrue(a.atMs - S <= Math.ceil(x * 1000.0).toLong() + WAKE_GUARD_MS + 1, "late: ${a.atMs - S} vs boundary ${x * 1000}")
                n++
            }
        }
        assertEquals(240, n)
    }

    @Suppress("FunctionName")
    private fun TMathMax(a: Double, b: Double): Double = if (a > b) a else b

    // ================================================================ U106 a/b: no wake-up storm (GPS OK + stopped)

    /**
     * U106 (a), (b) (T10 mục T10.5 §6; was the T12.1 tester's storm characterisation). GPS OK, the last fix is STATIONARY (stop in
     * progress): dNow = dSmooth, so predicted = now + T with T constant (it slides with now). Before T10.5 every c4 / near-zone
     * candidate with T just above its boundary B landed at now + (T − B) + 1 s: a wake-up every 1 499 ms (40 / 60 / 360 before
     * c2; 794 in a 20-minute SPARSE stop). T10.5: c3/c4 come from wakeBasisAt (= deadlineAt while sliding), so the only wake-up
     * left is c2.
     */
    @Test
    fun `U106 a b GPS OK and stopped with T just above a boundary asks for no wake-up storm`() {
        val out = StringBuilder()
        val expectWake = mapOf(SamplingTier.DENSE to 60_000L, SamplingTier.MEDIUM to 90_000L, SamplingTier.SPARSE to 540_000L)
        for ((tier, b) in listOf(SamplingTier.DENSE to 600, SamplingTier.MEDIUM to 900, SamplingTier.SPARSE to 3600)) {
            // DISTANCE 1000, cvDr = 12.5: T = (d − 1000)/12.5. T = B + 0.5 s.
            val d = 1000.0 + 12.5 * (b + 0.5)
            val st = trackingState(cfg(), d = d, inStop = true, tier = tier)
            val e = driverFrom(st)
            var s = e.tickMs(S + 1)
            assertEquals(null, i13(s))
            assertEquals(S + expectWake.getValue(tier), s.view.wakeAtMs, "$tier: wakeAtMs after Tick(S + 1)")
            var wakes = 0
            while (s.view.gps == GpsStatus.OK && s.events.none { it is Alarm }) {
                s = e.tickMs(s.view.wakeAtMs!!)
                assertEquals(null, i13(s), "$tier")
                if (++wakes > 5_000) break
            }
            out.append("tier $tier B=$b: $wakes wake-up Tick(s) until GpsLost at ${(s.state.nowMs - S) / 1000.0} s (before T10.5: 40/60/360)\n")
            assertEquals(1, wakes, "$tier: wake-up Ticks until GpsLost")
            val lost = s.events.filterIsInstance<GpsLost>().single()
            assertEquals(GpsLostCause.NO_FIX_TIMEOUT, lost.cause)
            val alarm = s.events.filterIsInstance<Alarm>()
            if (tier == SamplingTier.SPARSE) {
                assertTrue(alarm.isEmpty(), "SPARSE: only GpsLost")
            } else {
                // etaS 640.5 / 910.5 < gpsLostAlarmEtaS 1 200.
                assertTrue(alarm.single().reason == AlarmReason.GPS_LOST && alarm.single().ringNow, "$tier: $alarm")
            }
        }
        // (b) Stationary fixes every 180 s for a 20-minute SPARSE stop; a wake-up Tick only when it comes before the next fix.
        val d = 1000.0 + 12.5 * 3600.5
        val e = driverFrom(trackingState(cfg(), d = d, inStop = true, tier = SamplingTier.SPARSE))
        var s = e.tickMs(S + 1)
        var ticks = 0
        var nextFix = S + 180_000
        while (s.state.nowMs < S + 1_200_000) {
            val w = s.view.wakeAtMs!!
            s = if (nextFix <= w) {
                e.fix(((nextFix - S) / 1000).toInt(), d, spd = 0.0).also { nextFix += 180_000 }
            } else {
                ticks++
                e.tickMs(w)
            }
            assertEquals(null, i13(s))
            assertEquals(GpsStatus.OK, s.view.gps)
            assertTrue(s.events.none { it is Alarm })
        }
        out.append("SPARSE B=3600, stopped 1 200 s with a stationary fix every 180 s: $ticks wake-up Ticks (before T10.5: 794)\n")
        assertEquals(0, ticks, "U106 b: wake-up Ticks during the stop")
        File(outDir, "u106-storm.txt").writeText(out.toString())
    }

    // ================================================================ Doze platform fuzz

    private class Truth(r: Rng, val d0: Double) {
        // Piecewise speed profile: (startS, speed m/s).
        val segs = ArrayList<Pair<Double, Double>>()
        val base = r.dbl(3.0, 35.0)

        init {
            var t = 0.0
            while (t < 200_000.0) {
                val moveS = r.dbl(300.0, 3_600.0)
                segs += t to base * r.dbl(0.7, 1.3)
                t += moveS
                if (r.chance(0.3)) {
                    segs += t to 0.0
                    t += r.dbl(30.0, 1_500.0)
                }
            }
        }

        fun dAt(tS: Double): Double {
            var d = d0
            for (i in segs.indices) {
                val (s0, v) = segs[i]
                if (s0 >= tS) break
                val s1 = if (i + 1 < segs.size) minOf(segs[i + 1].first, tS) else tS
                d -= v * (s1 - s0)
            }
            return d
        }

        fun speedAt(tS: Double): Double = segs.last { it.first <= tS }.second
    }

    private class FuzzStats {
        var trips = 0
        var steps = 0
        var probes = 0
        val firstBy = sortedMapOf<String, Int>()
        val violations = sortedMapOf<String, Int>()
        val firstViolation = sortedMapOf<String, String>()
        var kills = 0
        var minWakeGapMs = Long.MAX_VALUE
        var maxWakesIn9Min = 0
        var dozeTickAlarms = 0
        var dozeTickAlarmsWithin9Min = 0
        var ties = 0
        val lateVsTruth = ArrayList<Double>()
        val lateCases = ArrayList<Pair<Double, String>>()
        val fbAfterInfo = ArrayList<String>()

        /** T10.5: urgent later shifts (I4 exception) emitted in the fuzz. */
        var urgentShifts = 0

        /** T10.5: `fallback (new info after planning)` first alarms: predicted at the last Step before it fired − F, s. */
        val earlyS = ArrayList<Double>()

        /**
         * T10.5 round 2: first alarm from a fallback planned on unchanged information while the engine believes it is stopped with
         * <= Q to the boundary, by the truth speed at the ring (< stationarySpeedMps: really stopped).
         */
        val believedStopReal = ArrayList<String>()

        /** U116 (b): OVERSHOOT / PASSED_CLOSEST using a minD from the GPS-gap chord. */
        var gapTriggers = 0
        val gapLines = ArrayList<String>()
        val believedStopMoving = ArrayList<String>()

        /** U126 (T10.6): first alarms due to the "long loss" term W alone; true seconds to the destination at them (< 0: after). */
        var longLostAlarms = 0
        val longLostRemainingS = ArrayList<Double>()

        /** U126: per-seed lines for the seeds of the review (55, 433, 787). */
        val seedLines = ArrayList<String>()

        /** U126 (after T12.3, D5): DISTANCE cases late > 1 800 s, (late, line). */
        val lateLines = ArrayList<Pair<Double, String>>()
        var lastFirstKey = ""

        fun v(kind: String, where: String) {
            violations[kind] = (violations[kind] ?: 0) + 1
            if (kind !in firstViolation) firstViolation[kind] = where
        }

        fun first(k: String) {
            lastFirstKey = k
            firstBy[k] = (firstBy[k] ?: 0) + 1
        }
    }

    private enum class Variant { DOZE_NO_FIX, DOZE_WITH_FIXES, DOZE_FROM_START }

    /**
     * T10.5 U111: the last Step that carried new information (fix, battery sample, restore): its now, the fallback in force
     * before it ([fBefore], [statusBefore]), the predicted time after it and whether it moved the fallback later.
     */
    private class InfoStep(val t: Long, val fBefore: Long?, val statusBefore: FallbackStatus, val predicted: Long?, val movedLater: Boolean)

    /**
     * One trip under a platform model. Awake phase: a fix every policy interval (GPS gaps allowed), wake-up Ticks, OS fallback.
     * Doze phase: per [variant], no fix at all, or a fix only with some probability at each wake-up. The OS fallback fires at
     * fallback.targetAtMs when it was CONFIRMED (FallbackScheduled ok); FallbackScheduled is delivered right after every
     * FallbackAlarmChanged(at ≠ null), ok with probability [okP]. Optional kill: the process dies at a random time and restarts
     * after a random delay, or when the OS fallback fires (restore RANG); some restarts are PENDING / MISSING / UNKNOWN.
     */
    private fun dozeTrip(
        seed: Long,
        variant: Variant,
        okP: Double,
        killP: Double,
        battery: Boolean,
        st: FuzzStats,
        trace: StringBuilder? = null,
        params: EngineParams = EngineParams(),
    ) {
        val r = Rng(seed * 7919 + variant.ordinal)
        val mode = AlarmMode.entries[r.int(3)]
        val config = TripConfig(
            "doze-$seed", DEST.lat, DEST.lng, mode,
            if (mode == AlarmMode.DISTANCE || r.chance(0.3)) 200 + r.int(9801) else null,
            if (mode == AlarmMode.TIME || (mode != AlarmMode.DISTANCE && r.chance(0.3))) 5 + r.int(56) else null,
            r.chance(0.7), VehicleKind.entries[r.int(4)],
        )
        val truth = Truth(r, r.dbl(3_000.0, 600_000.0))
        val p = params
        var step = TripEngine.start(config, p, S)
        val tripTag = "seed=$seed $variant mode=$mode thr=${config.distanceThresholdM}/${config.timeThresholdMin} d0=${truth.d0.toInt()}"
        // Doze begins at dozeAt (relative s); fixes are never delivered in [gapA, gapB) (tunnel / lost GPS).
        val dozeAtS = when (variant) {
            Variant.DOZE_FROM_START -> r.dbl(0.0, 300.0)
            else -> r.dbl(0.0, 1.0) * truth.d0 / truth.base
        }
        val gapA = if (r.chance(0.5)) r.dbl(0.0, 1.2) * truth.d0 / truth.base else Double.MAX_VALUE
        val gapB = gapA + r.dbl(60.0, 7_200.0)
        val withFixInDoze = variant == Variant.DOZE_WITH_FIXES
        val fixInDozeP = r.dbl(0.2, 0.9)
        var killAt: Long? = if (r.chance(killP)) S + (r.dbl(0.0, 1.5) * truth.d0 / truth.base * 1000.0).toLong() else null
        var lastFixAt = S - 1_000_000L
        var lastInfoAt = S // last input that may move predicted: fix, battery, restore
        var lastInfoKind = "start"
        var lastInfo: InfoStep? = null
        var chordMinD: Double? = null // U116 (b): last dChord of the trip
        var batteryAt = S
        var level = 20 + r.int(81)
        val drainPerH = r.dbl(1.0, 12.0)
        var rang = false
        var guard = 0
        val prevWakeTicks = ArrayDeque<Long>()
        val deadline = { s: EngineState -> s.startedAtMs + s.maxTripDurationS * 1000L + s.params.fallbackLagS * 1000L }
        var everDead = false
        // U126 classes: states after every Step (DISTANCE trips) and the harness death intervals [kill, restart).
        val states = ArrayList<EngineState>()
        if (mode == AlarmMode.DISTANCE) states += step.state
        val deadIntervals = ArrayList<Pair<Long, Long>>()

        fun inGap(tMs: Long): Boolean {
            val ts = (tMs - S) / 1000.0
            return ts >= gapA && ts < gapB
        }

        fun check(prev: Step, s: Step, label: String) {
            if (mode == AlarmMode.DISTANCE) states += s.state
            st.steps++
            val where = "$tripTag t=${(s.state.nowMs - S) / 1000.0} after $label"
            Checks.finiteStateViolation(s.state)?.let { st.v("finite", "$where: $it") }
            // I4 (T10.5 wording) and the urgent-later-shift counter.
            for (ev in s.events) {
                if (ev is FallbackAlarmChanged && ev.cause == FallbackCause.ETA) {
                    when (Checks.quietEmission(prev.view, s.view, ev, s.state.params)) {
                        false -> st.v("I4", where)
                        true -> st.urgentShifts++
                        null -> Unit
                    }
                }
            }
            i13(s)?.let { st.v(it.substringBefore(" in ").substringBefore(" ms"), where) }
            i14(s)?.let { st.v(it.take(40), where) }
            if (s.view.phase != TripPhase.ENDED) {
                // Restore PENDING at the state's own now behaves as Tick(now) (T10.4 §8).
                val rp = TripEngine.restore(s.state, s.state.nowMs, RestoreInfo(FallbackRestoreStatus.PENDING))
                if (rp.events.isNotEmpty() || rp.state != s.state) st.v("restore PENDING at now not silent", where)
                // Tick at wakeAtMs: rings / ends, or re-arms strictly later.
                val w = s.view.wakeAtMs
                if (w != null) {
                    val rr = TripEngine.reduce(s.state, Tick(w))
                    st.probes++
                    val ok = rr.events.any { it is Alarm } || rr.state.phase == TripPhase.ENDED || (rr.view.wakeAtMs ?: Long.MIN_VALUE) > w ||
                        rr.state.phase != s.state.phase
                    if (!ok) st.v("Tick(wakeAt) neither rings nor re-arms later", where)
                }
                val ph = s.view.phase
                if ((ph == TripPhase.ACQUIRING || ph == TripPhase.TRACKING) && s.state.fallback.targetAtMs == null &&
                    s.state.fallback.status != FallbackStatus.NONE
                ) {
                    st.v("active fb status without target", where)
                }
            }
            if (prev.state.alarm.atMs != null && prev.state.alarm.atMs != s.state.alarm.atMs) st.v("first alarm time changed", where)
        }

        while (step.state.phase != TripPhase.ENDED) {
            if (++guard > 60_000) {
                st.v("no end after 60 000 events", tripTag)
                break
            }
            val s0 = step.state
            val now = s0.nowMs
            val awake = (now - S) / 1000.0 < dozeAtS
            val interval = (step.view.samplingPolicy?.intervalS ?: 5) * 1000L
            // Candidate next events.
            val wake = step.view.wakeAtMs
            val fb = s0.fallback.targetAtMs?.takeIf { s0.fallback.status == FallbackStatus.CONFIRMED }
            var nextFix: Long? = null
            if (awake) {
                nextFix = maxOf(lastFixAt + interval, now + 1)
            } else if (withFixInDoze && wake != null && r.chance(fixInDozeP)) {
                nextFix = wake // a fix right at the wake-up (FGS location while the CPU is up)
            }
            if (nextFix != null && inGap(nextFix)) nextFix = null
            val nextBattery = if (battery) batteryAt + 600_000L else null
            val candidates = listOfNotNull(wake, fb?.coerceAtLeast(now), nextFix, nextBattery, killAt?.coerceAtLeast(now))
            if (candidates.isEmpty()) {
                st.v("nothing will ever run again", "$tripTag phase=${s0.phase}")
                break
            }
            val t = candidates.min()
            if (!rang && t > deadline(s0) && !everDead) st.v("silent past deadline + fallbackLag", tripTag)
            if (wake != null && fb != null && wake == fb) st.ties++
            val prev = step
            var label: String
            var input: EngineInput? = null
            if (killAt != null && t == killAt.coerceAtLeast(now)) {
                // Process death. Restart after a random delay, or when the OS fallback fires (it starts the app).
                st.kills++
                everDead = true
                val delay = (r.dbl(1.0, 7_200.0) * 1000.0).toLong()
                var restartAt = t + delay
                val info: RestoreInfo
                if (fb != null && fb <= restartAt) {
                    restartAt = maxOf(fb, t)
                    info = RestoreInfo(FallbackRestoreStatus.RANG, fb)
                } else {
                    info = when (r.int(10)) {
                        0 -> RestoreInfo(FallbackRestoreStatus.MISSING)
                        1 -> RestoreInfo(FallbackRestoreStatus.UNKNOWN)
                        else -> RestoreInfo(FallbackRestoreStatus.PENDING)
                    }
                }
                deadIntervals += t to restartAt
                killAt = if (r.chance(0.3)) restartAt + (r.dbl(60.0, 7_200.0) * 1000.0).toLong() else null
                val snap = TripEngine.decodeSnapshot(TripEngine.encodeSnapshot(s0))
                step = TripEngine.restore(snap, restartAt, info)
                lastInfoAt = restartAt
                lastInfoKind = "restore"
                lastInfo = infoStep(restartAt, s0, step)
                label = "RESTORE ${info.status}"
                if (!rang && step.events.any { it is Alarm }) {
                    rang = true
                    st.first("restore ${info.status} " + step.events.filterIsInstance<Alarm>().single().reason)
                    noteU126(st, seed, tripTag, config, truth, restartAt, step)
                }
            } else {
                val viaFb = fb != null && t == fb.coerceAtLeast(now) && (wake == null || fb < wake)
                input = when {
                    viaFb -> FallbackFired(t, fb!!)
                    t == nextFix -> {
                        val ts = (t - S) / 1000.0
                        val d = truth.dAt(ts)
                        var dd = kotlin.math.abs(d)
                        val acc = if (r.chance(0.1)) r.dbl(60.0, 400.0) else r.dbl(4.0, 30.0)
                        if (r.chance(0.03)) dd += r.dbl(-2_000.0, 4_000.0) // GPS jump
                        val pt0 = TestGeo.pointOnMeridian(DEST, if (d < 0) -dd else dd)
                        val pt = TestGeo.jitter(pt0, r.dbl(-15.0, 15.0), 0.0)
                        val spd = if (r.chance(0.3)) null else truth.speedAt(ts) * r.dbl(0.9, 1.1)
                        lastFixAt = t
                        lastInfoAt = t
                        lastInfoKind = "fix"
                        LocationFix(t, t - r.int(1_500), pt.lat, pt.lng, acc, spd)
                    }
                    t == wake -> Tick(t)
                    else -> {
                        batteryAt = t
                        level = maxOf(1, level - maxOf(0, (drainPerH / 6.0 + r.dbl(-0.5, 0.5)).toInt()))
                        lastInfoAt = t
                        val charging = r.chance(0.1)
                        lastInfoKind = "battery(charging=$charging)"
                        BatterySample(t, level, charging)
                    }
                }
                var gapFromPrevWake = Long.MAX_VALUE
                if (input is Tick && !awake) {
                    // Wake-up Ticks while the CPU sleeps (Doze): gap to the previous one, and how many in any 9-minute window
                    // (Android allows one setExactAndAllowWhileIdle per ~9 min in Doze: RK17).
                    if (prevWakeTicks.isNotEmpty()) gapFromPrevWake = t - prevWakeTicks.last()
                    prevWakeTicks.addLast(t)
                    while (prevWakeTicks.first() < t - 540_000L) prevWakeTicks.removeFirst()
                    st.maxWakesIn9Min = maxOf(st.maxWakesIn9Min, prevWakeTicks.size)
                    if (gapFromPrevWake != Long.MAX_VALUE) st.minWakeGapMs = minOf(st.minWakeGapMs, gapFromPrevWake)
                }
                step = TripEngine.reduce(s0, input)
                label = input.toString()
                if (input is LocationFix) {
                    // U116 (b) (round 3b): an OVERSHOOT / PASSED_CLOSEST that uses a minD from the GPS-gap chord must not come before
                    // the vehicle really passed the destination.
                    GapProbe.of(s0, input, step)?.dChord?.let { chordMinD = it }
                    val cm = chordMinD
                    val passEv = step.events.any {
                        it is Overshoot || (it is Alarm && (it.reason == AlarmReason.OVERSHOOT || it.reason == AlarmReason.PASSED_CLOSEST))
                    }
                    if (cm != null && passEv && step.state.minD == cm) {
                        st.gapTriggers++
                        val dTruth = truth.dAt((t - S) / 1000.0)
                        val kinds = step.events.filter { it is Overshoot || it is Alarm }.map { if (it is Alarm) it.reason.name else "Overshoot" }
                        st.gapLines += "$tripTag t=${(t - S) / 1000.0} truthD=${dTruth.toInt()} chordMinD=$cm $kinds"
                        if (dTruth > 0.0) st.v("chord minD used before the destination was passed", st.gapLines.last())
                    }
                }
                if (input is LocationFix || input is BatterySample) lastInfo = infoStep(t, s0, step)
                if (!rang && step.events.any { it is Alarm }) {
                    rang = true
                    val a = step.events.filterIsInstance<Alarm>().single()
                    noteU126(st, seed, tripTag, config, truth, t, step)
                    if (viaFb) {
                        // Engine-first: a fallback planned after the last new information (pure dead reckoning since then)
                        // must never beat the engine's own wake-up alarm.
                        val emitted = s0.fallback.emittedAtMs ?: Long.MIN_VALUE
                        val pv = prev.view.predictedAlarmAtMs
                        val detail = "$tripTag t=${(t - S) / 1000.0} emitted=${(emitted - S) / 1000.0} " +
                            "engineP=${pv?.let { (it - S) / 1000.0 }} engineWake=${prev.view.wakeAtMs?.let { (it - S) / 1000.0 }} " +
                            "gps=${prev.view.gps} stopped=${prev.state.stopStartMs != null}"
                        // T10 "T10.5" (a) + "T10.5 vòng 2" (2): the engine believes it is stopped (GPS OK, stop in progress) with
                        // predicted − now <= Q: K1 forbids moving the fallback and the forecast slides with now. Not a violation
                        // while the fallback rings no later than predicted (previous Step) + (fallbackLagS + fallbackNearSlackS)
                        // + 1 s (T10.5 round 3 §11: the near-zone hold band); split by the truth
                        // speed at the ring (really stopped / moving, the latter from a stop misclassified on two close fixes).
                        val believedStop = prev.view.gps == GpsStatus.OK && prev.state.stopStartMs != null && pv != null &&
                            pv - prev.state.nowMs <= p.fallbackQuietBeforeS * 1000L
                        if (emitted >= lastInfoAt && believedStop) {
                            val v = truth.speedAt((t - S) / 1000.0)
                            val moving = v >= p.stationarySpeedMps
                            val bound = pv + (p.fallbackLagS + p.fallbackNearSlackS) * 1000L + 1000L
                            val line = "$detail truthSpeed=$v ${if (moving) "moving" else "stopped"} ring-P=${(t - pv) / 1000.0} s"
                            if (t > bound) {
                                st.v("believed-stop fallback later than predicted + fallbackLag + fallbackNearSlack + 1 s", line)
                            }
                            st.first("fallback (pure DR, engine believes stopped, <= Q to the boundary) ${a.reason}")
                            if (moving) st.believedStopMoving += line else st.believedStopReal += line
                        } else if (emitted >= lastInfoAt) {
                            st.v("first alarm from OS fallback though planned on unchanged information", detail)
                            st.first("fallback (pure DR) ${a.reason}")
                        } else {
                            st.first("fallback (new info after planning) ${a.reason}")
                            val li = lastInfo
                            val q = p.fallbackQuietBeforeS * 1000L
                            // T10.5 U111: the last new information could rescue it (F − t >= minLead, predicted − t > Q, predicted >= F)
                            // so that Step must have moved the fallback later.
                            val f: Long = fb
                            if (li != null && li.fBefore == f && li.statusBefore != FallbackStatus.FAILED && li.predicted != null &&
                                f - li.t >= p.fallbackMinLeadS * 1000L && li.predicted - li.t > q && li.predicted >= f && !li.movedLater
                            ) {
                                st.v("eligible for the urgent later shift but not rescued", "$tripTag t=${(t - S) / 1000.0}")
                            }
                            prev.view.predictedAlarmAtMs?.let { st.earlyS += (it - t) / 1000.0 }
                            st.fbAfterInfo += "$tripTag F=${(t - S) / 1000.0} emitted=${(emitted - S) / 1000.0} lastInfo=$lastInfoKind@" +
                                "${(lastInfoAt - S) / 1000.0} F-tInfo=${(f - lastInfoAt) / 1000.0} " +
                                "engineP=${prev.view.predictedAlarmAtMs?.let { (it - S) / 1000.0 }} " +
                                "early=${prev.view.predictedAlarmAtMs?.let { (it - t) / 1000.0 }} " +
                                "engineWake=${prev.view.wakeAtMs?.let { (it - S) / 1000.0 }} gps=${prev.view.gps} " +
                                "stopped=${prev.state.stopStartMs != null}"
                        }
                    } else {
                        st.first((if (awake) "awake " else "doze ") + (if (a.ringNow) "engine " else "noRing ") + a.reason)
                        if (input is Tick && !awake) {
                            st.dozeTickAlarms++
                            if (gapFromPrevWake < 540_000L) st.dozeTickAlarmsWithin9Min++
                        }
                        if (!a.ringNow) st.v("engine alarm without ringNow", tripTag)
                    }
                    if (mode == AlarmMode.DISTANCE) {
                        // Truth at the first alarm: distance left vs threshold (positive = rang before reaching the threshold).
                        val thr = config.distanceThresholdM!!.toDouble()
                        st.lateVsTruth += truth.dAt((t - S) / 1000.0) - thr
                        if (truth.dAt((t - S) / 1000.0) < thr) {
                            var lo = 0.0
                            var hi = (t - S) / 1000.0
                            repeat(60) { val m = (lo + hi) / 2; if (truth.dAt(m) > thr) lo = m else hi = m }
                            val cross = S + (hi * 1000).toLong()
                            val lateS = (t - cross) / 1000.0
                            if (lateS > 1_800.0) {
                                st.lateLines += lateS to app.napstop.core.trip.support.lateCaseLine(
                                    tripTag, config.vehicleHint, lateS, st.lastFirstKey,
                                    deadIntervals.any { cross >= it.first && cross < it.second }, cross, thr,
                                    states.lastOrNull { it.nowMs <= cross },
                                ) { ms -> truth.dAt((ms - S) / 1000.0) }
                            }
                            st.lateCases += ((t - cross) / 1000.0) to
                                "$tripTag late ${(t - cross) / 1000.0} s reason ${a.reason} gapAtCross=${inGap(cross)} dozeAt=${dozeAtS.toInt()} s " +
                                "cross=${(cross - S) / 1000} s everDead=$everDead fixesInDozeP=${if (withFixInDoze) fixInDozeP else 0.0} " +
                                "speedAtCross=${truth.speedAt((cross - S) / 1000.0)} base=${truth.base}"
                        }
                    }
                }
            }
            check(prev, step, label)
            trace?.append(
                "t=${(step.state.nowMs - S) / 1000.0} truthD=${truth.dAt((step.state.nowMs - S) / 1000.0).toInt()} ${label.take(60)} -> " +
                    "${step.view.phase} gps=${step.view.gps} dist=${step.view.distanceM} eta=${step.view.etaS} v=${step.view.speedKmh} " +
                    "P=${step.view.predictedAlarmAtMs?.let { (it - S) / 1000.0 }} wake=${step.view.wakeAtMs?.let { (it - S) / 1000.0 }} " +
                    "fb=${step.view.fallbackAtMs?.let { (it - S) / 1000.0 }}/${step.view.fallbackStatus} tier=${step.view.samplingPolicy?.tier} " +
                    "drop=${step.view.droppedFixes} ev=${step.events.map { it.javaClass.simpleName }}\n",
            )
            // Platform: confirm the requested fallback alarm (ok with probability okP).
            val fbEvent = step.events.filterIsInstance<FallbackAlarmChanged>().lastOrNull()
            if (fbEvent?.fallbackAtMs != null && step.state.phase != TripPhase.ENDED) {
                val prev2 = step
                step = TripEngine.reduce(step.state, FallbackScheduled(step.state.nowMs, fbEvent.fallbackAtMs!!, r.chance(okP)))
                check(prev2, step, "FallbackScheduled")
                if (step.events.any { it is Alarm }) st.v("FallbackScheduled at now produced an alarm", tripTag)
            }
            // Nobody answers: alarms stop after alarmMaxActiveS (c6) and the trip ends MISSED.
        }
        if (!rang) st.v("trip ended without any alarm", tripTag)
        st.trips++
    }

    /** U126: true time of arrival (dAt <= 0), s from S; null when not within 200 000 s. */
    private fun arrivalS(truth: Truth): Double? {
        if (truth.dAt(200_000.0) > 0.0) return null
        var lo = 0.0
        var hi = 200_000.0
        repeat(60) { val m = (lo + hi) / 2; if (truth.dAt(m) > 0.0) lo = m else hi = m }
        return hi
    }

    /** U126 (T10.6): statistics of the first alarm of a trip ([t] its time, [step] the Step that raised it). */
    private fun noteU126(st: FuzzStats, seed: Long, tripTag: String, config: TripConfig, truth: Truth, t: Long, step: Step) {
        val a = step.events.filterIsInstance<Alarm>().single()
        val ts = (t - S) / 1000.0
        val arr = arrivalS(truth)
        val info = if (a.reason == AlarmReason.GPS_LOST) app.napstop.core.trip.support.lostAlarmInfo(step.state) else null
        if (info?.longLostOnly == true) {
            st.longLostAlarms++
            if (arr != null) st.longLostRemainingS += arr - ts
        }
        if (seed in U126_SEEDS) {
            val thr = config.distanceThresholdM
            var lateTxt = "-"
            if (config.mode == AlarmMode.DISTANCE && thr != null) {
                var lo = 0.0
                var hi = 200_000.0
                if (truth.dAt(hi) <= thr) {
                    repeat(60) { val m = (lo + hi) / 2; if (truth.dAt(m) > thr) lo = m else hi = m }
                    lateTxt = String.format(java.util.Locale.ROOT, "%.0f", ts - hi)
                }
            }
            val e = app.napstop.core.trip.estimate(app.napstop.core.trip.StepWork(step.state))
            st.seedLines += "$tripTag hint=${config.vehicleHint}: ${a.reason} at ${ts.toInt()} s; vs DISTANCE crossing $lateTxt s (+ late); " +
                "true remaining ${arr?.let { (it - ts).toInt() }} s; cvDr ${e?.cvDr?.let { String.format(java.util.Locale.ROOT, "%.2f", it) }}; " +
                "preV ${info?.preV ?: false}; W alone ${info?.longLostOnly ?: false}"
        }
    }

    private fun infoStep(t: Long, s0: EngineState, step: Step): InfoStep {
        val f = s0.fallback.targetAtMs
        val moved = f != null && step.events.any { it is FallbackAlarmChanged && (it.fallbackAtMs ?: Long.MIN_VALUE) > f }
        return InfoStep(t, f, s0.fallback.status, step.view.predictedAlarmAtMs, moved)
    }

    private fun runDozeFuzz(
        name: String,
        seeds: LongRange,
        variant: Variant,
        okP: Double,
        killP: Double,
        battery: Boolean,
        params: EngineParams = EngineParams(),
        write: Boolean = true,
    ): FuzzStats {
        val st = FuzzStats()
        for (seed in seeds) dozeTrip(seed, variant, okP, killP, battery, st, params = params)
        if (!write) return st
        val late = st.lateVsTruth.sorted()
        val lateTxt = if (late.isEmpty()) "-" else "min ${late.first().toInt()} m, p05 ${late[late.size / 20].toInt()} m, median ${late[late.size / 2].toInt()} m, " +
            "rang after passing the threshold: ${late.count { it < 0 }}/${late.size}"
        val early = st.earlyS.sorted()
        val fbNewInfo = st.firstBy.filterKeys { it.startsWith("fallback (new info after planning)") }.values.sum()
        // T10.5 round 2: DISTANCE lateness vs truth (threshold crossing → first alarm) of the trips that rang after the threshold.
        val lateS = st.lateCases.map { it.first }.sorted()
        fun q(f: Double) = lateS[minOf(lateS.size - 1, (f * lateS.size).toInt())]
        val lateSTxt = if (lateS.isEmpty()) "-" else "n ${lateS.size}, p50 ${q(0.5)} s, p90 ${q(0.9)} s, max ${lateS.last()} s"
        val warn = if (st.believedStopMoving.size > 3) "WARNING: believed-stop moving > 3, report to the designer\n" else ""
        File(outDir, "u111-doze-$name.txt").writeText(
            "trips=${st.trips} steps=${st.steps} probes=${st.probes} kills=${st.kills} ties=${st.ties}\n" +
                "urgentLaterShifts=${st.urgentShifts} fallbackNewInfoAfterPlanning=$fbNewInfo earlyVsPredictedS: " +
                (if (early.isEmpty()) "-" else "median ${early[early.size / 2]} max ${early.last()}") + "\n" +
                "believedStopFallbackFirst: stopped=${st.believedStopReal.size} moving=${st.believedStopMoving.size}\n" + warn +
                "chordMinDPassAlarms=${st.gapTriggers}${st.gapLines.joinToString("") { "\n  $it" }}\n" +
                "DISTANCE late vs truth (crossing → first alarm, rang after the threshold): $lateSTxt\n" +
                "firstAlarm=${st.firstBy}\nviolations=${st.violations}\nfirst=${st.firstViolation}\n" +
                "minGapBetweenDozeWakeTicksMs=${st.minWakeGapMs} maxDozeWakeTicksIn9Min=${st.maxWakesIn9Min} " +
                "firstAlarmFromDozeTick=${st.dozeTickAlarms} ofWhichWithin9MinOfPreviousWake=${st.dozeTickAlarmsWithin9Min}\nDISTANCE truth at first alarm (d − thr): $lateTxt\n" +
                st.lateCases.sortedByDescending { it.first }.take(25).joinToString("\n") { it.second } + "\n" +
                "fallback first after new information:\n" + st.fbAfterInfo.joinToString("\n") + "\n" +
                "fallback first, engine believes stopped with <= Q to the boundary (not a violation within P + lag + 1 s):\n" +
                (st.believedStopReal + st.believedStopMoving).joinToString("\n") + "\n",
        )
        return st
    }

    @Test
    fun `U111 a Doze fuzz no fix in Doze, fallback always scheduled OK, no kill - engine always rings first`() {
        val st = runDozeFuzz("nofix-ok", 1L..700L, Variant.DOZE_NO_FIX, okP = 1.0, killP = 0.0, battery = false)
        assertTrue(st.steps > 100_000) { "too small: ${st.steps}" }
        assertTrue(st.violations.isEmpty()) { "violations ${st.violations} first ${st.firstViolation}" }
        assertTrue(st.firstBy.keys.none { it.startsWith("fallback") }) { "first alarms: ${st.firstBy}" }
    }

    @Test
    fun `U111 b Doze fuzz from trip start, random fallback failures and kills - invariants and liveness`() {
        val st = runDozeFuzz("fromstart", 1L..700L, Variant.DOZE_FROM_START, okP = 0.85, killP = 0.5, battery = true)
        assertTrue(st.violations.isEmpty()) { "violations ${st.violations} first ${st.firstViolation}" }
    }

    @Test
    fun `U111 c Doze fuzz with fixes at wake-ups, battery, failures and kills - invariants, liveness, urgent later shift`() {
        val st = runDozeFuzz("withfix", 1L..700L, Variant.DOZE_WITH_FIXES, okP = 0.85, killP = 0.4, battery = true)
        assertTrue(st.violations.isEmpty()) { "violations ${st.violations} first ${st.firstViolation}" }
    }

    @Test
    fun `U111 d Doze fuzz no fix in Doze with battery, failures and kills - invariants and liveness`() {
        val st = runDozeFuzz("nofix-mixed", 701L..1400L, Variant.DOZE_NO_FIX, okP = 0.85, killP = 0.4, battery = true)
        assertTrue(st.violations.isEmpty()) { "violations ${st.violations} first ${st.firstViolation}" }
    }

    /**
     * U126 (T10.6 (1)(2)(4), statistics): the four Doze fuzzes of U111 with T10.6 off (T12.2) and on (defaults). Gate: no violation
     * and an alarm on every trip with T10.6 on (as U111). Written to u126-longloss.txt: DISTANCE lateness vs truth T12.2 → T10.6,
     * first alarms due to W alone and the true time left to the destination at them, the review seeds 55, 433 (withfix), 787
     * (nofix-mixed).
     */
    @Test
    fun `U126 a Doze fuzz lateness T12_2 vs T10_6, long-loss alarms and the review seeds`() {
        val runs = listOf(
            Triple("nofix-ok", 1L..700L, listOf(Variant.DOZE_NO_FIX, 1.0, 0.0, false)),
            Triple("fromstart", 1L..700L, listOf(Variant.DOZE_FROM_START, 0.85, 0.5, true)),
            Triple("withfix", 1L..700L, listOf(Variant.DOZE_WITH_FIXES, 0.85, 0.4, true)),
            Triple("nofix-mixed", 701L..1400L, listOf(Variant.DOZE_NO_FIX, 0.85, 0.4, true)),
        )
        val out = StringBuilder("# U126 (T10.6) Doze fuzz of U111: off (gpsLostLongS 0, passedClosestSlowRiseM 0; preV on) -> T10.6 (defaults)\n")
        val bad = ArrayList<String>()
        for ((name, seeds, cfgs) in runs) {
            val (variant, okP, killP, battery) = cfgs
            val off = runDozeFuzz(name, seeds, variant as Variant, okP as Double, killP as Double, battery as Boolean, app.napstop.core.trip.support.T106_OFF_PARAMS, write = false)
            val on = runDozeFuzz(name, seeds, variant, okP, killP, battery, write = false)
            if (on.violations.isNotEmpty()) bad += "$name: ${on.violations} ${on.firstViolation}"
            val lateOff = off.lateCases.map { it.first }
            val lateOn = on.lateCases.map { it.first }
            out.append("\n## $name\n")
                .append("DISTANCE late vs truth (s, rang after the threshold): off ${app.napstop.core.trip.support.quantiles(lateOff)} -> T10.6 ${app.napstop.core.trip.support.quantiles(lateOn)}\n")
                .append("late > 1800 s: off ${lateOff.count { it > 1_800.0 }} -> T10.6 ${lateOn.count { it > 1_800.0 }}\n")
            for ((_, l) in on.lateLines.sortedByDescending { it.first }) out.append(l).append('\n')
            out
                .append("first alarms due to W alone: ${on.longLostAlarms}; true time left at them (s): ${app.napstop.core.trip.support.quantiles(on.longLostRemainingS)}; ")
                .append("after arrival: ${on.longLostRemainingS.count { it < 0.0 }}\n")
                .append("firstAlarm off ${off.firstBy}\nfirstAlarm T10.6 ${on.firstBy}\n")
            for (l in off.seedLines) out.append("seed off ").append(l).append('\n')
            for (l in on.seedLines) out.append("seed T10.6 ").append(l).append('\n')
        }
        File(outDir, "u126-longloss.txt").writeText(out.toString())
        assertTrue(bad.isEmpty()) { bad.joinToString("\n") }
    }

    private companion object {
        /** U126: the seeds of review T12.2 round 2. */
        val U126_SEEDS = setOf(55L, 433L, 787L)
    }
}
