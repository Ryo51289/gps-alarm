package app.napstop.core.bridge.permission

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import app.napstop.core.bridge.SettingsTargetMsg

/** One settings intent to try: [action], with `package:<pkg>` data and/or EXTRA_APP_PACKAGE. */
data class IntentSpec(val action: String, val packageUri: Boolean = false, val extraAppPackage: Boolean = false)

/** Settings pages per target and API level (spec T21 §4.4). Pure. */
object SettingsIntents {
    private val APP_DETAILS = IntentSpec(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, packageUri = true)

    /**
     * Candidates in order; empty = not applicable on this API. Never
     * ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS (Play policy, ARCHITECTURE §7.1).
     */
    fun candidates(target: SettingsTargetMsg, sdkInt: Int): List<IntentSpec> =
        when (target) {
            SettingsTargetMsg.APP_DETAILS -> listOf(APP_DETAILS)
            SettingsTargetMsg.LOCATION_SERVICES -> listOf(IntentSpec(Settings.ACTION_LOCATION_SOURCE_SETTINGS))
            SettingsTargetMsg.NOTIFICATIONS ->
                listOf(IntentSpec(Settings.ACTION_APP_NOTIFICATION_SETTINGS, extraAppPackage = true), APP_DETAILS)
            SettingsTargetMsg.FULL_SCREEN_INTENT ->
                if (sdkInt >= PermissionMapping.SDK_FULL_SCREEN_INTENT) {
                    listOf(IntentSpec(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, packageUri = true), APP_DETAILS)
                } else {
                    emptyList()
                }
            SettingsTargetMsg.EXACT_ALARM ->
                if (sdkInt >= PermissionMapping.SDK_EXACT_ALARM) {
                    listOf(IntentSpec(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, packageUri = true), APP_DETAILS)
                } else {
                    emptyList()
                }
            SettingsTargetMsg.BATTERY_OPTIMIZATION ->
                listOf(IntentSpec(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS), APP_DETAILS)
        }
}

/**
 * Opens the first candidate that starts (spec T21 §4.4, A-PKG): no `resolveActivity` (it would
 * need `<queries>`), a missing page throws ActivityNotFoundException and the next one is tried.
 * [start] launches one spec and may throw.
 */
class SettingsLauncher(private val start: (IntentSpec) -> Unit) {
    /** True when one candidate opened. */
    fun open(specs: List<IntentSpec>): Boolean {
        for (spec in specs) {
            try {
                start(spec)
                return true
            } catch (_: ActivityNotFoundException) {
                // Next candidate.
            } catch (_: SecurityException) {
                // Next candidate.
            }
        }
        return false
    }

    companion object {
        /** Starts from the attached [activity], else from the application context in a new task. */
        fun android(context: Context, activity: () -> Activity?): SettingsLauncher {
            val appContext = context.applicationContext
            val pkg = appContext.packageName
            return SettingsLauncher { spec ->
                val intent = Intent(spec.action)
                if (spec.packageUri) intent.data = Uri.fromParts("package", pkg, null)
                if (spec.extraAppPackage) intent.putExtra(Settings.EXTRA_APP_PACKAGE, pkg)
                val host = activity()
                if (host != null) {
                    host.startActivity(intent)
                } else {
                    appContext.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                }
            }
        }
    }
}
