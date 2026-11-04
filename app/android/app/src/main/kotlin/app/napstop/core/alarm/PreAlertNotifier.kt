package app.napstop.core.alarm

import android.app.NotificationManager
import android.content.Context
import android.util.Log
import androidx.core.app.NotificationCompat
import app.napstop.R
import app.napstop.core.trip.host.TripNotifications
import java.util.Locale

/** Pre-alert (spec T16 D20): channel `napstop_prealert` (DEFAULT, no sound, light vibration), from the main process. */
class PreAlertNotifier(context: Context, private val locale: () -> Locale) {
    private val ctx = context.applicationContext
    private val nm: NotificationManager? get() = ctx.getSystemService(NotificationManager::class.java)

    fun post(r: PreAlertRequest) {
        try {
            AlarmChannels.ensure(ctx)
            val text = RingStrings.text(ctx, RingCopy.preAlert(r, locale()))
            val publicVersion =
                NotificationCompat.Builder(ctx, AlarmChannels.PRE_ALERT)
                    .setSmallIcon(R.drawable.ic_stat_napstop)
                    .setContentTitle(ctx.getString(R.string.notif_tracking_public))
                    .build()
            val n =
                NotificationCompat.Builder(ctx, AlarmChannels.PRE_ALERT)
                    .setSmallIcon(R.drawable.ic_stat_napstop)
                    .setContentTitle(text)
                    .setStyle(NotificationCompat.BigTextStyle().bigText(text))
                    .setCategory(NotificationCompat.CATEGORY_REMINDER)
                    .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                    .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
                    .setPublicVersion(publicVersion)
                    .setAutoCancel(true)
                    .setTimeoutAfter(PRE_ALERT_TIMEOUT_MS)
                    .setContentIntent(TripNotifications.openAppIntent(ctx, RingIntents.REQ_PRE_ALERT_OPEN, null))
                    .build()
            nm?.notify(r.tripId, TripNotifications.ID_PRE_ALERT, n)
        } catch (e: Exception) {
            Log.w(TAG, "pre-alert failed (${e.javaClass.simpleName})")
        }
    }

    fun cancel(tripId: String) {
        try {
            nm?.cancel(tripId, TripNotifications.ID_PRE_ALERT)
        } catch (e: Exception) {
            Log.w(TAG, "pre-alert cancel failed (${e.javaClass.simpleName})")
        }
    }

    private companion object {
        const val TAG = "NapStopAlarm"
        const val PRE_ALERT_TIMEOUT_MS = 30 * 60_000L
    }
}
