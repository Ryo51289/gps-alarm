package app.napstop.core.trip.host

import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element

/**
 * T15 L33 (spec §8): native notification strings equal their ARB keys, vi (source) and en, after mapping the ARB
 * placeholders `{name}` to `%1$s`, `%2$s`… in order of appearance. A missing key on either side fails.
 */
class NativeStringsParityTest {
    private val pairs =
        listOf(
            "notifChannelTracking" to "notif_channel_tracking",
            "notifChannelTripAlerts" to "notif_channel_trip_alerts",
            "notifTrackingTitle" to "notif_tracking_title",
            // T18 SM33.
            "notifTrackingSimTitle" to "notif_tracking_sim_title",
            "notifTrackingPublic" to "notif_tracking_public",
            "notifTrackingAcquiring" to "notif_tracking_acquiring",
            "notifTrackingDistanceEta" to "notif_tracking_distance_eta",
            "notifTrackingDistance" to "notif_tracking_distance",
            "notifTrackingEstimating" to "notif_tracking_estimating",
            "notifTrackingAlarming" to "notif_tracking_alarming",
            "notifTrackingSnoozed" to "notif_tracking_snoozed",
            "notifActionStop" to "notif_action_stop",
            "notifInterruptedTitle" to "notif_interrupted_title",
            "notifInterruptedBody" to "notif_interrupted_body",
            "gpsNotAcquired" to "gps_not_acquired",
            "gpsPermissionRevoked" to "gps_permission_revoked",
            "gpsServicesOff" to "gps_services_off",
            "fallbackScheduleFailed" to "fallback_schedule_failed",
            "alarmReasonFallback" to "alarm_reason_fallback",
            "notifActionSnooze" to "notif_action_snooze",
            "notifDestinationUnknown" to "notif_destination_unknown",
            // T16 §9 (AA2): native alarm copy.
            "notifChannelAlarm" to "notif_channel_alarm",
            "notifChannelAlarmBackup" to "notif_channel_alarm_backup",
            "notifChannelPreAlert" to "notif_channel_prealert",
            "notifAlarmTitle" to "notif_alarm_title",
            "notifAlarmPublic" to "notif_alarm_public",
            "alarmReasonDistance" to "alarm_reason_distance",
            "alarmReasonTime" to "alarm_reason_time",
            "alarmReasonGpsLost" to "alarm_reason_gps_lost",
            "alarmReasonLowBattery" to "alarm_reason_low_battery",
            "alarmReasonPassedClosest" to "alarm_reason_passed_closest",
            "alarmReasonOvershoot" to "alarm_reason_overshoot",
            "alarmReasonSnoozeEnd" to "alarm_reason_snooze_end",
            "alarmReasonTimeout" to "alarm_reason_timeout",
            "alarmReasonFallbackMissed" to "alarm_reason_fallback_missed",
            "preAlertBody" to "prealert_body",
            "preAlertBodyDistance" to "prealert_body_distance",
            "alarmOverlineArriving" to "alarm_overline_arriving",
            "alarmOverlineOvershoot" to "alarm_overline_overshoot",
            "alarmOvershootPast" to "alarm_overshoot_past",
            "alarmRouteBack" to "alarm_route_back",
            "alarmSwipeHint" to "alarm_swipe_hint",
            "alarmShakeHint" to "alarm_shake_hint",
            "alarmShakeProgressA11y" to "alarm_shake_progress_a11y",
            "alarmMathHint" to "alarm_math_hint",
            "alarmMathWrong" to "alarm_math_wrong",
            "alarmMathConfirm" to "alarm_math_confirm",
            "alarmMathDelete" to "alarm_math_delete",
            "alarmStopA11y" to "alarm_stop_a11y",
            "alarmSnoozeMinutes" to "alarm_snooze_minutes",
            "alarmSnoozeSeconds" to "alarm_snooze_seconds",
            "alarmHeadphonesUnplugged" to "alarm_headphones_unplugged",
        )

    private val l10nDir = File(System.getProperty("napstop.l10nDir") ?: "../../lib/l10n")
    private val resDir = File("src/main/res")

    private fun arb(name: String): JSONObject = JSONObject(File(l10nDir, name).readText(Charsets.UTF_8))

    private fun strings(dir: String): Map<String, String> {
        val doc = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(File(resDir, "$dir/strings.xml"))
        val nodes = doc.getElementsByTagName("string")
        return (0 until nodes.length).associate { i ->
            val e = nodes.item(i) as Element
            e.getAttribute("name") to e.textContent.replace("\\'", "'").replace("\\\"", "\"")
        }
    }

    /** `{name}` → `%n$s` in order of appearance; with placeholders a literal `%` is `%%` (Android format string). */
    private fun toAndroid(arb: String): String {
        var n = 0
        val ph = Regex("\\{[A-Za-z]+\\}")
        val escaped = if (ph.containsMatchIn(arb)) arb.replace("%", "%%") else arb
        return ph.replace(escaped) { "%${++n}\$s" }
    }

    /** T16 AA2: the interim alarm of T15 is gone on both sides. */
    @Test
    fun aa2_removedKeysAreGoneOnBothSides() {
        val removed =
            listOf(
                "notifChannelAlarmInterim" to "notif_channel_alarm_interim",
                "notifAlarmInterimTitle" to "notif_alarm_interim_title",
                "notifActionDismiss" to "notif_action_dismiss",
            )
        for ((arbFile, dir) in listOf("app_vi.arb" to "values", "app_en.arb" to "values-en")) {
            val a = arb(arbFile)
            val s = strings(dir)
            for ((key, res) in removed) {
                assertTrue("$arbFile still has $key", !a.has(key) && !a.has("@$key"))
                assertTrue("$dir still has $res", !s.containsKey(res))
            }
        }
    }

    /** T16: the placeholder order the native code passes (CopyKeys.PLACEHOLDERS) is the order in both ARB files. */
    @Test
    fun aa2_placeholderOrderMatchesCopyKeys() {
        for (arbFile in listOf("app_vi.arb", "app_en.arb")) {
            val a = arb(arbFile)
            for ((key, order) in app.napstop.core.alarm.CopyKeys.PLACEHOLDERS) {
                val names = Regex("\\{([A-Za-z]+)\\}").findAll(a.getString(key)).map { it.groupValues[1] }.toList()
                assertEquals("$arbFile $key", order, names)
            }
        }
    }

    @Test
    fun l33_viAndEnMatchTheArbFiles() {
        for ((arbFile, dir) in listOf("app_vi.arb" to "values", "app_en.arb" to "values-en")) {
            val a = arb(arbFile)
            val s = strings(dir)
            for ((key, res) in pairs) {
                assertTrue("$arbFile has $key", a.has(key))
                assertTrue("$dir has $res", s.containsKey(res))
                assertEquals("$dir/$res", toAndroid(a.getString(key)), s[res])
            }
        }
    }

    @Test
    fun l33_placeholdersAreDeclaredInTheSourceArb() {
        val a = arb("app_vi.arb")
        for ((key, _) in pairs) {
            val names = Regex("\\{([A-Za-z]+)\\}").findAll(a.getString(key)).map { it.groupValues[1] }.toList()
            if (names.isEmpty()) continue
            val ph = a.getJSONObject("@$key").getJSONObject("placeholders")
            for (n in names) assertTrue("$key declares $n", ph.has(n))
        }
    }
}
