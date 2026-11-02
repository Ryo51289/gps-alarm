package app.napstop.core.bridge

import android.app.NotificationManager
import android.os.BatteryManager
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** K01 of T22 + battery parsing of the sticky intent (spec T14.1). */
class DeviceStatusMappingTest {
    /** Stands in for the sticky ACTION_BATTERY_CHANGED intent: `getIntExtra(name, default)`. */
    private fun fakeIntent(vararg extras: Pair<String, Int>): (String, Int) -> Int {
        val map = extras.toMap()
        return { name, default -> map[name] ?: default }
    }

    @Test
    fun batteryFromTheStickyIntent() {
        val battery =
            DeviceStatusMapping.battery(
                fakeIntent(
                    BatteryManager.EXTRA_LEVEL to 57,
                    BatteryManager.EXTRA_SCALE to 100,
                    BatteryManager.EXTRA_STATUS to BatteryManager.BATTERY_STATUS_DISCHARGING,
                ),
            )
        assertEquals(DeviceStatusMapping.Battery(pct = 57, charging = false), battery)
    }

    @Test
    fun batteryRoundsDownOnOtherScales() {
        // 2/3 = 66.6 % -> 66 (T25 §7: integer division).
        val battery =
            DeviceStatusMapping.battery(
                fakeIntent(
                    BatteryManager.EXTRA_LEVEL to 2,
                    BatteryManager.EXTRA_SCALE to 3,
                    BatteryManager.EXTRA_STATUS to BatteryManager.BATTERY_STATUS_FULL,
                ),
            )
        assertEquals(DeviceStatusMapping.Battery(pct = 66, charging = true), battery)
    }

    @Test
    fun missingExtrasAreUnknown() {
        assertEquals(DeviceStatusMapping.Battery.UNKNOWN, DeviceStatusMapping.battery(fakeIntent()))
        // Level without scale, scale without level: no percentage; status still read.
        assertEquals(
            DeviceStatusMapping.Battery(pct = null, charging = true),
            DeviceStatusMapping.battery(
                fakeIntent(
                    BatteryManager.EXTRA_LEVEL to 40,
                    BatteryManager.EXTRA_STATUS to BatteryManager.BATTERY_STATUS_CHARGING,
                ),
            ),
        )
        assertEquals(
            DeviceStatusMapping.Battery(pct = null, charging = null),
            DeviceStatusMapping.battery(fakeIntent(BatteryManager.EXTRA_SCALE to 100)),
        )
    }

    @Test
    fun batteryPctEdges() {
        assertEquals(0L, DeviceStatusMapping.batteryPct(0, 100))
        assertEquals(100L, DeviceStatusMapping.batteryPct(100, 100))
        assertEquals(100L, DeviceStatusMapping.batteryPct(120, 100)) // bogus level clamps
        assertNull(DeviceStatusMapping.batteryPct(-1, 100))
        assertNull(DeviceStatusMapping.batteryPct(50, 0))
        assertNull(DeviceStatusMapping.batteryPct(50, -1))
    }

    @Test
    fun chargingFromStatus() {
        assertEquals(true, DeviceStatusMapping.charging(BatteryManager.BATTERY_STATUS_CHARGING))
        assertEquals(true, DeviceStatusMapping.charging(BatteryManager.BATTERY_STATUS_FULL))
        assertEquals(false, DeviceStatusMapping.charging(BatteryManager.BATTERY_STATUS_DISCHARGING))
        assertEquals(false, DeviceStatusMapping.charging(BatteryManager.BATTERY_STATUS_NOT_CHARGING))
        assertNull(DeviceStatusMapping.charging(BatteryManager.BATTERY_STATUS_UNKNOWN))
        assertNull(DeviceStatusMapping.charging(-1))
        assertNull(DeviceStatusMapping.charging(42))
    }

    @Test
    fun volumePct() {
        // T22 K01.
        assertEquals(100L, DeviceStatusMapping.volumePct(7, 7))
        assertEquals(0L, DeviceStatusMapping.volumePct(0, 7))
        assertEquals(43L, DeviceStatusMapping.volumePct(3, 7))
        assertNull(DeviceStatusMapping.volumePct(1, 0))
        assertNull(DeviceStatusMapping.volumePct(1, -1))
    }

    @Test
    fun interruptionFilter() {
        // T22 K01: 0..4 and 9 -> unknown/all/priority/none/alarms/unknown.
        val mapped = listOf(0, 1, 2, 3, 4, 9).map(DeviceStatusMapping::mapInterruptionFilter)
        assertEquals(
            listOf(
                InterruptionFilterMsg.UNKNOWN,
                InterruptionFilterMsg.ALL,
                InterruptionFilterMsg.PRIORITY,
                InterruptionFilterMsg.NONE,
                InterruptionFilterMsg.ALARMS,
                InterruptionFilterMsg.UNKNOWN,
            ),
            mapped,
        )
        // The numbers above are the platform constants.
        assertEquals(1, NotificationManager.INTERRUPTION_FILTER_ALL)
        assertEquals(2, NotificationManager.INTERRUPTION_FILTER_PRIORITY)
        assertEquals(3, NotificationManager.INTERRUPTION_FILTER_NONE)
        assertEquals(4, NotificationManager.INTERRUPTION_FILTER_ALARMS)
    }

    @Test
    fun priorityAllowsAlarms() {
        // T22 K01.
        val alarms = NotificationManager.Policy.PRIORITY_CATEGORY_ALARMS
        val priority = InterruptionFilterMsg.PRIORITY
        assertNull(DeviceStatusMapping.priorityAllowsAlarms(29, priority, alarms))
        assertEquals(true, DeviceStatusMapping.priorityAllowsAlarms(30, priority, alarms))
        assertEquals(true, DeviceStatusMapping.priorityAllowsAlarms(35, priority, alarms or 1))
        assertEquals(false, DeviceStatusMapping.priorityAllowsAlarms(30, priority, 0))
        assertNull(DeviceStatusMapping.priorityAllowsAlarms(30, InterruptionFilterMsg.ALL, alarms))
    }
}
