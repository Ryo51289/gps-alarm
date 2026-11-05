// CLLocation → engine fix (docs/specs/T17.md §5.4). Pure.
import Trip

public enum FixMapper {
    /// nil = dropped at the platform layer (invalid accuracy or coordinate); the runtime counts and journals it.
    public static func map(_ raw: RawFix, nowWallMs: Int64, nowTripMs: Int64) -> LocationFix? {
        if !(raw.horizontalAccuracyM > 0) || !raw.lat.isFinite || !raw.lng.isFinite { return nil }
        let ageMs = max(0, nowWallMs - raw.timestampWallMs)
        let speed: Double? = raw.speedMps >= 0 ? raw.speedMps : nil
        return LocationFix(atMs: nowTripMs, fixAtMs: nowTripMs - ageMs, lat: raw.lat, lng: raw.lng,
                           accuracyM: raw.horizontalAccuracyM, speedMps: speed)
    }
}

/// Keeps the ~1 Hz Core Location stream at the engine's sampling interval (D9). Pure state, in memory only.
public struct FixThrottle: Sendable, Equatable {
    public private(set) var lastForwardedFixAtMs: Int64?
    public let slackMs: Int64

    public init(slackMs: Int64) { self.slackMs = slackMs }

    /// True = forward to the engine (and remember it); false = drop (not an engine rejection).
    public mutating func forward(_ fix: LocationFix, intervalMs: Int64) -> Bool {
        if let last = lastForwardedFixAtMs, fix.fixAtMs - last < intervalMs - slackMs { return false }
        lastForwardedFixAtMs = fix.fixAtMs
        return true
    }

    public mutating func reset() { lastForwardedFixAtMs = nil }
}

/// Sampling tier → Core Location accuracy + throttle interval (§5.4).
public enum LocationRequestMapper {
    public static func spec(_ policy: SamplingPolicy?, _ params: EngineParams) -> LocationRequestSpec {
        guard let p = policy else {
            return LocationRequestSpec(accuracy: .best, intervalMs: Int64(params.samplingDenseIntervalS) * 1000)
        }
        let acc: LocationAccuracyClass
        switch p.tier {
        case .sparse: acc = .hundredMeters
        case .medium: acc = .nearestTenMeters
        case .dense: acc = .best
        }
        return LocationRequestSpec(accuracy: acc, intervalMs: Int64(p.intervalS) * 1000)
    }
}
