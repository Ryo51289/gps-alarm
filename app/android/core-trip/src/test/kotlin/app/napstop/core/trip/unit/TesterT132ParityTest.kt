package app.napstop.core.trip.unit

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmMode
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.AlarmSilenced
import app.napstop.core.trip.AvailabilityCause
import app.napstop.core.trip.BatterySample
import app.napstop.core.trip.EngineInput
import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.EngineState
import app.napstop.core.trip.FallbackAlarmChanged
import app.napstop.core.trip.FallbackFired
import app.napstop.core.trip.FallbackRestoreStatus
import app.napstop.core.trip.FallbackScheduled
import app.napstop.core.trip.FallbackState
import app.napstop.core.trip.FallbackStatus
import app.napstop.core.trip.FixRec
import app.napstop.core.trip.GpsLost
import app.napstop.core.trip.GpsStatus
import app.napstop.core.trip.K_METRES_PER_DEG_LAT
import app.napstop.core.trip.LocationAvailability
import app.napstop.core.trip.LocationFix
import app.napstop.core.trip.Overshoot
import app.napstop.core.trip.RestoreInfo
import app.napstop.core.trip.SamplingTier
import app.napstop.core.trip.SnapshotFormatException
import app.napstop.core.trip.Step
import app.napstop.core.trip.Tick
import app.napstop.core.trip.TripConfig
import app.napstop.core.trip.TripEngine

import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.UserAction
import app.napstop.core.trip.UserActionKind
import app.napstop.core.trip.VehicleKind
import app.napstop.core.trip.chordClosest
import app.napstop.core.trip.chordProjection
import app.napstop.core.trip.cosDeg
import app.napstop.core.trip.distanceM
import app.napstop.core.trip.support.DEST
import app.napstop.core.trip.support.LatLng
import app.napstop.core.trip.support.S
import app.napstop.core.trip.support.TestGeo
import app.napstop.core.trip.support.cfg
import app.napstop.core.trip.support.trackingState
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Tag
import org.junit.jupiter.api.Test
import java.io.File
import kotlin.math.sqrt

/**
 * Tester T13.2 (docs/test-reports/T13.2.md): Kotlin ↔ Swift parity checks added in BOTH engines with identical inputs
 * (mirror: app/ios/Core/Tests/TripTests/Unit/TesterT132ParityTests.swift). Every test writes `t132p-*.txt`; the Swift files must be
 * byte-identical.
 *  - Review T13.2 minor #1: chordProjection bits pinned (U113 cases + chords with Δlng ≠ 0 and destLat ≠ 0).
 *  - Review T13.2 minor #2: the round-3d guard of `notCloser` kept alive after round 3e (chord minD, vehicle still approaching,
 *    one accepted outlier).
 *  - Snapshot `minDChord`: round trip, missing / null / string / number / duplicate key, restore paths.
 *  - Parity fuzz: random trips with chords at destLat ≠ 0, outliers, stale/inaccurate fixes, wake-up Ticks, fallback, restores;
 *    per-Step transcript with a hash of the snapshot (Doubles canonicalised by bit pattern).
 */
class TesterT132ParityTest {
    private val outDir = File(System.getProperty("napstop.outDir") ?: "build/napstop").also { it.mkdirs() }
    private val n = S + 3_600_000L

    private fun bits(x: Double?): String = x?.let { java.lang.Long.toHexString(java.lang.Double.doubleToRawLongBits(it)).padStart(16, '0') } ?: "null"

    private fun pt(south: Double, east: Double = 0.0): LatLng {
        val p0 = TestGeo.pointOnMeridian(DEST, south)
        return if (east == 0.0) p0 else TestGeo.jitter(p0, east, 0.0)
    }

    private fun rec(p: LatLng, at: Long = n): FixRec = FixRec(at, p.lat, p.lng, 8.0, distanceM(p.lat, p.lng, DEST.lat, DEST.lng), null)

    private fun raw(lat: Double, lng: Double): FixRec = FixRec(n, lat, lng, 8.0, 1.0, null)

    private fun dest(lat: Double, lng: Double): TripConfig = TripConfig("trip-1", lat, lng, AlarmMode.DISTANCE, 1000, null, true, VehicleKind.TRAIN)

    // ================================================================ (1) chordProjection bits (review minor #1)

    @Test
    fun `T132P chord bits pinned for the U113 cases and chords with dLng != 0 and destLat != 0`() {
        val east = 1_500.0 / K_METRES_PER_DEG_LAT
        val c0 = cfg()
        val cases = listOf(
            Triple("a", c0, rec(pt(29_410.0)) to rec(pt(-3_100.0))),
            Triple("b", c0, rec(pt(5_000.0)) to rec(pt(1_000.0))),
            Triple("c", c0, rec(pt(3_000.0)) to rec(pt(3_000.0))),
            Triple("d", c0, rec(pt(5_000.0, 1_500.0)) to rec(pt(-5_000.0, 1_500.0))),
            Triple("e", c0, rec(pt(5_000.0, 200.0)) to rec(pt(-5_000.0))),
            Triple("f", c0, rec(pt(5_000.0)) to FixRec(n, 0.01, DEST.lng + 181.0, 8.0, 1.0, null)),
            Triple("g", c0, FixRec(n, -0.045, DEST.lng + east, 8.0, 1.0, null) to FixRec(n, 0.0, DEST.lng + east, 8.0, 1.0, null)),
            Triple("h", c0, FixRec(n, -0.045, DEST.lng + east, 8.0, 1.0, null) to FixRec(n, 1e-9, DEST.lng + east, 8.0, 1.0, null)),
            // New: destLat != 0 (cosDeg != 1) and dLng != 0 at both ends, so (dLng * c) * m != dLng * (c * m) can show.
            Triple("i", dest(21.0, 105.8), raw(20.90, 105.70) to raw(21.02, 105.86)),
            Triple("j", dest(21.0, 105.8), raw(21.30, 105.95) to raw(20.80, 105.62)),
            Triple("k", dest(-33.9, 151.2), raw(-34.05, 151.05) to raw(-33.80, 151.33)),
            Triple("l", dest(59.9, 10.75), raw(59.70, 10.40) to raw(60.05, 11.10)),
            Triple("m", dest(21.0, 105.8), raw(21.0005, 105.7990) to raw(20.9993, 105.8012)),
            Triple("n", dest(-45.25, -170.5), raw(-45.40, -170.20) to raw(-45.05, -170.95)),
        )
        val text = cases.joinToString("") { (k, c, lf) ->
            val p = chordProjection(lf.first.lat, lf.first.lng, lf.second.lat, lf.second.lng, c)
            "$k u=${bits(p?.u)} dist=${bits(p?.distM)} closest=${bits(chordClosest(lf.first, lf.second, c))}\n"
        }
        File(outDir, "t132p-chord.txt").writeText(text)
        assertEquals(PINNED_CHORD, text)
    }

    // ================================================================ (2) round-3d guard after round 3e (review minor #2)

    /** U114 (i) builder: fix before the gap 20 km south, 700 s gap, GPS LOST. */
    private fun bypassState(): EngineState {
        val lp = pt(20_000.0)
        val ld = distanceM(lp.lat, lp.lng, DEST.lat, DEST.lng)
        val base = trackingState(
            cfg(AlarmMode.DISTANCE, thr = 1000), d = ld, ground = 10.0, closing = 10.0, gps = GpsStatus.LOST, now = n - 1_000,
            lastFixAt = n - 700_000, tier = SamplingTier.DENSE, maxTripS = 14_400, startedAt = n - 3_000_000,
            fallback = FallbackState(n + 400_000, n - 600_000, FallbackStatus.CONFIRMED, n - 599_000, false, false),
        )
        val l = FixRec(n - 700_000, lp.lat, lp.lng, 8.0, ld, null)
        return base.copy(last = l, recent = listOf(l), dSmooth = ld, minD = ld, last3 = listOf(ld), dStartM = ld + 20_000.0)
    }

    private fun names(s: Step): String = s.events.joinToString(",", "[", "]") { e ->
        val nm = e.javaClass.simpleName.replaceFirstChar { it.lowercaseChar() }
        when (e) {
            is Alarm -> "$nm:${e.reason}:${e.ringNow}"
            is Overshoot -> "$nm:${e.pastM}"
            is GpsLost -> "$nm:${e.cause}"
            is FallbackAlarmChanged -> "$nm:${e.fallbackAtMs?.let { it - S }}:${e.cause}"
            else -> nm
        }
    }

    /**
     * After the chord fix (2 km north / 0.5 km east, chord 454 m from the destination, minDChord = true) the vehicle keeps approaching
     * at 5 m/s, one fix every 30 s (> smoothWindowS, so dSmooth = the fix). Fix 1 is an accepted outlier [outlierM] closer. At fix 3
     * last3 = [outlier, r2, r3] with r3 >= outlier: lag-2 holds, no stop, dSmooth − minD >= 1 000, minD < 1 000; only the round-3d
     * guard (min(last3) − minD >= overshootOpenM) decides.
     */
    private fun guardRun(outlierM: Double, tag: String, log: StringBuilder): List<Step> {
        val d0 = sqrt(2_000.0 * 2_000.0 + 500.0 * 500.0)
        var s = bypassState()
        val out = ArrayList<Step>()
        for (i in 0 until 20) {
            val r = d0 - 150.0 * i - (if (i == 1) outlierM else 0.0)
            val k = r / d0
            val p = pt(-2_000.0 * k, 500.0 * k)
            val at = n + 30_000L * i
            val step = TripEngine.reduce(s, LocationFix(at, at, p.lat, p.lng, 8.0, 5.0))
            out += step
            s = step.state
            log.append(
                "$tag $i t=${(at - n) / 1000} d=${s.dSmooth} minD=${s.minD} chord=${s.minDChord} last3=${s.last3} " +
                    "stop=${s.stopStartMs != null} ev=${names(step)}\n",
            )
            if (step.events.any { it is Alarm }) break
        }
        return out
    }

    @Test
    fun `T132P round-3d guard still blocks a wrong-wording OVERSHOOT after a chord when one accepted outlier fakes lag-2`() {
        val log = StringBuilder()
        val g = guardRun(600.0, "guard600", log)
        assertTrue(g[0].state.minDChord && g[0].state.minD!! > 400.0 && g[0].state.minD!! < 500.0, "chord fix: ${g[0].state.minD}")
        val s3 = g[3].state
        val l3 = s3.last3
        val minD = s3.minD!!
        // Every other condition of the standing term holds at fix 3: only the guard blocks.
        assertTrue(s3.minDChord && s3.stopStartMs == null && l3.size == 3 && l3[2] >= l3[0], "fix 3 state $l3")
        assertTrue(s3.dSmooth!! - minD >= 1_000.0 && minD < 1_000.0, "fix 3 open ${s3.dSmooth} minD $minD")
        assertTrue(l3.minOrNull()!! - minD < 1_000.0, "fix 3 guard ${l3.minOrNull()!! - minD}")
        assertTrue(g.none { st -> st.events.any { it is Overshoot } }, "no Overshoot")
        val a = g.last().events.filterIsInstance<Alarm>().single()
        assertEquals(AlarmReason.DISTANCE, a.reason)
        assertTrue(a.ringNow && g.last().state.dSmooth!! <= 1_000.0)
        // Control (measured, pinned): an outlier only 400 m closer passes the guard (min(last3) − minD = 1 058 m) → the standing
        // term rings a wrong-wording OVERSHOOT at fix 3 while the vehicle approaches: RK20 (a) family (chord through a bypass).
        val c = guardRun(400.0, "control400", log)
        File(outDir, "t132p-guard3d.txt").writeText(log.toString())
        val ca = c.last().events.filterIsInstance<Alarm>().single()
        assertEquals(AlarmReason.OVERSHOOT, ca.reason)
        assertEquals(n + 90_000, c.last().state.nowMs)
    }

    // ================================================================ (3) snapshot minDChord: adversarial decode, restore paths

    private fun reproState(): EngineState = trackingState(
        cfg(AlarmMode.DISTANCE, thr = 1000), d = 11_800.0 + 10.0 * 1_761, ground = 10.0, closing = 10.0, gps = GpsStatus.LOST,
        now = n - 1_000, lastFixAt = n - 1_761_000L, tier = SamplingTier.DENSE, maxTripS = 14_400, startedAt = n - 3_000_000,
        fallback = FallbackState(n + 29_000, n - 600_000, FallbackStatus.CONFIRMED, n - 599_000, false, true),
    )

    private fun fixAt(st: EngineState, south: Double, at: Long, spd: Double?): Step {
        val p = pt(south)
        return TripEngine.reduce(st, LocationFix(at, at, p.lat, p.lng, 8.0, spd))
    }

    @Test
    fun `T132P snapshot minDChord adversarial decode and restore paths`() {
        val out = StringBuilder()
        val chordStep = fixAt(reproState(), -3_100.0, n, 0.0) // passed in the gap, standing 3 100 m beyond
        val st = chordStep.state
        assertTrue(st.minDChord, "chord flag")
        val enc = TripEngine.encodeSnapshot(st)
        out.append("enc ").append(enc).append('\n')
        assertTrue(enc.contains("\"minD\":") && enc.indexOf("\"minDChord\":true") > enc.indexOf("\"minD\":"))
        val key = "\"minDChord\":true"
        val variants = listOf(
            "orig" to enc,
            "missing" to enc.replace("$key,", ""),
            "false" to enc.replace(key, "\"minDChord\":false"),
            "null" to enc.replace(key, "\"minDChord\":null"),
            "string" to enc.replace(key, "\"minDChord\":\"true\""),
            "number" to enc.replace(key, "\"minDChord\":1"),
            "upper" to enc.replace(key, "\"minDChord\":TRUE"),
            "spaces" to enc.replace(key, "\"minDChord\" : true"),
            "moved" to enc.replace("$key,", "").removeSuffix("}") + ",\"minDChord\":true}",
            "dupFalseAfter" to enc.replace(key, "$key,\"minDChord\":false"),
            "dupTrueAfter" to enc.replace(key, "\"minDChord\":false,$key"),
            "array" to enc.replace(key, "\"minDChord\":[true]"),
        )
        val decoded = HashMap<String, EngineState>()
        for ((name, json) in variants) {
            try {
                val d = TripEngine.decodeSnapshot(json)
                decoded[name] = d
                out.append("$name ok flag=${d.minDChord} sameState=${d == st} reEnc=${TripEngine.encodeSnapshot(d) == enc}\n")
            } catch (e: SnapshotFormatException) {
                out.append("$name error ${e.message}\n")
            }
        }
        // Restore paths: snapshot with / without the key, every status, then standing fixes every 5 s.
        val target = st.fallback.targetAtMs
        val infos = listOf(
            "PENDING" to RestoreInfo(FallbackRestoreStatus.PENDING),
            "MISSING" to RestoreInfo(FallbackRestoreStatus.MISSING),
            "UNKNOWN" to RestoreInfo(FallbackRestoreStatus.UNKNOWN),
            "RANG" to RestoreInfo(FallbackRestoreStatus.RANG, target ?: n),
            "DISMISSED" to RestoreInfo(FallbackRestoreStatus.DISMISSED, target ?: n, n + 2_000),
        )
        for (src in listOf("orig", "missing")) {
            val base = decoded.getValue(src)
            for ((iname, info) in infos) {
                val r = TripEngine.restore(base, n + 2_000, info)
                var s = r.state
                val line = StringBuilder("restore $src $iname ev=${names(r)} ph=${r.view.phase} flag=${s.minDChord}")
                var first: String? = if (r.events.any { it is Alarm }) "restore" else null
                var i = 1
                while (first == null && i <= 40 && s.phase != TripPhase.ENDED) {
                    val step = fixAt(s, -3_100.0, n + 5_000L * i, 0.0)
                    s = step.state
                    if (step.events.any { it is Alarm }) first = "fix$i ${names(step)}"
                    i++
                }
                out.append(line).append(" first=").append(first).append('\n')
            }
        }
        File(outDir, "t132p-snapshot.txt").writeText(out.toString())
        assertEquals(true, decoded.getValue("orig").minDChord)
        assertEquals(false, decoded.getValue("missing").minDChord)
        assertTrue("null" !in decoded && "string" !in decoded && "number" !in decoded && "array" !in decoded)
    }

    // ================================================================ (4) parity fuzz

    private class Rng(seed: Long) {
        private var x = seed * -0x61c8864680b583ebL + 0x2468ACEL

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

    /** Straight route at offset [off] from the destination, along-track position from a piecewise speed profile with stops. */
    private class Route(r: Rng) {
        val d0 = r.dbl(3_000.0, 80_000.0)
        val off = if (r.chance(0.5)) r.dbl(0.0, 300.0) else r.dbl(300.0, 5_000.0)
        val dx0 = r.dbl(-1.0, 1.0)
        val dy0 = r.dbl(-1.0, 1.0)
        val base = r.dbl(3.0, 35.0)
        val segs = ArrayList<Pair<Double, Double>>()

        init {
            var t = 0.0
            while (t < 30_000.0) {
                val moveS = r.dbl(120.0, 2_400.0)
                segs += t to base * r.dbl(0.6, 1.4)
                t += moveS
                if (r.chance(0.3)) {
                    segs += t to 0.0
                    t += r.dbl(20.0, 900.0)
                }
            }
        }

        val norm = sqrt(dx0 * dx0 + dy0 * dy0)
        val dx = if (norm < 1e-6) 1.0 else dx0 / norm
        val dy = if (norm < 1e-6) 0.0 else dy0 / norm

        fun along(tS: Double): Double {
            var s = -d0
            for (i in segs.indices) {
                val (s0, v) = segs[i]
                if (s0 >= tS) break
                val s1 = if (i + 1 < segs.size) minOf(segs[i + 1].first, tS) else tS
                s += v * (s1 - s0)
            }
            return s
        }

        fun speedAt(tS: Double): Double = segs.last { it.first <= tS }.second
    }

    /** Snapshot with every Double token replaced by its bit pattern (Kotlin and Swift print Doubles differently). */
    private fun canon(json: String): String {
        val sb = StringBuilder(json.length)
        var i = 0
        var inStr = false
        while (i < json.length) {
            val ch = json[i]
            if (inStr) {
                sb.append(ch)
                if (ch == '"') inStr = false
                i++
            } else if (ch == '"') {
                inStr = true
                sb.append(ch)
                i++
            } else if (ch == '-' || ch in '0'..'9') {
                var j = i + 1
                while (j < json.length && (json[j] in '0'..'9' || json[j] == '.' || json[j] == 'e' || json[j] == 'E' || json[j] == '+' || json[j] == '-')) j++
                val tok = json.substring(i, j)
                if (tok.any { it == '.' || it == 'e' || it == 'E' }) sb.append("d").append(bits(tok.toDouble())) else sb.append(tok)
                i = j
            } else {
                sb.append(ch)
                i++
            }
        }
        return sb.toString()
    }

    private fun fnv(s: String): String {
        var h = -0x340d631b7bdddcdbL // 0xcbf29ce484222325
        for (ch in s) {
            h = h xor (ch.code.toLong() and 0xff)
            h *= 0x100000001b3L
        }
        return java.lang.Long.toHexString(h).padStart(16, '0')
    }

    private fun fuzzTrip(seed: Long, out: StringBuilder) {
        val r = Rng(seed)
        val mode = AlarmMode.entries[r.int(3)]
        val thr = if (mode == AlarmMode.DISTANCE || r.chance(0.3)) 200 + r.int(9801) else null
        val thrMin = if (mode == AlarmMode.TIME || (mode != AlarmMode.DISTANCE && r.chance(0.3))) 5 + r.int(56) else null
        val preAlert = r.chance(0.7)
        val hint = VehicleKind.entries[r.int(4)]
        val destLat = if (r.chance(0.4)) 0.0 else r.dbl(-60.0, 60.0)
        val destLng = r.dbl(-170.0, 170.0)
        val config = TripConfig("px-$seed", destLat, destLng, mode, thr, thrMin, preAlert, hint)
        val route = Route(r)
        // GPS gap: none, anywhere, or around the pass of the destination (chord through / near it).
        val gapA = when (r.int(3)) {
            0 -> Double.MAX_VALUE
            1 -> r.dbl(0.0, 1.3) * route.d0 / route.base
            else -> route.d0 / route.base - r.dbl(60.0, 900.0)
        }
        val gapB = gapA + r.dbl(60.0, 3_000.0)
        var level = 20 + r.int(81)
        val steps = 150 + r.int(350)
        val k = K_METRES_PER_DEG_LAT
        val cd = cosDeg(destLat)
        var step = TripEngine.start(config, EngineParams(), S)
        var t = S
        var lastFb: Long? = step.state.fallback.targetAtMs
        out.append("trip $seed $mode $thr/$thrMin $preAlert $hint dest=${bits(destLat)},${bits(destLng)} steps=$steps\n")
        fun emit(i: Int, code: String, s: Step) {
            val v = s.view
            out.append(
                "$i $code ${t - S} ev=${names(s)} ph=${v.phase} w=${v.wakeAtMs?.let { it - S }} p=${v.predictedAlarmAtMs?.let { it - S }} " +
                    "f=${v.fallbackAtMs?.let { it - S }} h=${fnv(canon(TripEngine.encodeSnapshot(s.state)))}\n",
            )
        }
        emit(0, "start", step)
        for (i in 1..steps) {
            if (step.state.phase == TripPhase.ENDED) break
            val s0 = step.state
            val interval = (step.view.samplingPolicy?.intervalS ?: 5) * 1000L
            val kk = r.int(100)
            var input: EngineInput? = null
            var restore: RestoreInfo? = null
            val code: String
            when {
                kk < 55 -> {
                    t += maxOf(1L, (interval * r.dbl(0.5, 1.5)).toLong())
                    val ts = (t - S) / 1000.0
                    if (ts >= gapA && ts < gapB && !r.chance(0.05)) {
                        input = Tick(t)
                        code = "G"
                    } else {
                        val sa = route.along(ts)
                        var x = sa * route.dx - route.off * route.dy
                        var y = sa * route.dy + route.off * route.dx
                        if (r.chance(0.04)) {
                            x += r.dbl(-3_000.0, 3_000.0)
                            y += r.dbl(-3_000.0, 3_000.0)
                        }
                        val acc = if (r.chance(0.08)) r.dbl(60.0, 2_000.0) else r.dbl(3.0, 30.0)
                        val age = if (r.chance(0.05)) r.int(200_000).toLong() else r.int(1_500).toLong()
                        val spd = if (r.chance(0.3)) null else route.speedAt(ts) * r.dbl(0.9, 1.1)
                        input = LocationFix(t, t - age, destLat + y / k, destLng + x / (k * cd), acc, spd)
                        code = "F"
                    }
                }
                kk < 70 -> {
                    val w = step.view.wakeAtMs
                    t = if (w != null && w > t) w else t + 1 + r.int(60_000)
                    input = Tick(t)
                    code = "T"
                }
                kk < 73 -> {
                    input = Tick(t - r.int(20_000))
                    code = "t"
                }
                kk < 77 -> {
                    t += r.int(5_000)
                    level = maxOf(1, level - r.int(3))
                    input = BatterySample(t, level, r.chance(0.15))
                    code = "B"
                }
                kk < 83 -> {
                    val lf = lastFb
                    val at = if (lf != null && r.chance(0.8)) lf else t + r.int(3_600_000)
                    input = FallbackScheduled(t, at, r.chance(0.85))
                    code = "S"
                }
                kk < 86 -> {
                    // The OS alarm fires at its own time (due within 60 s, or the app sleeps until then), otherwise a plain Tick.
                    val fb = s0.fallback.targetAtMs
                    if (fb != null && (fb <= t + 60_000 || r.chance(0.15))) {
                        t = maxOf(t, fb)
                        input = FallbackFired(t, fb)
                        code = "X"
                    } else {
                        t += r.int(10_000)
                        input = Tick(t)
                        code = "x"
                    }
                }
                kk < 88 -> {
                    input = AlarmSilenced(t, t)
                    code = "Q"
                }
                kk < 92 -> {
                    val a = when (r.int(6)) {
                        0 -> UserActionKind.DISMISS
                        1 -> UserActionKind.SNOOZE
                        2 -> UserActionKind.STOP_TRIP
                        3 -> UserActionKind.BATTERY_MAX_SAVING
                        4 -> UserActionKind.BATTERY_ALARM_AT_5
                        else -> UserActionKind.BATTERY_ALARM_EARLIER
                    }
                    input = if ((a == UserActionKind.DISMISS || a == UserActionKind.STOP_TRIP) && !r.chance(0.2)) Tick(t) else UserAction(t, a)
                    code = "U"
                }
                kk < 95 -> {
                    input = LocationAvailability(
                        t,
                        when (r.int(3)) {
                            0 -> AvailabilityCause.AVAILABLE
                            1 -> AvailabilityCause.PERMISSION_REVOKED
                            else -> AvailabilityCause.SERVICES_OFF
                        },
                    )
                    code = "A"
                }
                else -> {
                    t += r.int(600_000)
                    restore = when (r.int(5)) {
                        0 -> RestoreInfo(FallbackRestoreStatus.RANG, t - r.int(60_000))
                        1 -> RestoreInfo(FallbackRestoreStatus.DISMISSED, t - r.int(60_000), t)
                        2 -> RestoreInfo(FallbackRestoreStatus.PENDING)
                        3 -> RestoreInfo(FallbackRestoreStatus.MISSING)
                        else -> RestoreInfo(FallbackRestoreStatus.UNKNOWN)
                    }
                    code = "R"
                }
            }
            step = if (restore != null) {
                TripEngine.restore(TripEngine.decodeSnapshot(TripEngine.encodeSnapshot(s0)), t, restore)
            } else {
                TripEngine.reduce(s0, input!!)
            }
            emit(i, code, step)
            lastFb = step.state.fallback.targetAtMs ?: lastFb
        }
        out.append("end ${step.view.phase} ${step.view.outcome} alarm=${step.state.alarm.reason}\n")
    }

    @Tag("slow")
    @Test
    fun `T132P parity fuzz 2000 random trips (chords at destLat != 0, outliers, wake-ups, restores) per-Step transcript`() {
        val out = StringBuilder()
        for (seed in 9_001L..11_000L) fuzzTrip(seed, out)
        File(outDir, "t132p-fuzz.txt").writeText(out.toString())
        val lines = out.count { it == '\n' }
        assertTrue(lines > 50_000, "fuzz too small: $lines")
    }

    private companion object {
        /** Kotlin bits (JDK 17, T12.2 engine `bb8248d`); the Swift mirror pins the same string. */
        val PINNED_CHORD = listOf(
            "a u=3fecf2d97e62bf09 dist=0000000000000000 closest=0000000000000000\n",
            "b u=3ff4000000000000 dist=0000000000000000 closest=null\n",
            "c u=null dist=null closest=null\n",
            "d u=3fe0000000000000 dist=409770007918305b closest=409770007918305b\n",
            "e u=3fe001a34350e41a dist=4058feb8ec2ab14e closest=4058feb8ec2ab14e\n",
            "f u=null dist=null closest=null\n",
            "g u=3ff0000000000000 dist=40976ffffffff428 closest=null\n",
            "h u=3feffffff411cd14 dist=40976ffffffff428 closest=40976ffffffff428\n",
            "i u=3fe69d6c196f69fa dist=40a0ee53f81b2d8b closest=40a0ee53f81b2d8b\n",
            "j u=3fe1eb4d8fbfc400 dist=40b09237d523077a closest=40b09237d523077a\n",
            "k u=3fe23f11e7be4d3f dist=409302f7bb7c3470 closest=409302f7bb7c3470\n",
            "l u=3fe123b05308a4a3 dist=409ec287f5a0d2a0 closest=409ec287f5a0d2a0\n",
            "m u=3fdc7955ee25ea19 dist=401174ca7dfaa036 closest=401174ca7dfaa036\n",
            "n u=3fda287f442db822 dist=408cf693820526de closest=408cf693820526de\n",
        ).joinToString("")
    }
}
