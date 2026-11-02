package app.napstop.core.bridge

import org.junit.Assert.fail

/** Shared builders for the bridge JVM tests (T14). */
object BridgeTestData {
    fun alarm(soundId: String = "default", volume: Double = 0.8): AlarmSettingsMsg =
        AlarmSettingsMsg(
            soundId = soundId,
            volume = volume,
            rampUp = true,
            vibration = VibrationMsg.MEDIUM,
            flash = false,
            preferHeadphones = true,
            dismissMethod = DismissMethodMsg.SWIPE,
        )

    fun config(
        tripId: String = "t1",
        mode: AlarmModeMsg = AlarmModeMsg.SMART,
        distanceThresholdM: Long? = null,
        timeThresholdMin: Long? = null,
        preAlertEnabled: Boolean = true,
        destinationName: String = "Ga Đông Hà",
        alarm: AlarmSettingsMsg = alarm(),
        engineParamsJson: String? = null,
    ): TripConfigMsg =
        TripConfigMsg(
            tripId = tripId,
            destinationName = destinationName,
            mode = mode,
            distanceThresholdM = distanceThresholdM,
            timeThresholdMin = timeThresholdMin,
            preAlertEnabled = preAlertEnabled,
            vehicleHint = VehicleKindMsg.TRAIN,
            alarm = alarm,
            engineParamsJson = engineParamsJson,
        )

    inline fun expectFlutterError(block: () -> Unit): FlutterError {
        try {
            block()
        } catch (e: FlutterError) {
            return e
        }
        fail("expected FlutterError")
        throw AssertionError()
    }
}
