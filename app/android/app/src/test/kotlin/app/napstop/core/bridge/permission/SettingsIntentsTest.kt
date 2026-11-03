package app.napstop.core.bridge.permission

import android.provider.Settings
import app.napstop.core.bridge.SettingsTargetMsg
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

/** K03: SettingsIntents.candidates (spec T21 §4.4). */
class SettingsIntentsTest {
    private val appDetails = IntentSpec(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, packageUri = true)
    private val sdks = listOf(26, 30, 31, 33, 34)

    private fun expected(target: SettingsTargetMsg, sdk: Int): List<IntentSpec> =
        when (target) {
            SettingsTargetMsg.APP_DETAILS -> listOf(appDetails)
            SettingsTargetMsg.LOCATION_SERVICES -> listOf(IntentSpec("android.settings.LOCATION_SOURCE_SETTINGS"))
            SettingsTargetMsg.NOTIFICATIONS ->
                listOf(IntentSpec("android.settings.APP_NOTIFICATION_SETTINGS", extraAppPackage = true), appDetails)
            SettingsTargetMsg.FULL_SCREEN_INTENT ->
                if (sdk >= 34) {
                    listOf(IntentSpec("android.settings.MANAGE_APP_USE_FULL_SCREEN_INTENT", packageUri = true), appDetails)
                } else {
                    emptyList()
                }
            SettingsTargetMsg.EXACT_ALARM ->
                if (sdk >= 31) {
                    listOf(IntentSpec("android.settings.REQUEST_SCHEDULE_EXACT_ALARM", packageUri = true), appDetails)
                } else {
                    emptyList()
                }
            SettingsTargetMsg.BATTERY_OPTIMIZATION ->
                listOf(IntentSpec("android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS"), appDetails)
        }

    @Test
    fun k03CandidatesMatchTheTable() {
        assertEquals("android.settings.APPLICATION_DETAILS_SETTINGS", appDetails.action)
        for (target in SettingsTargetMsg.entries) {
            for (sdk in sdks) {
                assertEquals("$target sdk $sdk", expected(target, sdk), SettingsIntents.candidates(target, sdk))
            }
        }
    }

    @Test
    fun k03NeverTheDirectBatteryExemptionRequest() {
        for (target in SettingsTargetMsg.entries) {
            for (sdk in sdks + listOf(36)) {
                assertFalse(
                    SettingsIntents.candidates(target, sdk).any {
                        it.action == Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS ||
                            it.action == "android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"
                    },
                )
            }
        }
    }

    @Test
    fun k03NotApplicableBelowTheirApiLevel() {
        assertEquals(emptyList<IntentSpec>(), SettingsIntents.candidates(SettingsTargetMsg.FULL_SCREEN_INTENT, 33))
        assertEquals(emptyList<IntentSpec>(), SettingsIntents.candidates(SettingsTargetMsg.EXACT_ALARM, 30))
    }
}
