package app.napstop.core.alarm

import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.runtime.NoticeFormatter
import java.util.Locale
import kotlin.math.ceil

enum class RingVariant { ARRIVING, OVERSHOOT }

/**
 * One line of copy: an ARB key (T16 §9; Android maps it to res/values strings) and its named arguments. A missing
 * `destination` argument means "unknown destination" (`notifDestinationUnknown`, filled in by the platform).
 */
data class CopyLine(val key: String, val args: Map<String, String> = emptyMap()) {
    override fun toString(): String = "CopyLine(key=$key)"
}

/** What the alarm screen and the alarm notification show. `title` = destinationName (null → notifDestinationUnknown). */
data class RingContent(
    val variant: RingVariant,
    val title: String?,
    val subtitle: CopyLine,
    val pastLine: CopyLine?,
    /** null when the ring cannot be snoozed. */
    val snoozeLabel: CopyLine?,
) {
    override fun toString(): String = "RingContent(variant=$variant, subtitle=${subtitle.key})"
}

/** ARB keys of the native alarm copy and the order of their placeholders (= Android `%1$s`, `%2$s`…). */
object CopyKeys {
    const val NOTIF_ALARM_TITLE = "notifAlarmTitle"
    const val REASON_DISTANCE = "alarmReasonDistance"
    const val REASON_TIME = "alarmReasonTime"
    const val REASON_GPS_LOST = "alarmReasonGpsLost"
    const val REASON_LOW_BATTERY = "alarmReasonLowBattery"
    const val REASON_PASSED_CLOSEST = "alarmReasonPassedClosest"
    const val REASON_OVERSHOOT = "alarmReasonOvershoot"
    const val REASON_SNOOZE_END = "alarmReasonSnoozeEnd"
    const val REASON_TIMEOUT = "alarmReasonTimeout"
    const val REASON_FALLBACK = "alarmReasonFallback"
    const val REASON_FALLBACK_MISSED = "alarmReasonFallbackMissed"
    const val OVERSHOOT_PAST = "alarmOvershootPast"
    const val SNOOZE_MINUTES = "alarmSnoozeMinutes"
    const val SNOOZE_SECONDS = "alarmSnoozeSeconds"
    const val PRE_ALERT_BODY = "preAlertBody"
    const val PRE_ALERT_BODY_DISTANCE = "preAlertBodyDistance"

    const val DESTINATION = "destination"
    const val DISTANCE = "distance"
    const val MINUTES = "minutes"
    const val SECONDS = "seconds"
    const val PERCENT = "percent"

    /** Placeholder order per key, as in app_vi.arb (the en text keeps the same order; NativeStringsParityTest). */
    val PLACEHOLDERS: Map<String, List<String>> =
        mapOf(
            NOTIF_ALARM_TITLE to listOf(DESTINATION),
            REASON_DISTANCE to listOf(DISTANCE, DESTINATION),
            REASON_TIME to listOf(MINUTES, DESTINATION),
            REASON_GPS_LOST to listOf(DESTINATION),
            REASON_LOW_BATTERY to listOf(PERCENT),
            REASON_PASSED_CLOSEST to listOf(DESTINATION),
            REASON_OVERSHOOT to listOf(DESTINATION),
            REASON_SNOOZE_END to listOf(DESTINATION),
            REASON_TIMEOUT to listOf(DESTINATION),
            REASON_FALLBACK to listOf(DESTINATION),
            REASON_FALLBACK_MISSED to listOf(DESTINATION),
            OVERSHOOT_PAST to listOf(DISTANCE),
            SNOOZE_MINUTES to listOf(MINUTES),
            SNOOZE_SECONDS to listOf(SECONDS),
            PRE_ALERT_BODY to listOf(DESTINATION, MINUTES),
            PRE_ALERT_BODY_DISTANCE to listOf(DESTINATION, DISTANCE),
        )
}

/** Copy of the alarm screen / notification (spec T16 §9, T10 §10). Pure. */
object RingCopy {
    fun variant(r: RingRequest, overshootPastM: Int?): RingVariant =
        if (overshootPastM != null || r.reason == AlarmReason.OVERSHOOT) RingVariant.OVERSHOOT else RingVariant.ARRIVING

    /** The snooze button is shown (and honoured) only when the engine allows it and the ring is not the overshoot one. */
    fun snoozeShown(r: RingRequest, overshootPastM: Int?): Boolean = r.snoozeAllowed && variant(r, overshootPastM) == RingVariant.ARRIVING

    fun content(r: RingRequest, overshootPastM: Int?, snoozeS: Int, locale: Locale): RingContent {
        val v = variant(r, overshootPastM)
        val dest = destArgs(r.destinationName)
        val subtitle = if (v == RingVariant.OVERSHOOT) CopyLine(CopyKeys.REASON_OVERSHOOT, dest) else reasonLine(r, dest, locale)
        val past = overshootPastM?.let { CopyLine(CopyKeys.OVERSHOOT_PAST, mapOf(CopyKeys.DISTANCE to distance(it, locale))) }
        return RingContent(
            variant = v,
            title = r.destinationName,
            subtitle = subtitle,
            pastLine = if (v == RingVariant.OVERSHOOT) past else null,
            snoozeLabel = if (snoozeShown(r, overshootPastM)) SnoozeLabel.of(snoozeS) else null,
        )
    }

    /** Pre-alert body (T10 §10): distance copy in DISTANCE mode, minutes otherwise (distance when the ETA is unknown). */
    fun preAlert(r: PreAlertRequest, locale: Locale): CopyLine {
        val dest = destArgs(r.destinationName)
        val eta = r.etaS
        return if (r.byDistance || eta == null) {
            CopyLine(CopyKeys.PRE_ALERT_BODY_DISTANCE, dest + (CopyKeys.DISTANCE to distance(r.distanceM, locale)))
        } else {
            CopyLine(CopyKeys.PRE_ALERT_BODY, dest + (CopyKeys.MINUTES to minutes(eta).toString()))
        }
    }

    /** max(1, ceil(etaS / 60)). */
    fun minutes(etaS: Int): Int = maxOf(1, ceil(etaS.coerceAtLeast(0) / 60.0).toInt())

    fun distance(m: Int, locale: Locale): String = NoticeFormatter.distance(m.toDouble(), locale)

    private fun destArgs(name: String?): Map<String, String> = if (name == null) emptyMap() else mapOf(CopyKeys.DESTINATION to name)

    private fun reasonLine(r: RingRequest, dest: Map<String, String>, locale: Locale): CopyLine {
        val generic = CopyLine(CopyKeys.NOTIF_ALARM_TITLE, dest)
        return when (r.reason) {
            null -> if (r.source == RingSource.FALLBACK) CopyLine(CopyKeys.REASON_FALLBACK, dest) else generic
            AlarmReason.DISTANCE, AlarmReason.SMART_DISTANCE, AlarmReason.SMART_SLOW_DISTANCE ->
                r.distanceM?.let { CopyLine(CopyKeys.REASON_DISTANCE, dest + (CopyKeys.DISTANCE to distance(it, locale))) } ?: generic
            AlarmReason.TIME, AlarmReason.SMART_TIME ->
                r.etaS?.let { CopyLine(CopyKeys.REASON_TIME, dest + (CopyKeys.MINUTES to minutes(it).toString())) } ?: generic
            AlarmReason.GPS_LOST -> CopyLine(CopyKeys.REASON_GPS_LOST, dest)
            AlarmReason.LOW_BATTERY ->
                r.batteryPct?.let { CopyLine(CopyKeys.REASON_LOW_BATTERY, mapOf(CopyKeys.PERCENT to it.toString())) } ?: generic
            AlarmReason.PASSED_CLOSEST -> CopyLine(CopyKeys.REASON_PASSED_CLOSEST, dest)
            AlarmReason.OVERSHOOT -> CopyLine(CopyKeys.REASON_OVERSHOOT, dest)
            AlarmReason.SNOOZE_END -> CopyLine(CopyKeys.REASON_SNOOZE_END, dest)
            AlarmReason.TIMEOUT -> CopyLine(CopyKeys.REASON_TIMEOUT, dest)
            AlarmReason.FALLBACK -> CopyLine(CopyKeys.REASON_FALLBACK, dest)
            AlarmReason.FALLBACK_MISSED -> CopyLine(CopyKeys.REASON_FALLBACK_MISSED, dest)
        }
    }
}

/** Snooze button label: whole minutes → alarmSnoozeMinutes, otherwise alarmSnoozeSeconds. */
object SnoozeLabel {
    fun of(snoozeS: Int): CopyLine =
        if (snoozeS > 0 && snoozeS % 60 == 0) {
            CopyLine(CopyKeys.SNOOZE_MINUTES, mapOf(CopyKeys.MINUTES to (snoozeS / 60).toString()))
        } else {
            CopyLine(CopyKeys.SNOOZE_SECONDS, mapOf(CopyKeys.SECONDS to snoozeS.toString()))
        }
}
