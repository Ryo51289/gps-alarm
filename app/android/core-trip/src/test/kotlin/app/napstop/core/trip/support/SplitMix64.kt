package app.napstop.core.trip.support

/**
 * splitmix64, deterministic (the generator of T105GapTest U114 t). T10.7 round 2 (U127 m, U128): uniform position noise that
 * Swift reproduces bit for bit (no `nextGaussian`).
 */
internal class SplitMix64(seed: Long) {
    private var x = seed

    fun next(): Long {
        x += -0x61c8864680b583ebL
        var z = x
        z = (z xor (z ushr 30)) * -0x40a7b892e31b1a47L
        z = (z xor (z ushr 27)) * -0x6b2fb644ecceee15L
        return z xor (z ushr 31)
    }

    /** Uniform in [lo, hi): 53 high bits / 2^53. */
    fun dbl(lo: Double, hi: Double): Double = lo + (hi - lo) * ((next() ushr 11).toDouble() / (1L shl 53).toDouble())
}
