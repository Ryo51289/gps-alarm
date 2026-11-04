package app.napstop.core.alarm

import android.content.ContentResolver
import android.content.Context
import android.media.RingtoneManager
import android.net.Uri
import app.napstop.R

/** Sound sources of a ring, in the order they are tried (spec T16 §5.6, RK-T16-13). */
object RingSounds {
    private val RAW: Map<String, Int> =
        mapOf(
            "alarm_horn" to R.raw.alarm_horn,
            "alarm_bell" to R.raw.alarm_bell,
            "alarm_beep" to R.raw.alarm_beep,
        )

    fun rawUri(ctx: Context, rawName: String): Uri? =
        RAW[rawName]?.let {
            Uri.Builder().scheme(ContentResolver.SCHEME_ANDROID_RESOURCE).authority(ctx.packageName).appendPath(it.toString()).build()
        }

    /** raw "alarm_<id>" → device alarm sound → raw "alarm_horn" → ringtone → notification sound (null entries dropped). */
    fun sourceChain(ctx: Context, soundId: String): List<Uri> {
        val id = AlarmSounds.resolve(soundId)
        val out = ArrayList<Uri?>()
        AlarmSounds.rawName(id)?.let { out += rawUri(ctx, it) }
        out += systemUri(ctx, RingtoneManager.TYPE_ALARM)
        out += rawUri(ctx, AlarmSounds.rawName(AlarmSounds.HORN)!!)
        out += systemUri(ctx, RingtoneManager.TYPE_RINGTONE)
        out += systemUri(ctx, RingtoneManager.TYPE_NOTIFICATION)
        return out.filterNotNull().distinct()
    }

    private fun systemUri(ctx: Context, type: Int): Uri? =
        try {
            RingtoneManager.getActualDefaultRingtoneUri(ctx, type)
        } catch (e: Exception) {
            null
        }
}
