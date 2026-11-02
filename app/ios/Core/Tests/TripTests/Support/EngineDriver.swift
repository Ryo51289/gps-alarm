@testable import Trip

/// Trip builder for unit tests (T12 `EngineDriver`): times in seconds from `start`, positions as distance to dest.
struct EngineDriver {
    var state: EngineState
    var steps: [Step] = []
    var startMs: Int64

    static func config(_ mode: AlarmMode = .distance, thr: Int? = 1000, thrMin: Int? = nil, hint: VehicleKind = .train,
                       preAlert: Bool = true) -> TripConfig {
        TripConfig(tripId: "trip-1", destLat: TestGeo.destLat, destLng: TestGeo.destLng, mode: mode,
                   distanceThresholdM: mode == .distance ? thr : (mode == .time ? nil : nil),
                   timeThresholdMin: mode == .time ? (thrMin ?? 15) : nil, preAlertEnabled: preAlert, vehicleHint: hint)
    }

    static func params(_ json: String? = nil) -> EngineParams {
        let r = EngineParamsFactory.parseOverrides(json)
        precondition(!r.malformed && r.rejected.isEmpty, "test params rejected: \(r.rejected)")
        return r.params
    }

    init(_ mode: AlarmMode = .distance, thr: Int? = 1000, thrMin: Int? = nil, hint: VehicleKind = .train,
         preAlert: Bool = true, params: String? = nil, startMs: Int64 = 1_000_000_000) {
        self.startMs = startMs
        let cfg = EngineDriver.config(mode, thr: thr, thrMin: thrMin, hint: hint, preAlert: preAlert)
        let s = try! TripEngine.start(config: cfg, params: EngineDriver.params(params), nowMs: startMs)
        state = s.state
        steps = [s]
    }

    var last: Step { steps[steps.count - 1] }
    var view: TripView { last.view }
    var events: [TripEvent] { last.events }

    func ms(_ t: Double) -> Int64 { startMs + Int64((t * 1000).rounded()) }

    @discardableResult
    mutating func feed(_ x: EngineInput) -> Step {
        let s = TripEngine.reduce(state, x)
        state = s.state
        steps.append(s)
        return s
    }

    @discardableResult
    mutating func fix(_ t: Double, d: Double, acc: Double = 8, spd: Double? = nil, east: Double = 0, exact: Bool = false,
                      fixAge: Double = 0) -> Step {
        let lat: Double, lng: Double
        if exact { lat = TestGeo.latAtExactDistance(d); lng = 0 } else if east == 0 { lat = TestGeo.latOnMeridian(d); lng = 0 } else {
            (lat, lng) = TestGeo.point(d: d, east: east)
        }
        return feed(.locationFix(LocationFix(atMs: ms(t), fixAtMs: ms(t - fixAge), lat: lat, lng: lng, accuracyM: acc, speedMps: spd)))
    }

    @discardableResult mutating func tick(_ t: Double) -> Step { feed(.tick(atMs: ms(t))) }
    @discardableResult mutating func user(_ t: Double, _ a: UserActionKind) -> Step { feed(.userAction(atMs: ms(t), action: a)) }
    @discardableResult mutating func battery(_ t: Double, _ level: Int, charging: Bool = false) -> Step {
        feed(.batterySample(atMs: ms(t), levelPct: level, charging: charging))
    }
    @discardableResult mutating func avail(_ t: Double, _ c: AvailabilityCause) -> Step { feed(.locationAvailability(atMs: ms(t), cause: c)) }
    @discardableResult mutating func fired(_ t: Double, firedAtMs: Int64) -> Step { feed(.fallbackFired(atMs: ms(t), firedAtMs: firedAtMs)) }
    @discardableResult mutating func silenced(_ t: Double) -> Step { feed(.alarmSilenced(atMs: ms(t), silencedAtMs: ms(t))) }
    @discardableResult mutating func scheduled(_ t: Double, _ at: Int64, ok: Bool) -> Step {
        feed(.fallbackScheduled(atMs: ms(t), fallbackAtMs: at, ok: ok))
    }
    @discardableResult mutating func restore(_ t: Double, _ info: RestoreInfo) -> Step {
        let s = TripEngine.restore(state, nowMs: ms(t), info: info)
        state = s.state
        steps.append(s)
        return s
    }

    /// Constant-speed approach: Doppler `v`, distance decreasing `v / k` per second, fixes every `dt` s.
    mutating func drive(from t0: Double, d0: Double, v: Double, k: Double = 1.0, count: Int, dt: Double = 5, exact: Bool = false) {
        for i in 0..<count {
            let t = t0 + Double(i) * dt
            fix(t, d: d0 - v / k * (t - t0), spd: v, exact: exact)
        }
    }

    var estimate: Estimate? { Estimator.estimate(state, now: state.nowMs) }

    func allEvents(from index: Int = 0) -> [TripEvent] { steps[index...].flatMap(\.events) }
}

extension TripEvent {
    var asAlarm: TripEvent.Alarm? { if case let .alarm(a) = self { return a } else { return nil } }
    var asFallback: TripEvent.FallbackAlarmChanged? { if case let .fallbackAlarmChanged(f) = self { return f } else { return nil } }
    var asGpsLost: TripEvent.GpsLost? { if case let .gpsLost(g) = self { return g } else { return nil } }
    var asEnded: TripEvent.TripEnded? { if case let .tripEnded(e) = self { return e } else { return nil } }
}

extension Array where Element == TripEvent {
    var alarms: [TripEvent.Alarm] { compactMap(\.asAlarm) }
    var fallbacks: [TripEvent.FallbackAlarmChanged] { compactMap(\.asFallback) }
    func named(_ n: String) -> [TripEvent] { filter { $0.fixtureName == n } }
}

func approx(_ a: Double?, _ b: Double, _ tol: Double = 1e-6) -> Bool {
    guard let a else { return false }
    return (a - b).magnitude <= tol
}
