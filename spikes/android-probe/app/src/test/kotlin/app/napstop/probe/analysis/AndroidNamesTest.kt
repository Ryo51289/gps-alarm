package app.napstop.probe.analysis

import android.app.ApplicationExitInfo
import android.app.NotificationManager
import android.app.usage.UsageStatsManager
import android.media.AudioManager
import org.junit.Assert.assertEquals
import org.junit.Test

/** The literal values in AndroidNames must match the SDK constants (inlined from android.jar at compile time). */
class AndroidNamesTest {

    @Test
    fun `exit reasons`() {
        val expected = mapOf(
            ApplicationExitInfo.REASON_UNKNOWN to "REASON_UNKNOWN",
            ApplicationExitInfo.REASON_EXIT_SELF to "REASON_EXIT_SELF",
            ApplicationExitInfo.REASON_SIGNALED to "REASON_SIGNALED",
            ApplicationExitInfo.REASON_LOW_MEMORY to "REASON_LOW_MEMORY",
            ApplicationExitInfo.REASON_CRASH to "REASON_CRASH",
            ApplicationExitInfo.REASON_CRASH_NATIVE to "REASON_CRASH_NATIVE",
            ApplicationExitInfo.REASON_ANR to "REASON_ANR",
            ApplicationExitInfo.REASON_INITIALIZATION_FAILURE to "REASON_INITIALIZATION_FAILURE",
            ApplicationExitInfo.REASON_PERMISSION_CHANGE to "REASON_PERMISSION_CHANGE",
            ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE to "REASON_EXCESSIVE_RESOURCE_USAGE",
            ApplicationExitInfo.REASON_USER_REQUESTED to "REASON_USER_REQUESTED",
            ApplicationExitInfo.REASON_USER_STOPPED to "REASON_USER_STOPPED",
            ApplicationExitInfo.REASON_DEPENDENCY_DIED to "REASON_DEPENDENCY_DIED",
            ApplicationExitInfo.REASON_OTHER to "REASON_OTHER",
            ApplicationExitInfo.REASON_FREEZER to "REASON_FREEZER",
            ApplicationExitInfo.REASON_PACKAGE_STATE_CHANGE to "REASON_PACKAGE_STATE_CHANGE",
            ApplicationExitInfo.REASON_PACKAGE_UPDATED to "REASON_PACKAGE_UPDATED",
        )
        expected.forEach { (code, name) -> assertEquals(name, AndroidNames.exitReason(code)) }
        assertEquals("REASON_99", AndroidNames.exitReason(99))
    }

    @Test
    fun `standby buckets`() {
        assertEquals("ACTIVE", AndroidNames.standbyBucket(UsageStatsManager.STANDBY_BUCKET_ACTIVE))
        assertEquals("WORKING_SET", AndroidNames.standbyBucket(UsageStatsManager.STANDBY_BUCKET_WORKING_SET))
        assertEquals("FREQUENT", AndroidNames.standbyBucket(UsageStatsManager.STANDBY_BUCKET_FREQUENT))
        assertEquals("RARE", AndroidNames.standbyBucket(UsageStatsManager.STANDBY_BUCKET_RARE))
        assertEquals("RESTRICTED", AndroidNames.standbyBucket(UsageStatsManager.STANDBY_BUCKET_RESTRICTED))
    }

    @Test
    fun `interruption filters and ringer modes`() {
        assertEquals("UNKNOWN", AndroidNames.interruptionFilter(NotificationManager.INTERRUPTION_FILTER_UNKNOWN))
        assertEquals("ALL", AndroidNames.interruptionFilter(NotificationManager.INTERRUPTION_FILTER_ALL))
        assertEquals("PRIORITY", AndroidNames.interruptionFilter(NotificationManager.INTERRUPTION_FILTER_PRIORITY))
        assertEquals("NONE", AndroidNames.interruptionFilter(NotificationManager.INTERRUPTION_FILTER_NONE))
        assertEquals("ALARMS", AndroidNames.interruptionFilter(NotificationManager.INTERRUPTION_FILTER_ALARMS))
        assertEquals("SILENT", AndroidNames.ringerMode(AudioManager.RINGER_MODE_SILENT))
        assertEquals("VIBRATE", AndroidNames.ringerMode(AudioManager.RINGER_MODE_VIBRATE))
        assertEquals("NORMAL", AndroidNames.ringerMode(AudioManager.RINGER_MODE_NORMAL))
    }
}
