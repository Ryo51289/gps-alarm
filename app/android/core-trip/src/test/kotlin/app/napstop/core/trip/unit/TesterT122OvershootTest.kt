package app.napstop.core.trip.unit

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmMode
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.LocationFix
import app.napstop.core.trip.Step
import app.napstop.core.trip.Tick
import app.napstop.core.trip.TripConfig
import app.napstop.core.trip.TripEngine
import app.napstop.core.trip.VehicleKind
import app.napstop.core.trip.support.DEST
import app.napstop.core.trip.support.S
import app.napstop.core.trip.support.TestGeo
import app.napstop.core.trip.support.cfg
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File
import kotlin.math.abs
import kotlin.math.sqrt

/**
 * Tester, T12.2 retest (T10.5 vòng 3–3d): adversarial cases for the new overshoot rule
 * `overshoot = (increasing && fast) || (TRACKING/ACQUIRING && not alarmed && notCloser)`,
 * `notCloser = inStop || (last3 lag-2 not decreasing && min(last3) − minD >= overshootOpenM)`, and the GPS-gap chord on minD.
 * A "wrong-wording" alarm = OVERSHOOT or PASSED_CLOSEST while the vehicle has not reached its closest point to the destination
 * yet (it is still approaching): the user is told "Có thể bạn đã đi quá …" before the stop; Dismiss ends the trip (Q11 = A).
 * Truth: the route runs along the meridian of the destination shifted [Path.offsetM] east; y = signed along-route position
 * (negative = before the closest point). Fixes: position + uniform noise ±acc, optional outliers, at the policy interval or a
 * slower forced interval (platform delivering sparse fixes), wake-up Ticks in between. Stops at the first alarm.
 */
class TesterT122OvershootTest {
    private val outDir = File(System.getProperty("napstop.outDir") ?: "build/napstop").also { it.mkdirs() }
    private val p = EngineParams()

    private class Rng(seed: Long) {
        private var x = seed * -0x61c8864680b583ebL + 0x1357911L

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

        fun chance(q: Double): Boolean = dbl() < q
    }

    /** Piecewise-constant along-route speed (m/s, negative = reversing). */
    private class Path(val y0: Double, val offsetM: Double) {
        val segs = ArrayList<Pair<Long, Double>>()

        fun yAt(t: Long): Double {
            var y = y0
            for (i in segs.indices) {
                val (s0, v) = segs[i]
                if (s0 >= t) break
                val s1 = if (i + 1 < segs.size) minOf(segs[i + 1].first, t) else t
                y += v * (s1 - s0) / 1000.0
            }
            return y
        }

        fun vAt(t: Long): Double = segs.lastOrNull { it.first <= t }?.second ?: 0.0

        fun dAt(t: Long): Double {
            val y = yAt(t)
            return sqrt(y * y + offsetM * offsetM)
        }
    }

    private class Outcome(val alarm: Alarm?, val y: Double, val d: Double, val steps: Int, val wrong: Boolean)

    /**
     * Drives a trip until the first alarm or [horizonMs]. [forcedIntervalMs] null = the policy interval. [fix] builds the fix
     * delivered at t (null = dropped). Wrong wording: OVERSHOOT/PASSED_CLOSEST while y < 0 at the alarm.
     */
    private fun drive(
        config: TripConfig,
        path: Path,
        horizonMs: Long,
        forcedIntervalMs: Long?,
        fix: (Long, Step) -> LocationFix?,
    ): Outcome {
        var step: Step = TripEngine.start(config, p, S)
        var nextFix = S + 1_000L
        var n = 0
        while (step.events.none { it is Alarm } && step.state.nowMs < horizonMs && ++n < 200_000) {
            val wake = step.view.wakeAtMs
            step = if (wake != null && wake < nextFix) {
                TripEngine.reduce(step.state, Tick(wake))
            } else {
                val t = nextFix
                nextFix = t + (forcedIntervalMs ?: ((step.view.samplingPolicy?.intervalS ?: 5) * 1000L))
                val f = fix(t, step) ?: continue
                TripEngine.reduce(step.state, f)
            }
        }
        val a = step.events.filterIsInstance<Alarm>().firstOrNull()
        val t = step.state.nowMs
        val wrong = a != null && (a.reason == AlarmReason.OVERSHOOT || a.reason == AlarmReason.PASSED_CLOSEST) && path.yAt(t) < 0.0
        return Outcome(a, path.yAt(t), path.dAt(t), n, wrong)
    }

    private fun fixAt(t: Long, y: Double, east: Double, acc: Double, spd: Double?): LocationFix {
        val pt = TestGeo.jitter(TestGeo.pointOnMeridian(DEST, -y), east, 0.0)
        return LocationFix(t, t, pt.lat, pt.lng, acc, spd)
    }

    private val modes: List<Pair<String, TripConfig>> = listOf(
        "D200" to cfg(AlarmMode.DISTANCE, thr = 200), "D500" to cfg(AlarmMode.DISTANCE, thr = 500),
        "D800" to cfg(AlarmMode.DISTANCE, thr = 800), "D1000" to cfg(AlarmMode.DISTANCE, thr = 1000),
        "D2000" to cfg(AlarmMode.DISTANCE, thr = 2000), "T5" to cfg(AlarmMode.TIME, thrMin = 5),
        "T15" to cfg(AlarmMode.TIME, thrMin = 15), "SMART" to cfg(AlarmMode.SMART),
    )

    // ================================================================ O1: stuck in traffic before the destination + outlier fix(es)

    /**
     * Approach at 12 m/s from 20 km; at [jamY] (m before the destination, negative) the vehicle stops (or crawls [crawl] m/s) for
     * 20 min, then runs on at 12 m/s. During the jam, [outliers] consecutive fixes are reported [delta] m closer to the destination
     * (multipath, reported accuracy 15 m, same Doppler as the true fixes). Fixes every [interval] (null = policy), noise ±8 m.
     */
    private fun jam(
        config: TripConfig,
        jamY: Double,
        crawl: Double,
        doppler: Boolean,
        delta: Double,
        outliers: Int,
        interval: Long?,
        dropFirst: Boolean = false,
    ): Outcome {
        val path = Path(-20_000.0, 0.0)
        val tJam = S + ((20_000.0 + jamY) / 12.0 * 1000).toLong()
        path.segs += S to 12.0
        path.segs += tJam to crawl
        path.segs += (tJam + 1_200_000L) to 12.0
        val r = Rng(jamY.toLong() * 31 + delta.toLong())
        val outAt = tJam + 300_000L
        var outLeft = outliers
        return drive(config, path, S + 6 * 3_600_000L, interval) { t, _ ->
            val y = path.yAt(t)
            val spd = if (doppler) abs(path.vAt(t)) else null
            if (t >= outAt && outLeft > 0) {
                outLeft--
                // O1c (T10.5 vòng 3f): the first outlier never arrives (dropped by the platform) instead of being rejected.
                if (dropFirst && outLeft == outliers - 1) return@drive null
                fixAt(t, y + delta, r.dbl(-8.0, 8.0), 15.0, spd)
            } else {
                fixAt(t, y + r.dbl(-8.0, 8.0), r.dbl(-8.0, 8.0), 10.0, spd)
            }
        }
    }

    @Test
    fun `T122 O1 stuck in traffic before the destination with an outlier fix - wrong-wording OVERSHOOT count`() {
        val out = StringBuilder()
        val wrong = ArrayList<String>()
        var runs = 0
        for ((name, config) in modes) for (jamY in listOf(-1_200.0, -1_500.0, -1_900.0, -2_500.0)) {
            for (crawl in listOf(0.0, 0.3)) for (doppler in listOf(true, false)) for (delta in listOf(1_100.0, 1_500.0, 2_000.0)) {
                for (outliers in listOf(0, 1, 2)) for (interval in listOf<Long?>(null, 30_000L, 180_000L)) {
                    val o = jam(config, jamY, crawl, doppler, delta, outliers, interval)
                    runs++
                    val line = "$name jamY=${jamY.toInt()} crawl=$crawl doppler=$doppler delta=${delta.toInt()} outliers=$outliers " +
                        "interval=${interval?.div(1000) ?: "policy"}: ${o.alarm?.reason} at y=${o.y.toInt()} d=${o.d.toInt()}"
                    out.append(line).append('\n')
                    if (o.wrong) wrong += line
                }
            }
        }
        File(outDir, "t122-o1-jam-outlier.txt").writeText("runs=$runs wrongWording=${wrong.size}\n${wrong.joinToString("\n")}\n\nall:\n$out")
        // Without outliers the rule must never fire before the destination.
        assertTrue(wrong.none { it.contains("outliers=0") }) { wrong.filter { it.contains("outliers=0") }.take(5).joinToString("\n") }
        assertEquals(PINNED_O1, wrong.size)
    }

    /**
     * O1c (T10.5 vòng 3f, RK20 c, recorded): as O1 but the first outlier fix never arrives (dropped by the platform, so it is not
     * in `rejects`) and the next one(s) are outliers: with Δt ≥ lostAfterS the accepted outlier can be a GPS-gap chord fix.
     * outliers = 2 / 3: one dropped + 1 / 2 delivered outliers.
     */
    @Test
    fun `T122 O1c stuck before the destination, first outlier dropped by the platform instead of rejected - wrong-wording count`() {
        val out = StringBuilder()
        val wrong = ArrayList<String>()
        var runs = 0
        for ((name, config) in modes) for (jamY in listOf(-1_200.0, -1_500.0, -1_900.0, -2_500.0)) {
            for (crawl in listOf(0.0, 0.3)) for (doppler in listOf(true, false)) for (delta in listOf(1_100.0, 1_500.0, 2_000.0)) {
                for (outliers in listOf(2, 3)) for (interval in listOf<Long?>(null, 30_000L, 180_000L)) {
                    val o = jam(config, jamY, crawl, doppler, delta, outliers, interval, dropFirst = true)
                    runs++
                    val line = "$name jamY=${jamY.toInt()} crawl=$crawl doppler=$doppler delta=${delta.toInt()} outliers=$outliers(first dropped) " +
                        "interval=${interval?.div(1000) ?: "policy"}: ${o.alarm?.reason} at y=${o.y.toInt()} d=${o.d.toInt()}"
                    out.append(line).append('\n')
                    if (o.wrong) wrong += line
                }
            }
        }
        File(outDir, "t122-o1c-dropped-outlier.txt").writeText("runs=$runs wrongWording=${wrong.size}\n${wrong.joinToString("\n")}\n\nall:\n$out")
        assertEquals(PINNED_O1C, wrong.size)
    }

    /**
     * O1b, the engine's own sampling policy (no forced interval): stop-and-go traffic from [jamY] (60 s at [crawl] m/s, 120 s
     * stopped with Doppler 0) for 40 min, so the speed EMA drops, ETA grows and the policy may go MEDIUM (30 s); one outlier fix
     * [delta] m closer at the middle of a stopped phase. Returns the outcome and the policy interval in force at the outlier.
     */
    private fun stopAndGo(
        config: TripConfig, jamY: Double, crawl: Double, delta: Double, outlierAfterS: Int, vApproach: Double = 12.0,
    ): Pair<Outcome, Int?> {
        val y0 = if (vApproach >= 5.0) -20_000.0 else jamY - 2_000.0
        val path = Path(y0, 0.0)
        val tJam = S + ((jamY - y0) / vApproach * 1000).toLong()
        path.segs += S to vApproach
        var t = tJam
        while (t < tJam + 2_400_000L) {
            path.segs += t to crawl
            path.segs += (t + 60_000L) to 0.0
            t += 180_000L
        }
        path.segs += t to 12.0
        val r = Rng(jamY.toLong() + delta.toLong() + outlierAfterS)
        // The outlier lands 60 s into a stopped phase after [outlierAfterS] s of jam.
        val k = (outlierAfterS * 1000L) / 180_000L
        val outAt = tJam + k * 180_000L + 120_000L
        var done = false
        var intervalAtOutlier: Int? = null
        val o = drive(config, path, S + 6 * 3_600_000L, null) { at, st ->
            val y = path.yAt(at)
            val spd = abs(path.vAt(at))
            if (!done && at >= outAt && path.vAt(at) == 0.0) {
                done = true
                intervalAtOutlier = st.view.samplingPolicy?.intervalS
                fixAt(at, y + delta, r.dbl(-8.0, 8.0), 15.0, spd)
            } else {
                fixAt(at, y + r.dbl(-8.0, 8.0), r.dbl(-8.0, 8.0), 10.0, spd)
            }
        }
        return o to intervalAtOutlier
    }

    @Test
    fun `T122 O1b stop-and-go traffic with the engine's own sampling policy and one outlier fix`() {
        val out = StringBuilder()
        val wrong = ArrayList<String>()
        var runs = 0
        for ((name, config) in modes) for (jamY in listOf(-1_200.0, -1_500.0, -1_900.0, -2_500.0)) {
            for (crawl in listOf(1.2, 1.5, 2.5)) for (delta in listOf(1_100.0, 1_300.0, 1_500.0)) for (after in listOf(600, 1_200, 1_800))
            for (vA in listOf(12.0, 1.3)) {
                val (o, iv) = stopAndGo(config, jamY, crawl, delta, after, vA)
                runs++
                val line = "$name vApproach=$vA jamY=${jamY.toInt()} crawl=$crawl delta=${delta.toInt()} outlierAfter=$after s intervalAtOutlier=$iv: ${o.alarm?.reason} at y=${o.y.toInt()} d=${o.d.toInt()}"
                out.append(line).append('\n')
                if (o.wrong) wrong += line
            }
        }
        File(outDir, "t122-o1b-stopgo.txt").writeText("runs=$runs wrongWording=${wrong.size}\n${wrong.joinToString("\n")}\n\nall:\n$out")
        assertEquals(PINNED_O1B, wrong.size)
    }

    /**
     * Minimal repro (report Lần 2, bug R2-1): DISTANCE 500, approach at 12 m/s, stopped (Doppler 0) at 1 900 m from the
     * destination, fixes every 30 s (sparse: `recent` holds one fix, dSmooth = raw), one accepted outlier fix 1 100 m closer
     * (800 m, plausible at 55 m/s). minD = 800 < nearRadius 1 000; the next true fix: inStop, dSmooth − minD = 1 100 ≥ 1 000.
     */
    @Test
    fun `T122 O1 repro stopped 1_9 km before the destination, one outlier fix at 800 m, fixes every 30 s - pins bug R2-1`() {
        val o = jam(cfg(AlarmMode.DISTANCE, thr = 500), -1_900.0, 0.0, true, 1_100.0, 1, 30_000L)
        val got = "${o.alarm?.reason} ringNow=${o.alarm?.ringNow} at d=${o.d.toInt()} m (y=${o.y.toInt()})"
        File(outDir, "t122-o1-repro.txt").writeText(got + "\n")
        assertEquals(PINNED_O1_REPRO, got)
    }

    // ================================================================ O2: normal approach, GPS jitter, sparse fixes (fuzz)

    @Test
    fun `T122 O2 normal approach fuzz - jitter, sparse fixes, off-route destination, rare outliers - wrong wording only with outliers`() {
        val out = StringBuilder()
        val byCause = sortedMapOf<String, Int>()
        val firsts = sortedMapOf<String, Int>()
        val lateAfterPass = ArrayList<Double>()
        var runs = 0
        for (seed in 1L..3_000L) {
            val r = Rng(seed)
            val (name, config) = modes[r.int(modes.size)]
            val v = r.dbl(2.0, 30.0)
            val offset = if (r.chance(0.4)) 0.0 else r.dbl(50.0, 900.0)
            val path = Path(-r.dbl(5_000.0, 30_000.0), offset)
            path.segs += S to v
            val acc = r.dbl(5.0, 60.0)
            val noDoppler = r.chance(0.3)
            val forced = listOf<Long?>(null, null, 30_000L, 60_000L, 180_000L)[r.int(5)]
            val drop = r.dbl(0.0, 0.5)
            val outlierP = if (r.chance(0.5)) 0.0 else 0.02
            var outliers = 0
            val o = drive(config, path, S + 8 * 3_600_000L, forced) { t, _ ->
                if (r.chance(drop)) return@drive null
                val y = path.yAt(t)
                val spd = if (noDoppler) null else abs(path.vAt(t)) * r.dbl(0.9, 1.1)
                if (r.chance(outlierP)) {
                    outliers++
                    fixAt(t, y + r.dbl(-2_000.0, 2_000.0), offset + r.dbl(-300.0, 300.0), r.dbl(10.0, 30.0), spd)
                } else {
                    fixAt(t, y + r.dbl(-acc, acc), offset + r.dbl(-acc, acc), acc, spd)
                }
            }
            runs++
            val k = "${o.alarm?.reason}"
            firsts[k] = (firsts[k] ?: 0) + 1
            if (o.y > 0) lateAfterPass += o.y / v
            if (o.wrong) {
                val cause = if (outliers > 0) "with outliers" else if (forced != null) "sparse, no outlier" else "policy, no outlier"
                byCause[cause] = (byCause[cause] ?: 0) + 1
                out.append("seed=$seed $name v=${"%.1f".format(v)} offset=${offset.toInt()} acc=${acc.toInt()} forced=$forced drop=${"%.2f".format(drop)} ")
                    .append("noDoppler=$noDoppler outliers=$outliers: ${o.alarm?.reason} at y=${o.y.toInt()} d=${o.d.toInt()}\n")
            }
        }
        val l = lateAfterPass.sorted()
        File(outDir, "t122-o2-approach.txt").writeText(
            "runs=$runs firstAlarm=$firsts wrongWording=$byCause\n" +
                "rang after the closest point (s after it): n ${l.size}${if (l.isEmpty()) "" else ", p50 ${l[l.size / 2].toInt()}, p90 ${l[(l.size * 9) / 10].toInt()}, max ${l.last().toInt()}"}\n$out",
        )
        assertTrue(byCause.keys.all { it == "with outliers" }) { "wrong wording without an outlier: $byCause\n$out" }
        assertEquals(PINNED_O2, byCause["with outliers"] ?: 0)
    }

    // ================================================================ O3: covered station before the destination, alternating sources

    @Test
    fun `T122 O3 stopped in a covered station before the destination, coordinates alternating between two sources`() {
        val out = StringBuilder()
        val wrong = ArrayList<String>()
        var runs = 0
        for ((name, config) in modes) for (ds in listOf(600.0, 900.0, 1_200.0, 1_500.0, 2_500.0)) {
            for (delta in listOf(30.0, 300.0, 1_100.0, -1_100.0)) for (acc in listOf(20.0, 80.0)) for (interval in listOf<Long?>(null, 30_000L)) {
                val path = Path(-20_000.0, 0.0)
                val tStop = S + ((20_000.0 - ds) / 12.0 * 1000).toLong()
                path.segs += S to 12.0
                path.segs += tStop to 0.0
                path.segs += (tStop + 900_000L) to 12.0
                var k = 0
                val o = drive(config, path, S + 4 * 3_600_000L, interval) { t, _ ->
                    val y = path.yAt(t)
                    val inStation = t >= tStop && t < tStop + 900_000L
                    val alt = inStation && (k++ % 2 == 1)
                    fixAt(t, if (alt) y + delta else y, 0.0, if (inStation) acc else 8.0, if (inStation) null else 12.0)
                }
                runs++
                val line = "$name ds=${ds.toInt()} delta=${delta.toInt()} acc=${acc.toInt()} interval=${interval?.div(1000) ?: "policy"}: " +
                    "${o.alarm?.reason} at y=${o.y.toInt()} d=${o.d.toInt()}"
                out.append(line).append('\n')
                if (o.wrong) wrong += line
            }
        }
        File(outDir, "t122-o3-station.txt").writeText("runs=$runs wrongWording=${wrong.size}\n${wrong.joinToString("\n")}\n\nall:\n$out")
        assertEquals(PINNED_O3, wrong.size)
    }

    // ================================================================ O4: slow crawl away after the pass, vehicle reversing before it

    @Test
    fun `T122 O4 slow crawl away after an off-route pass and a vehicle reversing before the destination`() {
        val out = StringBuilder()
        var wrongReverse = 0
        var silentCrawl = 0
        for ((name, config) in modes) {
            // (i) off-route destination 600 m from the road, slow pass then crawl away at 0.5–2 m/s for 2 h.
            for (crawl in listOf(0.5, 1.0, 2.0, 2.7)) {
                val path = Path(-3_000.0, 600.0)
                path.segs += S to crawl
                val r = Rng(crawl.toLong() + 7)
                val o = drive(config, path, S + 2 * 3_600_000L, null) { t, _ -> fixAt(t, path.yAt(t) + r.dbl(-8.0, 8.0), 600.0 + r.dbl(-8.0, 8.0), 10.0, crawl) }
                if (o.alarm == null) silentCrawl++
                out.append("crawl $name offset=600 v=$crawl: ${o.alarm?.reason} at y=${o.y.toInt()} d=${o.d.toInt()} (${(o.y + 3_000.0) / crawl / 60} min)\n")
            }
            // (ii) approach to R before the destination, reverse 1.5 km, then forward again to the destination.
            for (rr in listOf(700.0, 900.0, 1_500.0)) for (vRev in listOf(5.0, 12.0)) {
                val path = Path(-15_000.0, 0.0)
                val t1 = S + ((15_000.0 - rr) / 12.0 * 1000).toLong()
                path.segs += S to 12.0
                path.segs += t1 to -vRev
                path.segs += (t1 + (1_500.0 / vRev * 1000).toLong()) to 12.0
                val r = Rng(rr.toLong() + vRev.toLong())
                val o = drive(config, path, S + 3 * 3_600_000L, null) { t, _ -> fixAt(t, path.yAt(t) + r.dbl(-8.0, 8.0), r.dbl(-8.0, 8.0), 10.0, abs(path.vAt(t))) }
                if (o.wrong) wrongReverse++
                out.append("reverse $name R=${rr.toInt()} vRev=$vRev: ${o.alarm?.reason} at y=${o.y.toInt()} d=${o.d.toInt()}${if (o.wrong) "  <- wrong wording" else ""}\n")
            }
        }
        File(outDir, "t122-o4-crawl-reverse.txt").writeText("silentCrawl=$silentCrawl wrongReverse=$wrongReverse\n$out")
        assertEquals(PINNED_O4, "silentCrawl=$silentCrawl wrongReverse=$wrongReverse")
    }

    // ================================================================ U114 (ae), (af): the two minDChord branches (review vòng 7 #1)

    /** GPS LOST since n − [gapS] s, last fix L at [lSouth] m south / [east] m east, DISTANCE [thr], DENSE, established 10 m/s. */
    private fun gapState(thr: Int, lSouth: Double, east: Double, gapS: Int = 1_761): app.napstop.core.trip.EngineState {
        val n = S + 3_600_000L
        val st = app.napstop.core.trip.support.trackingState(
            cfg(AlarmMode.DISTANCE, thr = thr), d = lSouth, ground = 10.0, closing = 10.0,
            gps = app.napstop.core.trip.GpsStatus.LOST, now = n - 1_000, lastFixAt = n - gapS * 1000L,
            tier = app.napstop.core.trip.SamplingTier.DENSE, maxTripS = 14_400, startedAt = n - 3_000_000,
        )
        val p0 = TestGeo.jitter(TestGeo.pointOnMeridian(DEST, lSouth), east, 0.0)
        val l = app.napstop.core.trip.FixRec(n - gapS * 1000L, p0.lat, p0.lng, 8.0, app.napstop.core.trip.distanceM(p0.lat, p0.lng, DEST.lat, DEST.lng), null)
        return st.copy(last = l, recent = listOf(l), dSmooth = l.d, minD = l.d, last3 = listOf(l.d), dStartM = l.d + 20_000.0)
    }

    private fun fixN(s: app.napstop.core.trip.EngineState, at: Long, south: Double, east: Double, spd: Double?): Step =
        TripEngine.reduce(s, fixAt(at, -south, east, 8.0, spd))

    /**
     * U114 (ae): the chord fix sets the flag (minD ≈ 0, 3 100 m beyond); three fixes 600 m beyond the destination are rejected as
     * IMPLAUSIBLE (2.5 km in 5–35 s) and the third REANCHORs: minD = 600, flag false. The vehicle then crawls away at 2 m/s (not
     * "fast") to 1 800 m and stands there 2 min. Flag false → the T12.1 rule: no OVERSHOOT (kills F4 "REANCHOR keeps the flag",
     * under which inStop / lag-2 with minD 600 would ring). Control: without the three jumps the chord flag stays and the same
     * crawl rings OVERSHOOT (U114 u).
     */
    @Test
    fun `U114 ae a REANCHOR below 1 km after a chord fix clears the flag, no OVERSHOOT on a slow crawl away and stop`() {
        val n = S + 3_600_000L
        fun run(jumps: Boolean): Pair<List<Step>, Step?> {
            val out = ArrayList<Step>()
            var s = gapState(200, 11_800.0 + 10.0 * 1_761, 0.0).let { fixN(it, n, -3_100.0, 0.0, 0.0) }
            out += s
            assertTrue(s.state.minDChord && s.state.minD!! <= 1.0, "ae chord fix: flag ${s.state.minDChord} minD ${s.state.minD}")
            var reanchor: Step? = null
            var t = n
            var y = 3_100.0
            if (jumps) {
                for (dt in listOf(5_000L, 20_000L, 35_000L)) {
                    s = fixN(s.state, n + dt, -600.0, 0.0, 2.0)
                    out += s
                }
                reanchor = s
                t = n + 35_000L
                y = 600.0
            }
            // Crawl away north at 2 m/s every 5 s up to 1 800 m beyond, then stand 2 min (Doppler 0).
            while (out.none { st -> st.events.any { it is Alarm } } && t < n + 1_200_000L) {
                t += 5_000L
                val standing = y >= 1_800.0
                if (!standing) y += 10.0
                s = fixN(s.state, t, -y, 0.0, if (standing) 0.0 else 2.0)
                out += s
                if (standing && t > n + 1_200_000L) break
                if (standing && out.count { it.state.stopStartMs != null } > 24) break
            }
            return out to reanchor
        }
        val (steps, re) = run(jumps = true)
        assertTrue(re != null && !re.state.minDChord && kotlin.math.abs(re.state.minD!! - 600.0) <= 1.0, "ae REANCHOR: flag ${re?.state?.minDChord} minD ${re?.state?.minD}")
        assertTrue(steps.flatMap { it.events }.none { it is Alarm && it.reason == AlarmReason.OVERSHOOT }, "ae: OVERSHOOT after a REANCHOR")
        assertTrue(steps.dropWhile { it !== re }.none { it.state.minDChord }, "ae: flag set again after the REANCHOR")
        val (control, _) = run(jumps = false)
        val ca = control.flatMap { it.events }.filterIsInstance<Alarm>().firstOrNull()
        assertEquals(AlarmReason.OVERSHOOT, ca?.reason, "ae control (chord flag kept)")
        File(outDir, "u114-ae.txt").writeText("ae: reanchor minD=${re!!.state.minD} flag=${re.state.minDChord}; first alarm ${steps.flatMap { it.events }.filterIsInstance<Alarm>().firstOrNull()?.reason}; control ${ca?.reason}\n")
    }

    /**
     * U114 (af): observed minD 900 m (no chord, flag false), GPS lost, then the chord L (950 m east, far south) → f (950 m east,
     * 3 000 m north) passes at 950 m > minD: minD stays 900, the flag stays false. The vehicle stands at f (Doppler 0) 2 min.
     * Flag false → no OVERSHOOT (kills F5 "a chord sets the flag even when dChord >= minD": inStop, minD 900 < 1 000, d − minD ≥
     * 1 000 would ring). Control: the same without the observed minD → the chord sets the flag and the stop rings OVERSHOOT.
     */
    @Test
    fun `U114 af a chord farther than the observed minD keeps the flag false, no OVERSHOOT when standing after the gap`() {
        val n = S + 3_600_000L
        fun run(observed: Boolean): List<Step> {
            var st = gapState(200, 29_410.0, 950.0)
            if (observed) st = st.copy(minD = 900.0, minDChord = false)
            val out = ArrayList<Step>()
            var s = fixN(st, n, -3_000.0, 950.0, 0.0)
            out += s
            for (i in 1..24) {
                if (s.events.any { it is Alarm }) break
                s = fixN(s.state, n + 5_000L * i, -3_000.0, 950.0, 0.0)
                out += s
            }
            return out
        }
        val steps = run(observed = true)
        val first = steps.first().state
        assertTrue(!first.minDChord && first.minD == 900.0, "af chord fix: flag ${first.minDChord} minD ${first.minD}")
        assertTrue(steps.all { !it.state.minDChord }, "af: flag set")
        assertTrue(steps.flatMap { it.events }.none { it is Alarm && it.reason == AlarmReason.OVERSHOOT }, "af: OVERSHOOT")
        val control = run(observed = false)
        assertTrue(control.first().state.minDChord && kotlin.math.abs(control.first().state.minD!! - 950.0) <= 2.0, "af control chord ${control.first().state.minD}")
        val ca = control.flatMap { it.events }.filterIsInstance<Alarm>().firstOrNull()
        assertEquals(AlarmReason.OVERSHOOT, ca?.reason, "af control (flag set by the chord)")
        File(outDir, "u114-af.txt").writeText("af: chord fix minD=${first.minD} flag=${first.minDChord}; first alarm ${steps.flatMap { it.events }.filterIsInstance<Alarm>().firstOrNull()?.reason}; control ${ca?.reason}\n")
    }

    private companion object {
        const val PINNED_O1 = 14 // = HEAD (T12.1), run-by-run (T12.2 round 8); vòng 3c/3d had 54 (R2-1), vòng 3e 25
        const val PINNED_O2 = 0
        const val PINNED_O3 = 0
        const val PINNED_O4 = "silentCrawl=8 wrongReverse=18" // = HEAD (crawl: T10.6 known; reverse: PASSED_CLOSEST, RK10)
        const val PINNED_O1C = 43 // T10.5 vòng 3f, RK20 c: measured in T12.2 round 8 (2 304 runs)
        const val PINNED_O1B = 0 // = HEAD (vòng 3c/3d: 44, R2-1)
        const val PINNED_O1_REPRO = "DISTANCE ringNow=true at d=480 m (y=-480)" // = HEAD (vòng 3c/3d: OVERSHOOT at 1 900 m, R2-1)
    }
}
