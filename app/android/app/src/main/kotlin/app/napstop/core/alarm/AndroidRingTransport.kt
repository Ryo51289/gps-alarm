package app.napstop.core.alarm

import android.app.ForegroundServiceStartNotAllowedException
import android.content.Context
import android.os.Build
import android.util.Log
import app.napstop.core.trip.host.AppVisibilityTracker

/** [RingTransport] on Android: binder calls only (startForegroundService, broadcasts, notifications). */
class AndroidRingTransport(
    context: Context,
    private val backup: BackupRingNotifier,
    private val preAlerts: PreAlertNotifier,
) : RingTransport {
    private val ctx = context.applicationContext

    override fun startRingService(s: RingStart) {
        try {
            // D3: allowed while the `location` FGS runs (the app is not "in the background") or inside an exact-alarm
            // receiver (setAlarmClock / setExactAndAllowWhileIdle exemption). RK-T15-8: AE1/AE2 measure it.
            ctx.startForegroundService(RingIntents.startService(ctx, s))
        } catch (e: IllegalStateException) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && e is ForegroundServiceStartNotAllowedException) {
                throw RingStartDenied("ForegroundServiceStartNotAllowedException")
            }
            throw RingStartDenied(e.javaClass.simpleName.ifEmpty { "IllegalStateException" })
        } catch (e: SecurityException) {
            throw RingStartDenied("SecurityException")
        }
    }

    override fun sendToRing(c: RingCommand) {
        try {
            ctx.sendBroadcast(RingIntents.command(ctx, c))
        } catch (e: Exception) {
            Log.w(TAG, "ring command failed (${e.javaClass.simpleName})")
        }
    }

    override fun postBackup(s: RingStart, content: RingContent): Boolean = backup.post(s, content)

    override fun cancelBackup(tripId: String) = backup.cancel(tripId)

    override fun backupShowing(tripId: String): Boolean = backup.showing(tripId)

    override fun postPreAlert(r: PreAlertRequest) = preAlerts.post(r)

    override fun cancelPreAlert(tripId: String) = preAlerts.cancel(tripId)

    override fun appVisible(): Boolean = AppVisibilityTracker.isVisible()

    private companion object {
        const val TAG = "NapStopAlarm"
    }
}
