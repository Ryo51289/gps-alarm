package app.napstop.probe

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat

/** Notification channels (S1 §5.6), the FGS notification and the alarm notification with full-screen intent (S2 §5.2). */
object AlarmNotifier {
    const val CHANNEL_TRACKING = "probe_tracking"
    const val CHANNEL_ALARM = "probe_alarm"
    const val ID_TRACKING = 1
    const val ID_ALARM = 2

    private const val REQ_OPEN_MAIN = 10
    private const val REQ_ALARM_UI = 11
    private const val REQ_DISMISS = 12

    fun createChannels(context: Context) {
        val nm = context.getSystemService(NotificationManager::class.java)
        val tracking = NotificationChannel(
            CHANNEL_TRACKING,
            context.getString(R.string.channel_tracking),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            setSound(null, null)
            enableVibration(false)
        }
        val alarm = NotificationChannel(
            CHANNEL_ALARM,
            context.getString(R.string.channel_alarm),
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            // Sound and vibration come from AlarmPlayer (USAGE_ALARM), not from the notification.
            setSound(null, null)
            enableVibration(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        nm.createNotificationChannels(listOf(tracking, alarm))
    }

    fun trackingNotification(context: Context, text: String): Notification {
        val open = PendingIntent.getActivity(
            context,
            REQ_OPEN_MAIN,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(context, CHANNEL_TRACKING)
            .setSmallIcon(R.drawable.ic_stat_probe)
            .setContentTitle(context.getString(R.string.notif_tracking_title))
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(open)
            .build()
    }

    fun alarmNotification(context: Context, plannedClock: String, src: String): Notification {
        val alarmPi = PendingIntent.getActivity(
            context,
            REQ_ALARM_UI,
            AlarmActivity.intent(context, plannedClock, src),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val dismissPi = PendingIntent.getService(
            context,
            REQ_DISMISS,
            ProbeService.dismissIntent(context, ProbeService.BY_NOTIF_ACTION),
            PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(context, CHANNEL_ALARM)
            .setSmallIcon(R.drawable.ic_stat_probe)
            .setContentTitle(context.getString(R.string.notif_alarm_title))
            .setContentText(context.getString(R.string.notif_alarm_text, plannedClock, src))
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setFullScreenIntent(alarmPi, true)
            .setContentIntent(alarmPi)
            .addAction(0, context.getString(R.string.notif_alarm_dismiss), dismissPi)
            .build()
    }
}
