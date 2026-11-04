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
            "notifChannelAlarmInterim" to "notif_channel_alarm_interim",
            "notifTrackingTitle" to "notif_tracking_title",
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
            "notifAlarmInterimTitle" to "notif_alarm_interim_title",
            "alarmReasonFallback" to "alarm_reason_fallback",
            "notifActionDismiss" to "notif_action_dismiss",
            "notifActionSnooze" to "notif_action_snooze",
            "notifDestinationUnknown" to "notif_destination_unknown",
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

    /** `{name}` → `%n$s` in order of appearance. */
    private fun toAndroid(arb: String): String {
        var n = 0
        return Regex("\\{[A-Za-z]+\\}").replace(arb) { "%${++n}\$s" }
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
