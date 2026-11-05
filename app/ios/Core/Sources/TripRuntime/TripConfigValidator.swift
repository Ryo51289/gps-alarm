// Safety net for TripHostApi.startTrip (T14 §6, V1–V11), port of Android bridge/TripConfigValidator.kt. Pure.
// Messages name the field and the rule only, never the value (T10 §10).
import Foundation

public struct SimulationInput: Sendable, Equatable {
    public let traceAsset: String
    public let speedFactor: Double
    public init(traceAsset: String, speedFactor: Double) {
        self.traceAsset = traceAsset
        self.speedFactor = speedFactor
    }
}

public enum TripConfigValidator {
    public static let maxDestinationNameLength = 200
    /// V11 (T14.1): UTF-16 code units (Dart String.length, Kotlin String.length).
    public static let maxEngineParamsJsonLength = 16_384

    /// nil = valid; else "<field>: <rule>" (wire code `invalid-config`).
    public static func validate(_ m: TripMeta, destLat: Double, destLng: Double, simulation: SimulationInput?) -> String? {
        // V1
        let idOk = !m.tripId.isEmpty && m.tripId.utf8.count <= 64
            && m.tripId.unicodeScalars.allSatisfy { s in
                (s >= "A" && s <= "Z") || (s >= "a" && s <= "z") || (s >= "0" && s <= "9") || s == "_" || s == "-"
            }
        if !idOk { return "tripId: format" }
        // V2 (Kotlin isNotBlank: whitespace only is blank)
        if m.destinationName.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) {
            return "destinationName: empty"
        }
        if m.destinationName.utf16.count > maxDestinationNameLength { return "destinationName: too long" }
        // V3, V4
        if !(destLat.isFinite && destLat >= -90.0 && destLat <= 90.0) { return "destLat: out of range" }
        if !(destLng.isFinite && destLng >= -180.0 && destLng < 180.0) { return "destLng: out of range" }
        // V5, V6
        if m.mode == .distance && m.distanceThresholdM == nil { return "distanceThresholdM: required" }
        if m.mode == .time && m.timeThresholdMin == nil { return "timeThresholdMin: required" }
        // V7, V8: every mode.
        if let d = m.distanceThresholdM, !(200...10_000).contains(d) { return "distanceThresholdM: out of range" }
        if let t = m.timeThresholdMin, !(5...60).contains(t) { return "timeThresholdMin: out of range" }
        // V9
        if m.alarm.soundId.isEmpty { return "alarm.soundId: empty" }
        let v = m.alarm.volume
        if !(v.isFinite && v >= 0.0 && v <= 1.0) { return "alarm.volume: out of range" }
        // V10
        if let s = simulation {
            if s.traceAsset.isEmpty { return "simulation.traceAsset: empty" }
            if !(s.speedFactor.isFinite && s.speedFactor >= 1.0 && s.speedFactor <= 600.0) {
                return "simulation.speedFactor: out of range"
            }
        }
        // V11: length only; the engine validates the content (T10 §5).
        if let j = m.engineParamsJson, j.utf16.count > maxEngineParamsJsonLength { return "engineParamsJson: too long" }
        return nil
    }
}
