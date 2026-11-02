package app.napstop.core.bridge

import android.app.NotificationManager
import android.os.BatteryManager
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Tester additions for T14.1 (beyond DeviceStatusMappingTest): edge cases of the pure
 * part of DeviceStatusReader. The reader itself is not JVM-testable: Context
 * .getSystemService(Class) and NotificationManager getters are final in android.jar and
 * throw "not mocked" at run time, and readOrNull logs with android.util.Log (see the
 * test report for the hook request).
 */
class DeviceStatusMappingTesterTest {
    private fun intent(vararg extras: Pair<String, Int>): (String, Int) -> Int {
        val map = extras.toMap()
        return { name, default -> map[name] ?: default }
    }

    @Test
    fun batteryPctIsNullUnlessLevelAndScaleAreUsable() {
        // A wrong 0 % would raise the low-battery banner (T25) for nothing.
        val cases =
            listOf(
                Triple(-1, 100, null),
                Triple(Int.MIN_VALUE, 100, null),
                Triple(50, 0, null),
                Triple(50, -1, null),
                Triple(-1, -1, null),
                Triple(0, 0, null),
                Triple(0, 100, 0L),
                Triple(1, 100, 1L),
                Triple(99, 100, 99L),
                Triple(1, 1, 100L),
                Triple(149, 150, 99L), // rounds down, never reports more than there is
                // level * 100 is done in Long: no Int overflow on odd scales.
                Triple(Int.MAX_VALUE, Int.MAX_VALUE, 100L),
                Triple(30_000_000, 100_000_000, 30L),
            )
        for ((level, scale, pct) in cases) {
            assertEquals("$level/$scale", pct, DeviceStatusMapping.batteryPct(level, scale))
        }
    }

    @Test
    fun batteryFromIntentExtras() {
        val cases =
            listOf(
                intent() to DeviceStatusMapping.Battery.UNKNOWN,
                intent(BatteryManager.EXTRA_LEVEL to -1, BatteryManager.EXTRA_SCALE to 100) to DeviceStatusMapping.Battery.UNKNOWN,
                intent(BatteryManager.EXTRA_LEVEL to 50, BatteryManager.EXTRA_SCALE to 0) to DeviceStatusMapping.Battery.UNKNOWN,
                intent(
                    BatteryManager.EXTRA_LEVEL to 15,
                    BatteryManager.EXTRA_SCALE to 100,
                    BatteryManager.EXTRA_STATUS to BatteryManager.BATTERY_STATUS_UNKNOWN,
                ) to DeviceStatusMapping.Battery(15, null),
                // Plugged in but not charging (adaptive charging, heat): not charging (review nit 2).
                intent(
                    BatteryManager.EXTRA_LEVEL to 80,
                    BatteryManager.EXTRA_SCALE to 100,
                    BatteryManager.EXTRA_STATUS to BatteryManager.BATTERY_STATUS_NOT_CHARGING,
                    BatteryManager.EXTRA_PLUGGED to BatteryManager.BATTERY_PLUGGED_AC,
                ) to DeviceStatusMapping.Battery(80, false),
                intent(
                    BatteryManager.EXTRA_LEVEL to 100,
                    BatteryManager.EXTRA_SCALE to 100,
                    BatteryManager.EXTRA_STATUS to BatteryManager.BATTERY_STATUS_FULL,
                ) to DeviceStatusMapping.Battery(100, true),
            )
        for ((extras, expected) in cases) {
            assertEquals(expected, DeviceStatusMapping.battery(extras))
        }
    }

    @Test
    fun batteryReadsOnlyLevelScaleAndStatusWithMinusOneDefaults() {
        val asked = mutableListOf<Pair<String, Int>>()
        DeviceStatusMapping.battery { name, default ->
            asked += name to default
            default
        }
        assertEquals(
            setOf(
                BatteryManager.EXTRA_LEVEL to -1,
                BatteryManager.EXTRA_SCALE to -1,
                BatteryManager.EXTRA_STATUS to -1,
            ),
            asked.toSet(),
        )
        assertEquals(3, asked.size)
    }

    @Test
    fun alarmVolumeEdges() {
        val cases =
            listOf(
                Triple(0, 7, 0L),
                Triple(1, 7, 14L),
                Triple(6, 7, 86L), // emulator API 34 default, seen on napstop_api34
                Triple(7, 7, 100L),
                Triple(1, 15, 7L),
                Triple(1, 200, 1L), // 0.5 rounds half up
                Triple(1, 201, 0L),
                Triple(9, 7, 100L), // above max clamps
                Triple(-1, 7, 0L), // below zero clamps
                Triple(1, 0, null),
                Triple(0, 0, null),
                Triple(5, -3, null),
                Triple(0, Int.MIN_VALUE, null),
            )
        for ((volume, max, pct) in cases) {
            assertEquals("$volume/$max", pct, DeviceStatusMapping.volumePct(volume, max))
        }
    }

    @Test
    fun everyInterruptionFilterValue() {
        val expected =
            mapOf(
                NotificationManager.INTERRUPTION_FILTER_UNKNOWN to InterruptionFilterMsg.UNKNOWN,
                NotificationManager.INTERRUPTION_FILTER_ALL to InterruptionFilterMsg.ALL,
                NotificationManager.INTERRUPTION_FILTER_PRIORITY to InterruptionFilterMsg.PRIORITY,
                NotificationManager.INTERRUPTION_FILTER_NONE to InterruptionFilterMsg.NONE,
                NotificationManager.INTERRUPTION_FILTER_ALARMS to InterruptionFilterMsg.ALARMS,
                5 to InterruptionFilterMsg.UNKNOWN,
                -1 to InterruptionFilterMsg.UNKNOWN,
                Int.MAX_VALUE to InterruptionFilterMsg.UNKNOWN,
            )
        for ((platform, wire) in expected) {
            assertEquals("filter $platform", wire, DeviceStatusMapping.mapInterruptionFilter(platform))
        }
        // Wire value is the enum index, not the platform constant (NONE: 3 on the platform, 4 on the wire).
        assertEquals(listOf(0, 1, 2, 3, 4), InterruptionFilterMsg.entries.map { it.raw })
        assertEquals(
            listOf("UNKNOWN", "ALL", "PRIORITY", "ALARMS", "NONE"),
            InterruptionFilterMsg.entries.map { it.name },
        )
        for (value in InterruptionFilterMsg.entries) {
            assertEquals(value, InterruptionFilterMsg.ofRaw(value.raw))
        }
        assertNull(InterruptionFilterMsg.ofRaw(5))
    }

    @Test
    fun priorityAllowsAlarmsOnlyForPriorityOnApi30Plus() {
        val alarms = NotificationManager.Policy.PRIORITY_CATEGORY_ALARMS
        val everything = -1
        // API 26..29: never known (getConsolidatedNotificationPolicy is API 30+).
        for (sdk in 26..29) {
            for (filter in InterruptionFilterMsg.entries) {
                assertNull("sdk $sdk $filter", DeviceStatusMapping.priorityAllowsAlarms(sdk, filter, everything))
            }
        }
        // API 30+: only meaningful under priority-only.
        for (sdk in listOf(30, 34, 36)) {
            for (filter in InterruptionFilterMsg.entries - InterruptionFilterMsg.PRIORITY) {
                assertNull("sdk $sdk $filter", DeviceStatusMapping.priorityAllowsAlarms(sdk, filter, everything))
            }
            val priority = InterruptionFilterMsg.PRIORITY
            assertEquals(true, DeviceStatusMapping.priorityAllowsAlarms(sdk, priority, alarms))
            assertEquals(true, DeviceStatusMapping.priorityAllowsAlarms(sdk, priority, everything))
            assertEquals(false, DeviceStatusMapping.priorityAllowsAlarms(sdk, priority, 0))
            assertEquals(false, DeviceStatusMapping.priorityAllowsAlarms(sdk, priority, everything and alarms.inv()))
        }
    }

    @Test
    fun unknownDeviceStatusIsAllNullAndUnknown() {
        val unknown = PermissionHostApiStub.UNKNOWN_DEVICE_STATUS
        assertEquals(
            DeviceStatusMsg(
                batteryPct = null,
                charging = null,
                alarmVolumePct = null,
                alarmMuted = null,
                interruptionFilter = InterruptionFilterMsg.UNKNOWN,
                priorityAllowsAlarms = null,
            ),
            unknown,
        )
    }

    @Test
    fun deviceStatusRoundTripsThroughTheKotlinCodec() {
        val codec = PermissionHostApi.codec
        for (filter in InterruptionFilterMsg.entries) {
            for (msg in listOf(
                DeviceStatusMsg(interruptionFilter = filter),
                DeviceStatusMsg(0, false, 0, true, filter, false),
                DeviceStatusMsg(100, true, 100, false, filter, true),
            )) {
                val bytes = codec.encodeMessage(msg)!!.apply { rewind() }
                assertEquals(msg, codec.decodeMessage(bytes))
            }
        }
    }
}
