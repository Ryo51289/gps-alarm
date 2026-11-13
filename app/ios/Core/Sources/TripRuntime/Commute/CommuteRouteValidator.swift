// Validation of a commute route before it is stored (docs/specs/T23.8.md §5.7 setRoute, D12, §5.6, §5.6a). Pure.
// Same rules as app/lib/features/commute/domain/commute_validation.dart; shared cases in fixtures/commute/validation_cases.json.
// Messages name the field and the rule only, never the value (T10 §10); wire code `invalid-config`.
import Foundation
import Trip

public enum CommuteRouteValidator {
    public static let maxNameLength = TripConfigValidator.maxDestinationNameLength

    /// nil = valid; else "<field>: <rule>". The first failing rule in this order: revision, names, coordinates,
    /// windows (towardB then towardA), templates (V1–V11, towardB then towardA), A–B separation.
    /// Windows are checked even when their direction (or the route) is off: the stored config stays valid.
    public static func validate(_ r: CommuteRoute, constants c: CommuteConstants = .default) -> String? {
        if r.revision < 0 { return "revision: outOfRange" }
        if let e = name(r.nameA, "nameA") ?? name(r.nameB, "nameB") { return e }
        if let e = latitude(r.aLat, "aLat") ?? longitude(r.aLng, "aLng") ?? latitude(r.bLat, "bLat")
            ?? longitude(r.bLng, "bLng") { return e }
        if let e = window(r.towardB, "towardB", c) ?? window(r.towardA, "towardA", c) { return e }
        if let e = template(r.templateTowardB, "templateTowardB", destLat: r.bLat, destLng: r.bLng) { return e }
        if let e = template(r.templateTowardA, "templateTowardA", destLat: r.aLat, destLng: r.aLng) { return e }
        if distanceM(r.aLat, r.aLng, r.bLat, r.bLng) < Double(requiredSeparationM(r, constants: c)) {
            return "route: tooClose"
        }
        return nil
    }

    /// D12 / §5.6a: max(COMMUTE_MIN_AB_M, ceil(max(R(templateTowardB), R(templateTowardA)) + COMMUTE_AB_MARGIN_M)).
    public static func requiredSeparationM(_ r: CommuteRoute, constants c: CommuteConstants = .default) -> Int {
        let reach = max(stationaryReachM(r.templateTowardB), stationaryReachM(r.templateTowardA))
        let need = max(c.minAbM, (reach + c.abThresholdMarginM).rounded(.up))
        return need.isFinite ? Int(need) : Int.max
    }

    /// Both numbers of a `route: tooClose` error (§5.6a `details`): actualM rounded down to the metre. No coordinates.
    public static func separation(_ r: CommuteRoute, constants c: CommuteConstants = .default)
        -> (requiredM: Int, actualM: Int) {
        let d = distanceM(r.aLat, r.aLng, r.bLat, r.bLng)
        return (requiredSeparationM(r, constants: c), d.isFinite ? Int(d.rounded(.down)) : 0)
    }

    /// §5.6a R(m): the largest distance to the destination at which the engine can alarm in this template's mode while the
    /// vehicle has not moved yet (good GPS, speed not established), with the params the trip will run with
    /// (`EngineParamsFactory.fromOverrides(engineParamsJson)`, as TripRuntime.start). Mirrors Trip ModeRules/Estimator
    /// (internal there); CU28 checks it against the real engine.
    public static func stationaryReachM(_ m: TripMeta) -> Double {
        let p = EngineParamsFactory.fromOverrides(m.engineParamsJson)
        switch m.mode {
        case .distance:
            return Double(m.distanceThresholdM ?? 0) * p.distanceModeFactor
        case .time:
            return max(Double(p.arrivedRadiusM), reach(Double((m.timeThresholdMin ?? 0) * 60), m.vehicleHint, p))
        case .smart:
            return max(slowDistM(p), Double(p.smartFloorM), reach(Double(p.smartTargetS), m.vehicleHint, p))
        }
    }

    /// Estimator.expectedSpeedKmh.
    static func hintKmh(_ h: VehicleKind, _ p: EngineParams) -> Int {
        switch h {
        case .train: p.expectedSpeedKmhTrain
        case .coach: p.expectedSpeedKmhCoach
        case .bus: p.expectedSpeedKmhBus
        case .unknown: p.expectedSpeedKmhUnknown
        }
    }

    /// Largest dNow with eta = dNow·k/v + penalty ≤ t before the speed is established (v = hint speed, k = routeFactorPrior).
    /// No ETA at all when the hint speed is below minSpeedForEtaMps (Estimator: etaS = nil).
    static func reach(_ t: Double, _ h: VehicleKind, _ p: EngineParams) -> Double {
        let v = Double(hintKmh(h, p)) / 3.6
        guard v >= p.minSpeedForEtaMps else { return 0 }
        return max(0, t - Double(p.etaStopPenaltyS)) * v / p.routeFactorPrior
    }

    /// ModeRules.slowDistM (≥ smartFloorM).
    static func slowDistM(_ p: EngineParams) -> Double {
        max(Double(p.smartTargetS * p.smartSlowSpeedKmh) / 3.6, Double(p.smartFloorM))
    }

    /// Great-circle distance in metres (haversine, mean Earth radius), same formula as Dart `destination_logic.distanceM`.
    public static func distanceM(_ aLat: Double, _ aLng: Double, _ bLat: Double, _ bLng: Double) -> Double {
        let earthRadiusM = 6_371_008.8
        func rad(_ deg: Double) -> Double { deg * Double.pi / 180 }
        let dLat = rad(bLat - aLat)
        let dLng = rad(bLng - aLng)
        let sLat = sin(dLat / 2)
        let sLng = sin(dLng / 2)
        let h = sLat * sLat + cos(rad(aLat)) * cos(rad(bLat)) * sLng * sLng
        return 2 * earthRadiusM * asin(min(1, h.squareRoot()))
    }

    private static func name(_ s: String, _ field: String) -> String? {
        if s.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) { return "\(field): empty" }
        if s.utf16.count > maxNameLength { return "\(field): tooLong" }
        return nil
    }

    private static func latitude(_ v: Double, _ field: String) -> String? {
        v.isFinite && v >= -90 && v <= 90 ? nil : "\(field): outOfRange"
    }

    /// [-180, 180) like V4.
    private static func longitude(_ v: Double, _ field: String) -> String? {
        v.isFinite && v >= -180 && v < 180 ? nil : "\(field): outOfRange"
    }

    private static func window(_ w: CommuteWindow, _ field: String, _ c: CommuteConstants) -> String? {
        if !(0...1439).contains(w.startMinute) { return "\(field).startMinute: outOfRange" }
        if !(1...1440).contains(w.endMinute) { return "\(field).endMinute: outOfRange" }
        if w.endMinute <= w.startMinute { return "\(field): order" }
        let len = w.endMinute - w.startMinute
        if len < c.windowMinMin { return "\(field): tooShort" }
        if len > c.windowMaxMin { return "\(field): tooLong" }
        if !(1...127).contains(w.weekdayMask) { return "\(field).weekdayMask: outOfRange" }
        return nil
    }

    private static func template(_ m: TripMeta, _ field: String, destLat: Double, destLng: Double) -> String? {
        if m.simulation != nil { return "\(field).simulation: notAllowed" }
        guard let e = TripConfigValidator.validate(m, destLat: destLat, destLng: destLng, simulation: nil) else { return nil }
        return "\(field).\(e)"
    }
}
