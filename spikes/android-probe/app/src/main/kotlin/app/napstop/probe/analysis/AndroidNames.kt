package app.napstop.probe.analysis

/**
 * Names for Android int constants that end up in the log. Literal values (not the SDK constants) so this stays
 * pure Kotlin; AndroidNamesTest checks them against the android.jar constants.
 */
object AndroidNames {

    /** android.app.ApplicationExitInfo.REASON_* */
    fun exitReason(reason: Int): String = when (reason) {
        0 -> "REASON_UNKNOWN"
        1 -> "REASON_EXIT_SELF"
        2 -> "REASON_SIGNALED"
        3 -> "REASON_LOW_MEMORY"
        4 -> "REASON_CRASH"
        5 -> "REASON_CRASH_NATIVE"
        6 -> "REASON_ANR"
        7 -> "REASON_INITIALIZATION_FAILURE"
        8 -> "REASON_PERMISSION_CHANGE"
        9 -> "REASON_EXCESSIVE_RESOURCE_USAGE"
        10 -> "REASON_USER_REQUESTED"
        11 -> "REASON_USER_STOPPED"
        12 -> "REASON_DEPENDENCY_DIED"
        13 -> "REASON_OTHER"
        14 -> "REASON_FREEZER"
        15 -> "REASON_PACKAGE_STATE_CHANGE"
        16 -> "REASON_PACKAGE_UPDATED"
        else -> "REASON_$reason"
    }

    /** android.app.usage.UsageStatsManager.STANDBY_BUCKET_* (public ones). */
    fun standbyBucket(bucket: Int): String = when (bucket) {
        10 -> "ACTIVE"
        20 -> "WORKING_SET"
        30 -> "FREQUENT"
        40 -> "RARE"
        45 -> "RESTRICTED"
        else -> "BUCKET_$bucket"
    }

    /** android.app.NotificationManager.INTERRUPTION_FILTER_* */
    fun interruptionFilter(filter: Int): String = when (filter) {
        0 -> "UNKNOWN"
        1 -> "ALL"
        2 -> "PRIORITY"
        3 -> "NONE"
        4 -> "ALARMS"
        else -> "FILTER_$filter"
    }

    /** android.media.AudioManager.RINGER_MODE_* */
    fun ringerMode(mode: Int): String = when (mode) {
        0 -> "SILENT"
        1 -> "VIBRATE"
        2 -> "NORMAL"
        else -> "RINGER_$mode"
    }
}
