package app.napstop.core.trip.harness

/** Anchors of README §3.1: static anchors already carry `t` in the fixture; runtime ones are resolved from a run. */
internal object Anchors {
    fun isRuntime(anchor: String): Boolean = anchor.startsWith("event:") || anchor == "relaunch" || anchor == "osFallbackFired"

    /** Tick B = anchor + offsetS, or null when a runtime anchor never happened. */
    fun resolve(a: At, firstEventT: Map<String, Int>, relaunchT: Int?, osFallbackFiredT: Int?, killT: Int?): Int? {
        a.t?.let { return it }
        val anchor = a.anchor ?: return null
        val base = when {
            anchor.startsWith("event:") -> firstEventT[anchor.removePrefix("event:")]
            anchor == "relaunch" -> relaunchT
            anchor == "osFallbackFired" -> osFallbackFiredT
            anchor == "kill" -> killT
            else -> throw ConfigError("static anchor without t: $anchor")
        } ?: return null
        return base + a.offsetS
    }
}
