package app.napstop.core.trip.runtime.sim

/** One GPX sample of a bundled trace (fixtures/traces/README.md §2); [t] = seconds from the first sample. */
data class TraceSample(val t: Int, val lat: Double, val lng: Double, val accM: Float, val spdMps: Float?) {
    override fun toString(): String = "TraceSample(t=$t, accM=$accM, spdMps=$spdMps, position=<redacted>)"
}

/** A parsed trace: [samples] non-empty, t strictly increasing, samples[0].t == 0. */
class SimTrace(val id: String, val samples: List<TraceSample>) {
    init {
        require(samples.isNotEmpty() && samples[0].t == 0) { "samples" }
    }

    override fun toString(): String = "SimTrace(id=$id, samples=${samples.size})"
}

/** The simulation of a trip (T18): bundled trace id and speed factor (1..600, UI 1/10/60). */
data class SimSpec(val traceId: String, val speedFactor: Double)

/** A GPX that breaks README §2; [message] names the rule, never a value. */
class TraceFormatException(message: String) : RuntimeException(message)

/** Trace ids (README §1, T18 D11): never a path. */
object SimTraceIds {
    val PATTERN = Regex("^[a-z0-9]+(_[a-z0-9]+)*$")
    const val MAX_LENGTH = 64

    fun valid(id: String): Boolean = id.length <= MAX_LENGTH && PATTERN.matches(id)
}
