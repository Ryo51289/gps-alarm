package app.napstop.core.trip

import kotlin.math.floor

/**
 * Deterministic helpers of T10 §4.0 / D1–D7. Library min/max are not used for Double because they
 * differ from Swift on -0.0/NaN; these definitions are shared word for word with T13.
 */
internal object TMath {
    fun min(a: Double, b: Double): Double = if (a <= b) a else b

    fun max(a: Double, b: Double): Double = if (a >= b) a else b

    fun clamp(x: Double, lo: Double, hi: Double): Double = min(max(x, lo), hi)

    fun min(a: Int, b: Int): Int = if (a <= b) a else b

    fun max(a: Int, b: Int): Int = if (a >= b) a else b

    fun clamp(x: Int, lo: Int, hi: Int): Int = min(max(x, lo), hi)

    fun min(a: Long, b: Long): Long = if (a <= b) a else b

    fun max(a: Long, b: Long): Long = if (a >= b) a else b

    fun clamp(x: Long, lo: Long, hi: Long): Long = min(max(x, lo), hi)

    /** Minimum of the non-null values, scanned left to right; all null → null. */
    fun minOrNull(vararg xs: Long?): Long? {
        var best: Long? = null
        for (x in xs) {
            if (x == null) continue
            best = if (best == null) x else min(best, x)
        }
        return best
    }

    /** Drop nulls, sort ascending, take index floor(n / 2): n = 2 gives the larger value. */
    fun medianHi(xs: List<Double?>): Double? {
        val v = ArrayList<Double>(xs.size)
        for (x in xs) if (x != null) v.add(x)
        if (v.isEmpty()) return null
        // Insertion sort with `<` only (n <= 3); stable and identical on every platform.
        for (i in 1 until v.size) {
            val cur = v[i]
            var j = i - 1
            while (j >= 0 && cur < v[j]) {
                v[j + 1] = v[j]
                j--
            }
            v[j + 1] = cur
        }
        return v[v.size / 2]
    }

    /** Seconds (>= 0) to milliseconds. */
    fun floorMs(s: Double): Long = floor(s * 1000.0).toLong()

    /** Milliseconds to seconds. */
    fun toS(ms: Long): Double = ms / 1000.0

    /** Only for x >= 0. */
    fun roundHalfUp(x: Double): Int = floor(x + 0.5).toInt()

    fun blend(ema: Double?, x: Double, dt: Double, tauS: Int): Double =
        if (ema == null) x else ema + (x - ema) * dt / (tauS.toDouble() + dt)

    fun maxTier(a: SamplingTier, b: SamplingTier): SamplingTier = if (a.ordinal >= b.ordinal) a else b
}
