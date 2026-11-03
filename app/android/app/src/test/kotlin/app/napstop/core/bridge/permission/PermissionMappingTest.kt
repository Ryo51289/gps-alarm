package app.napstop.core.bridge.permission

import app.napstop.core.bridge.LocationAccessMsg
import app.napstop.core.bridge.PermissionKindMsg
import app.napstop.core.bridge.PermissionStateMsg
import app.napstop.core.bridge.PermissionStatusMsg
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

/** K01, K02: PermissionMapping.status / plan (spec T21 §4.2, §4.3). */
class PermissionMappingTest {
    private fun snap(
        sdkInt: Int = 34,
        fine: Boolean = true,
        coarse: Boolean = true,
        locationRequested: Boolean = false,
        locationRationale: Boolean? = null,
        preciseUpgradeAttempts: Int = 0,
        locationEnabled: Boolean = true,
        postNotificationsGranted: Boolean = true,
        notificationsEnabled: Boolean = true,
        notificationsRequested: Boolean = false,
        notificationsRationale: Boolean? = null,
        canUseFullScreenIntent: Boolean? = true,
        canScheduleExactAlarms: Boolean? = true,
        ignoringBatteryOptimizations: Boolean? = true,
    ) = PermissionSnapshot(
        sdkInt = sdkInt,
        fine = fine,
        coarse = coarse,
        locationRequested = locationRequested,
        locationRationale = locationRationale,
        preciseUpgradeAttempts = preciseUpgradeAttempts,
        locationEnabled = locationEnabled,
        postNotificationsGranted = postNotificationsGranted,
        notificationsEnabled = notificationsEnabled,
        notificationsRequested = notificationsRequested,
        notificationsRationale = notificationsRationale,
        canUseFullScreenIntent = canUseFullScreenIntent,
        canScheduleExactAlarms = canScheduleExactAlarms,
        ignoringBatteryOptimizations = ignoringBatteryOptimizations,
    )

    private fun status(s: PermissionSnapshot): PermissionStatusMsg = PermissionMapping.status(s)

    // ---------------------------------------------------------------- K01 sweep

    @Test
    fun k01InvariantsHoldForEveryCombination() {
        val bools = listOf(false, true)
        val rationales = listOf(null, false, true)
        val optionals = listOf(null, false, true)
        var count = 0
        for (sdk in listOf(26, 28, 30, 31, 32, 33, 34, 36)) {
            for (fine in bools) for (coarse in bools) for (requested in bools) for (rationale in rationales) {
                for (attempts in listOf(0, 1)) for (enabled in bools) for (post in bools) for (notifOn in bools) {
                    for (notifRequested in bools) for (notifRationale in rationales) for (fsi in optionals) {
                        for (exact in optionals) for (battery in optionals) {
                            val m =
                                status(
                                    snap(
                                        sdkInt = sdk,
                                        fine = fine,
                                        coarse = coarse,
                                        locationRequested = requested,
                                        locationRationale = rationale,
                                        preciseUpgradeAttempts = attempts,
                                        locationEnabled = enabled,
                                        postNotificationsGranted = post,
                                        notificationsEnabled = notifOn,
                                        notificationsRequested = notifRequested,
                                        notificationsRationale = notifRationale,
                                        canUseFullScreenIntent = fsi,
                                        canScheduleExactAlarms = exact,
                                        ignoringBatteryOptimizations = battery,
                                    ),
                                )
                            assertNotEquals(PermissionStateMsg.NOT_APPLICABLE, m.precise)
                            assertNotEquals(LocationAccessMsg.ALWAYS, m.location)
                            assertEquals(PermissionStateMsg.NOT_APPLICABLE, m.alarmKit)
                            for (other in listOf(m.notifications, m.fullScreenIntent, m.exactAlarm, m.batteryOptimizationIgnored)) {
                                assertNotEquals(PermissionStateMsg.NOT_APPLICABLE, other)
                            }
                            assertEquals(enabled, m.locationServicesEnabled)
                            count++
                        }
                    }
                }
            }
        }
        assertEquals(8 * 2 * 2 * 2 * 3 * 2 * 2 * 2 * 2 * 2 * 3 * 3 * 3 * 3, count)
    }

    // ---------------------------------------------------------------- K01 cases

    @Test
    fun k01LocationNeverAsked() {
        val m = status(snap(fine = false, coarse = false, locationRequested = false))
        assertEquals(LocationAccessMsg.NOT_DETERMINED, m.location)
        assertEquals(PermissionStateMsg.NOT_DETERMINED, m.precise)
    }

    @Test
    fun k01LocationAskedWithRationaleCanStillPrompt() {
        val m = status(snap(fine = false, coarse = false, locationRequested = true, locationRationale = true))
        assertEquals(LocationAccessMsg.NOT_DETERMINED, m.location)
    }

    @Test
    fun k01LocationAskedWithoutRationaleIsDenied() {
        for (rationale in listOf(false, null)) {
            val m = status(snap(fine = false, coarse = false, locationRequested = true, locationRationale = rationale))
            assertEquals("rationale=$rationale", LocationAccessMsg.DENIED, m.location)
        }
    }

    @Test
    fun k01FineIsWhileInUseAndPrecise() {
        val m = status(snap(fine = true, coarse = true))
        assertEquals(LocationAccessMsg.WHILE_IN_USE, m.location)
        assertEquals(PermissionStateMsg.GRANTED, m.precise)
    }

    @Test
    fun k01CoarseOnlyPrecise() {
        assertEquals(
            PermissionStateMsg.NOT_DETERMINED,
            status(snap(sdkInt = 31, fine = false, coarse = true, preciseUpgradeAttempts = 0)).precise,
        )
        assertEquals(
            PermissionStateMsg.DENIED,
            status(snap(sdkInt = 31, fine = false, coarse = true, preciseUpgradeAttempts = 1)).precise,
        )
        assertEquals(PermissionStateMsg.DENIED, status(snap(sdkInt = 30, fine = false, coarse = true)).precise)
        assertEquals(LocationAccessMsg.WHILE_IN_USE, status(snap(sdkInt = 31, fine = false, coarse = true)).location)
    }

    @Test
    fun k01Notifications() {
        assertEquals(PermissionStateMsg.GRANTED, status(snap(notificationsEnabled = true)).notifications)
        assertEquals(
            PermissionStateMsg.DENIED,
            status(snap(sdkInt = 32, notificationsEnabled = false, postNotificationsGranted = false)).notifications,
        )
        assertEquals(
            PermissionStateMsg.DENIED,
            status(snap(sdkInt = 33, notificationsEnabled = false, postNotificationsGranted = true)).notifications,
        )
        assertEquals(
            PermissionStateMsg.NOT_DETERMINED,
            status(
                snap(sdkInt = 33, notificationsEnabled = false, postNotificationsGranted = false, notificationsRequested = false),
            ).notifications,
        )
        assertEquals(
            PermissionStateMsg.NOT_DETERMINED,
            status(
                snap(
                    sdkInt = 33,
                    notificationsEnabled = false,
                    postNotificationsGranted = false,
                    notificationsRequested = true,
                    notificationsRationale = true,
                ),
            ).notifications,
        )
        assertEquals(
            PermissionStateMsg.DENIED,
            status(
                snap(
                    sdkInt = 33,
                    notificationsEnabled = false,
                    postNotificationsGranted = false,
                    notificationsRequested = true,
                    notificationsRationale = false,
                ),
            ).notifications,
        )
    }

    @Test
    fun k01FullScreenIntent() {
        assertEquals(PermissionStateMsg.GRANTED, status(snap(sdkInt = 33, canUseFullScreenIntent = null)).fullScreenIntent)
        assertEquals(PermissionStateMsg.GRANTED, status(snap(sdkInt = 34, canUseFullScreenIntent = true)).fullScreenIntent)
        assertEquals(PermissionStateMsg.DENIED, status(snap(sdkInt = 34, canUseFullScreenIntent = false)).fullScreenIntent)
        assertEquals(PermissionStateMsg.DENIED, status(snap(sdkInt = 34, canUseFullScreenIntent = null)).fullScreenIntent)
    }

    @Test
    fun k01ExactAlarmAndBattery() {
        assertEquals(PermissionStateMsg.GRANTED, status(snap(sdkInt = 30, canScheduleExactAlarms = null)).exactAlarm)
        assertEquals(PermissionStateMsg.DENIED, status(snap(sdkInt = 31, canScheduleExactAlarms = null)).exactAlarm)
        assertEquals(PermissionStateMsg.DENIED, status(snap(sdkInt = 31, canScheduleExactAlarms = false)).exactAlarm)
        assertEquals(PermissionStateMsg.GRANTED, status(snap(sdkInt = 34, canScheduleExactAlarms = true)).exactAlarm)
        assertEquals(PermissionStateMsg.DENIED, status(snap(ignoringBatteryOptimizations = null)).batteryOptimizationIgnored)
        assertEquals(PermissionStateMsg.DENIED, status(snap(ignoringBatteryOptimizations = false)).batteryOptimizationIgnored)
        assertEquals(PermissionStateMsg.GRANTED, status(snap(ignoringBatteryOptimizations = true)).batteryOptimizationIgnored)
    }

    // ---------------------------------------------------------------- K02

    private val fine = PermissionMapping.FINE
    private val coarse = PermissionMapping.COARSE

    @Test
    fun k02LocationPlans() {
        assertEquals(RequestPlan.None, PermissionMapping.plan(PermissionKindMsg.LOCATION, snap(fine = true)))
        assertEquals(
            RequestPlan.Prompt(listOf(fine, coarse), markLocation = true, countPreciseAttempt = true),
            PermissionMapping.plan(PermissionKindMsg.LOCATION, snap(fine = false, coarse = true)),
        )
        assertEquals(
            RequestPlan.Prompt(listOf(fine, coarse), markLocation = true),
            PermissionMapping.plan(PermissionKindMsg.LOCATION, snap(fine = false, coarse = false)),
        )
    }

    @Test
    fun k02NotificationPlans() {
        val kind = PermissionKindMsg.NOTIFICATIONS
        assertEquals(
            RequestPlan.None,
            PermissionMapping.plan(kind, snap(sdkInt = 32, notificationsEnabled = false, postNotificationsGranted = false)),
        )
        assertEquals(RequestPlan.None, PermissionMapping.plan(kind, snap(sdkInt = 33, notificationsEnabled = true)))
        assertEquals(
            RequestPlan.None,
            PermissionMapping.plan(kind, snap(sdkInt = 33, notificationsEnabled = false, postNotificationsGranted = true)),
        )
        assertEquals(
            RequestPlan.Prompt(listOf("android.permission.POST_NOTIFICATIONS"), markNotifications = true),
            PermissionMapping.plan(kind, snap(sdkInt = 33, notificationsEnabled = false, postNotificationsGranted = false)),
        )
    }

    @Test
    fun k02AlarmKitIsNeverPrompted() {
        assertEquals(RequestPlan.None, PermissionMapping.plan(PermissionKindMsg.ALARM_KIT, snap(fine = false, coarse = false)))
    }
}
