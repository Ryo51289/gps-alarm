package app.napstop.probe

/**
 * Alarm routing (docs/spikes/S2.md "Vòng 4" V4-1). Pure (JVM unit-tested, U39): no Android types.
 */
object AlarmRoute {
    enum class Fallback { NONE, PROBE_SERVICE, RING_SERVICE }

    const val TYPE_SYSTEM_EXEMPTED = "systemExempted"
    const val TYPE_MEDIA_PLAYBACK = "mediaPlayback"
    const val TYPE_NONE = "none"

    /** ALARM_FALLBACK received. */
    fun forFallback(alarmFired: Boolean, probeAlive: Boolean): Fallback = when {
        alarmFired -> Fallback.NONE
        probeAlive -> Fallback.PROBE_SERVICE // ProbeService.triggerFallback(), as before
        else -> Fallback.RING_SERVICE // startForegroundService(AlarmRingService, ACTION_RING)
    }

    /**
     * FGS types for AlarmRingService, in the order to try. Names only (JVM-testable); the service maps them to
     * ServiceInfo constants. systemExempted exists from API 34, FGS types from API 29.
     */
    fun ringFgsTypes(sdk: Int): List<String> = when {
        sdk >= 34 -> listOf(TYPE_SYSTEM_EXEMPTED, TYPE_MEDIA_PLAYBACK)
        sdk >= 29 -> listOf(TYPE_MEDIA_PLAYBACK)
        else -> listOf(TYPE_NONE)
    }
}
