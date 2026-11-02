// Short-distance warning for screen 3 (T10 §4.7), integers only.

public enum TripRules {
    /// T10 §4.7, integers only: thr · 36 < shortDistanceWarnS · expectedSpeedKmh(vehicle) · 10.
    public static func shortDistanceWarning(thresholdM: Int, vehicle: VehicleKind, params: EngineParams) -> Bool {
        thresholdM * 36 < params.shortDistanceWarnS * Estimator.expectedSpeedKmh(vehicle, params) * 10
    }
}
