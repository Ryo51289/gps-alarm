package app.napstop.probe

import android.Manifest
import android.app.ActivityManager
import android.app.AlarmManager
import android.app.NotificationManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import app.napstop.probe.analysis.AndroidNames
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability

/** Permission / power / sound state (S1 §5.5, `perm_snapshot` in §5.7). `null` = not applicable on this API level. */
data class PermState(
    val fine: Boolean,
    val coarse: Boolean,
    val bg: Boolean?,
    val notif: Boolean?,
    val notifEnabled: Boolean,
    val fsi: Boolean?,
    val exact: Boolean?,
    val ignBatOpt: Boolean,
    val bgRestricted: Boolean?,
    val bucket: String?,
    val powerSave: Boolean,
    val chTrackingImp: Int?,
    val chAlarmImp: Int?,
    val alarmVol: Int,
    val alarmVolMax: Int,
    val ringer: Int,
    val zen: Int,
) {
    val hasLocation: Boolean get() = fine || coarse

    fun toMap(): Map<String, Any?> = linkedMapOf(
        "fine" to fine,
        "coarse" to coarse,
        "bg" to bg,
        "notif" to notif,
        "notifEnabled" to notifEnabled,
        "fsi" to fsi,
        "exact" to exact,
        "ignBatOpt" to ignBatOpt,
        "bgRestricted" to bgRestricted,
        "bucket" to bucket,
        "powerSave" to powerSave,
        "chTrackingImp" to chTrackingImp,
        "chAlarmImp" to chAlarmImp,
        "alarmVol" to alarmVol,
        "alarmVolMax" to alarmVolMax,
        "ringer" to ringer,
        "zen" to zen,
    )
}

object DeviceSnapshot {

    fun permState(context: Context): PermState {
        val nm = context.getSystemService(NotificationManager::class.java)
        val am = context.getSystemService(AlarmManager::class.java)
        val pm = context.getSystemService(PowerManager::class.java)
        val activityManager = context.getSystemService(ActivityManager::class.java)
        val audio = context.getSystemService(AudioManager::class.java)
        fun granted(permission: String) =
            ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

        return PermState(
            fine = granted(Manifest.permission.ACCESS_FINE_LOCATION),
            coarse = granted(Manifest.permission.ACCESS_COARSE_LOCATION),
            bg = if (Build.VERSION.SDK_INT >= 29) granted(Manifest.permission.ACCESS_BACKGROUND_LOCATION) else null,
            notif = if (Build.VERSION.SDK_INT >= 33) granted(Manifest.permission.POST_NOTIFICATIONS) else null,
            notifEnabled = NotificationManagerCompat.from(context).areNotificationsEnabled(),
            fsi = if (Build.VERSION.SDK_INT >= 34) nm.canUseFullScreenIntent() else null,
            exact = if (Build.VERSION.SDK_INT >= 31) am.canScheduleExactAlarms() else null,
            ignBatOpt = pm.isIgnoringBatteryOptimizations(context.packageName),
            bgRestricted = if (Build.VERSION.SDK_INT >= 28) activityManager.isBackgroundRestricted else null,
            bucket = if (Build.VERSION.SDK_INT >= 28) {
                val usm = context.getSystemService(UsageStatsManager::class.java)
                AndroidNames.standbyBucket(usm.appStandbyBucket)
            } else {
                null
            },
            powerSave = pm.isPowerSaveMode,
            chTrackingImp = nm.getNotificationChannel(AlarmNotifier.CHANNEL_TRACKING)?.importance,
            chAlarmImp = nm.getNotificationChannel(AlarmNotifier.CHANNEL_ALARM)?.importance,
            alarmVol = audio.getStreamVolume(AudioManager.STREAM_ALARM),
            alarmVolMax = audio.getStreamMaxVolume(AudioManager.STREAM_ALARM),
            ringer = audio.ringerMode,
            zen = nm.currentInterruptionFilter,
        )
    }

    /** Logs `perm_snapshot` (at run_start, every svc_start_cmd and alarm_trigger). */
    fun logPermSnapshot(context: Context) {
        EventLog.log("perm_snapshot", permState(context).toMap())
    }

    /** Device fields for `run_start` (no identifiers beyond make/model/build). */
    fun device(context: Context): Map<String, Any?> = linkedMapOf(
        "manufacturer" to Build.MANUFACTURER,
        "brand" to Build.BRAND,
        "model" to Build.MODEL,
        "sdk" to Build.VERSION.SDK_INT,
        "release" to Build.VERSION.RELEASE,
        "display" to Build.DISPLAY,
        "secPatch" to Build.VERSION.SECURITY_PATCH,
        "gms" to gmsStatus(context),
    )

    fun gmsStatus(context: Context): String {
        val code = GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context)
        return if (code == ConnectionResult.SUCCESS) "OK" else "ERR_$code"
    }

    fun bootCount(context: Context): Int =
        Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT, -1)
}
