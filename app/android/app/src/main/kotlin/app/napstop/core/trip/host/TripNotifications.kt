package app.napstop.core.trip.host

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.text.format.DateFormat
import android.util.Log
import androidx.core.app.NotificationCompat
import app.napstop.MainActivity
import app.napstop.R
import app.napstop.core.alarm.AppLocale
import app.napstop.core.trip.runtime.NoticeFormatter
import app.napstop.core.trip.runtime.NoticeTemplates
import app.napstop.core.trip.runtime.TrackingNotice
import app.napstop.core.trip.runtime.TripNotice
import app.napstop.core.trip.runtime.TripNotifier
import java.util.Date
import java.util.Locale

/**
 * Notification channels and notifications of a trip (spec T15 §5.10, D15). The ongoing one belongs to LocationService
 * (id [ID_TRACKING], channel `napstop_tracking`, LOW); alerts go to `napstop_trip_alerts` (HIGH) with tag = tripId.
 * Copy only from strings.xml (= ARB keys, §8). Lock screen: VISIBILITY_PRIVATE with a public version without the
 * destination name. Missing POST_NOTIFICATIONS: posting fails quietly, the trip goes on (PRD §3.1). Strings and number /
 * time formats follow the app language ([AppLocale], T28); a change shows at the next update of the ongoing notification.
 */
class TripNotifications(context: Context) : TripNotifier {
    private val ctx = context.applicationContext
    private val nm: NotificationManager? get() = ctx.getSystemService(NotificationManager::class.java)

    /**
     * Display strings in the app language, read on each use (the language may change during a trip). Never reads the disk:
     * often called on the main thread (LocationService); before the first read finishes it is the device language.
     */
    private val res: Context get() = AppLocale.localizedWith(ctx, AppLocale.tagNow(ctx))

    /**
     * Creates the channels; renames them to the app language once it is known (T28 D10). Before that only missing channels
     * are created, so a device-language name never overwrites the chosen one ([AppLocale.refreshChannels] renames them).
     */
    fun ensureChannels() {
        val m = nm ?: return
        val rename = AppLocale.isLoaded
        val res = res
        fun create(channel: NotificationChannel) {
            if (rename || m.getNotificationChannel(channel.id) == null) m.createNotificationChannel(channel)
        }
        create(
            NotificationChannel(CHANNEL_TRACKING, res.getString(R.string.notif_channel_tracking), NotificationManager.IMPORTANCE_LOW).apply {
                setShowBadge(false)
            },
        )
        create(NotificationChannel(CHANNEL_ALERTS, res.getString(R.string.notif_channel_trip_alerts), NotificationManager.IMPORTANCE_HIGH))
    }

    fun templates(): NoticeTemplates {
        val res = res
        return NoticeTemplates(
            title = res.getString(R.string.notif_tracking_title),
            acquiring = res.getString(R.string.notif_tracking_acquiring),
            distanceEta = res.getString(R.string.notif_tracking_distance_eta),
            distance = res.getString(R.string.notif_tracking_distance),
            estimating = res.getString(R.string.notif_tracking_estimating),
            alarming = res.getString(R.string.notif_tracking_alarming),
            snoozed = res.getString(R.string.notif_tracking_snoozed),
            destinationUnknown = res.getString(R.string.notif_destination_unknown),
            simTitle = res.getString(R.string.notif_tracking_sim_title),
        )
    }

    fun locale(): Locale = AppLocale.localeWith(ctx, AppLocale.tagNow(ctx))

    /** The ongoing notification; [content] null = the first one, before the runtime committed the trip. */
    fun tracking(content: TrackingNotice?): Notification {
        ensureChannels()
        val t = templates()
        val title = content?.let { NoticeFormatter.title(it.destinationName, t, it.simulated) } ?: res.getString(R.string.notif_tracking_public)
        val body =
            content?.let { NoticeFormatter.body(it, t, locale()) { ms -> DateFormat.getTimeFormat(res).format(Date(ms)) } }
                ?: t.acquiring
        val publicVersion =
            NotificationCompat.Builder(ctx, CHANNEL_TRACKING)
                .setSmallIcon(R.drawable.ic_stat_napstop)
                .setContentTitle(res.getString(R.string.notif_tracking_public))
                .build()
        val b =
            NotificationCompat.Builder(ctx, CHANNEL_TRACKING)
                .setSmallIcon(R.drawable.ic_stat_napstop)
                .setContentTitle(title)
                .setContentText(body)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setSilent(true)
                .setCategory(NotificationCompat.CATEGORY_NAVIGATION)
                .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
                .setPublicVersion(publicVersion)
                .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
                .setContentIntent(openAppIntent(ctx, REQ_OPEN, resumeTripId = null))
        content?.let { b.addAction(0, res.getString(R.string.notif_action_stop), stopIntent(it.tripId)) }
        return b.build()
    }

    fun updateTracking(content: TrackingNotice) {
        post(null, ID_TRACKING) { tracking(content) }
    }

    override fun show(tripId: String, notice: TripNotice, destinationName: String?, alert: Boolean) {
        ensureChannels()
        post(tripId, idOf(notice)) {
            val b =
                NotificationCompat.Builder(ctx, CHANNEL_ALERTS)
                    .setSmallIcon(R.drawable.ic_stat_napstop)
                    .setPriority(NotificationCompat.PRIORITY_HIGH)
                    .setCategory(NotificationCompat.CATEGORY_STATUS)
                    .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
                    .setAutoCancel(notice != TripNotice.Interrupted)
                    // Re-posting a notice that is still shown never alerts again; a silent post never alerts (R2-3).
                    .setOnlyAlertOnce(true)
                    .setSilent(!alert)
            when (notice) {
                TripNotice.Interrupted -> {
                    b.setContentTitle(res.getString(R.string.notif_interrupted_title))
                        .setContentText(res.getString(R.string.notif_interrupted_body))
                        .setContentIntent(openAppIntent(ctx, REQ_RESUME, resumeTripId = tripId))
                        .addAction(0, res.getString(R.string.notif_action_stop), stopIntent(tripId))
                }
                else -> {
                    val text = res.getString(textOf(notice))
                    b.setContentTitle(text).setStyle(NotificationCompat.BigTextStyle().bigText(text))
                        .setContentIntent(openAppIntent(ctx, REQ_OPEN, resumeTripId = null))
                }
            }
            b.build()
        }
    }

    override fun clear(tripId: String, notice: TripNotice) {
        try {
            nm?.cancel(tripId, idOf(notice))
        } catch (e: Exception) {
            Log.w(TAG, "notification cancel failed (${e.javaClass.simpleName})")
        }
    }

    override fun clearAll(tripId: String) {
        for (n in ALL) clear(tripId, n)
    }

    private fun post(tag: String?, id: Int, build: () -> Notification) {
        try {
            nm?.notify(tag, id, build())
        } catch (e: Exception) {
            // SecurityException without POST_NOTIFICATIONS (Android 13+): the trip goes on.
            Log.w(TAG, "notification failed (${e.javaClass.simpleName})")
        }
    }

    private fun stopIntent(tripId: String): PendingIntent =
        PendingIntent.getBroadcast(
            ctx,
            REQ_STOP,
            Intent(ctx, TripActionReceiver::class.java).setAction(TripActionReceiver.ACTION_STOP).putExtra(TripActionReceiver.EXTRA_TRIP_ID, tripId),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    companion object {
        private const val TAG = "NapStopRuntime"
        const val CHANNEL_TRACKING = "napstop_tracking"
        const val CHANNEL_ALERTS = "napstop_trip_alerts"
        const val ID_TRACKING = 1001
        const val ID_NO_GPS = 1101
        const val ID_PERMISSION = 1102
        const val ID_SERVICES_OFF = 1103
        const val ID_FALLBACK_FAILED = 1104
        const val ID_INTERRUPTED = 1105
        const val ID_PRE_ALERT = 1106

        /** MainActivity extra of the "interrupted" notification (spec T15 §5.8, D11). */
        const val EXTRA_RESUME_TRIP_ID = "napstop.resumeTripId"
        private const val REQ_OPEN = 0x4E5730
        private const val REQ_RESUME = 0x4E5731
        private const val REQ_STOP = 0x4E5732
        private val ALL = listOf(TripNotice.NoGpsYet, TripNotice.PermissionRevoked, TripNotice.ServicesOff, TripNotice.FallbackFailed, TripNotice.Interrupted)

        fun idOf(n: TripNotice): Int =
            when (n) {
                TripNotice.NoGpsYet -> ID_NO_GPS
                TripNotice.PermissionRevoked -> ID_PERMISSION
                TripNotice.ServicesOff -> ID_SERVICES_OFF
                TripNotice.FallbackFailed -> ID_FALLBACK_FAILED
                TripNotice.Interrupted -> ID_INTERRUPTED
            }

        private fun textOf(n: TripNotice): Int =
            when (n) {
                TripNotice.NoGpsYet -> R.string.gps_not_acquired
                TripNotice.PermissionRevoked -> R.string.gps_permission_revoked
                TripNotice.ServicesOff -> R.string.gps_services_off
                TripNotice.FallbackFailed -> R.string.fallback_schedule_failed
                TripNotice.Interrupted -> R.string.notif_interrupted_title
            }

        /** Opens MainActivity (single top); with [resumeTripId] the activity resumes a HEADLESS trip (D11). */
        fun openAppIntent(context: Context, requestCode: Int, resumeTripId: String?): PendingIntent {
            val i =
                Intent(context, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            resumeTripId?.let { i.putExtra(EXTRA_RESUME_TRIP_ID, it) }
            return PendingIntent.getActivity(context, requestCode, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
    }
}
