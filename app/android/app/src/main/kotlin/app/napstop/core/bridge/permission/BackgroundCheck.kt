package app.napstop.core.bridge.permission

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import app.napstop.core.bridge.BackgroundCheckMsg
import app.napstop.core.bridge.BridgeErrors
import app.napstop.core.bridge.FlutterError
import app.napstop.core.trip.host.TripNotifications
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** One screen 9 background check (spec T21 §5). Epoch ms. No coordinates. */
data class BackgroundCheckRecord(
    val scheduledAtMs: Long,
    val dueAtMs: Long,
    val firedAtMs: Long?,
    val screenOnAtFire: Boolean?,
    val exact: Boolean,
) {
    fun toMsg(): BackgroundCheckMsg =
        BackgroundCheckMsg(
            scheduledAtMs = scheduledAtMs,
            dueAtMs = dueAtMs,
            firedAtMs = firedAtMs,
            screenOnAtFire = screenOnAtFire,
            exact = exact,
        )
}

/** Pure rules of the background check, JVM-testable (K08). */
object BackgroundCheckLogic {
    const val MIN_DELAY_MS = 5_000L
    const val MAX_DELAY_MS = 120_000L

    private const val KEY_SCHEDULED = "scheduledAtMs"
    private const val KEY_DUE = "dueAtMs"
    private const val KEY_FIRED = "firedAtMs"
    private const val KEY_SCREEN_ON = "screenOnAtFire"
    private const val KEY_EXACT = "exact"

    /** Throws invalid-config outside [MIN_DELAY_MS]..[MAX_DELAY_MS]. */
    fun validate(delayMs: Long) {
        if (delayMs !in MIN_DELAY_MS..MAX_DELAY_MS) {
            throw FlutterError(BridgeErrors.INVALID_CONFIG, "delayMs: out of range", null)
        }
    }

    fun useExact(sdkInt: Int, canScheduleExact: Boolean?): Boolean =
        sdkInt < PermissionMapping.SDK_EXACT_ALARM || canScheduleExact == true

    /** Receiver: the new record, or null to ignore (no record, another check, already fired). */
    fun onFired(
        r: BackgroundCheckRecord?,
        scheduledAtExtra: Long,
        nowMs: Long,
        interactive: Boolean,
    ): BackgroundCheckRecord? {
        if (r == null || r.scheduledAtMs != scheduledAtExtra || r.firedAtMs != null) return null
        return r.copy(firedAtMs = nowMs, screenOnAtFire = interactive)
    }

    fun encode(r: BackgroundCheckRecord): Map<String, Any?> =
        mapOf(
            KEY_SCHEDULED to r.scheduledAtMs,
            KEY_DUE to r.dueAtMs,
            KEY_FIRED to r.firedAtMs,
            KEY_SCREEN_ON to r.screenOnAtFire,
            KEY_EXACT to r.exact,
        )

    /** Null when a required key is missing or has the wrong type. */
    fun decode(m: Map<String, *>): BackgroundCheckRecord? {
        val scheduled = m[KEY_SCHEDULED] as? Long ?: return null
        val due = m[KEY_DUE] as? Long ?: return null
        val exact = m[KEY_EXACT] as? Boolean ?: return null
        val firedRaw = m[KEY_FIRED]
        val screenOnRaw = m[KEY_SCREEN_ON]
        val fired = firedRaw as? Long
        val screenOn = screenOnRaw as? Boolean
        if ((firedRaw != null && fired == null) || (screenOnRaw != null && screenOn == null)) return null
        return BackgroundCheckRecord(scheduled, due, fired, screenOn, exact)
    }
}

/** What PermissionHostApiImpl needs from the check (fake in JVM tests). */
interface BackgroundChecks {
    suspend fun start(delayMs: Long): BackgroundCheckRecord

    suspend fun read(): BackgroundCheckRecord?

    suspend fun cancel()
}

/** The record in SharedPreferences [PREFS]. Blocking: call off the main thread. */
internal class BackgroundCheckStore(context: Context) {
    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun read(): BackgroundCheckRecord? = BackgroundCheckLogic.decode(prefs.all)

    fun write(r: BackgroundCheckRecord) {
        val editor = prefs.edit().clear()
        for ((key, value) in BackgroundCheckLogic.encode(r)) {
            when (value) {
                is Long -> editor.putLong(key, value)
                is Boolean -> editor.putBoolean(key, value)
                else -> Unit // null: absent
            }
        }
        editor.commit()
    }

    fun clear() {
        prefs.edit().clear().commit()
    }

    companion object {
        const val PREFS = "napstop_bg_check"
    }
}

/**
 * Schedules the screen 9 check (spec T21 §5, D15): one exact alarm (setAlarmClock since T15, the
 * same API as the fallback alarm of ADR-001) whose receiver records when it ran and vibrates. Survives
 * process death: the record is written before the alarm is set.
 */
class BackgroundCheckScheduler(
    context: Context,
    private val clock: () -> Long = System::currentTimeMillis,
    private val io: CoroutineDispatcher = Dispatchers.IO,
) : BackgroundChecks {
    private val appContext = context.applicationContext
    private val store by lazy { BackgroundCheckStore(appContext) }
    private val alarms: AlarmManager? get() = appContext.getSystemService(AlarmManager::class.java)

    override suspend fun start(delayMs: Long): BackgroundCheckRecord {
        BackgroundCheckLogic.validate(delayMs)
        return withContext(io) {
            val am = alarms ?: throw IllegalStateException("no AlarmManager")
            val now = clock()
            val due = now + delayMs
            val canExact = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) am.canScheduleExactAlarms() else null
            var record =
                BackgroundCheckRecord(
                    scheduledAtMs = now,
                    dueAtMs = due,
                    firedAtMs = null,
                    screenOnAtFire = null,
                    exact = BackgroundCheckLogic.useExact(Build.VERSION.SDK_INT, canExact),
                )
            store.write(record)
            val pi = pendingIntent(now)
            if (record.exact) {
                try {
                    // T15 D5: the same API as the trip's fallback alarm (setAlarmClock, on time in Doze), so the
                    // screen 9 check measures what the real safety net does.
                    am.setAlarmClock(AlarmManager.AlarmClockInfo(due, TripNotifications.openAppIntent(appContext, SHOW_REQUEST_CODE, null)), pi)
                } catch (_: SecurityException) {
                    record = record.copy(exact = false)
                    store.write(record)
                    am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, due, pi)
                }
            } else {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, due, pi)
            }
            record
        }
    }

    override suspend fun read(): BackgroundCheckRecord? = withContext(io) { store.read() }

    override suspend fun cancel() =
        withContext(io) {
            // Extras take no part in PendingIntent matching: this finds the scheduled one.
            PendingIntent.getBroadcast(
                appContext,
                REQUEST_CODE,
                Intent(appContext, BackgroundCheckReceiver::class.java),
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
            )?.let { pi ->
                alarms?.cancel(pi)
                pi.cancel()
            }
            store.clear()
        }

    /** FLAG_UPDATE_CURRENT: a new check replaces the extra of the previous one. */
    private fun pendingIntent(scheduledAtMs: Long): PendingIntent =
        PendingIntent.getBroadcast(
            appContext,
            REQUEST_CODE,
            Intent(appContext, BackgroundCheckReceiver::class.java)
                .putExtra(BackgroundCheckReceiver.EXTRA_SCHEDULED_AT, scheduledAtMs),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private companion object {
        const val REQUEST_CODE = 0x4E51
        const val SHOW_REQUEST_CODE = 0x4E52
    }
}
