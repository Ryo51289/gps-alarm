package app.napstop.probe

import android.app.KeyguardManager
import android.app.NotificationManager
import android.content.Context
import android.os.PowerManager
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * Process-wide alarm state (docs/spikes/S2.md "Vòng 4" V4-1): whether an alarm is ringing in this process and which service
 * owns it (`probe` = ProbeService, `ring` = AlarmRingService). AlarmActivity closes itself on `active = false`; the
 * "Tắt báo thức" and "Dừng lượt" buttons are routed to [owner].
 */
object AlarmState {
    const val OWNER_PROBE = "probe"
    const val OWNER_RING = "ring"

    private val activeFlow = MutableStateFlow(false)
    val active: StateFlow<Boolean> get() = activeFlow

    @Volatile
    var owner: String? = null
        private set

    /** Screen state when the alarm fired, for AlarmActivity's `viaFsi`. */
    @Volatile
    var interactiveAtTrigger: Boolean? = null
        private set

    @Synchronized
    fun set(newOwner: String) {
        owner = newOwner
        activeFlow.value = true
    }

    /** Sets [newOwner] only if no alarm is active; returns true if [newOwner] owns the alarm afterwards. */
    @Synchronized
    fun claim(newOwner: String): Boolean {
        if (activeFlow.value) return owner == newOwner
        set(newOwner)
        return true
    }

    /** Clears the state only if [byOwner] owns it (one service never clears the other's alarm). */
    @Synchronized
    fun clear(byOwner: String) {
        if (owner != byOwner) return
        owner = null
        activeFlow.value = false
    }

    fun isRinging(byOwner: String): Boolean = activeFlow.value && owner == byOwner

    internal fun recordTrigger(interactive: Boolean) {
        interactiveAtTrigger = interactive
    }
}

/** Alarm log lines shared by ProbeService and AlarmRingService so both paths log the same fields (S2 §5.4). */
internal object AlarmEvents {

    /** `alarm_trigger` + `perm_snapshot` (S2 §5.2 step 1); [svc] = `probe`/`ring` (Vòng 4). */
    fun trigger(context: Context, src: String, svc: String, deadlineWallMs: Long, nowWallMs: Long) {
        val pm = context.getSystemService(PowerManager::class.java)
        val km = context.getSystemService(KeyguardManager::class.java)
        val interactive = pm.isInteractive
        AlarmState.recordTrigger(interactive)
        EventLog.log(
            "alarm_trigger",
            "src" to src,
            "svc" to svc,
            "planned" to EventLog.iso(deadlineWallMs),
            "lateMs" to nowWallMs - deadlineWallMs,
            "interactive" to interactive,
            "keyguardLocked" to km.isKeyguardLocked,
            "idle" to pm.isDeviceIdleMode,
        )
        DeviceSnapshot.logPermSnapshot(context)
    }

    /** `alarm_notif_posted` (S2 §5.4). */
    fun notifPosted(context: Context, nm: NotificationManager) {
        EventLog.log(
            "alarm_notif_posted",
            "fsiAllowed" to DeviceSnapshot.permState(context).let { it.fsi ?: true },
            "notifEnabled" to nm.areNotificationsEnabled(),
            "chAlarmImp" to nm.getNotificationChannel(AlarmNotifier.CHANNEL_ALARM)?.importance,
        )
    }
}
