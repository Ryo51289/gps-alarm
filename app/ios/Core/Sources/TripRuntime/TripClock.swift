// Trip clock (docs/specs/T17.md §5.3, T18.1 §3): wall anchor + ContinuousClock, never goes back. A simulated trip runs it
// at `speed` trip ms per real ms (T18.1 D1); `speed == 1.0` takes the integer path, so a real trip computes exactly what it
// did before T18.1 (SIU01).

public struct ClockAnchor: Sendable, Codable, Equatable {
    public let wallMs: Int64
    public let elapsedMs: Int64
    public let bootSessionId: String?
    /// Trip ms per real ms: 1.0 for a real trip, the simulation speed for a simulated one (T18.1 D1).
    public let speed: Double

    public init(wallMs: Int64, elapsedMs: Int64, bootSessionId: String?, speed: Double = 1.0) {
        self.wallMs = wallMs
        self.elapsedMs = elapsedMs
        self.bootSessionId = bootSessionId
        self.speed = speed
    }

    public static func now(_ t: TimeSource) -> ClockAnchor {
        ClockAnchor(wallMs: t.wallMs(), elapsedMs: t.elapsedMs(), bootSessionId: t.bootSessionId())
    }

    private enum CodingKeys: String, CodingKey { case wallMs, elapsedMs, bootSessionId, speed }

    /// The key `speed` is written only when ≠ 1.0, so the snapshot of a real trip keeps the T17 bytes (SIU04).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(wallMs, forKey: .wallMs)
        try c.encode(elapsedMs, forKey: .elapsedMs)
        try c.encodeIfPresent(bootSessionId, forKey: .bootSessionId)
        if speed != 1.0 { try c.encode(speed, forKey: .speed) }
    }

    /// Missing `speed` = 1.0; not finite or ≤ 0 = a decoding error.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        wallMs = try c.decode(Int64.self, forKey: .wallMs)
        elapsedMs = try c.decode(Int64.self, forKey: .elapsedMs)
        bootSessionId = try c.decodeIfPresent(String.self, forKey: .bootSessionId)
        let s = try c.decodeIfPresent(Double.self, forKey: .speed) ?? 1.0
        guard s.isFinite, s > 0 else {
            throw DecodingError.dataCorruptedError(forKey: .speed, in: c, debugDescription: "speed invalid")
        }
        speed = s
    }
}

/// Duration conversions of a clock with a speed factor (T18 §3, same as Kotlin `ClockMath`).
public enum ClockMath {
    /// Real duration → trip duration.
    public static func up(_ d: Int64, _ speed: Double) -> Int64 { speed == 1.0 ? d : Int64((Double(d) * speed).rounded(.down)) }

    /// Trip duration → real duration; ceil: when it is due, the trip time has been reached.
    public static func down(_ d: Int64, _ speed: Double) -> Int64 { speed == 1.0 ? d : Int64((Double(d) / speed).rounded(.up)) }
}

public struct TripClock: Sendable {
    public private(set) var anchor: ClockAnchor
    public private(set) var lastIssued: Int64

    public init(anchor: ClockAnchor) {
        self.anchor = anchor
        lastIssued = anchor.wallMs
    }

    public var speed: Double { anchor.speed }

    private func tripAt(_ elapsed: Int64) -> Int64 { anchor.wallMs + ClockMath.up(elapsed - anchor.elapsedMs, anchor.speed) }

    /// max(lastIssued, anchor.wall + up(elapsed − anchor.elapsed)) (T10 §2.6).
    public mutating func now(_ t: TimeSource) -> Int64 {
        let v = tripAt(t.elapsedMs())
        if v > lastIssued { lastIssued = v }
        return lastIssued
    }

    public static func sameBoot(_ a: ClockAnchor, _ t: TimeSource) -> Bool {
        if let mine = a.bootSessionId, let cur = t.bootSessionId() { return mine == cur }
        return t.elapsedMs() >= a.elapsedMs
    }

    public static func anchorValid(_ a: ClockAnchor, _ t: TimeSource, driftMaxMs: Int64) -> Bool {
        guard sameBoot(a, t) else { return false }
        let projected = a.wallMs + (t.elapsedMs() - a.elapsedMs)
        let drift = projected - t.wallMs()
        return (drift < 0 ? -drift : drift) <= driftMaxMs
    }

    /// For Alarm.Schedule.fixed(Date) [I13]: wall + down(max(0, tTrip − now)).
    public mutating func toWall(_ tripMs: Int64, _ t: TimeSource) -> Int64 {
        let n = now(t)
        return t.wallMs() + ClockMath.down(max(0, tripMs - n), anchor.speed)
    }

    /// now − up(max(0, wall − w)). Future wall times map to now.
    public mutating func toTrip(wall w: Int64, _ t: TimeSource) -> Int64 {
        let n = now(t)
        return n - ClockMath.up(max(0, t.wallMs() - w), anchor.speed)
    }

    /// A wall time in the future, on the trip clock: now + up(max(0, w − wall)). Past wall times map to now.
    public mutating func futureWallToTrip(_ w: Int64, _ t: TimeSource) -> Int64 {
        let n = now(t)
        return n + ClockMath.up(max(0, w - t.wallMs()), anchor.speed)
    }

    /// Real ms until trip time `tripMs`; 0 if reached.
    public mutating func realDelayMs(_ tripMs: Int64, _ t: TimeSource) -> Int64 {
        let n = now(t)
        return ClockMath.down(max(0, tripMs - n), anchor.speed)
    }

    /// New speed from now on (T18.1 D1): continuous, never goes back. A speed that is not finite or ≤ 0 is refused (false,
    /// clock unchanged), as Kotlin `rebase` throws (SM03).
    @discardableResult
    public mutating func rebase(_ newSpeed: Double, _ t: TimeSource) -> Bool {
        guard newSpeed.isFinite, newSpeed > 0 else { return false }
        let e = t.elapsedMs()
        let n = max(lastIssued, tripAt(e))
        lastIssued = n
        anchor = ClockAnchor(wallMs: n, elapsedMs: e, bootSessionId: anchor.bootSessionId, speed: newSpeed)
        return true
    }

    /// T18.1 D8 (round 2): new speed from trip time `atTripMs`, the trip time of the Step being handled (≤ now). A
    /// simulated trip's catch-up may run behind its clock (late timer, suspended app); restarting from the event time keeps
    /// the trip time between the event and the clock from being skipped (at 600× a 2 s late timer is 20 trip minutes).
    /// Only trip times up to `atTripMs` have reached the engine, so the engine time never goes back. Same refusals as
    /// `rebase(_:_:)`; `atTripMs` above now is clamped to now.
    @discardableResult
    public mutating func rebase(_ newSpeed: Double, _ t: TimeSource, atTripMs: Int64) -> Bool {
        guard newSpeed.isFinite, newSpeed > 0 else { return false }
        let e = t.elapsedMs()
        let n = min(atTripMs, max(lastIssued, tripAt(e)))
        lastIssued = n
        anchor = ClockAnchor(wallMs: n, elapsedMs: e, bootSessionId: anchor.bootSessionId, speed: newSpeed)
        return true
    }
}
