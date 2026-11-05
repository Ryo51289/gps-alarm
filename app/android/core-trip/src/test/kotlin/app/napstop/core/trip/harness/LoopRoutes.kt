package app.napstop.core.trip.harness

import app.napstop.core.trip.K_DEG_TO_RAD
import app.napstop.core.trip.K_EARTH_RADIUS_M
import app.napstop.core.trip.cosDeg
import app.napstop.core.trip.support.SplitMix64
import java.io.File
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * T10.7 round 2 §7 (U128): the loop-route geometry of the tester's `TesterT124Test` RK20e (T12.4 test report #1) as a shared trace
 * builder, built in memory around the TR40 destination (never written to a file, not in P05). Local plane x east / y north in
 * metres, converted with s = K_EARTH_RADIUS_M · K_DEG_TO_RAD and cosDeg(destLat) as `chordClosest`. Vehicle [V] m/s, a sample
 * every 5 s, accuracy 8 m, Doppler [V]; approach from (−3 000, −15 000) north; the gap [GAP] hides the loop north of the
 * destination: (−3 000, 0) → (−3 000, 3 000) → (3 000, 3 000) → (3 000, 0), so the chord passes through it (dChord ≈ 0) while the
 * road stays ≥ 3 km away. Noise: uniform in ±a m per axis from [SplitMix64] (x then y, delivered samples only).
 */
internal object LoopRoutes {
    const val V = 15.0

    /** Last fix (−3 000, 0) at 1 000, first fix (3 000, 0) at 1 800 (12 km at 15 m/s). */
    val GAP = 1_005 to 1_800

    /** Polyline in the local plane (x east, y north, metres). */
    class Route(val pts: List<DoubleArray>) {
        private val cum: DoubleArray = DoubleArray(pts.size).also { c ->
            for (i in 1 until pts.size) c[i] = c[i - 1] + len(pts[i - 1], pts[i])
        }
        val length: Double get() = cum.last()

        fun at(s: Double): DoubleArray {
            if (s <= 0.0) return pts.first()
            for (i in 1 until pts.size) {
                if (s <= cum[i]) {
                    val k = (s - cum[i - 1]) / (cum[i] - cum[i - 1])
                    return doubleArrayOf(pts[i - 1][0] + k * (pts[i][0] - pts[i - 1][0]), pts[i - 1][1] + k * (pts[i][1] - pts[i - 1][1]))
                }
            }
            return pts.last()
        }

        /** Arc length of the first route point closest to the destination (1 m steps). */
        fun closestS(): Double {
            var best = Double.MAX_VALUE
            var bs = 0.0
            var s = 0.0
            while (s <= length) {
                val p = at(s)
                val d = sqrt(p[0] * p[0] + p[1] * p[1])
                if (d < best - 1e-9) {
                    best = d
                    bs = s
                }
                s += 1.0
            }
            return bs
        }

        private companion object {
            fun len(a: DoubleArray, b: DoubleArray): Double {
                val dx = b[0] - a[0]
                val dy = b[1] - a[1]
                return sqrt(dx * dx + dy * dy)
            }
        }
    }

    /** A built trace with its truth: the vehicle is at arc length V·t; [sD] = arc length of the closest point to the destination. */
    class Synth(val id: String, val trace: TraceModel, val route: Route, val sD: Double, val gap: Pair<Int, Int>) {
        val arrivalS: Double get() = sD / V

        /** Truth: the vehicle reached the destination (its closest route point) at tick [t]. */
        fun passed(t: Int): Boolean = V * t >= sD

        fun trueD(t: Int): Double {
            val p = route.at(V * t)
            return sqrt(p[0] * p[0] + p[1] * p[1])
        }
    }

    fun pt(x: Double, y: Double): DoubleArray = doubleArrayOf(x, y)

    /** 90 points from angle [a0] to [a1] (degrees, math convention), radius [r] → [r1]. */
    fun arc(r: Double, a0: Double, a1: Double, r1: Double = r): List<DoubleArray> = (1..90).map { i ->
        val a = (a0 + (a1 - a0) * i / 90) * PI / 180.0
        val ri = r + (r1 - r) * i / 90
        pt(ri * cos(a), ri * sin(a))
    }

    fun approach(): List<DoubleArray> =
        listOf(pt(-3_000.0, -15_000.0), pt(-3_000.0, 0.0), pt(-3_000.0, 3_000.0), pt(3_000.0, 3_000.0), pt(3_000.0, 0.0))

    /** L1: 3 km south (away, d 3 000 → 4 243 m), west, then north to the destination and 3 km on. */
    fun l1() = Route(approach() + listOf(pt(3_000.0, -3_000.0), pt(0.0, -3_000.0), pt(0.0, 0.0), pt(0.0, 3_000.0)))

    /** L2: 300 m south (d +15 m), west 3 km, north 300 m to the destination and 3 km on. */
    fun l2() = Route(approach() + listOf(pt(3_000.0, -300.0), pt(0.0, -300.0), pt(0.0, 0.0), pt(0.0, 3_000.0)))

    /** L3 (control): straight to the destination and 3 km past it. */
    fun l3() = Route(approach() + listOf(pt(0.0, 0.0), pt(-3_000.0, 0.0)))

    /** L4: a quarter circle of radius 3 000 m around the destination, then north to it and 3 km on. */
    fun l4() = Route(approach() + arc(3_000.0, 0.0, -90.0) + listOf(pt(0.0, 0.0), pt(0.0, 3_000.0)))

    /** L5: a spiral (radius 3 000 → 2 000 m over a quarter turn), then north to the destination and 3 km on. */
    fun l5() = Route(approach() + arc(3_000.0, 0.0, -90.0, 2_000.0) + listOf(pt(0.0, 0.0), pt(0.0, 3_000.0)))

    /** Samples every 5 s along [route] around [base]'s destination (same start time), none in [gap]; noise ±[noiseA] m. */
    fun synth(base: TraceModel, id: String, route: Route, noiseA: Double = 0.0, seed: Long = 124L, gap: Pair<Int, Int> = GAP): Synth {
        val s = K_EARTH_RADIUS_M * K_DEG_TO_RAD
        val c = cosDeg(base.destLat)
        val dur = ((route.length / V).toInt() / 5) * 5
        val rnd = SplitMix64(seed)
        val samples = ArrayList<TraceSample>()
        var t = 0
        while (t <= dur) {
            if (t < gap.first || t >= gap.second) {
                val p = route.at(V * t)
                val nx = if (noiseA > 0.0) rnd.dbl(-noiseA, noiseA) else 0.0
                val ny = if (noiseA > 0.0) rnd.dbl(-noiseA, noiseA) else 0.0
                samples += TraceSample(samples.size, t, base.destLat + (p[1] + ny) / s, base.destLng + (p[0] + nx) / (c * s), 8.0, V)
            }
            t += 5
        }
        val sD = route.closestS()
        val tr = TraceModel(
            "u128_$id", "coach", File("u128_$id.gpx"), base.startMs, 5, dur, samples.size, base.destLat, base.destLng, (sD / V).toInt(),
            emptyList(), listOf(gap), gpxOverride = GpxTrace(base.startMs, samples),
        )
        return Synth(id, tr, route, sD, gap)
    }
}
