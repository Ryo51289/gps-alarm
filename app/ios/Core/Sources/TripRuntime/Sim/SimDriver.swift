// Event queue of a simulated trip on the trip clock (docs/specs/T18.1.md D2–D4, §4). Pure. Every engine input of a
// simulated trip (GPX sample, engine wake, virtual fallback ring) comes out of here in trip-time order and carries the
// trip time of the event itself, never the time it is processed: the engine sequence does not depend on the speed or on
// how late the real timer fires (the T18.2 bug).

public enum SimEvent: Sendable, Equatable {
    case fallbackDue(atTripMs: Int64)
    case engineWake(atTripMs: Int64)
    case sample(TraceSample, atTripMs: Int64)

    public var atTripMs: Int64 {
        switch self {
        case let .fallbackDue(t), let .engineWake(t), let .sample(_, t): t
        }
    }
}

public struct SimDriver: Sendable {
    public let trace: SimTrace
    /// Trip time of sample t = 0.
    public let startTripMs: Int64
    /// D6: the one virtual fallback slot (setting it again replaces it).
    public var fallbackDueTripMs: Int64?
    /// = setTimer(dueTripMs) of the EffectPlanner on a simulated trip.
    public var engineWakeTripMs: Int64?
    /// Next sample not yet delivered or dropped.
    public private(set) var nextIndex = 0
    /// tMs of the last delivered sample (D4).
    public private(set) var lastDeliveredTMs: Int64?
    /// Trip time of the last event handed out: an event due earlier comes out at this time (never back).
    public private(set) var cursorTripMs: Int64

    public init(trace: SimTrace, startTripMs: Int64) {
        self.trace = trace
        self.startTripMs = startTripMs
        cursorTripMs = startTripMs
    }

    private func sampleTripMs(_ i: Int) -> Int64 { startTripMs + trace.samples[i].tMs }

    /// D4 (`policy`, README §6): the first sample, or tMs − tLastMs ≥ intervalMs. nil interval = no location request.
    private func eligible(_ i: Int, _ intervalMs: Int64?) -> Bool {
        guard let iv = intervalMs else { return false }
        guard let last = lastDeliveredTMs else { return true }
        return trace.samples[i].tMs - last >= iv
    }

    /// min(fallback, engine wake, next sample deliverable under `intervalMs`); nil = nothing left. Times before the
    /// cursor come out at the cursor.
    public func nextDueTripMs(intervalMs: Int64?) -> Int64? {
        var best = [fallbackDueTripMs, engineWakeTripMs].compactMap { $0 }.min()
        if intervalMs != nil {
            var i = nextIndex
            while i < trace.samples.count {
                if eligible(i, intervalMs) {
                    let s = sampleTripMs(i)
                    best = min(best ?? s, s)
                    break
                }
                i += 1
            }
        }
        return best.map { max($0, cursorTripMs) }
    }

    /// Takes the next event with trip time ≤ `upTo` in the order of D3 (fallback → engine wake → sample at the same
    /// time); nil if none. A due sample that is not deliverable under `intervalMs` is dropped (like a GPS without a
    /// request), never delivered later.
    public mutating func pop(upTo: Int64, intervalMs: Int64?) -> SimEvent? {
        while true {
            let f = fallbackDueTripMs.map { max($0, cursorTripMs) }
            let w = engineWakeTripMs.map { max($0, cursorTripMs) }
            let s = nextIndex < trace.samples.count ? max(sampleTripMs(nextIndex), cursorTripMs) : nil
            guard let m = [f, w, s].compactMap({ $0 }).min(), m <= upTo else { return nil }
            cursorTripMs = m
            if f == m {
                fallbackDueTripMs = nil
                return .fallbackDue(atTripMs: m)
            }
            if w == m {
                engineWakeTripMs = nil
                return .engineWake(atTripMs: m)
            }
            let i = nextIndex
            nextIndex += 1
            if eligible(i, intervalMs) {
                lastDeliveredTMs = trace.samples[i].tMs
                return .sample(trace.samples[i], atTripMs: m)
            }
        }
    }

    /// No sample left (the engine may still wake).
    public var traceEnded: Bool { nextIndex >= trace.samples.count }
}
