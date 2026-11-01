package app.napstop.core.bridge

/** Error codes sent to Dart as FlutterError.code (spec T14 §4). Mirrors Dart BridgeErrorCode. */
object BridgeErrors {
    const val INVALID_CONFIG = "invalid-config"
    const val TRIP_ACTIVE = "trip-active"
    const val SIMULATION_UNAVAILABLE = "simulation-unavailable"
    const val PERMISSION_MISSING = "permission-missing"
    const val NOT_FOREGROUND = "not-foreground"
    const val START_FAILED = "start-failed"
    const val REQUEST_IN_PROGRESS = "request-in-progress"
    const val INTERNAL = "internal"

    val ALL: List<String> =
        listOf(
            INVALID_CONFIG,
            TRIP_ACTIVE,
            SIMULATION_UNAVAILABLE,
            PERMISSION_MISSING,
            NOT_FOREGROUND,
            START_FAILED,
            REQUEST_IN_PROGRESS,
            INTERNAL,
        )
}
