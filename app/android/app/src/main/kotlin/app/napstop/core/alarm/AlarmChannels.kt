package app.napstop.core.alarm

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentResolver
import android.content.Context
import android.media.AudioAttributes
import android.net.Uri
import android.util.Log
import app.napstop.R

/** Notification channels of the alarm (spec T16 §5.9). Idempotent; called in both processes. */
object AlarmChannels {
    const val ALARM = "napstop_alarm"
    const val BACKUP = "napstop_alarm_backup"
    const val PRE_ALERT = "napstop_prealert"

    /** The T15 interim channel: deleted on every ensure (AE6). */
    const val INTERIM_REMOVED = "napstop_alarm_interim"

    private const val TAG = "NapStopAlarm"

    fun ensure(context: Context) {
        val ctx = context.applicationContext
        val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
        try {
            nm.deleteNotificationChannel(INTERIM_REMOVED)
            // The ring service plays its own sound and vibration: the channel stays silent.
            nm.createNotificationChannel(
                NotificationChannel(ALARM, ctx.getString(R.string.notif_channel_alarm), NotificationManager.IMPORTANCE_HIGH).apply {
                    setSound(null, null)
                    enableVibration(false)
                    setShowBadge(false)
                    lockscreenVisibility = android.app.Notification.VISIBILITY_PRIVATE
                },
            )
            nm.createNotificationChannel(
                NotificationChannel(BACKUP, ctx.getString(R.string.notif_channel_alarm_backup), NotificationManager.IMPORTANCE_HIGH).apply {
                    setSound(backupSoundUri(ctx), alarmAttributes())
                    enableVibration(true)
                    vibrationPattern = VibrationPatterns.STRONG.timingsMs
                    setShowBadge(false)
                },
            )
            nm.createNotificationChannel(
                NotificationChannel(PRE_ALERT, ctx.getString(R.string.notif_channel_prealert), NotificationManager.IMPORTANCE_DEFAULT).apply {
                    setSound(null, null)
                    enableVibration(true)
                    vibrationPattern = VibrationPatterns.PRE_ALERT
                },
            )
        } catch (e: Exception) {
            Log.w(TAG, "alarm channels failed (${e.javaClass.simpleName})")
        }
    }

    fun backupSoundUri(ctx: Context): Uri =
        Uri.Builder().scheme(ContentResolver.SCHEME_ANDROID_RESOURCE).authority(ctx.packageName)
            .appendPath("raw").appendPath(AlarmSounds.rawName(AlarmSounds.HORN)!!).build()

    fun alarmAttributes(usage: Int = AudioAttributes.USAGE_ALARM): AudioAttributes =
        AudioAttributes.Builder().setUsage(usage).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
}
