package app.napstop.core.trip.host

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import app.napstop.core.trip.runtime.OsAlarmScheduler
import app.napstop.core.trip.runtime.RestoreCause
import app.napstop.core.trip.runtime.SlotKind
import app.napstop.core.trip.runtime.WakeMechanism

/**
 * AlarmManager side of the runtime (spec T15 §5.5, §5.6, D5–D7):
 * - wake-up at `wakeAtMs`: one PendingIntent to [WakeAlarmReceiver], `setExactAndAllowWhileIdle(ELAPSED_REALTIME_WAKEUP)`
 *   (D6; `setAlarmClock` only behind NEAR_WAKE_USES_ALARM_CLOCK, `setAndAllowWhileIdle` without the exact permission);
 * - fallback alarm: two slots (request codes [REQ_FALLBACK_BASE] + 0/1) to [FallbackAlarmReceiver], `setAlarmClock`
 *   (wall time [A-ACI]; fires on time in Doze [A-DOZE]); `setAndAllowWhileIdle(RTC_WAKEUP)` without the exact permission.
 * Extras carry ids and times only: no coordinates, no destination name.
 */
class AndroidAlarmScheduler(context: Context) : OsAlarmScheduler {
    private val appContext = context.applicationContext
    private val am: AlarmManager get() = appContext.getSystemService(AlarmManager::class.java) ?: throw IllegalStateException("no AlarmManager")

    override fun canScheduleExact(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || am.canScheduleExactAlarms()

    override fun setWake(triggerElapsedMs: Long, mechanism: WakeMechanism, triggerWallMs: Long, wakeAtMs: Long) {
        // F5: the alarm carries what it was set for (FLAG_UPDATE_CURRENT replaces the extras every time).
        val pi =
            PendingIntent.getBroadcast(
                appContext,
                REQ_WAKE,
                Intent(appContext, WakeAlarmReceiver::class.java)
                    .putExtra(WakeAlarmReceiver.EXTRA_WAKE_AT, wakeAtMs)
                    .putExtra(WakeAlarmReceiver.EXTRA_WAKE_AT_WALL, triggerWallMs),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        when (mechanism) {
            WakeMechanism.EXACT_IDLE ->
                try {
                    am.setExactAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerElapsedMs, pi)
                } catch (_: SecurityException) {
                    am.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerElapsedMs, pi)
                }
            WakeMechanism.INEXACT_IDLE -> am.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerElapsedMs, pi)
            WakeMechanism.ALARM_CLOCK -> am.setAlarmClock(AlarmManager.AlarmClockInfo(triggerWallMs, showIntent()), pi)
        }
    }

    override fun cancelWake() {
        wakeIntent(PendingIntent.FLAG_NO_CREATE)?.let {
            am.cancel(it)
            it.cancel()
        }
    }

    override fun setFallback(slot: Int, tripId: String, generation: Long, targetAtMs: Long, triggerWallMs: Long, exact: Boolean, kind: SlotKind) {
        val intent =
            Intent(appContext, FallbackAlarmReceiver::class.java)
                .putExtra(FallbackAlarmReceiver.EXTRA_TRIP_ID, tripId)
                .putExtra(FallbackAlarmReceiver.EXTRA_SLOT, slot)
                .putExtra(FallbackAlarmReceiver.EXTRA_GENERATION, generation)
                .putExtra(FallbackAlarmReceiver.EXTRA_TARGET_AT, targetAtMs)
                .putExtra(FallbackAlarmReceiver.EXTRA_KIND, kind.name)
        val pi =
            PendingIntent.getBroadcast(
                appContext,
                REQ_FALLBACK_BASE + slot,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        if (exact) {
            am.setAlarmClock(AlarmManager.AlarmClockInfo(triggerWallMs, showIntent()), pi)
        } else {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerWallMs, pi)
        }
    }

    override fun cancelFallback(slot: Int) {
        PendingIntent.getBroadcast(
            appContext,
            REQ_FALLBACK_BASE + slot,
            Intent(appContext, FallbackAlarmReceiver::class.java),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        )?.let {
            am.cancel(it)
            it.cancel()
        }
    }

    /** B3: its own PendingIntent (request code [REQ_RESTORE_RETRY]) to WakeAlarmReceiver; no location data. */
    override fun setRestoreRetry(triggerElapsedMs: Long, attempt: Int, cause: RestoreCause, sinceWallMs: Long, exact: Boolean) {
        val pi =
            PendingIntent.getBroadcast(
                appContext,
                REQ_RESTORE_RETRY,
                Intent(appContext, WakeAlarmReceiver::class.java)
                    .putExtra(WakeAlarmReceiver.EXTRA_RESTORE_RETRY, attempt)
                    .putExtra(WakeAlarmReceiver.EXTRA_CAUSE, cause.name)
                    .putExtra(WakeAlarmReceiver.EXTRA_SINCE_WALL, sinceWallMs),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        if (exact) {
            try {
                am.setExactAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerElapsedMs, pi)
                return
            } catch (_: SecurityException) {
                // falls through to the inexact alarm
            }
        }
        am.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerElapsedMs, pi)
    }

    override fun cancelRestoreRetry() {
        PendingIntent.getBroadcast(
            appContext,
            REQ_RESTORE_RETRY,
            Intent(appContext, WakeAlarmReceiver::class.java),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        )?.let {
            am.cancel(it)
            it.cancel()
        }
    }

    private fun wakeIntent(flag: Int): PendingIntent? =
        PendingIntent.getBroadcast(appContext, REQ_WAKE, Intent(appContext, WakeAlarmReceiver::class.java), flag or PendingIntent.FLAG_IMMUTABLE)

    /** Tapping the alarm icon / "next alarm" opens the app (AlarmClockInfo showIntent). */
    private fun showIntent(): PendingIntent = TripNotifications.openAppIntent(appContext, REQ_SHOW, resumeTripId = null)

    companion object {
        const val REQ_WAKE = 0x4E5701
        const val REQ_FALLBACK_BASE = 0x4E5710
        const val REQ_SHOW = 0x4E5720
        const val REQ_RESTORE_RETRY = 0x4E5702
    }
}
