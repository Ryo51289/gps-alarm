package app.napstop.core.alarm

import android.content.Context
import app.napstop.R

/**
 * [CopyLine] (ARB key + named args, pure) → text from res/values{,-en}/strings.xml (T16 §9). Strings come from the
 * Context of the calling process, so a per-app language (T28) applies in `:ring` too. A missing `destination` = the
 * unknown-destination word.
 */
object RingStrings {
    private val IDS: Map<String, Int> =
        mapOf(
            CopyKeys.NOTIF_ALARM_TITLE to R.string.notif_alarm_title,
            CopyKeys.REASON_DISTANCE to R.string.alarm_reason_distance,
            CopyKeys.REASON_TIME to R.string.alarm_reason_time,
            CopyKeys.REASON_GPS_LOST to R.string.alarm_reason_gps_lost,
            CopyKeys.REASON_LOW_BATTERY to R.string.alarm_reason_low_battery,
            CopyKeys.REASON_PASSED_CLOSEST to R.string.alarm_reason_passed_closest,
            CopyKeys.REASON_OVERSHOOT to R.string.alarm_reason_overshoot,
            CopyKeys.REASON_SNOOZE_END to R.string.alarm_reason_snooze_end,
            CopyKeys.REASON_TIMEOUT to R.string.alarm_reason_timeout,
            CopyKeys.REASON_FALLBACK to R.string.alarm_reason_fallback,
            CopyKeys.REASON_FALLBACK_MISSED to R.string.alarm_reason_fallback_missed,
            CopyKeys.OVERSHOOT_PAST to R.string.alarm_overshoot_past,
            CopyKeys.SNOOZE_MINUTES to R.string.alarm_snooze_minutes,
            CopyKeys.SNOOZE_SECONDS to R.string.alarm_snooze_seconds,
            CopyKeys.PRE_ALERT_BODY to R.string.prealert_body,
            CopyKeys.PRE_ALERT_BODY_DISTANCE to R.string.prealert_body_distance,
            RingSessionMachine.BANNER_HEADPHONES_UNPLUGGED to R.string.alarm_headphones_unplugged,
        )

    fun text(ctx: Context, line: CopyLine): String {
        val id = IDS[line.key] ?: return ""
        val order = CopyKeys.PLACEHOLDERS[line.key] ?: emptyList()
        if (order.isEmpty()) return ctx.getString(id)
        val args = order.map { name -> line.args[name] ?: if (name == CopyKeys.DESTINATION) destinationUnknown(ctx) else "" }
        return ctx.getString(id, *args.toTypedArray())
    }

    fun key(ctx: Context, key: String): String = IDS[key]?.let { ctx.getString(it) } ?: ""

    fun title(ctx: Context, content: RingContent): String = content.title ?: destinationUnknown(ctx)

    fun destinationUnknown(ctx: Context): String = ctx.getString(R.string.notif_destination_unknown)
}
