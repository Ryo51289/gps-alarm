package app.napstop.core.bridge

import android.app.NotificationManager
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Tester T21 (O6, D9): what the native side hands to the "Sẵn sàng" card on API 26..36 for
 * every Do Not Disturb filter. API 26-29 cannot read the applied policy, so
 * priorityAllowsAlarms must be null there (Dart then shows "dndCheckAlarms"), never a guess.
 */
class T21DeviceStatusTesterTest {
    private class Sources(
        val filter: Int?,
        val categories: Int?,
        val throwPolicy: Boolean = false,
    ) : DeviceStatusSources {
        var policyCalls = 0

        override fun batteryExtras(): ((String, Int) -> Int)? = null

        override fun alarmVolume(): Int? = 5

        override fun alarmMaxVolume(): Int? = 7

        override fun alarmMuted(): Boolean? = false

        override fun interruptionFilter(): Int? = filter

        override fun consolidatedPriorityCategories(): Int? {
            policyCalls++
            if (throwPolicy) throw SecurityException("policy 21.0")
            return categories
        }
    }

    private val alarms = NotificationManager.Policy.PRIORITY_CATEGORY_ALARMS
    private val filters =
        mapOf(
            NotificationManager.INTERRUPTION_FILTER_ALL to InterruptionFilterMsg.ALL,
            NotificationManager.INTERRUPTION_FILTER_PRIORITY to InterruptionFilterMsg.PRIORITY,
            NotificationManager.INTERRUPTION_FILTER_NONE to InterruptionFilterMsg.NONE,
            NotificationManager.INTERRUPTION_FILTER_ALARMS to InterruptionFilterMsg.ALARMS,
            NotificationManager.INTERRUPTION_FILTER_UNKNOWN to InterruptionFilterMsg.UNKNOWN,
            12345 to InterruptionFilterMsg.UNKNOWN,
        )

    @Test
    fun priorityPolicyIsReadOnlyOnApi30AndNeverGuessedBelow() {
        for (sdk in 26..36) {
            for ((raw, wire) in filters) {
                for (categories in listOf(0, alarms, alarms or 1, 1)) {
                    val src = Sources(raw, categories)
                    val warnings = mutableListOf<String>()
                    val msg = DeviceStatusReader(src, sdk, { warnings += it }).read()
                    assertEquals("$sdk/$raw", wire, msg.interruptionFilter)
                    val priority = wire == InterruptionFilterMsg.PRIORITY
                    if (sdk >= 30 && priority) {
                        assertEquals("$sdk/$raw/$categories", 1, src.policyCalls)
                        assertEquals((categories and alarms) != 0, msg.priorityAllowsAlarms)
                    } else {
                        assertEquals("$sdk/$raw: policy read", 0, src.policyCalls)
                        assertNull("$sdk/$raw: guessed", msg.priorityAllowsAlarms)
                    }
                    assertEquals(71L, msg.alarmVolumePct)
                    assertEquals(false, msg.alarmMuted)
                    assertEquals(emptyList<String>(), warnings)
                }
            }
        }
    }

    @Test
    fun unreadablePolicyOrFilterIsUnknownNotAllowed() {
        for (sdk in 30..36) {
            val warnings = mutableListOf<String>()
            val msg =
                DeviceStatusReader(Sources(NotificationManager.INTERRUPTION_FILTER_PRIORITY, alarms, throwPolicy = true), sdk) {
                    warnings += it
                }.read()
            assertEquals(InterruptionFilterMsg.PRIORITY, msg.interruptionFilter)
            assertNull(msg.priorityAllowsAlarms)
            assertEquals(listOf("device status policy: SecurityException"), warnings)
            // No NotificationManager at all.
            val none = DeviceStatusReader(Sources(null, alarms), sdk) {}.read()
            assertEquals(InterruptionFilterMsg.UNKNOWN, none.interruptionFilter)
            assertNull(none.priorityAllowsAlarms)
            // Applied policy without alarms: explicit false (dndBlocksAlarms), not null.
            val blocked = DeviceStatusReader(Sources(NotificationManager.INTERRUPTION_FILTER_PRIORITY, 0), sdk) {}.read()
            assertEquals(false, blocked.priorityAllowsAlarms)
            assertFalse(warnings.any { it.contains("21.0") })
        }
    }
}
