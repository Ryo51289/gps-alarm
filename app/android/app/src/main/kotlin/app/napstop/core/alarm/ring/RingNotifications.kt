package app.napstop.core.alarm.ring

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.app.NotificationCompat
import app.napstop.R
import app.napstop.core.alarm.AlarmChannels
import app.napstop.core.alarm.RingContent
import app.napstop.core.alarm.RingIntents
import app.napstop.core.alarm.RingNotificationBuilder

/** The ring service notification, id 1202 on `napstop_alarm` (spec T16 D10, §5.9). */
object RingNotifications {
    const val ID_RING_FGS = 1202
    private const val TAG = "NapStopRing"

    /** First notification of startForeground, before the session knows the trip: generic title, FSI to AlarmActivity. */
    fun placeholder(ctx: Context): Notification {
        AlarmChannels.ensure(ctx)
        val activity =
            PendingIntent.getActivity(
                ctx,
                RingIntents.REQ_BACKUP_ACTIVITY,
                Intent(ctx, AlarmActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_USER_ACTION),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        return NotificationCompat.Builder(ctx, AlarmChannels.ALARM)
            .setSmallIcon(R.drawable.ic_stat_napstop)
            .setContentTitle(ctx.getString(R.string.notif_alarm_public))
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            // The first post of 1202 is this one: it carries the full-screen intent (the activity waits for the session).
            .setFullScreenIntent(activity, true)
            .setContentIntent(activity)
            .build()
    }

    /**
     * [firstOfSession]: the first real post of a ring alerts (full-screen intent). It replaces the placeholder within
     * milliseconds; with onlyAlertOnce SystemUI would treat it as a silent update and never launch the full-screen
     * intent (seen on the API 34 emulator). Later content updates do not alert again.
     */
    fun ringing(ctx: Context, tripId: String, content: RingContent, firstOfSession: Boolean): Notification =
        RingNotificationBuilder.build(ctx, AlarmChannels.ALARM, tripId, content)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setOnlyAlertOnce(!firstOfSession)
            .build()

    fun post(ctx: Context, n: Notification) {
        try {
            ctx.getSystemService(NotificationManager::class.java)?.notify(ID_RING_FGS, n)
        } catch (e: Exception) {
            // No POST_NOTIFICATIONS: the FGS still runs and the sound plays (A-NOTIF); the app opens AlarmActivity.
            Log.w(TAG, "ring notification failed (${e.javaClass.simpleName})")
        }
    }
}
