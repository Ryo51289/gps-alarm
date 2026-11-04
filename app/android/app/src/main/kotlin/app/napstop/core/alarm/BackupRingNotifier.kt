package app.napstop.core.alarm

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import app.napstop.R
import app.napstop.core.alarm.ring.RingCommandReceiver

/**
 * Backup ring of spec T16 D4: when the ring service cannot start, a notification on `napstop_alarm_backup` rings with the
 * channel's alarm sound (USAGE_ALARM, FLAG_INSISTENT: the system repeats it), full-screen intent to AlarmActivity (which
 * may then start the service and adopt the ring). Swiping it away → BackupRingReceiver.
 */
class BackupRingNotifier(context: Context, private val ringMaxMs: () -> Long) {
    private val ctx = context.applicationContext
    private val nm: NotificationManager? get() = ctx.getSystemService(NotificationManager::class.java)

    fun post(s: RingStart, content: RingContent): Boolean {
        val m = nm ?: return false
        return try {
            if (!m.areNotificationsEnabled()) return false
            AlarmChannels.ensure(ctx)
            // A blocked channel (or its group) drops the post silently: that is no backup ring (review T16 #6).
            val ch = m.getNotificationChannel(AlarmChannels.BACKUP)
            if (ch == null || ch.importance == NotificationManager.IMPORTANCE_NONE) return false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && ch.group != null && m.getNotificationChannelGroup(ch.group)?.isBlocked == true) {
                return false
            }
            val trip = s.request.tripId
            val already = showing(trip)
            val started = s.resumeStartedAtWallMs ?: System.currentTimeMillis()
            val left = (started + ringMaxMs() - System.currentTimeMillis()).coerceAtLeast(1_000L)
            val delete =
                PendingIntent.getBroadcast(
                    ctx,
                    RingIntents.REQ_BACKUP_DELETE,
                    Intent(ctx, BackupRingReceiver::class.java).setAction(BackupRingReceiver.ACTION).putExtra(RingIntents.EXTRA_TRIP_ID, trip),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
            val n =
                RingNotificationBuilder.build(ctx, AlarmChannels.BACKUP, trip, content, adoptStart = s)
                    .setOnlyAlertOnce(already)
                    .setTimeoutAfter(left)
                    .setDeleteIntent(delete)
                    .build()
            n.flags = n.flags or Notification.FLAG_INSISTENT
            m.notify(trip, ID_BACKUP, n)
            true
        } catch (e: Exception) {
            Log.w(TAG, "backup ring failed (${e.javaClass.simpleName})")
            false
        }
    }

    fun cancel(tripId: String) {
        try {
            nm?.cancel(tripId, ID_BACKUP)
        } catch (e: Exception) {
            Log.w(TAG, "backup cancel failed (${e.javaClass.simpleName})")
        }
    }

    fun showing(tripId: String): Boolean =
        try {
            nm?.activeNotifications?.any { it.id == ID_BACKUP && it.tag == tripId } ?: false
        } catch (e: Exception) {
            false
        }

    companion object {
        const val ID_BACKUP = 1203
        private const val TAG = "NapStopAlarm"
    }
}

/** Common look of the alarm notifications 1202 (FGS) and 1203 (backup), spec T16 §5.9. */
object RingNotificationBuilder {
    /** [adoptStart]: the backup ring's request, handed to AlarmActivity so the adopted ring keeps its copy and settings. */
    fun build(ctx: Context, channel: String, tripId: String, content: RingContent, adoptStart: RingStart? = null): NotificationCompat.Builder {
        val dest = content.title?.let { mapOf(CopyKeys.DESTINATION to it) } ?: emptyMap()
        val titleKey = if (content.variant == RingVariant.OVERSHOOT) CopyKeys.REASON_OVERSHOOT else CopyKeys.NOTIF_ALARM_TITLE
        val title = RingStrings.text(ctx, CopyLine(titleKey, dest))
        val body = RingStrings.text(ctx, content.subtitle)
        val activity =
            PendingIntent.getActivity(
                ctx,
                if (adoptStart != null) RingIntents.REQ_BACKUP_ADOPT else RingIntents.REQ_ACTIVITY,
                RingIntents.activity(ctx, tripId).also { i -> adoptStart?.let { i.putExtra(RingIntents.EXTRA_RING_START, RingIntents.toBundle(it)) } },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        val publicVersion =
            NotificationCompat.Builder(ctx, channel)
                .setSmallIcon(R.drawable.ic_stat_napstop)
                .setContentTitle(ctx.getString(R.string.notif_alarm_public))
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .build()
        val b =
            NotificationCompat.Builder(ctx, channel)
                .setSmallIcon(R.drawable.ic_stat_napstop)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
                .setPublicVersion(publicVersion)
                .setOngoing(true)
                .setFullScreenIntent(activity, true)
                .setContentIntent(activity)
        if (content.snoozeLabel != null) {
            // atWallMs is taken when the tap arrives (RingIntents.parseCommand), not when the notification was built.
            val snooze =
                PendingIntent.getBroadcast(
                    ctx,
                    RingIntents.REQ_SNOOZE,
                    Intent(ctx, RingCommandReceiver::class.java)
                        .setAction(RingIntents.ACTION_RING_COMMAND)
                        .putExtra(RingIntents.EXTRA_TRIP_ID, tripId)
                        .putExtra(RingIntents.EXTRA_CMD, RingIntents.CMD_SNOOZE),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
            b.addAction(0, ctx.getString(R.string.notif_action_snooze), snooze)
        }
        return b
    }
}
