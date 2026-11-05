// Simulated trips (docs/specs/T18.1.md §4): bundled trace samples, the simulation of a trip, trace ids, the asset port.
// Port of Kotlin `sim/SimTrace.kt`. Nothing here prints a coordinate.
import Foundation

/// One GPX sample of a bundled trace (fixtures/traces/README.md §2); `t` = seconds from the first sample.
public struct TraceSample: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    /// Whole seconds from the first sample (= Kotlin `TraceSample.t`).
    public let t: Int
    public let lat: Double
    public let lng: Double
    /// napstop:acc, > 0.
    public let accM: Double
    /// napstop:spd, ≥ 0; nil = the device reported no speed.
    public let spdMps: Double?
    /// Milliseconds from the first sample (T18.1 round 2: a GPX time with fractional seconds keeps its milliseconds; the
    /// bundled traces use whole seconds, so `tMs == t·1000`). The simulation runs on this.
    public let tMs: Int64

    /// `tMs` nil = `t`·1000.
    public init(t: Int, lat: Double, lng: Double, accM: Double, spdMps: Double?, tMs: Int64? = nil) {
        self.t = t
        self.tMs = tMs ?? Int64(t) * 1000
        self.lat = lat
        self.lng = lng
        self.accM = accM
        self.spdMps = spdMps
    }

    public var description: String { "TraceSample(t=\(t), position=<redacted>)" }
    public var debugDescription: String { description }
}

/// A parsed trace: `samples` non-empty, tMs strictly increasing, samples[0].tMs == 0.
public struct SimTrace: Sendable, CustomStringConvertible {
    public let id: String
    public let samples: [TraceSample]

    public init(id: String, samples: [TraceSample]) {
        precondition(!samples.isEmpty && samples[0].tMs == 0, "samples")
        self.id = id
        self.samples = samples
    }

    public var description: String { "SimTrace(id=\(id), samples=\(samples.count))" }
}

/// The simulation of a trip (T18.1 D1, D15): bundled trace id and speed factor (1..600, UI 1/10/60).
public struct SimSpec: Sendable, Codable, Equatable {
    public let traceId: String
    public let speedFactor: Double

    public init(traceId: String, speedFactor: Double) {
        self.traceId = traceId
        self.speedFactor = speedFactor
    }
}

/// Trace ids (README §1, T18 D11): never a path.
public enum SimTraceIds {
    public static let maxLength = 64

    /// `^[a-z0-9]+(_[a-z0-9]+)*$`, at most 64 characters.
    public static func valid(_ id: String) -> Bool {
        let b = Array(id.utf8)
        guard !b.isEmpty, b.count <= maxLength, b.first != 0x5F, b.last != 0x5F else { return false }
        var prevUnderscore = false
        for c in b {
            let isUnderscore = c == 0x5F
            let ok = (c >= 0x61 && c <= 0x7A) || (c >= 0x30 && c <= 0x39) || isUnderscore
            if !ok || (isUnderscore && prevUnderscore) { return false }
            prevUnderscore = isUnderscore
        }
        return true
    }
}

/// A GPX that breaks README §2; `rule` names the rule, never a value.
public struct TraceFormatError: Error, Equatable, CustomStringConvertible {
    public let rule: String
    public init(rule: String) { self.rule = rule }
    public var description: String { "TraceFormatError(\(rule))" }
}

/// Bundled traces (T18.1 D12). Blocking; the runtime calls it off its queue with a time budget. nil = no such trace.
public protocol TraceStore: Sendable {
    func open(_ traceId: String) -> Data?
}

/// Default port: no trace at all (every simulated start is `simulation-unavailable` "TraceNotFound").
public struct NoTraceStore: TraceStore {
    public init() {}
    public func open(_ traceId: String) -> Data? { nil }
}
