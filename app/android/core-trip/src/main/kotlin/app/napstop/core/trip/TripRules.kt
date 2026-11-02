package app.napstop.core.trip

/** Pure rules shared with Flutter (T25 re-implements §4.7 in Dart with the same integer formula). */
object TripRules {
    /** T10 §4.7: integers only, so Kotlin, Swift and Dart agree exactly. */
    fun shortDistanceWarning(thresholdM: Int, vehicle: VehicleKind, params: EngineParams): Boolean =
        thresholdM * 36 < params.shortDistanceWarnS * expectedSpeedKmh(vehicle, params) * 10
}
