import Testing
@testable import Trip

/// Tester T13 additions (review T13 round 2, nits #12, #13 and the Remote Config blank set).
/// The C16-ENDED inputs are shared with the Kotlin mirror test (T12 tester): same snapshot JSON, same inputs, same expectations.
@Suite("TesterT13Tests")
struct TesterT13Tests {
    // MARK: - #13 C16 exception: ENDED keeps a stale snoozeUntilMs (pre-C16 snapshot)

    static let x: Int64 = 1_000_300_000          // stale snoozeUntilMs
    static let endedNow: Int64 = 1_000_250_000   // state.nowMs of the ENDED snapshot
    static let later: Int64 = 1_000_310_000      // inputs arrive after X (and after nowMs)

    /// ENDED snapshot as written by an engine before C16: snoozed at +240 s (until +300 s), dismissed at +250 s.
    /// `params: {}` → every parameter takes its default (T10.2). Identical string in the Kotlin mirror.
    static let endedSnapshot = """
    {"snapshotVersion":1,"params":{},\
    "config":{"tripId":"c16-ended","destLat":21.0,"destLng":105.8,"mode":"DISTANCE","distanceThresholdM":1000,\
    "timeThresholdMin":null,"preAlertEnabled":true,"vehicleHint":"TRAIN"},\
    "nowMs":1000250000,"startedAtMs":1000000000,"phase":"ENDED","gps":"OK","locationCause":"AVAILABLE",\
    "last":{"fixAtMs":1000240000,"lat":20.9955,"lng":105.8,"accM":8.0,"d":500.0,"groundSample":11.0},\
    "stopAnchor":null,\
    "recent":[{"fixAtMs":1000240000,"lat":20.9955,"lng":105.8,"accM":8.0,"d":500.0,"groundSample":11.0}],\
    "rejects":[],"dSmooth":500.0,"dStartM":3000.0,"minD":500.0,"last3":[700.0,600.0,500.0],"ground":11.0,"closing":11.0,\
    "movingTimeS":240.0,"movingSamples":10,"movingDistM":2500.0,"stopStartMs":null,"slow":false,"cvGuard":[],\
    "policy":{"tier":"DENSE","intervalS":5,"minIntervalS":5,"accuracy":"HIGH"},"policyIntervalAtLastFixS":5,\
    "gpsLostAtMs":null,"lostEmittedBeforeFirstFix":false,"preAlertArmed":false,"preAlertFired":true,"arrivedFired":false,\
    "alarm":{"atMs":1000200000,"reason":"DISTANCE","source":"ENGINE","lastRingAtMs":1000200000,"lastReason":"DISTANCE",\
    "ringing":false,"snoozeCount":1,"snoozeUntilMs":1000300000,"dismissedAtMs":1000250000},\
    "overshootAtMs":null,"overshootPastM":null,\
    "fallback":{"targetAtMs":null,"emittedAtMs":null,"status":"NONE","confirmedAtMs":null,"resync":false,"near":false},\
    "battery":{"levelPct":80,"charging":false,"segT0":null,"segL0":null,"armed":false,"riskEmitted":false,"choice":null,\
    "choicePct":null},"maxTripDurationS":36000,"droppedFixes":0,\
    "ended":{"outcome":"SNOOZED","endReason":"DISMISSED","atMs":1000250000}}
    """

    /// Every input kind the OS layer could still deliver after the trip ended (some with atMs < nowMs: clock never goes back).
    static let lateInputs: [EngineInput] = [
        .tick(atMs: later),
        .tick(atMs: endedNow - 5_000),
        .locationFix(LocationFix(atMs: later, fixAtMs: later, lat: 21.0, lng: 105.8, accuracyM: 5, speedMps: 0)),
        .batterySample(atMs: later, levelPct: 3, charging: false),
        .locationAvailability(atMs: later, cause: .servicesOff),
        .fallbackScheduled(atMs: later, fallbackAtMs: later + 60_000, ok: true),
        .fallbackFired(atMs: later, firedAtMs: x),
        .alarmSilenced(atMs: later, silencedAtMs: later),
        .userAction(atMs: later, action: .snooze),
        .userAction(atMs: later, action: .dismiss),
        .userAction(atMs: later, action: .stopTrip),
    ]

    static let restoreInfos: [RestoreInfo] = [
        RestoreInfo(status: .missing, firedAtMs: nil, dismissedAtMs: nil),
        RestoreInfo(status: .pending, firedAtMs: nil, dismissedAtMs: nil),
        RestoreInfo(status: .rang, firedAtMs: x, dismissedAtMs: nil),
        RestoreInfo(status: .dismissed, firedAtMs: x, dismissedAtMs: later),
        RestoreInfo(status: .unknown, firedAtMs: nil, dismissedAtMs: nil),
    ]

    /// Checks one Step on an ENDED state carrying snoozeUntilMs = X; returns failure tags.
    static func endedUnchanged(_ s: EngineState, _ step: Step, _ tag: String) -> [String] {
        var f: [String] = []
        if step.state != s { f.append("\(tag): state changed") }
        if TripEngine.encodeSnapshot(step.state) != TripEngine.encodeSnapshot(s) { f.append("\(tag): snapshot changed") }
        if !step.events.isEmpty { f.append("\(tag): events \(step.events.map(\.fixtureName))") }
        if step.state.alarm.snoozeUntilMs != x { f.append("\(tag): state.snoozeUntilMs normalised") }
        let v = step.view
        if v.snoozeUntilMs != x { f.append("\(tag): view.snoozeUntilMs \(String(describing: v.snoozeUntilMs))") }
        if v.phase != .ended || v.atMs != s.nowMs { f.append("\(tag): view phase/atMs \(v.phase) \(v.atMs)") }
        if v.predictedAlarmAtMs != nil || v.wakeAtMs != nil || v.batteryRisk { f.append("\(tag): predicted/wakeAt/risk set") }
        return f
    }

    @Test("C16-ENDED (review #13): pre-C16 ENDED snapshot with snoozeUntilMs = X → reduce(any input)/restore(any status) leave state unchanged, view keeps X, no events")
    func c16EndedSnapshot() throws {
        let s = try TripEngine.decodeSnapshot(Self.endedSnapshot)
        #expect(s.phase == .ended && s.alarm.snoozeUntilMs == Self.x && s.nowMs == Self.endedNow)
        // The decoder does not normalise either (round trip keeps X).
        #expect(try TripEngine.decodeSnapshot(TripEngine.encodeSnapshot(s)) == s)
        var failures: [String] = []
        var views: [TripView] = []
        for (i, input) in Self.lateInputs.enumerated() {
            let step = TripEngine.reduce(s, input)
            failures += Self.endedUnchanged(s, step, "reduce[\(i)]")
            views.append(step.view)
        }
        for info in Self.restoreInfos {
            for now in [Self.later, Self.endedNow - 5_000] {
                let step = TripEngine.restore(s, nowMs: now, info: info)
                failures += Self.endedUnchanged(s, step, "restore \(info.status) @\(now - Self.endedNow)")
                views.append(step.view)
            }
        }
        #expect(failures.isEmpty, "\(failures)")
        // Every Step on the same ENDED state has the same view (computed at state.nowMs, not at the input time).
        #expect(views.allSatisfy { $0 == views[0] })
        // Whole view = what the Kotlin engine (T12 classes, JDK 17) returns for the same snapshot and inputs (tester probe).
        let dense = SamplingPolicy(tier: .dense, intervalS: 5, minIntervalS: 5, accuracy: .high)
        let kotlin = TripView(
            tripId: "c16-ended", atMs: 1_000_250_000, phase: .ended, gps: .ok, locationCause: .available, distanceM: 390,
            routeDistanceEstM: 390, distanceErrorM: 8, isEstimated: false, etaS: 55, etaMinS: 51, etaMaxS: 60, speedKmh: 39.6,
            progress: 0.87, alarmMarkerProgress: 0.6666666666666667, predictedAlarmAtMs: nil, samplingPolicy: dense,
            fallbackAtMs: nil, fallbackStatus: .notSet, batteryPct: 80, batteryRisk: false, preAlertFired: true,
            alarmAtMs: 1_000_200_000, alarmReason: .distance, alarmRinging: false, snoozeCount: 1, snoozeUntilMs: Self.x,
            overshootPastM: nil, outcome: .snoozed, vehicleGuess: .train, travelledM: 2500, droppedFixes: 0, wakeAtMs: nil)
        #expect(views[0] == kotlin)
    }

    // MARK: - Hand-made (corrupted) TRACKING snapshots through decode → reduce, compared with the Kotlin engine's output

    /// TRACKING 5 000 m before a DISTANCE 1000 destination at 11 m/s. `gps`, last fix time and `fallback` vary per case.
    static func tracking(gps: String, lastFixAtMs: Int64, fallback: String) -> String {
        let fix = #"{"fixAtMs":\#(lastFixAtMs),"lat":20.955034,"lng":105.8,"accM":8.0,"d":5000.0,"groundSample":11.0}"#
        return #"{"snapshotVersion":1,"params":{},"config":{"tripId":"tester-t13","destLat":21.0,"destLng":105.8,"mode":"DISTANCE","#
            + #""distanceThresholdM":1000,"timeThresholdMin":null,"preAlertEnabled":true,"vehicleHint":"TRAIN"},"#
            + #""nowMs":1000250000,"startedAtMs":1000000000,"phase":"TRACKING","gps":"\#(gps)","locationCause":"AVAILABLE","#
            + #""last":\#(fix),"stopAnchor":null,"recent":[\#(fix)],"rejects":[],"dSmooth":5000.0,"dStartM":8000.0,"minD":5000.0,"#
            + #""last3":[5220.0,5110.0,5000.0],"ground":11.0,"closing":11.0,"movingTimeS":240.0,"movingSamples":10,"#
            + #""movingDistM":2500.0,"stopStartMs":null,"slow":false,"cvGuard":[11.0],"#
            + #""policy":{"tier":"DENSE","intervalS":5,"minIntervalS":5,"accuracy":"HIGH"},"policyIntervalAtLastFixS":5,"#
            + #""gpsLostAtMs":null,"lostEmittedBeforeFirstFix":false,"preAlertArmed":true,"preAlertFired":false,"arrivedFired":false,"#
            + #""alarm":{"atMs":null,"reason":null,"source":null,"lastRingAtMs":null,"lastReason":null,"ringing":false,"#
            + #""snoozeCount":0,"snoozeUntilMs":null,"dismissedAtMs":null},"overshootAtMs":null,"overshootPastM":null,"#
            + #""fallback":\#(fallback),"battery":{"levelPct":80,"charging":false,"segT0":null,"segL0":null,"armed":false,"#
            + #""riskEmitted":false,"choice":null,"choicePct":null},"maxTripDurationS":36000,"droppedFixes":0,"ended":null}"#
    }

    static let t1: Int64 = 1_000_255_000
    static let policy2 = SamplingPolicy(tier: .dense, intervalS: 5, minIntervalS: 2, accuracy: .high)
    static let nextFix = EngineInput.locationFix(LocationFix(atMs: t1, fixAtMs: t1, lat: 20.95553, lng: 105.8, accuracyM: 8,
                                                             speedMps: 11))

    static func trackingView(distanceM: Int, routeM: Int, eta: (Int, Int, Int), progress: Double, predicted: Int64,
                             fb: Int64, travelledM: Int, wakeAtMs: Int64) -> TripView {
        TripView(tripId: "tester-t13", atMs: t1, phase: .tracking, gps: .ok, locationCause: .available, distanceM: distanceM,
                 routeDistanceEstM: routeM, distanceErrorM: 8, isEstimated: false, etaS: eta.0, etaMinS: eta.1, etaMaxS: eta.2,
                 speedKmh: 39.6, progress: progress, alarmMarkerProgress: 0.875, predictedAlarmAtMs: predicted,
                 samplingPolicy: policy2, fallbackAtMs: fb, fallbackStatus: .requested, batteryPct: 80, batteryRisk: false,
                 preAlertFired: true, alarmAtMs: nil, alarmReason: nil, alarmRinging: false, snoozeCount: 0, snoozeUntilMs: nil,
                 overshootPastM: nil, outcome: nil, vehicleGuess: .train, travelledM: travelledM, droppedFixes: 0,
                 wakeAtMs: wakeAtMs)
    }

    @Test("Corrupt snapshot (review #3): fallback FAILED with emittedAtMs null → Tick / fix re-request the fallback at once; events and view = Kotlin")
    func failedWithoutEmissionSnapshot() throws {
        let fb = #"{"targetAtMs":1000700000,"emittedAtMs":null,"status":"FAILED","confirmedAtMs":null,"resync":false,"near":false}"#
        let s = try TripEngine.decodeSnapshot(Self.tracking(gps: "OK", lastFixAtMs: 1_000_250_000, fallback: fb))
        #expect(s.fallback.status == .failed && s.fallback.emittedAtMs == nil)
        let tick = TripEngine.reduce(s, .tick(atMs: Self.t1))
        #expect(tick.events == [
            .preAlert(.init(atMs: Self.t1, distanceM: 4945, etaS: 470)),
            .samplingPolicyChanged(.init(atMs: Self.t1, policy: Self.policy2)),
            .fallbackAlarmChanged(.init(atMs: Self.t1, fallbackAtMs: 1_000_643_636, cause: .eta)),
        ])
        #expect(tick.view == Self.trackingView(distanceM: 4945, routeM: 4945, eta: (470, 424, 515), progress: 0.38187499999999996,
                                               predicted: 1_000_613_636, fb: 1_000_643_636, travelledM: 2500, wakeAtMs: 1_000_310_000))
        let fix = TripEngine.reduce(s, Self.nextFix)
        #expect(fix.events == [
            .preAlert(.init(atMs: Self.t1, distanceM: 5000, etaS: 475)),
            .samplingPolicyChanged(.init(atMs: Self.t1, policy: Self.policy2)),
            .fallbackAlarmChanged(.init(atMs: Self.t1, fallbackAtMs: 1_000_648_636, cause: .eta)),
        ])
        #expect(fix.view == Self.trackingView(distanceM: 5000, routeM: 5000, eta: (475, 428, 521), progress: 0.375,
                                              predicted: 1_000_618_636, fb: 1_000_648_636, travelledM: 2555, wakeAtMs: 1_000_315_000))
    }

    @Test("Corrupt snapshot (review #4): gps LOST with gpsLostAtMs null → good fix recovers without GpsRecovered; Tick rings GPS_LOST; = Kotlin")
    func lostWithoutLostAtSnapshot() throws {
        let fb = #"{"targetAtMs":1000700000,"emittedAtMs":1000240000,"status":"CONFIRMED","confirmedAtMs":1000240000,"resync":false,"near":false}"#
        let s = try TripEngine.decodeSnapshot(Self.tracking(gps: "LOST", lastFixAtMs: 1_000_150_000, fallback: fb))
        let fix = TripEngine.reduce(s, Self.nextFix)
        #expect(fix.events == [
            .preAlert(.init(atMs: Self.t1, distanceM: 4945, etaS: 617)),
            .samplingPolicyChanged(.init(atMs: Self.t1, policy: Self.policy2)),
            .fallbackAlarmChanged(.init(atMs: Self.t1, fallbackAtMs: 1_000_761_181, cause: .eta)),
        ])
        #expect(fix.state.gps == .ok && fix.state.gpsLostAtMs == nil)
        #expect(fix.view == Self.trackingView(distanceM: 4945, routeM: 6566, eta: (617, 556, 678), progress: 0.3818943477518427,
                                              predicted: 1_000_731_181, fb: 1_000_761_181, travelledM: 3655, wakeAtMs: 1_000_315_000))
        let tick = TripEngine.reduce(s, .tick(atMs: Self.t1))
        #expect(tick.events == [
            .alarm(.init(atMs: Self.t1, reason: .gpsLost, ringNow: true, snoozeAllowed: true, distanceM: 3845, etaS: 370, batteryPct: 80)),
            .samplingPolicyChanged(.init(atMs: Self.t1, policy: Self.policy2)),
            .fallbackAlarmChanged(.init(atMs: Self.t1, fallbackAtMs: nil, cause: .superseded)),
        ])
        #expect(tick.view.phase == .alarming && tick.view.gps == .lost && tick.view.isEstimated && tick.view.distanceM == 3845
                && tick.view.distanceErrorM == 297 && tick.view.routeDistanceEstM == 3845 && tick.view.etaMinS == 310
                && tick.view.etaMaxS == 434 && tick.view.progress == 0.5193749999999999 && tick.view.wakeAtMs == 1_003_855_000
                && tick.view.fallbackStatus == .notSet && tick.view.fallbackAtMs == nil && tick.view.alarmRinging)
    }

    @Test("C16-ENDED (review #13): engine-made ENDED state with snoozeUntilMs forced to X behaves the same (Tick, restore MISSING)")
    func c16EndedDriver() {
        let r = Round2Tests.snoozed()
        var d = r.0
        let n = r.1
        d.user(n + 5, .dismiss)
        #expect(d.view.phase == .ended && d.state.alarm.snoozeUntilMs == nil)   // C16 in the normal path
        var s = d.state
        let forced = d.ms(n + 60)
        s.alarm.snoozeUntilMs = forced
        let a = TripEngine.reduce(s, .tick(atMs: d.ms(n + 90)))
        let b = TripEngine.restore(s, nowMs: d.ms(n + 90), info: RestoreInfo(status: .missing, firedAtMs: nil, dismissedAtMs: nil))
        for step in [a, b] {
            #expect(step.state == s && step.events.isEmpty && step.view.snoozeUntilMs == forced && step.view.phase == .ended)
            #expect(TripEngine.encodeSnapshot(step.state) == TripEngine.encodeSnapshot(s))
        }
        #expect(a.view == b.view)
    }

    // MARK: - #12 allowFallbackFirst: the three missing cases

    static let base = #""id":"x","status":"final","testIds":["TR38"],"forbid":[]"#
    static let cfg = #""config":{"mode":"distance","thresholdM":1000,"preAlert":true}"#
    static let alarmFalse = #""expect":[{"event":"alarm","ringNow":false,"notBefore":0,"notAfter":10,"window":{},"ref":"x"}]"#
    static let v15 = "allowFallbackFirst cannot be used with config.kill or killSweep"
    static let v16 = "allowFallbackFirst needs an expect entry for alarm with ringNow false"

    @Test("allowFallbackFirst V14 also for a number; V15 with killSweep (no config.kill); V16 when the only alarm expect has ringNow true")
    func allowFallbackFirstMissingCases() throws {
        guard let trace = LoadedTrace.named("bus_hn_brt01") else { Issue.record("trace"); return }
        // V14: 1 is not a bool (Kotlin HarnessSelfTest checks "yes" and 1).
        #expect(throws: (any Error).self) {
            _ = try SwiftSpecificTests.caseJson("{\(Self.base),\(Self.cfg),\"allowFallbackFirst\":1,\(Self.alarmFalse)}")
        }
        // V15: killSweep alone.
        let ks = #""killSweep":{"from":{"t":5},"everyS":5,"notAfter":{"t":30},"earlyFrom":{"t":20}}"#
        let withSweep = try SwiftSpecificTests.caseJson("{\(Self.base),\(Self.cfg),\(ks),\"allowFallbackFirst\":true,\(Self.alarmFalse)}")
        #expect(withSweep.config.kill == nil && withSweep.killSweep != nil)
        let e15 = Runner(trace: trace, spec: withSweep, mode: "all").configErrors
        #expect(e15.contains { $0.contains(Self.v15) } && !e15.contains { $0.contains(Self.v16) }, "\(e15)")
        // V16: only ringNow true (and one with ringNow absent) → still an error.
        let onlyTrue = #""expect":[{"event":"alarm","ringNow":true,"notBefore":0,"notAfter":10,"window":{},"ref":"x"},{"event":"alarm","notBefore":0,"notAfter":10,"window":{},"ref":"y"}]"#
        let trueSpec = try SwiftSpecificTests.caseJson("{\(Self.base),\(Self.cfg),\"allowFallbackFirst\":true,\(onlyTrue)}")
        let e16 = Runner(trace: trace, spec: trueSpec, mode: "all").configErrors
        #expect(e16.contains { $0.contains(Self.v16) } && !e16.contains { $0.contains(Self.v15) }, "\(e16)")
        // Explicit false: parses, no V15/V16 even with kill.
        let off = try SwiftSpecificTests.caseJson(
            "{\(Self.base),\"config\":{\"mode\":\"distance\",\"thresholdM\":1000,\"preAlert\":true,\"kill\":{\"t\":100}},\"allowFallbackFirst\":false,\"expect\":[]}")
        #expect(!off.allowFallbackFirst)
        #expect(!Runner(trace: trace, spec: off, mode: "all").configErrors.contains { $0.contains("allowFallbackFirst") })
    }

    /// Runner whose only record is START with a first Alarm(ringNow = false) (like Kotlin `P02 is exempted only by allowFallbackFirst`).
    static func p02Failures(_ caseBody: String) throws -> [String] {
        guard let trace = LoadedTrace.named("bus_hn_brt01") else { return ["trace missing"] }
        let spec = try SwiftSpecificTests.caseJson(caseBody)
        var r = Runner(trace: trace, spec: spec, mode: "all")
        guard r.configErrors.isEmpty else { return ["config: \(r.configErrors)"] }
        let alarm = TripEvent.alarm(TripEvent.Alarm(atMs: r.startMs, reason: .fallback, ringNow: false, snoozeAllowed: true,
                                                    distanceM: nil, etaS: nil, batteryPct: nil))
        r.records = [StepRecord(t: 0, input: .start, events: [alarm], view: r.lastView, v: "")]
        return Checks.run(r).filter { $0.contains("P02") }
    }

    @Test("P02 is exempted only by allowFallbackFirst = true: same first Alarm(ringNow=false) fails P02 with the flag false or absent")
    func p02ExemptOnlyWithFlag() throws {
        #expect(try Self.p02Failures("{\(Self.base),\(Self.cfg),\"allowFallbackFirst\":true,\(Self.alarmFalse)}").isEmpty)
        let off = try Self.p02Failures("{\(Self.base),\(Self.cfg),\"allowFallbackFirst\":false,\(Self.alarmFalse)}")
        #expect(off.count == 1 && off[0].contains("P02: first alarm at t=0 has ringNow=false"), "\(off)")
        let absent = try Self.p02Failures("{\(Self.base),\(Self.cfg),\(Self.alarmFalse)}")
        #expect(absent.count == 1, "\(absent)")
    }

    // MARK: - Exact mirrors of TesterT12Test.kt (docs/test-reports/T12.md "Giá trị cho T13")

    static let S: Int64 = 1_800_000_000_000

    /// Kotlin `cfg()`: DISTANCE 1000, preAlert, TRAIN, destination (0.0, 106.0), tripId "trip-1".
    static func t12Config() -> TripConfig {
        TripConfig(tripId: "trip-1", destLat: 0.0, destLng: 106.0, mode: .distance, distanceThresholdM: 1000, timeThresholdMin: nil,
                   preAlertEnabled: true, vehicleHint: .train)
    }

    /// Kotlin `trackingState(...)` (support/States.kt) with its defaults: now = startedAt = S, ground 15, closing 12.5, established,
    /// gps OK, fix at now, acc 8, dStart = d + 20 000, minD = d, last3 = [d].
    static func t12TrackingState(_ config: TripConfig = t12Config(), d: Double, ground: Double? = 15.0, closing: Double? = 12.5,
                                 inStop: Bool = false, slow: Bool = false, cvGuard: [Double] = [], tier: SamplingTier = .dense,
                                 policyAtFix: Int? = nil) -> EngineState {
        let p = EngineParams.defaults
        var s = EngineState.initial(config: config, params: p, nowMs: S)
        let fix = FixRec(fixAtMs: S, lat: 0.0 - d / Geo.kMetresPerDegLat, lng: 106.0, accM: 8.0, d: d, groundSample: nil)
        let pol = SamplingPlanner.policyFor(tier, p, maxSaving: false)
        s.nowMs = S; s.phase = .tracking; s.gps = .ok; s.last = fix; s.recent = [fix]
        s.dSmooth = d; s.dStartM = d + 20_000.0; s.minD = d; s.last3 = [d]; s.ground = ground; s.closing = closing
        s.movingTimeS = 600.0; s.movingSamples = 10; s.movingDistM = 6000.0
        s.stopStartMs = inStop ? S : nil; s.stopAnchor = inStop ? fix : nil; s.slow = slow; s.cvGuard = cvGuard
        s.policy = pol; s.policyIntervalAtLastFixS = policyAtFix ?? pol.intervalS; s.maxTripDurationS = p.maxTripCapS
        s.battery = .initial; s.alarm = .empty; s.fallback = .cleared; s.preAlertArmed = true; s.gpsLostAtMs = nil
        return s
    }

    /// Kotlin `driverFrom(state)`: driver whose clock base is S, no recorded steps.
    static func t12Driver(_ s: EngineState) -> EngineDriver {
        var d = EngineDriver(startMs: S)
        d.state = s
        d.steps = []
        return d
    }

    /// Kotlin `endedWithStaleSnooze()`: TRACKING at 900 m stopped → Tick(S) Alarm(DISTANCE) → DISMISS at S + 10 s → ENDED;
    /// then alarm.snoozeUntilMs = S + 60 000 by hand.
    static func t12EndedWithStaleSnooze() -> EngineState {
        var e = t12Driver(t12TrackingState(d: 900.0, inStop: true))
        let alarm = e.tick(0)
        #expect(alarm.events.alarms.map(\.reason) == [.distance])
        let ended = e.user(10, .dismiss)
        #expect(ended.view.phase == .ended && ended.state.alarm.snoozeUntilMs == nil && ended.state.nowMs == S + 10_000)
        var s = ended.state
        s.alarm.snoozeUntilMs = S + 60_000
        return s
    }

    static func t12AssertUnchanged(_ input: EngineState, _ s: Step, _ tag: String) -> [String] {
        var f: [String] = []
        if s.state != input || TripEngine.encodeSnapshot(s.state) != TripEngine.encodeSnapshot(input) { f.append("\(tag): state changed") }
        if !s.events.isEmpty { f.append("\(tag): events") }
        if s.view.phase != .ended { f.append("\(tag): phase") }
        if s.view.snoozeUntilMs != S + 60_000 || s.state.alarm.snoozeUntilMs != S + 60_000 { f.append("\(tag): snoozeUntilMs") }
        if s.view.predictedAlarmAtMs != nil || s.view.batteryRisk || s.view.wakeAtMs != nil { f.append("\(tag): C22 view") }
        if s.view.atMs != input.nowMs || s.view.atMs != S + 10_000 { f.append("\(tag): view.atMs \(s.view.atMs - S)") }
        return f
    }

    @Test("C16-ENDED mirror of T12T: ENDED (S + 10 s) with snoozeUntilMs = S + 60 s unchanged by every input/restore at S + 20 s, also after decode(encode)")
    func c16EndedT12Mirror() throws {
        let st = Self.t12EndedWithStaleSnooze()
        #expect(st.nowMs == Self.S + 10_000)
        let t = Self.S + 20_000
        let lat = 0.0 - 500.0 / Geo.kMetresPerDegLat
        var inputs: [EngineInput] = [
            .tick(atMs: t), .tick(atMs: Self.S), .tick(atMs: Self.S + 3_600_000),
            .locationFix(LocationFix(atMs: t, fixAtMs: t, lat: lat, lng: 106.0, accuracyM: 8.0, speedMps: 10.0)),
            .batterySample(atMs: t, levelPct: 3, charging: false), .locationAvailability(atMs: t, cause: .servicesOff),
            .fallbackScheduled(atMs: t, fallbackAtMs: Self.S + 90_000, ok: true),
            .fallbackScheduled(atMs: t, fallbackAtMs: Self.S + 90_000, ok: false),
            .fallbackFired(atMs: t, firedAtMs: Self.S + 15_000), .alarmSilenced(atMs: t, silencedAtMs: t),
        ]
        inputs += UserActionKind.allCases.map { EngineInput.userAction(atMs: t, action: $0) }
        #expect(inputs.count == 16)
        let infos = [
            RestoreInfo(status: .pending), RestoreInfo(status: .missing), RestoreInfo(status: .unknown),
            RestoreInfo(status: .rang, firedAtMs: Self.S + 15_000),
            RestoreInfo(status: .dismissed, firedAtMs: Self.S + 15_000, dismissedAtMs: Self.S + 16_000),
        ]
        var f: [String] = []
        for (i, x) in inputs.enumerated() { f += Self.t12AssertUnchanged(st, TripEngine.reduce(st, x), "reduce[\(i)]") }
        for i in infos { f += Self.t12AssertUnchanged(st, TripEngine.restore(st, nowMs: t, info: i), "restore \(i.status)") }
        let decoded = try TripEngine.decodeSnapshot(TripEngine.encodeSnapshot(st))
        #expect(decoded.alarm.snoozeUntilMs == Self.S + 60_000 && decoded == st)
        f += Self.t12AssertUnchanged(decoded, TripEngine.reduce(decoded, .tick(atMs: t)), "decoded reduce")
        f += Self.t12AssertUnchanged(decoded, TripEngine.restore(decoded, nowMs: t, info: RestoreInfo(status: .missing)), "decoded restore")
        #expect(f.isEmpty, "\(f)")
    }

    @Test("C16 contrast mirror of T12T: TRACKING (20 km) with a stale snoozeUntilMs from a snapshot is normalised by the next Step")
    func c16NonEndedNormalised() throws {
        var st = Self.t12TrackingState(d: 20_000.0)
        st.alarm.snoozeUntilMs = Self.S + 60_000
        let s = TripEngine.reduce(try TripEngine.decodeSnapshot(TripEngine.encodeSnapshot(st)), .tick(atMs: Self.S + 5_000))
        #expect(s.view.snoozeUntilMs == nil && s.state.alarm.snoozeUntilMs == nil && s.view.phase == .tracking)
    }

    @Test("C12 blank set mirror of T12T: blank → defaults; not blank → malformed; only RFC 8259 whitespace around an object")
    func blankT12Mirror() {
        let blank = ["", " ", "\t", "\n", "\r\n", "\u{0B}", "\u{0C}", "\u{1C}", "\u{1D}", "\u{1E}", "\u{1F}",
                     "\u{A0}", "\u{1680}", "\u{2000}", "\u{2007}", "\u{200A}", "\u{2028}", "\u{2029}", "\u{202F}", "\u{205F}", "\u{3000}",
                     " \u{A0}\t\u{3000}\n"]
        for s in blank {
            let r = EngineParamsFactory.parseOverrides(s)
            #expect(!r.malformed && r.rejected.isEmpty && r.params == .defaults, "blank \(s.unicodeScalars.map(\.value))")
        }
        for s in ["\u{200B}", "\u{FEFF}", "\u{85}", "\u{180E}", "\u{2060}", "\u{0}", " \u{200B} "] {
            let r = EngineParamsFactory.parseOverrides(s)
            #expect(r.malformed && r.params == .defaults, "not blank \(s.unicodeScalars.map(\.value))")
        }
        #expect(EngineParamsFactory.parseOverrides(" \t\r\n{\"gpsLostMinS\":90}\n ").params.gpsLostMinS == 90)
        for pad in ["\u{A0}", "\u{3000}", "\u{0B}", "\u{0C}", "\u{2028}", "\u{FEFF}"] {
            let r = EngineParamsFactory.parseOverrides(pad + "{\"gpsLostMinS\":90}")
            #expect(r.malformed && r.params.gpsLostMinS == 60, "pad \(pad.unicodeScalars.map(\.value))")
        }
        #expect(!EngineParamsFactory.parseOverrides(nil).malformed)
    }

    /// Kotlin `fix(t, d)` in the T12 world: fix at `S + t` due south of (0, 106) at distance `d`, acc 8, no speed.
    @discardableResult
    static func t12Fix(_ e: inout EngineDriver, _ t: Double, _ d: Double) -> Step {
        e.feed(.locationFix(LocationFix(atMs: e.ms(t), fixAtMs: e.ms(t), lat: 0.0 - d / Geo.kMetresPerDegLat, lng: 106.0,
                                        accuracyM: 8.0, speedMps: nil)))
    }

    /// GAP-1 / GAP-2 repro base (T12T `lostTrip`): TRACKING, established, closing 12.5 m/s (k 1.2), one fix at S, tier SPARSE,
    /// policyIntervalAtLastFixS 5, then no fix. T10.4 closed both gaps: the pins became U99 / U100 (= Kotlin `WakeGuardT104Test`).
    static func lostTrip(_ t0S: Int) -> EngineDriver {
        t12Driver(t12TrackingState(d: 1000.0 + 12.5 * Double(t0S), tier: .sparse, policyAtFix: 5))
    }

    @Test("U99 GAP-1 (T10.4, was gap1Pin): Tick exactly at predicted keeps a wake-up (S + 2 511 000); the next one rings GPS_LOST")
    func u99Gap1() {
        var e = Self.lostTrip(3610)   // etaS = 3 710 − t
        let s10 = e.tick(10)
        #expect(s10.view.samplingPolicy?.tier == .medium && s10.events.compactMap(\.asGpsLost).isEmpty)
        #expect(s10.state.policyIntervalAtLastFixS == 180)
        #expect(s10.view.wakeAtMs == Self.S + 540_000)   // c2
        // (a) Doze loop.
        let wakes = WakeGuardT104Tests.doze(&e, "U99 a")
        #expect(wakes.map(\.0) == [540_000, 1_611_000, 1_911_000, 2_450_000, 2_511_000])
        guard wakes.count == 5 else { return }
        let lost = wakes[0].1
        #expect(lost.events.compactMap(\.asGpsLost) == [.init(atMs: Self.S + 540_000, cause: .noFixTimeout, lastFixAgeS: 540)])
        #expect(lost.view.predictedAlarmAtMs == Self.S + 2_510_000)
        #expect(wakes[1].1.view.samplingPolicy?.tier == .dense)
        #expect(wakes[2].1.events.fallbacks == [.init(atMs: Self.S + 1_911_000, fallbackAtMs: Self.S + 2_540_000, cause: .eta)])
        let ring = wakes[4].1
        #expect(ring.events.alarms.map(\.reason) == [.gpsLost] && ring.events.alarms.allSatisfy(\.ringNow))
        #expect(ring.events.fallbacks == [.init(atMs: Self.S + 2_511_000, fallbackAtMs: nil, cause: .superseded)])
        // (b) Same wake-ups up to the c8 Step, then a Tick exactly at P.
        var b = Self.lostTrip(3610)
        b.tick(10)
        for w: Int64 in [540_000, 1_611_000, 1_911_000, 2_450_000] { b.feed(.tick(atMs: Self.S + w)) }
        let atP = b.feed(.tick(atMs: Self.S + 2_510_000))
        #expect(atP.events.isEmpty, "Tick at P: \(atP.events)")
        #expect(atP.view.phase == .tracking && atP.view.predictedAlarmAtMs == Self.S + 2_510_000)
        #expect(atP.view.wakeAtMs == Self.S + 2_511_000)   // before T10.4: nil
        #expect(b.feed(.tick(atMs: Self.S + 2_511_000)).events.alarms.map(\.reason) == [.gpsLost])
    }

    @Test("U100 GAP-2 (T10.4, was gap2Pin): policy shortened in the Step keeps c2 and Tick(now) silent; GPS_LOST at 2 601 s (Doze) / 2 605 s (5 s ticks)")
    func u100Gap2() {
        var e = Self.lostTrip(3700)   // etaS = 3 800 − t
        let s = e.tick(100)
        #expect(s.view.samplingPolicy?.tier == .medium && s.view.gps == .ok && s.events.compactMap(\.asGpsLost).isEmpty)
        #expect(s.view.wakeAtMs == Self.S + 540_000)   // c2 not dropped
        #expect(WakeGuardT104Tests.i14(s) == nil)      // before T10.4: GpsLost(NO_FIX_TIMEOUT, 100)
        // (a) Doze loop.
        let wakes = WakeGuardT104Tests.doze(&e, "U100 a")
        #expect(wakes.map(\.0) == [540_000, 1_701_000, 2_001_000, 2_540_000, 2_601_000])
        guard wakes.count == 5 else { return }
        #expect(wakes[0].1.events.compactMap(\.asGpsLost) == [.init(atMs: Self.S + 540_000, cause: .noFixTimeout, lastFixAgeS: 540)])
        #expect(wakes[0].1.view.predictedAlarmAtMs == Self.S + 2_600_000)
        #expect(wakes[4].1.events.alarms.map(\.reason) == [.gpsLost])   // before: 2 800 000
        // (b) Ticks every 5 s.
        var f = Self.lostTrip(3700)
        var t = 0.0, lostT = -1.0, alarmT = -1.0
        while alarmT < 0 && t < 4000 {
            t += 5
            let st = f.tick(t)
            if lostT < 0 && !st.events.compactMap(\.asGpsLost).isEmpty { lostT = t }
            if !st.events.alarms.isEmpty { alarmT = t }
        }
        #expect(lostT == 540 && alarmT == 2605)   // before T10.4: 105, 2 605
    }

    // MARK: - Remote Config blank set = Kotlin isBlank (JVM 17: Character.isWhitespace || isSpaceChar)

    /// Computed on JDK 17.0.17 (the JVM Gradle runs the Kotlin tests on) over U+0000…U+FFFF.
    static let jvmBlank: Set<UInt32> = [
        0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x1C, 0x1D, 0x1E, 0x1F, 0x20, 0xA0, 0x1680,
        0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200A,
        0x2028, 0x2029, 0x202F, 0x205F, 0x3000,
    ]

    @Test("Remote Config blank: \\u00A0 \\u2007 \\u3000 \\t blank (defaults, not malformed); \\u200B, \\uFEFF, \\u0085 not blank (malformed)")
    func blankNamedCharacters() {
        for s in ["\u{A0}", "\u{2007}", "\u{3000}", "\t", " \u{A0}\t\u{3000}\u{2007} ", "\u{1680}\u{205F}"] {
            let r = EngineParamsFactory.parseOverrides(s)
            #expect(!r.malformed && r.rejected.isEmpty && r.params == .defaults, "\(s.unicodeScalars.map(\.value))")
        }
        // ZERO WIDTH SPACE (Cf), BOM (Cf) and NEL are not blank on the JVM → parsed as JSON → malformed.
        for s in ["\u{200B}", " \u{200B} ", "\u{FEFF}", "\u{85}", "\u{180E}"] {
            let r = EngineParamsFactory.parseOverrides(s)
            #expect(r.malformed && r.rejected.isEmpty && r.params == .defaults, "\(s.unicodeScalars.map(\.value))")
        }
        // Non-RFC whitespace around a valid object is not skipped by MiniJson → malformed (params stay default).
        let nbspObject = EngineParamsFactory.parseOverrides("\u{A0}{\"preAlertMinS\": 1}")
        #expect(nbspObject.malformed && nbspObject.params == .defaults)
        #expect(!EngineParamsFactory.parseOverrides(" \t\r\n{}\n").malformed)
    }

    @Test("Remote Config blank: isBlank(scalar) equals the JVM set for every BMP scalar; no supplementary scalar is blank")
    func blankWholeBmp() {
        var diff: [String] = []
        for v in UInt32(0)...0xFFFF {
            guard let u = Unicode.Scalar(v) else { continue }   // surrogates
            if EngineParamsFactory.isBlank(String(Character(u))) != Self.jvmBlank.contains(v) {
                diff.append(String(v, radix: 16))
            }
        }
        #expect(diff.isEmpty, "differs from JVM at U+\(diff)")
        for v: UInt32 in [0x1_0000, 0x1_F600, 0xE_0020, 0x10_FFFF] {
            #expect(!EngineParamsFactory.isBlank(String(Character(Unicode.Scalar(v)!))))
        }
        #expect(EngineParamsFactory.isBlank(""))
    }
}
