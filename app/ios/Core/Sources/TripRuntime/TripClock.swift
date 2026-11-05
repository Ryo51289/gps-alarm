// Trip clock (docs/specs/T17.md §5.3): wall anchor + ContinuousClock, never goes back.

public struct ClockAnchor: Sendable, Codable, Equatable {
    public let wallMs: Int64
    public let elapsedMs: Int64
    public let bootSessionId: String?
    public init(wallMs: Int64, elapsedMs: Int64, bootSessionId: String?) {
        self.wallMs = wallMs
        self.elapsedMs = elapsedMs
        self.bootSessionId = bootSessionId
    }

    public static func now(_ t: TimeSource) -> ClockAnchor {
        ClockAnchor(wallMs: t.wallMs(), elapsedMs: t.elapsedMs(), bootSessionId: t.bootSessionId())
    }
}

public struct TripClock: Sendable {
    public let anchor: ClockAnchor
    public private(set) var lastIssued: Int64

    public init(anchor: ClockAnchor) {
        self.anchor = anchor
        lastIssued = anchor.wallMs
    }

    /// max(lastIssued, anchor.wall + (elapsed − anchor.elapsed)) (T10 §2.6).
    public mutating func now(_ t: TimeSource) -> Int64 {
        let v = anchor.wallMs + (t.elapsedMs() - anchor.elapsedMs)
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

    /// For Alarm.Schedule.fixed(Date) [I13]: wall + max(0, tTrip − now).
    public mutating func toWall(_ tripMs: Int64, _ t: TimeSource) -> Int64 {
        let n = now(t)
        return t.wallMs() + max(0, tripMs - n)
    }

    /// now − max(0, wall − w).
    public mutating func toTrip(wall w: Int64, _ t: TimeSource) -> Int64 {
        let n = now(t)
        return n - max(0, t.wallMs() - w)
    }
}
