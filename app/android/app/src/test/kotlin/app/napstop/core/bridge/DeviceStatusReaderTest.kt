package app.napstop.core.bridge

import android.app.NotificationManager
import android.os.BatteryManager
import app.napstop.core.alarm.HeadphoneTypes
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** K04: DeviceStatusReader with injected sources (T14.1 O2, spec T21 §4.6); K01: headphones (T26 §9). */
class DeviceStatusReaderTest {
    private class FakeSources(
        var extras: Map<String, Int>? =
            mapOf(
                BatteryManager.EXTRA_LEVEL to 41,
                BatteryManager.EXTRA_SCALE to 50,
                BatteryManager.EXTRA_STATUS to BatteryManager.BATTERY_STATUS_CHARGING,
            ),
        var volume: Int? = 5,
        var maxVolume: Int? = 7,
        var muted: Boolean? = false,
        var filter: Int? = NotificationManager.INTERRUPTION_FILTER_PRIORITY,
        var categories: Int? = NotificationManager.Policy.PRIORITY_CATEGORY_ALARMS,
        var outputs: List<Int>? = listOf(HeadphoneTypes.TYPE_BUILTIN_SPEAKER, HeadphoneTypes.TYPE_WIRED_HEADSET),
    ) : DeviceStatusSources {
        var failing: String? = null
        var policyCalls = 0

        private fun <T> maybeThrow(item: String, value: T): T {
            if (failing == item) throw IllegalStateException("x 21.0")
            return value
        }

        override fun batteryExtras(): ((String, Int) -> Int)? =
            maybeThrow("battery", extras)?.let { map -> { name, default -> map[name] ?: default } }

        override fun alarmVolume(): Int? = maybeThrow("volume", volume)

        override fun alarmMaxVolume(): Int? = maxVolume

        override fun alarmMuted(): Boolean? = maybeThrow("mute", muted)

        override fun interruptionFilter(): Int? = maybeThrow("filter", filter)

        override fun consolidatedPriorityCategories(): Int? {
            policyCalls++
            return maybeThrow("policy", categories)
        }

        override fun outputDeviceTypes(): List<Int>? = maybeThrow("headphones", outputs)
    }

    private val warnings = mutableListOf<String>()

    private fun reader(sources: DeviceStatusSources, sdk: Int = 30) = DeviceStatusReader(sources, sdk) { warnings += it }

    private val full =
        DeviceStatusMsg(
            batteryPct = DeviceStatusMapping.batteryPct(41, 50),
            charging = true,
            alarmVolumePct = DeviceStatusMapping.volumePct(5, 7),
            alarmMuted = false,
            interruptionFilter = InterruptionFilterMsg.PRIORITY,
            priorityAllowsAlarms = true,
            headphonesConnected = true,
        )

    @Test
    fun k04FullDataMatchesTheMapping() {
        assertEquals(full, reader(FakeSources()).read())
        assertEquals(82L, full.batteryPct)
        assertEquals(71L, full.alarmVolumePct)
        assertTrue(warnings.isEmpty())
    }

    @Test
    fun k04EachFailingSourceOnlyDropsItsItem() {
        val expected =
            mapOf(
                "battery" to full.copy(batteryPct = null, charging = null),
                "volume" to full.copy(alarmVolumePct = null),
                "mute" to full.copy(alarmMuted = null),
                "filter" to full.copy(interruptionFilter = InterruptionFilterMsg.UNKNOWN, priorityAllowsAlarms = null),
                "policy" to full.copy(priorityAllowsAlarms = null),
                "headphones" to full.copy(headphonesConnected = null),
            )
        for ((item, msg) in expected) {
            warnings.clear()
            val sources = FakeSources().apply { failing = item }
            assertEquals(item, msg, reader(sources).read())
            assertEquals(item, listOf("device status $item: IllegalStateException"), warnings)
            assertFalse(warnings.single().contains("21.0"))
        }
    }

    @Test
    fun k04NullSourcesReadAsUnknown() {
        val sources = FakeSources(extras = null, volume = null, muted = null, filter = null, outputs = null)
        val msg = reader(sources).read()
        assertEquals(DeviceStatusMsg(interruptionFilter = InterruptionFilterMsg.UNKNOWN), msg)
        assertEquals(0, sources.policyCalls)
        assertTrue(warnings.isEmpty())
    }

    @Test
    fun k04PolicyOnlyReadFromApi30() {
        val old = FakeSources()
        val msg29 = reader(old, sdk = 29).read()
        assertNull(msg29.priorityAllowsAlarms)
        assertEquals(InterruptionFilterMsg.PRIORITY, msg29.interruptionFilter)
        assertEquals(0, old.policyCalls)

        val new = FakeSources(categories = 0)
        assertEquals(false, reader(new, sdk = 30).read().priorityAllowsAlarms)
        assertEquals(1, new.policyCalls)
    }

    @Test
    fun k04PolicyNotReadWhenTheFilterIsNotPriority() {
        val sources = FakeSources(filter = NotificationManager.INTERRUPTION_FILTER_ALL)
        assertNull(reader(sources, sdk = 34).read().priorityAllowsAlarms)
        assertEquals(0, sources.policyCalls)
    }

    @Test
    fun k01HeadphonesFromTheOutputDevices() {
        val cases =
            mapOf(
                listOf(HeadphoneTypes.TYPE_BUILTIN_SPEAKER, HeadphoneTypes.TYPE_WIRED_HEADSET) to true,
                listOf(HeadphoneTypes.TYPE_BUILTIN_SPEAKER, HeadphoneTypes.TYPE_BLUETOOTH_A2DP) to true,
                listOf(HeadphoneTypes.TYPE_USB_HEADSET) to true,
                listOf(HeadphoneTypes.TYPE_BUILTIN_EARPIECE, HeadphoneTypes.TYPE_BUILTIN_SPEAKER) to false,
                emptyList<Int>() to false,
            )
        for ((outputs, expected) in cases) {
            val msg = reader(FakeSources(outputs = outputs)).read()
            assertEquals("$outputs", full.copy(headphonesConnected = expected), msg)
        }
        assertTrue(warnings.isEmpty())
    }
}
