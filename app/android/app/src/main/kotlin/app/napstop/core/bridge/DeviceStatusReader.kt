package app.napstop.core.bridge

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.os.BatteryManager
import android.os.Build
import android.util.Log
import app.napstop.core.alarm.HeadphoneTypes

/**
 * Platform reads of [DeviceStatusReader] (T14.1 O2, T21 D8). Each call may throw; the reader
 * catches per item. Null = the system service (or the sticky intent) is missing.
 */
interface DeviceStatusSources {
    /** `getIntExtra` of the sticky ACTION_BATTERY_CHANGED intent; null = no intent. */
    fun batteryExtras(): ((String, Int) -> Int)?

    fun alarmVolume(): Int?

    fun alarmMaxVolume(): Int?

    fun alarmMuted(): Boolean?

    /** NotificationManager.getCurrentInterruptionFilter(); null = no NotificationManager. */
    fun interruptionFilter(): Int?

    /** Applied policy categories; only called when sdkInt >= 30 and the filter is priority. */
    fun consolidatedPriorityCategories(): Int?

    /**
     * `AudioDeviceInfo.getType()` of every output device (T26 §9); null = no AudioManager.
     * Default null (unknown) keeps the older fakes of the T21/T14.1 tests compiling.
     */
    fun outputDeviceTypes(): List<Int>? = null
}

/** [DeviceStatusSources] on the real system services. */
class AndroidDeviceStatusSources(context: Context) : DeviceStatusSources {
    private val appContext = context.applicationContext
    private val audio: AudioManager? get() = appContext.getSystemService(AudioManager::class.java)
    private val notifications: NotificationManager?
        get() = appContext.getSystemService(NotificationManager::class.java)

    // Sticky broadcast: a null receiver returns the latest ACTION_BATTERY_CHANGED
    // without registering anything (A-BAT). Same source as T15's BatterySample.
    override fun batteryExtras(): ((String, Int) -> Int)? =
        appContext.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))?.let { it::getIntExtra }

    override fun alarmVolume(): Int? = audio?.getStreamVolume(AudioManager.STREAM_ALARM)

    override fun alarmMaxVolume(): Int? = audio?.getStreamMaxVolume(AudioManager.STREAM_ALARM)

    override fun alarmMuted(): Boolean? = audio?.isStreamMute(AudioManager.STREAM_ALARM)

    override fun interruptionFilter(): Int? = notifications?.currentInterruptionFilter

    // Currently applied policy (API 30+), not getNotificationPolicy() = the default one (S2 V5-9).
    override fun consolidatedPriorityCategories(): Int? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            notifications?.consolidatedNotificationPolicy?.priorityCategories
        } else {
            null
        }

    // API 23+ (A-AUD); minSdk is above it. Same source as T16's HeadsetMonitor.
    override fun outputDeviceTypes(): List<Int>? =
        audio?.getDevices(AudioManager.GET_DEVICES_OUTPUTS)?.map { it.type }
}

/**
 * Real `PermissionHostApi.deviceStatus()` on Android (spec T14.1, T22 §8.1): battery,
 * alarm stream volume, Do Not Disturb and connected headphones (T26 §9), read on demand. No permission needed.
 * Every item is read on its own; one that cannot be read is null / unknown, so the
 * call never throws (a throw would go through Pigeon's wrapError with the stack trace).
 *
 * Runs on the main thread (synchronous Pigeon method): only cheap system-service calls,
 * no disk, no waiting. Sources, SDK level and logger are injectable for JVM tests (T14.1 O2).
 */
class DeviceStatusReader internal constructor(
    private val sources: DeviceStatusSources,
    private val sdkInt: Int,
    private val warn: (String) -> Unit,
) {
    constructor(context: Context) : this(
        AndroidDeviceStatusSources(context),
        Build.VERSION.SDK_INT,
        { Log.w(TAG, it) },
    )

    fun read(): DeviceStatusMsg {
        val battery =
            readOrNull("battery") { sources.batteryExtras()?.let(DeviceStatusMapping::battery) }
                ?: DeviceStatusMapping.Battery.UNKNOWN

        val alarmVolumePct =
            readOrNull("volume") {
                val volume = sources.alarmVolume()
                val max = sources.alarmMaxVolume()
                if (volume == null || max == null) null else DeviceStatusMapping.volumePct(volume, max)
            }
        val alarmMuted = readOrNull("mute") { sources.alarmMuted() }

        val filter =
            readOrNull("filter") { sources.interruptionFilter()?.let(DeviceStatusMapping::mapInterruptionFilter) }
                ?: InterruptionFilterMsg.UNKNOWN
        val priorityAllowsAlarms =
            if (sdkInt >= Build.VERSION_CODES.R && filter == InterruptionFilterMsg.PRIORITY) {
                readOrNull("policy") { sources.consolidatedPriorityCategories() }
                    ?.let { DeviceStatusMapping.priorityAllowsAlarms(sdkInt, filter, it) }
            } else {
                null
            }

        // T26 §9: wired / Bluetooth / USB / hearing-aid output (T16 HeadphoneTypes).
        val headphonesConnected =
            readOrNull("headphones") { sources.outputDeviceTypes()?.any(HeadphoneTypes::isHeadphone) }

        return DeviceStatusMsg(
            batteryPct = battery.pct,
            charging = battery.charging,
            alarmVolumePct = alarmVolumePct,
            alarmMuted = alarmMuted,
            interruptionFilter = filter,
            priorityAllowsAlarms = priorityAllowsAlarms,
            headphonesConnected = headphonesConnected,
        )
    }

    /** [block], or null after logging the item and the exception class only. */
    private inline fun <T> readOrNull(item: String, block: () -> T): T? =
        try {
            block()
        } catch (e: Exception) {
            warn("device status $item: ${e.javaClass.simpleName}")
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
