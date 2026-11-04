package app.napstop.core.alarm

/** Foreground service type of AlarmRingService (spec T16 D2). */
enum class FgsType { SYSTEM_EXEMPTED, MEDIA_PLAYBACK, NONE }

object FgsTypePolicy {
    /**
     * Types to try in order with startForeground: API 34+ `systemExempted` only when the app may schedule exact alarms
     * (else ForegroundServiceTypeNotAllowedException), then `mediaPlayback`; API 29–33 `mediaPlayback`; API 26–28 `0`.
     */
    fun ringTypes(sdk: Int, canScheduleExact: Boolean): List<FgsType> =
        when {
            sdk >= 34 -> if (canScheduleExact) listOf(FgsType.SYSTEM_EXEMPTED, FgsType.MEDIA_PLAYBACK) else listOf(FgsType.MEDIA_PLAYBACK)
            sdk >= 29 -> listOf(FgsType.MEDIA_PLAYBACK)
            else -> listOf(FgsType.NONE)
        }
}
