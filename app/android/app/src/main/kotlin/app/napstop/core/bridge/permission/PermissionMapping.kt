package app.napstop.core.bridge.permission

import android.Manifest
import app.napstop.core.bridge.LocationAccessMsg
import app.napstop.core.bridge.PermissionKindMsg
import app.napstop.core.bridge.PermissionStateMsg
import app.napstop.core.bridge.PermissionStatusMsg

/** Everything status() needs, read once (spec T21 §4.1). Pure data: JVM-testable. */
data class PermissionSnapshot(
    val sdkInt: Int,
    val fine: Boolean,
    val coarse: Boolean,
    /** [PermissionFlags]: the location prompt was shown at least once. */
    val locationRequested: Boolean,
    /** rationale(FINE) || rationale(COARSE); null = no activity. */
    val locationRationale: Boolean?,
    /** [PermissionFlags]: prompts shown while only COARSE was granted. */
    val preciseUpgradeAttempts: Int,
    val locationEnabled: Boolean,
    /** checkSelfPermission(POST_NOTIFICATIONS); false below 33. */
    val postNotificationsGranted: Boolean,
    /** NotificationManager.areNotificationsEnabled(). */
    val notificationsEnabled: Boolean,
    /** [PermissionFlags]: the notification prompt was shown at least once. */
    val notificationsRequested: Boolean,
    /** rationale(POST_NOTIFICATIONS); null = no activity or below 33. */
    val notificationsRationale: Boolean?,
    /** null: below 34 or unreadable. */
    val canUseFullScreenIntent: Boolean?,
    /** null: below 31 or unreadable. */
    val canScheduleExactAlarms: Boolean?,
    /** null: unreadable. */
    val ignoringBatteryOptimizations: Boolean?,
)

/** What request(kind) does: nothing, or one system prompt (+ the flags to set before it). */
sealed interface RequestPlan {
    data object None : RequestPlan

    data class Prompt(
        val permissions: List<String>,
        val markLocation: Boolean = false,
        val markNotifications: Boolean = false,
        val countPreciseAttempt: Boolean = false,
    ) : RequestPlan
}

/**
 * Android permission state as the Dart side sees it (spec T21 D2, §4.2, §4.3).
 * `notDetermined` = a system prompt can still be shown; `denied` = Settings only.
 * Never `precise = NOT_APPLICABLE` (review T22 #9), never `location = ALWAYS` (ADR-001).
 */
object PermissionMapping {
    const val FINE = Manifest.permission.ACCESS_FINE_LOCATION
    const val COARSE = Manifest.permission.ACCESS_COARSE_LOCATION
    const val POST_NOTIFICATIONS = "android.permission.POST_NOTIFICATIONS" // Manifest constant is API 33

    const val SDK_PRECISE_CHOICE = 31 // Android 12: "Precise / Approximate" in the dialog
    const val SDK_POST_NOTIFICATIONS = 33
    const val SDK_FULL_SCREEN_INTENT = 34
    const val SDK_EXACT_ALARM = 31

    private fun promptable(requested: Boolean, rationale: Boolean?): Boolean = !requested || rationale == true

    fun status(s: PermissionSnapshot): PermissionStatusMsg {
        val location =
            when {
                s.fine || s.coarse -> LocationAccessMsg.WHILE_IN_USE
                promptable(s.locationRequested, s.locationRationale) -> LocationAccessMsg.NOT_DETERMINED
                else -> LocationAccessMsg.DENIED
            }
        val precise =
            when {
                s.fine -> PermissionStateMsg.GRANTED
                s.coarse ->
                    if (s.sdkInt >= SDK_PRECISE_CHOICE && s.preciseUpgradeAttempts == 0) {
                        PermissionStateMsg.NOT_DETERMINED
                    } else {
                        PermissionStateMsg.DENIED
                    }
                // No location at all: checkStart ignores precise.
                else -> PermissionStateMsg.NOT_DETERMINED
            }
        val notifications =
            when {
                s.notificationsEnabled -> PermissionStateMsg.GRANTED
                s.sdkInt >= SDK_POST_NOTIFICATIONS &&
                    !s.postNotificationsGranted &&
                    promptable(s.notificationsRequested, s.notificationsRationale) ->
                    PermissionStateMsg.NOT_DETERMINED
                // Below 33, or granted but turned off by the user: Settings only.
                else -> PermissionStateMsg.DENIED
            }
        val fullScreenIntent =
            if (s.sdkInt < SDK_FULL_SCREEN_INTENT || s.canUseFullScreenIntent == true) {
                PermissionStateMsg.GRANTED
            } else {
                PermissionStateMsg.DENIED
            }
        val exactAlarm =
            if (s.sdkInt < SDK_EXACT_ALARM || s.canScheduleExactAlarms == true) {
                PermissionStateMsg.GRANTED
            } else {
                PermissionStateMsg.DENIED
            }
        return PermissionStatusMsg(
            location = location,
            precise = precise,
            locationServicesEnabled = s.locationEnabled,
            notifications = notifications,
            fullScreenIntent = fullScreenIntent,
            exactAlarm = exactAlarm,
            batteryOptimizationIgnored =
                if (s.ignoringBatteryOptimizations == true) PermissionStateMsg.GRANTED else PermissionStateMsg.DENIED,
            alarmKit = PermissionStateMsg.NOT_APPLICABLE,
        )
    }

    /** FINE is always asked together with COARSE, in one request (A-RT). */
    fun plan(kind: PermissionKindMsg, s: PermissionSnapshot): RequestPlan =
        when (kind) {
            PermissionKindMsg.LOCATION ->
                if (s.fine) {
                    RequestPlan.None
                } else {
                    RequestPlan.Prompt(listOf(FINE, COARSE), markLocation = true, countPreciseAttempt = s.coarse)
                }
            PermissionKindMsg.NOTIFICATIONS ->
                if (s.sdkInt < SDK_POST_NOTIFICATIONS || s.notificationsEnabled || s.postNotificationsGranted) {
                    RequestPlan.None
                } else {
                    RequestPlan.Prompt(listOf(POST_NOTIFICATIONS), markNotifications = true)
                }
            PermissionKindMsg.ALARM_KIT -> RequestPlan.None
        }
}
