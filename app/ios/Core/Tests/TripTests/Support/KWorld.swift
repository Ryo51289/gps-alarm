@testable import Trip

/// Mirror of the Kotlin test support (`support/States.kt`, `support/EngineDriver.kt`, `support/TestGeo.kt`) used by the T10.5
/// ports (T105*, TesterT132*): trip start S, destination (0, 106), `cfg`, `trackingState`, `driverFrom`, `pointOnMeridian`,
/// `jitter`. Same arithmetic and argument order as Kotlin, so the trips and the printed numbers are the Kotlin ones.
enum KW {
    static let S: Int64 = 1_800_000_000_000
    static let destLat = 0.0
    static let destLng = 106.0
    static let K = Geo.kMetresPerDegLat

    struct LatLng: Sendable, Equatable {
        let lat: Double
        let lng: Double
    }

    /// Kotlin `TestGeo.pointOnMeridian(DEST, d)`: due south of the destination at about d metres (negative d = north).
    static func pointOnMeridian(_ d: Double) -> LatLng { LatLng(lat: destLat - d / K, lng: destLng) }

    /// Kotlin `TestGeo.jitter(p, eastM, northM)`.
    static func jitter(_ p: LatLng, _ eastM: Double, _ northM: Double) -> LatLng {
        LatLng(lat: p.lat + northM / K, lng: p.lng + eastM / (K * Geo.cosDeg(p.lat)))
    }

    static func distToDest(_ p: LatLng) -> Double { Geo.distanceM(p.lat, p.lng, destLat, destLng) }

    /// Kotlin `cfg(mode, thr, thrMin, preAlert, hint)`: DISTANCE defaults to 1000 m, TIME to 15 min.
    static func cfg(_ mode: AlarmMode = .distance, thr: Int? = nil, thrMin: Int? = nil, preAlert: Bool = true,
                    hint: VehicleKind = .train) -> TripConfig {
        TripConfig(tripId: "trip-1", destLat: destLat, destLng: destLng, mode: mode,
                   distanceThresholdM: thr ?? (mode == .distance ? 1000 : nil), timeThresholdMin: thrMin ?? (mode == .time ? 15 : nil),
                   preAlertEnabled: preAlert, vehicleHint: hint)
    }

    static func params(_ json: String) -> EngineParams {
        let r = EngineParamsFactory.parseOverrides(json)
        precondition(!r.malformed && r.rejected.isEmpty, "test params rejected: \(r.rejected)")
        return r.params
    }

    /// Kotlin `trackingState(...)` with every parameter and default of `support/States.kt` (same order).
    static func trackingState(
        _ config: TripConfig = cfg(), p: EngineParams = .defaults, now: Int64 = S, startedAt: Int64 = S, d: Double = 50_000.0,
        ground: Double? = 15.0, closing: Double? = 12.5, established: Bool = true, gps: GpsStatus = .ok, lastFixAt: Int64? = nil,
        acc: Double = 8.0, inStop: Bool = false, slow: Bool = false, cvGuard: [Double] = [], tier: SamplingTier = .dense,
        policyAtFix: Int? = nil, phase: TripPhase = .tracking, maxTripS: Int? = nil, dStart: Double? = nil, minD: Double? = nil,
        battery: BatteryState = .initial, alarm: AlarmState = .empty, fallback: FallbackState = .cleared, preAlertArmed: Bool = true
    ) -> EngineState {
        let fixAt = lastFixAt ?? now
        let pt = pointOnMeridian(d)
        let fix = FixRec(fixAtMs: fixAt, lat: pt.lat, lng: pt.lng, accM: acc, d: d, groundSample: nil)
        let pol = SamplingPlanner.policyFor(tier, p, maxSaving: false)
        var s = EngineState.initial(config: config, params: p, nowMs: startedAt)
        s.nowMs = now; s.phase = phase; s.gps = gps; s.last = fix; s.recent = [fix]; s.dSmooth = d; s.dStartM = dStart ?? d + 20_000.0
        s.minD = minD ?? d; s.last3 = [d]; s.ground = ground; s.closing = closing
        s.movingTimeS = established ? 600.0 : 0.0; s.movingSamples = established ? 10 : 0; s.movingDistM = established ? 6000.0 : 0.0
        s.stopStartMs = inStop ? fixAt : nil; s.stopAnchor = inStop ? fix : nil; s.slow = slow; s.cvGuard = cvGuard
        s.policy = pol; s.policyIntervalAtLastFixS = policyAtFix ?? pol.intervalS; s.maxTripDurationS = maxTripS ?? p.maxTripCapS
        s.battery = battery; s.alarm = alarm; s.fallback = fallback; s.preAlertArmed = preAlertArmed
        s.gpsLostAtMs = gps == .lost ? fixAt : nil
        return s
    }

    /// Kotlin `FixRec` of a point (d from `distanceM`, acc 8).
    static func rec(_ p: LatLng, at: Int64) -> FixRec {
        FixRec(fixAtMs: at, lat: p.lat, lng: p.lng, accM: 8.0, d: distToDest(p), groundSample: nil)
    }

    /// Replaces `last` / `recent` / dSmooth / minD / last3 / dStartM of a state with one fix (the Kotlin `st.copy(last = l, …)`).
    static func withLast(_ s: EngineState, _ l: FixRec, dStartPlus: Double = 20_000.0) -> EngineState {
        var x = s
        x.last = l; x.recent = [l]; x.dSmooth = l.d; x.minD = l.d; x.last3 = [l.d]; x.dStartM = l.d + dStartPlus
        return x
    }

    static func hasAlarm(_ s: Step) -> Bool { !s.events.alarms.isEmpty }

    static func hasOvershoot(_ s: Step) -> Bool {
        s.events.contains { if case .overshoot = $0 { return true } else { return false } }
    }

    static func overshoots(_ events: [TripEvent]) -> [TripEvent.Overshoot] {
        events.compactMap { if case let .overshoot(o) = $0 { return o } else { return nil } }
    }

    static func hasRecovered(_ s: Step) -> Bool {
        s.events.contains { if case .gpsRecovered = $0 { return true } else { return false } }
    }

    /// TripView with some fields replaced (Kotlin `view.copy(...)`).
    static func view(_ v: TripView, atMs: Int64? = nil, predictedAlarmAtMs: Int64?? = nil, fallbackAtMs: Int64?? = nil,
                     fallbackStatus: FallbackStatus? = nil, wakeAtMs: Int64?? = nil) -> TripView {
        TripView(tripId: v.tripId, atMs: atMs ?? v.atMs, phase: v.phase, gps: v.gps, locationCause: v.locationCause,
                 distanceM: v.distanceM, routeDistanceEstM: v.routeDistanceEstM, distanceErrorM: v.distanceErrorM,
                 isEstimated: v.isEstimated, etaS: v.etaS, etaMinS: v.etaMinS, etaMaxS: v.etaMaxS, speedKmh: v.speedKmh,
                 progress: v.progress, alarmMarkerProgress: v.alarmMarkerProgress,
                 predictedAlarmAtMs: predictedAlarmAtMs ?? v.predictedAlarmAtMs, samplingPolicy: v.samplingPolicy,
                 fallbackAtMs: fallbackAtMs ?? v.fallbackAtMs, fallbackStatus: fallbackStatus ?? v.fallbackStatus,
                 batteryPct: v.batteryPct, batteryRisk: v.batteryRisk, preAlertFired: v.preAlertFired, alarmAtMs: v.alarmAtMs,
                 alarmReason: v.alarmReason, alarmRinging: v.alarmRinging, snoozeCount: v.snoozeCount,
                 snoozeUntilMs: v.snoozeUntilMs, overshootPastM: v.overshootPastM, outcome: v.outcome,
                 vehicleGuess: v.vehicleGuess, travelledM: v.travelledM, droppedFixes: v.droppedFixes,
                 wakeAtMs: wakeAtMs ?? v.wakeAtMs)
    }

    /// Kotlin `Double.toString` (JVM), see `TesterT131Tests.kd`.
    static func kd(_ x: Double) -> String { TesterT131Tests.kd(x) }

    static func kdOpt(_ x: Double?) -> String { x.map(kd) ?? "null" }

    /// Kotlin `Double.toInt()` (truncation; NaN → 0, saturating).
    static func ki(_ x: Double) -> Int {
        if x.isNaN { return 0 }
        if x >= Double(Int32.max) { return Int(Int32.max) }
        if x <= Double(Int32.min) { return Int(Int32.min) }
        return Int(x)
    }

    /// Kotlin `Double.toLong()` (truncation; NaN → 0, saturating).
    static func kl(_ x: Double) -> Int64 {
        if x.isNaN { return 0 }
        if x >= 9.223372036854775807e18 { return Int64.max }
        if x <= -9.223372036854775808e18 { return Int64.min }
        return Int64(x)
    }

    /// Java `String.format("%.Nf", x)` for |x| < 1e15: HALF_UP rounding of the `Double.toString` digits (not of the binary value).
    static func jf(_ x: Double, _ n: Int) -> String {
        if x.isNaN { return "NaN" }
        if x.isInfinite { return x < 0 ? "-Infinity" : "Infinity" }
        let neg = x < 0 || (x == 0 && x.sign == .minus)
        var s = "\(x.magnitude)"
        var e = 0
        if let i = s.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            e = Int(s[s.index(after: i)...].filter { $0 != "+" })!
            s = String(s[..<i])
        }
        var digits = Array(s.filter { $0 != "." }).map { Int($0.asciiValue! - 48) }
        var point = (s.firstIndex(of: ".").map { s.distance(from: s.startIndex, to: $0) } ?? s.count) + e
        while point <= 0 { digits.insert(0, at: 0); point += 1 }
        while digits.count < point + n + 1 { digits.append(0) }
        let keep = point + n
        var out = Array(digits[0..<keep])
        if digits[keep] >= 5 {
            var i = out.count - 1
            var carry = true
            while carry && i >= 0 {
                out[i] += 1
                if out[i] == 10 { out[i] = 0; i -= 1 } else { carry = false }
            }
            if carry { out.insert(1, at: 0); point += 1 }
        }
        let intPart = out[0..<point].map(String.init).joined()
        let frac = out[point...].map(String.init).joined()
        let body = (intPart.isEmpty ? "0" : intPart) + (n > 0 ? "." + frac : "")
        return (neg ? "-" : "") + body
    }

    /// Kotlin `sortedMapOf<String, Int>().toString()`.
    static func kmap<V>(_ m: [String: V]) -> String { "{" + m.keys.sorted().map { "\($0)=\(m[$0]!)" }.joined(separator: ", ") + "}" }

    /// Kotlin `List<String>.toString()`.
    static func klist(_ xs: [String]) -> String { "[" + xs.joined(separator: ", ") + "]" }
}

/// Kotlin `EngineDriver` continuing from a state (`driverFrom`): times in seconds from `startMs`, fixes due south of (0, 106).
struct KDriver {
    let startMs: Int64
    var state: EngineState
    var steps: [Step] = []

    init(from s: EngineState) {
        startMs = s.startedAtMs
        state = s
    }

    func ms(_ t: Int) -> Int64 { startMs + Int64(t) * 1000 }

    @discardableResult
    mutating func feed(_ x: EngineInput) -> Step {
        let s = TripEngine.reduce(state, x)
        steps.append(s)
        state = s.state
        return s
    }

    @discardableResult
    mutating func fix(_ t: Int, _ d: Double, acc: Double = 8.0, spd: Double? = nil, eastM: Double = 0.0, ageMs: Int64 = 0) -> Step {
        let p0 = KW.pointOnMeridian(d)
        let pt = eastM == 0.0 ? p0 : KW.jitter(p0, eastM, 0.0)
        return feed(.locationFix(LocationFix(atMs: ms(t), fixAtMs: ms(t) - ageMs, lat: pt.lat, lng: pt.lng, accuracyM: acc, speedMps: spd)))
    }

    @discardableResult mutating func tickMs(_ atMs: Int64) -> Step { feed(.tick(atMs: atMs)) }

    var view: TripView { steps[steps.count - 1].view }

    func events() -> [TripEvent] { steps.flatMap(\.events) }
}
