package app.napstop.core.trip.runtime

/**
 * A location source with an optional override: FLP or, on top, a replay source set over adb (debug builds, spec T15
 * §5.14) or the simulated source of a simulated trip (T18 §4; moved from :app).
 * Switching while a request is on moves the request to the new source.
 */
class SwitchableLocationSource(private val platform: LocationSource) : LocationSource {
    private val lock = Any()
    private var override: LocationSource? = null
    private var active: Pair<FlpRequestSpec, FixSink>? = null

    private val current: LocationSource get() = override ?: platform

    fun setOverride(source: LocationSource?) {
        synchronized(lock) {
            val a = active
            if (a != null) current.stop()
            override = source
            if (a != null) current.request(a.first, a.second)
        }
    }

    override fun request(spec: FlpRequestSpec, sink: FixSink) {
        synchronized(lock) {
            current.request(spec, sink)
            active = spec to sink
        }
    }

    override fun stop() {
        synchronized(lock) {
            active = null
            current.stop()
        }
    }

    override suspend fun lastKnown(): RawFix? = if (synchronized(lock) { override } != null) null else platform.lastKnown()
}
