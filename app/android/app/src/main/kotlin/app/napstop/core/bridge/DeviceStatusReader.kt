package app.napstop.core.bridge

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.os.BatteryManager
import android.os.Build
import android.util.Log

/**
 * Real `PermissionHostApi.deviceStatus()` on Android (spec T14.1, T22 §8.1): battery,
 * alarm stream volume and Do Not Disturb, read on demand. No permission needed.
 * Every item is read on its own; one that cannot be read is null / unknown, so the
 * call never throws (a throw would go through Pigeon's wrapError with the stack trace).
 *
 * Runs on the main thread (synchronous Pigeon method): only cheap system-service calls,
 * no disk, no waiting.
 */
class DeviceStatusReader(context: Context) {
    private val appContext = context.applicationContext

    fun read(): DeviceStatusMsg {
        // Sticky broadcast: a null receiver returns the latest ACTION_BATTERY_CHANGED
        // without registering anything (A-BAT). Same source as T15's BatterySample.
        val battery =
            readOrNull("battery") {
                appContext.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            }?.let { sticky -> DeviceStatusMapping.battery(sticky::getIntExtra) }
                ?: DeviceStatusMapping.Battery.UNKNOWN

        val audio = appContext.getSystemService(AudioManager::class.java)
        val alarmVolumePct =
            audio?.let { a ->
                readOrNull("volume") {
                    DeviceStatusMapping.volumePct(
                        a.getStreamVolume(AudioManager.STREAM_ALARM),
                        a.getStreamMaxVolume(AudioManager.STREAM_ALARM),
                    )
                }
            }
        val alarmMuted = audio?.let { a -> readOrNull("mute") { a.isStreamMute(AudioManager.STREAM_ALARM) } }

        val notifications = appContext.getSystemService(NotificationManager::class.java)
        val filter =
            notifications?.let { n ->
                readOrNull("filter") { DeviceStatusMapping.mapInterruptionFilter(n.currentInterruptionFilter) }
            } ?: InterruptionFilterMsg.UNKNOWN
        // Currently applied policy (API 30+), not getNotificationPolicy() = the default one (S2 V5-9).
        val priorityAllowsAlarms =
            if (notifications != null &&
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                filter == InterruptionFilterMsg.PRIORITY
            ) {
                readOrNull("policy") { notifications.consolidatedNotificationPolicy.priorityCategories }
                    ?.let { DeviceStatusMapping.priorityAllowsAlarms(Build.VERSION.SDK_INT, filter, it) }
            } else {
                null
            }

        return DeviceStatusMsg(
            batteryPct = battery.pct,
            charging = battery.charging,
            alarmVolumePct = alarmVolumePct,
            alarmMuted = alarmMuted,
            interruptionFilter = filter,
            priorityAllowsAlarms = priorityAllowsAlarms,
        )
    }

    /** [block], or null after logging the item and the exception class only. */
    private inline fun <T> readOrNull(item: String, block: () -> T): T? =
        try {
            block()
        } catch (e: Exception) {
            Log.w(TAG, "device status $item: ${e.javaClass.simpleName}")
            null
        }

    private companion object {
        const val TAG = "NapStopBridge"
    }
}

/** Pure parts of [DeviceStatusReader], JVM-testable (T14.1, T22 K01). */
object DeviceStatusMapping {
    data class Battery(val pct: Long?, val charging: Boolean?) {
        companion object {
            val UNKNOWN = Battery(pct = null, charging = null)
        }
    }

    /**
     * Battery from the extras of the sticky ACTION_BATTERY_CHANGED intent; [intExtra] is
     * `Intent::getIntExtra` (name, default). A missing extra reads as the default -1.
     */
    fun battery(intExtra: (String, Int) -> Int): Battery =
        Battery(
            pct = batteryPct(intExtra(BatteryManager.EXTRA_LEVEL, -1), intExtra(BatteryManager.EXTRA_SCALE, -1)),
            charging = charging(intExtra(BatteryManager.EXTRA_STATUS, -1)),
        )

    /** `level * 100 / scale` rounded down (T25 §7) when `level >= 0 && scale > 0`, else null. */
    fun batteryPct(level: Int, scale: Int): Long? =
        if (level >= 0 && scale > 0) (level.toLong() * 100 / scale).coerceIn(0L, 100L) else null

    /** CHARGING / FULL -> true, DISCHARGING / NOT_CHARGING -> false, UNKNOWN or missing -> null. */
    fun charging(status: Int): Boolean? =
        when (status) {
            BatteryManager.BATTERY_STATUS_CHARGING, BatteryManager.BATTERY_STATUS_FULL -> true
            BatteryManager.BATTERY_STATUS_DISCHARGING, BatteryManager.BATTERY_STATUS_NOT_CHARGING -> false
            else -> null
        }

    /** `round(100 * volume / max)` in 0..100; null when [max] <= 0. */
    fun volumePct(volume: Int, max: Int): Long? =
        if (max <= 0) null else Math.round(100.0 * volume / max).coerceIn(0L, 100L)

    /** NotificationManager.INTERRUPTION_FILTER_* -> wire enum; anything else is unknown. */
    fun mapInterruptionFilter(filter: Int): InterruptionFilterMsg =
        when (filter) {
            NotificationManager.INTERRUPTION_FILTER_ALL -> InterruptionFilterMsg.ALL
            NotificationManager.INTERRUPTION_FILTER_PRIORITY -> InterruptionFilterMsg.PRIORITY
            NotificationManager.INTERRUPTION_FILTER_NONE -> InterruptionFilterMsg.NONE
            NotificationManager.INTERRUPTION_FILTER_ALARMS -> InterruptionFilterMsg.ALARMS
            else -> InterruptionFilterMsg.UNKNOWN
        }

    /**
     * Whether the applied priority-only policy lets alarms through. Only meaningful on
     * API 30+ (getConsolidatedNotificationPolicy) and when [filter] is priority; else null.
     */
    fun priorityAllowsAlarms(sdk: Int, filter: InterruptionFilterMsg, categories: Int): Boolean? =
        if (sdk >= Build.VERSION_CODES.R && filter == InterruptionFilterMsg.PRIORITY) {
            (categories and NotificationManager.Policy.PRIORITY_CATEGORY_ALARMS) != 0
        } else {
            null
        }
}
