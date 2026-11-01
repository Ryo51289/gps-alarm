package app.napstop.core.bridge

import android.os.Build

/**
 * Fixed permission answers so screens can be built before the real implementation
 * (T21, spec T14 §5.5). deviceInfo() is real. ADR-001: Android never asks for
 * background location, so `location` is at most whileInUse.
 */
class PermissionHostApiStub : PermissionHostApi {
    override fun status(): PermissionStatusMsg = FIXED_STATUS

    override suspend fun request(kind: PermissionKindMsg): PermissionStatusMsg = status()

    override fun openSettings(target: SettingsTargetMsg): Boolean = false

    override fun deviceInfo(): DeviceInfoMsg =
        DeviceInfoMsg(
            platform = PlatformMsg.ANDROID,
            manufacturer = Build.MANUFACTURER.orEmpty(),
            brand = Build.BRAND.orEmpty(),
            model = Build.MODEL.orEmpty(),
            osVersion = Build.VERSION.RELEASE.orEmpty(),
            androidSdkInt = Build.VERSION.SDK_INT.toLong(),
            iosMajor = null,
        )

    companion object {
        val FIXED_STATUS =
            PermissionStatusMsg(
                location = LocationAccessMsg.WHILE_IN_USE,
                precise = PermissionStateMsg.GRANTED,
                locationServicesEnabled = true,
                notifications = PermissionStateMsg.GRANTED,
                fullScreenIntent = PermissionStateMsg.GRANTED,
                exactAlarm = PermissionStateMsg.GRANTED,
                // denied, so the UI shows the "guide" item.
                batteryOptimizationIgnored = PermissionStateMsg.DENIED,
                alarmKit = PermissionStateMsg.NOT_APPLICABLE,
            )
    }
}
