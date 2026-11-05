// Trip meta, snapshot file and store port (docs/specs/T17.md §4.3, §5.7).
import Foundation
import Trip

public struct RingSettings: Sendable, Codable, Equatable {
    public let soundId: String
    public let volume: Double
    public let rampUp: Bool
    public let vibration: String
    public let flash: Bool
    public let preferHeadphones: Bool
    public let dismissMethod: String

    public init(soundId: String, volume: Double, rampUp: Bool, vibration: String, flash: Bool, preferHeadphones: Bool,
                dismissMethod: String) {
        self.soundId = soundId
        self.volume = volume
        self.rampUp = rampUp
        self.vibration = vibration
        self.flash = flash
        self.preferHeadphones = preferHeadphones
        self.dismissMethod = dismissMethod
    }
}

/// Coordinate-free copy of TripConfigMsg (also ActiveTripMsg.config). description redacts destinationName.
public struct TripMeta: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let tripId: String
    public let destinationName: String
    public let mode: AlarmMode
    public let distanceThresholdM: Int?
    public let timeThresholdMin: Int?
    public let preAlertEnabled: Bool
    public let vehicleHint: VehicleKind
    public let alarm: RingSettings
    public let engineParamsJson: String?
    /// T18.1: the simulation of this trip; nil = a real trip.
    public let simulation: SimSpec?

    public init(tripId: String, destinationName: String, mode: AlarmMode, distanceThresholdM: Int?, timeThresholdMin: Int?,
                preAlertEnabled: Bool, vehicleHint: VehicleKind, alarm: RingSettings, engineParamsJson: String?,
                simulation: SimSpec? = nil) {
        self.tripId = tripId
        self.destinationName = destinationName
        self.mode = mode
        self.distanceThresholdM = distanceThresholdM
        self.timeThresholdMin = timeThresholdMin
        self.preAlertEnabled = preAlertEnabled
        self.vehicleHint = vehicleHint
        self.alarm = alarm
        self.engineParamsJson = engineParamsJson
        self.simulation = simulation
    }

    public var description: String { "TripMeta(\(tripId), <redacted>, simulated=\(simulation != nil))" }

    /// This meta with `simulation` set (the bridge maps SimulationMsg here).
    public func with(simulation s: SimSpec?) -> TripMeta {
        TripMeta(tripId: tripId, destinationName: destinationName, mode: mode, distanceThresholdM: distanceThresholdM,
                 timeThresholdMin: timeThresholdMin, preAlertEnabled: preAlertEnabled, vehicleHint: vehicleHint, alarm: alarm,
                 engineParamsJson: engineParamsJson, simulation: s)
    }
    public var debugDescription: String { description }

    public func config(destLat: Double, destLng: Double) -> TripConfig {
        TripConfig(tripId: tripId, destLat: destLat, destLng: destLng, mode: mode, distanceThresholdM: distanceThresholdM,
                   timeThresholdMin: timeThresholdMin, preAlertEnabled: preAlertEnabled, vehicleHint: vehicleHint)
    }
}

public struct StoredTrip: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    /// 1
    public let runtimeVersion: Int
    public let meta: TripMeta
    public let anchor: ClockAnchor
    /// TripEngine.encodeSnapshot (T10 §7.1, has coordinates).
    public let engineSnapshot: String
    public let savedAtWallMs: Int64

    public init(runtimeVersion: Int = 1, meta: TripMeta, anchor: ClockAnchor, engineSnapshot: String, savedAtWallMs: Int64) {
        self.runtimeVersion = runtimeVersion
        self.meta = meta
        self.anchor = anchor
        self.engineSnapshot = engineSnapshot
        self.savedAtWallMs = savedAtWallMs
    }

    public var description: String { "StoredTrip(<redacted>)" }
    public var debugDescription: String { description }
}

public enum StoredTripError: Error, Equatable, CustomStringConvertible {
    case corrupt, version
    public var description: String { self == .corrupt ? "storedTrip: corrupt" : "storedTrip: version" }
}

/// JSON; enums by name (AlarmMode.distance → "distance", …).
public enum StoredTripCodec {
    private struct MetaDTO: Codable {
        var tripId: String
        var destinationName: String
        var mode: String
        var distanceThresholdM: Int?
        var timeThresholdMin: Int?
        var preAlertEnabled: Bool
        var vehicleHint: String
        var alarm: RingSettings
        var engineParamsJson: String?
        /// T18.1: written only for a simulated trip.
        var simulation: SimSpec?
    }

    private struct DTO: Codable {
        var runtimeVersion: Int
        var meta: MetaDTO
        var anchor: ClockAnchor
        var engineSnapshot: String
        var savedAtWallMs: Int64
    }

    private struct VersionOnly: Codable { var runtimeVersion: Int }

    static func modeName(_ m: AlarmMode) -> String {
        switch m { case .distance: "distance"; case .time: "time"; case .smart: "smart" }
    }

    static func vehicleName(_ v: VehicleKind) -> String {
        switch v { case .train: "train"; case .coach: "coach"; case .bus: "bus"; case .unknown: "unknown" }
    }

    public static func encode(_ t: StoredTrip) -> Data {
        let m = t.meta
        let dto = DTO(runtimeVersion: t.runtimeVersion,
                      meta: MetaDTO(tripId: m.tripId, destinationName: m.destinationName, mode: modeName(m.mode),
                                    distanceThresholdM: m.distanceThresholdM, timeThresholdMin: m.timeThresholdMin,
                                    preAlertEnabled: m.preAlertEnabled, vehicleHint: vehicleName(m.vehicleHint), alarm: m.alarm,
                                    engineParamsJson: m.engineParamsJson, simulation: m.simulation),
                      anchor: t.anchor, engineSnapshot: t.engineSnapshot, savedAtWallMs: t.savedAtWallMs)
        // Encoding plain Codable values cannot fail.
        return (try? LedgerCodec.encode(dto)) ?? Data()
    }

    public static func decode(_ d: Data) throws(StoredTripError) -> StoredTrip {
        guard let v = try? JSONDecoder().decode(VersionOnly.self, from: d) else { throw .corrupt }
        if v.runtimeVersion != 1 { throw .version }
        guard let dto = try? JSONDecoder().decode(DTO.self, from: d) else { throw .corrupt }
        let m = dto.meta
        let modes: [String: AlarmMode] = ["distance": .distance, "time": .time, "smart": .smart]
        let vehicles: [String: VehicleKind] = ["train": .train, "coach": .coach, "bus": .bus, "unknown": .unknown]
        guard let mode = modes[m.mode], let vehicle = vehicles[m.vehicleHint] else { throw .corrupt }
        if let s = m.simulation, !(s.speedFactor.isFinite && s.speedFactor > 0) { throw .corrupt }
        let meta = TripMeta(tripId: m.tripId, destinationName: m.destinationName, mode: mode,
                            distanceThresholdM: m.distanceThresholdM, timeThresholdMin: m.timeThresholdMin,
                            preAlertEnabled: m.preAlertEnabled, vehicleHint: vehicle, alarm: m.alarm,
                            engineParamsJson: m.engineParamsJson, simulation: m.simulation)
        return StoredTrip(runtimeVersion: dto.runtimeVersion, meta: meta, anchor: dto.anchor, engineSnapshot: dto.engineSnapshot,
                          savedAtWallMs: dto.savedAtWallMs)
    }
}

/// Blocking; called on the store's own serial queue (FileRuntimeStore).
public protocol RuntimeStore: Sendable {
    /// missing → nil; corrupt/version → delete file, throw.
    func readActive() throws -> StoredTrip?
    func writeActive(_ t: StoredTrip) throws
    func deleteActive()
    /// missing/corrupt → .empty (corrupt: warn).
    func readLedger() -> AlarmLedger
    func writeLedger(_ l: AlarmLedger) throws
    func readRingEvents() -> [RingEventRec]
    func appendRingEvent(_ e: RingEventRec) throws
    func removeRingEvents(tripId: String)
    func writeFinished(_ r: FinishedRecord) throws
    func readFinished() -> [FinishedRecord]
    func deleteFinished(_ ids: [String])
    /// launch_action.json (T17.2 D7); missing/corrupt → nil.
    func readLaunchAction() -> LaunchActionRec?
    func writeLaunchAction(_ r: LaunchActionRec) throws
    func deleteLaunchAction()
}
