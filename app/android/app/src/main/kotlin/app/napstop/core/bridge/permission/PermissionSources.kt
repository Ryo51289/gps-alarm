package app.napstop.core.bridge.permission

import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.location.LocationManager
import android.os.Build
import android.os.PowerManager

/** Platform reads of status() (spec T21 §4.1). Every call may throw; the impl catches per item. */
interface PermissionSources {
    val sdkInt: Int

    /** Context.checkSelfPermission. */
    fun isGranted(permission: String): Boolean

    /** activity?.shouldShowRequestPermissionRationale; null = no activity. Main thread. */
    fun rationale(permission: String): Boolean?

    /** API 28+ isLocationEnabled; below, GPS or network provider enabled. */
    fun locationEnabled(): Boolean

    fun notificationsEnabled(): Boolean

    /** Only called when sdkInt >= 34. */
    fun canUseFullScreenIntent(): Boolean

    /** Only called when sdkInt >= 31. */
    fun canScheduleExactAlarms(): Boolean

    /** PowerManager.isIgnoringBatteryOptimizations(packageName). */
    fun ignoringBatteryOptimizations(): Boolean
}

/** [PermissionSources] on the real system services; rationale through [prompter] (the activity). */
class AndroidPermissionSources(
    context: Context,
    private val prompter: PermissionPrompter,
) : PermissionSources {
    private val appContext = context.applicationContext

    override val sdkInt: Int get() = Build.VERSION.SDK_INT

    override fun isGranted(permission: String): Boolean =
        appContext.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    override fun rationale(permission: String): Boolean? = prompter.rationale(permission)

    override fun locationEnabled(): Boolean {
        val lm = appContext.getSystemService(LocationManager::class.java) ?: return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            lm.isLocationEnabled
        } else {
            lm.isProviderEnabled(LocationManager.GPS_PROVIDER) || lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
        }
    }

    override fun notificationsEnabled(): Boolean =
        appContext.getSystemService(NotificationManager::class.java)?.areNotificationsEnabled() ?: false

    override fun canUseFullScreenIntent(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            appContext.getSystemService(NotificationManager::class.java)?.canUseFullScreenIntent() ?: false
        } else {
            true
        }

    override fun canScheduleExactAlarms(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            appContext.getSystemService(AlarmManager::class.java)?.canScheduleExactAlarms() ?: false
        } else {
            true
        }

    override fun ignoringBatteryOptimizations(): Boolean =
        appContext.getSystemService(PowerManager::class.java)?.isIgnoringBatteryOptimizations(appContext.packageName)
            ?: false
}
