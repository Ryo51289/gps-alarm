package app.napstop.core.bridge

/**
 * Safety net for TripHostApi.startTrip (spec T14 §6); Flutter validates first (T25).
 * Messages name the field and the rule only, never the value (T10 §10).
 */
object TripConfigValidator {
    const val MAX_DESTINATION_NAME_LENGTH = 200

    private val TRIP_ID = Regex("^[A-Za-z0-9_-]{1,64}$")

    /** Throws FlutterError(BridgeErrors.INVALID_CONFIG, "<field>: <rule>") on the first violated rule. */
    fun validate(config: TripConfigMsg, destLat: Double, destLng: Double, simulation: SimulationMsg?) {
        // V1
        require(TRIP_ID.matches(config.tripId)) { "tripId: format" }
        // V2
        require(config.destinationName.isNotBlank()) { "destinationName: empty" }
        require(config.destinationName.length <= MAX_DESTINATION_NAME_LENGTH) { "destinationName: too long" }
        // V3, V4
        require(destLat.isFinite() && destLat >= -90.0 && destLat <= 90.0) { "destLat: out of range" }
        require(destLng.isFinite() && destLng >= -180.0 && destLng < 180.0) { "destLng: out of range" }
        // V5, V6
        require(config.mode != AlarmModeMsg.DISTANCE || config.distanceThresholdM != null) {
            "distanceThresholdM: required"
        }
        require(config.mode != AlarmModeMsg.TIME || config.timeThresholdMin != null) {
            "timeThresholdMin: required"
        }
        // V7, V8: checked for every mode.
        config.distanceThresholdM?.let {
            require(it in 200L..10_000L) { "distanceThresholdM: out of range" }
        }
        config.timeThresholdMin?.let {
            require(it in 5L..60L) { "timeThresholdMin: out of range" }
        }
        // V9
        require(config.alarm.soundId.isNotEmpty()) { "alarm.soundId: empty" }
        val volume = config.alarm.volume
        require(volume.isFinite() && volume >= 0.0 && volume <= 1.0) { "alarm.volume: out of range" }
        // V10
        if (simulation != null) {
            require(simulation.traceAsset.isNotEmpty()) { "simulation.traceAsset: empty" }
            val speed = simulation.speedFactor
            require(speed.isFinite() && speed >= 1.0 && speed <= 600.0) {
                "simulation.speedFactor: out of range"
            }
        }
    }

    private inline fun require(ok: Boolean, message: () -> String) {
        if (!ok) throw FlutterError(BridgeErrors.INVALID_CONFIG, message(), null)
    }
}
