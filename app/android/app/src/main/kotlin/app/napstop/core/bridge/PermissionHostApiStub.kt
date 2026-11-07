package app.napstop.core.bridge

/**
 * Fixed permission answers (spec T14 §5.5). **Test/default only, not registered in
 * production**: since T21 `BridgeRegistrar.register(messenger, activity)` registers
 * `permission.PermissionHostApiImpl`; this stub stays the default of the JVM-test overload.
 * deviceStatus() and distancesFromLastKnownM() answer from the injected sources.
 * ADR-001: Android never asks for background location, so `location` is at most whileInUse.
 */
class PermissionHostApiStub(
    private val readDeviceStatus: () -> DeviceStatusMsg,
    private val readDistances: suspend (List<Double>, Long) -> List<Double>? = { _, _ -> null },
) : PermissionHostApi {
    override suspend fun status(): PermissionStatusMsg = FIXED_STATUS

    override suspend fun request(kind: PermissionKindMsg): PermissionStatusMsg = status()

    override fun openSettings(target: SettingsTargetMsg): Boolean = false

    override fun deviceInfo(): DeviceInfoMsg = BridgeRegistrar.readDeviceInfo()

    override fun deviceStatus(): DeviceStatusMsg = readDeviceStatus()

    override suspend fun distancesFromLastKnownM(latLngPairs: List<Double>, maxAgeMs: Long): List<Double>? =
        readDistances(latLngPairs, maxAgeMs)

    override suspend fun startBackgroundCheck(delayMs: Long): BackgroundCheckMsg =
        throw FlutterError(BridgeErrors.INTERNAL, "unsupported", null)

    override suspend fun backgroundCheck(): BackgroundCheckMsg? = null

    override suspend fun cancelBackgroundCheck() = Unit

    companion object {
        /** Nothing known; default of the JVM-test registration. */
        val UNKNOWN_DEVICE_STATUS = DeviceStatusMsg(interruptionFilter = InterruptionFilterMsg.UNKNOWN)

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
