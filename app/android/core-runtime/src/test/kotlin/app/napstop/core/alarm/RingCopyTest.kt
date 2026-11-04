package app.napstop.core.alarm

import app.napstop.core.alarm.AlarmData.request
import app.napstop.core.trip.AlarmReason
import java.util.Locale
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/** T16 A21 (copy per reason), A22 (snooze label), pre-alert copy (A36/A43 side). */
class RingCopyTest {
    private val vi = Locale.forLanguageTag("vi-VN")
    private val en = Locale.ENGLISH

    private fun line(r: RingRequest, l: Locale = vi) = RingCopy.content(r, null, 60, l).subtitle

    @Test
    fun a21_reasonKeys() {
        val want =
            mapOf(
                AlarmReason.DISTANCE to CopyKeys.REASON_DISTANCE,
                AlarmReason.SMART_DISTANCE to CopyKeys.REASON_DISTANCE,
                AlarmReason.SMART_SLOW_DISTANCE to CopyKeys.REASON_DISTANCE,
                AlarmReason.TIME to CopyKeys.REASON_TIME,
                AlarmReason.SMART_TIME to CopyKeys.REASON_TIME,
                AlarmReason.GPS_LOST to CopyKeys.REASON_GPS_LOST,
                AlarmReason.LOW_BATTERY to CopyKeys.REASON_LOW_BATTERY,
                AlarmReason.PASSED_CLOSEST to CopyKeys.REASON_PASSED_CLOSEST,
                AlarmReason.OVERSHOOT to CopyKeys.REASON_OVERSHOOT,
                AlarmReason.SNOOZE_END to CopyKeys.REASON_SNOOZE_END,
                AlarmReason.TIMEOUT to CopyKeys.REASON_TIMEOUT,
                AlarmReason.FALLBACK to CopyKeys.REASON_FALLBACK,
                AlarmReason.FALLBACK_MISSED to CopyKeys.REASON_FALLBACK_MISSED,
            )
        assertEquals(AlarmReason.entries.toSet(), want.keys)
        for ((reason, key) in want) assertEquals(key, line(request(reason = reason)).key, "$reason")
        assertEquals(CopyKeys.REASON_FALLBACK, line(request(source = RingSource.FALLBACK, reason = null)).key)
        assertEquals(CopyKeys.NOTIF_ALARM_TITLE, line(request(source = RingSource.ENGINE, reason = null)).key)
        // Numbers missing → the key without a number.
        assertEquals(CopyKeys.NOTIF_ALARM_TITLE, line(request(reason = AlarmReason.DISTANCE, distanceM = null)).key)
        assertEquals(CopyKeys.NOTIF_ALARM_TITLE, line(request(reason = AlarmReason.TIME, etaS = null)).key)
        assertEquals(CopyKeys.NOTIF_ALARM_TITLE, line(request(reason = AlarmReason.LOW_BATTERY, batteryPct = null)).key)
        // Arguments.
        assertEquals(mapOf("destination" to AlarmData.DEST, "distance" to "1,2 km"), line(request(distanceM = 1_200)).args)
        assertEquals("1.2 km", line(request(distanceM = 1_200), en).args["distance"])
        assertEquals("3", line(request(reason = AlarmReason.TIME, etaS = 130)).args["minutes"]) // ceil(130 / 60)
        assertEquals("1", line(request(reason = AlarmReason.TIME, etaS = 5)).args["minutes"])
        assertEquals("1", line(request(reason = AlarmReason.TIME, etaS = 0)).args["minutes"])
        assertEquals(mapOf("percent" to "12"), line(request(reason = AlarmReason.LOW_BATTERY)).args)
        // Unknown destination: no destination argument (the platform fills in notifDestinationUnknown).
        val unknown = RingCopy.content(request(destinationName = null), null, 60, vi)
        assertNull(unknown.title)
        assertNull(unknown.subtitle.args["destination"])
        // Overshoot variant.
        val o = RingCopy.content(request(), 1_500, 60, vi)
        assertEquals(RingVariant.OVERSHOOT, o.variant)
        assertEquals(CopyKeys.REASON_OVERSHOOT, o.subtitle.key)
        assertEquals(CopyLine(CopyKeys.OVERSHOOT_PAST, mapOf("distance" to "1,5 km")), o.pastLine)
        assertNull(o.snoozeLabel)
        val a = RingCopy.content(request(), null, 60, vi)
        assertEquals(RingVariant.ARRIVING, a.variant)
        assertNull(a.pastLine)
        assertEquals(SnoozeLabel.of(60), a.snoozeLabel)
        assertNull(RingCopy.content(request(snoozeAllowed = false), null, 60, vi).snoozeLabel)
    }

    @Test
    fun a22_snoozeLabel() {
        assertEquals(CopyLine(CopyKeys.SNOOZE_SECONDS, mapOf("seconds" to "30")), SnoozeLabel.of(30))
        assertEquals(CopyLine(CopyKeys.SNOOZE_MINUTES, mapOf("minutes" to "1")), SnoozeLabel.of(60))
        assertEquals(CopyLine(CopyKeys.SNOOZE_SECONDS, mapOf("seconds" to "90")), SnoozeLabel.of(90))
        assertEquals(CopyLine(CopyKeys.SNOOZE_MINUTES, mapOf("minutes" to "2")), SnoozeLabel.of(120))
        assertEquals(CopyLine(CopyKeys.SNOOZE_MINUTES, mapOf("minutes" to "10")), SnoozeLabel.of(600))
    }

    @Test
    fun preAlertCopy() {
        val d = RingCopy.preAlert(PreAlertRequest("t1", 3_000, 600, "Ga Huế", byDistance = true), vi)
        assertEquals(CopyLine(CopyKeys.PRE_ALERT_BODY_DISTANCE, mapOf("destination" to "Ga Huế", "distance" to "3 km")), d)
        val m = RingCopy.preAlert(PreAlertRequest("t1", 3_000, 600, "Ga Huế", byDistance = false), vi)
        assertEquals(CopyLine(CopyKeys.PRE_ALERT_BODY, mapOf("destination" to "Ga Huế", "minutes" to "10")), m)
        assertEquals(CopyKeys.PRE_ALERT_BODY_DISTANCE, RingCopy.preAlert(PreAlertRequest("t1", 3_000, null, null), vi).key)
    }

    @Test
    fun everyKeyHasAPlaceholderOrder() {
        for (k in listOf(CopyKeys.NOTIF_ALARM_TITLE, CopyKeys.REASON_LOW_BATTERY, CopyKeys.OVERSHOOT_PAST, CopyKeys.PRE_ALERT_BODY)) {
            assertEquals(true, CopyKeys.PLACEHOLDERS.containsKey(k), k)
        }
    }
}
