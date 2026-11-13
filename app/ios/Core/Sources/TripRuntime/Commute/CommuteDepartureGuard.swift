// "Not left the pickup point" guard of an automatic trip (docs/specs/T23.8.md §5.4, D11, D17). Pure, outside the engine.
// PRIVACY: distances live only in the state; description hides them.
import Foundation

public struct DepartureGuardState: Codable, Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let tripId: String
    /// TripClock elapsed time when the trip started.
    public let armedAtElapsedMs: Int64
    /// First valid distance to the destination.
    public var startDistanceM: Int?
    /// Smallest distance seen so far.
    public var minDistanceM: Int?
    /// Once true the guard never stops the trip.
    public var departed: Bool
    /// D17: the trip alarmed before `departed` (set by the controller, C2). A missing key reads as false (C1 state files).
    public var alarmedBeforeDeparture: Bool

    public init(tripId: String, armedAtElapsedMs: Int64, startDistanceM: Int? = nil, minDistanceM: Int? = nil,
                departed: Bool = false, alarmedBeforeDeparture: Bool = false) {
        self.tripId = tripId
        self.armedAtElapsedMs = armedAtElapsedMs
        self.startDistanceM = startDistanceM
        self.minDistanceM = minDistanceM
        self.departed = departed
        self.alarmedBeforeDeparture = alarmedBeforeDeparture
    }

    private enum CodingKeys: String, CodingKey {
        case tripId, armedAtElapsedMs, startDistanceM, minDistanceM, departed, alarmedBeforeDeparture
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(tripId: try c.decode(String.self, forKey: .tripId),
                  armedAtElapsedMs: try c.decode(Int64.self, forKey: .armedAtElapsedMs),
                  startDistanceM: try c.decodeIfPresent(Int.self, forKey: .startDistanceM),
                  minDistanceM: try c.decodeIfPresent(Int.self, forKey: .minDistanceM),
                  departed: try c.decode(Bool.self, forKey: .departed),
                  alarmedBeforeDeparture: try c.decodeIfPresent(Bool.self, forKey: .alarmedBeforeDeparture) ?? false)
    }

    public var description: String {
        "DepartureGuardState(\(tripId), armedAt=\(armedAtElapsedMs), fix=\(startDistanceM != nil), departed=\(departed), "
            + "alarmedBeforeDeparture=\(alarmedBeforeDeparture))"
    }

    public var debugDescription: String { description }
}

public enum DepartureGuard {
    /// Called for every Step of the armed trip. `distanceM` = the Step's distance to the destination (nil without a fix).
    /// Returns stop = true when the trip must be cancelled (`userAction(.stopTrip)`).
    public static func step(_ input: DepartureGuardState, distanceM: Int?, elapsedMs: Int64,
                            c: CommuteConstants = .default) -> (DepartureGuardState, stop: Bool) {
        var s = input
        if s.departed { return (s, false) }
        if let d = distanceM {
            if s.startDistanceM == nil { s.startDistanceM = d }
            s.minDistanceM = min(s.minDistanceM ?? d, d)
        }
        if let start = s.startDistanceM, let low = s.minDistanceM, start - low >= c.departMinProgressM {
            s.departed = true
            return (s, false)
        }
        // Also without any fix.
        let (since, overflow) = elapsedMs.subtractingReportingOverflow(s.armedAtElapsedMs)
        if !overflow && since >= c.departTimeoutMs { return (s, true) }
        return (s, false)
    }
}
