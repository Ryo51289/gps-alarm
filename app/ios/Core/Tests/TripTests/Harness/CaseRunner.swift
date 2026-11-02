import Foundation
@testable import Trip

/// One harness run = (trace, case, sampling mode, phase) — T12 §8.3. Value type: I8 copies it mid-run.
struct RunOptions: Sendable {
    var timeShiftMs: Int64 = 0
    var paramOverrides: [(String, JsonValue)] = []
    var keepStates = false
}

struct Runner: Sendable {
    let trace: LoadedTrace
    let spec: CaseSpec
    let mode: String          // "all", "policy", "policy-jNN"
    let isPolicy: Bool
    let j: Int
    let startMs: Int64
    let interval: Int
    let duration: Int
    let params: EngineParams
    let config: TripConfig
    let keepStates: Bool

    var state: EngineState
    var lastView: TripView
    var os: OsSim
    var alive = true
    var lastDelivered: Int? = nil
    var sparseShifted = false
    var locBlocked = false
    var killSnapshot: EngineState? = nil
    var relaunchT: Int? = nil
    var records: [StepRecord] = []
    var states: [EngineState?] = []
    var fbOsAfterTick: [Int64?]
    var predictedAfterTick: [Int64?]
    var firstAlarmT: Int? = nil
    var runAnchors: [String: Int] = [:]
    var configErrors: [String] = []
    var violations: [String] = []
    var actionDone: [Bool]
    var started = false

    var run: String { "\(trace.file.traceId)/\(spec.id)/\(mode)" }
    var killT: Int? { spec.config.kill?.t }

    /// Builds the runner; static configuration errors are returned in `configErrors` (run must then fail).
    init(trace: LoadedTrace, spec: CaseSpec, mode: String, options: RunOptions = RunOptions()) {
        self.trace = trace
        self.spec = spec
        self.mode = mode
        self.isPolicy = mode.hasPrefix("policy")
        self.j = mode.hasPrefix("policy-j") ? Int(mode.dropFirst("policy-j".count)) ?? 0 : 0
        self.startMs = trace.file.startMs + options.timeShiftMs
        self.interval = trace.file.intervalS
        self.duration = trace.file.durationS
        self.keepStates = options.keepStates
        var errors: [String] = []
        // params = parseOverrides(write(config.params ⊕ overrides))
        var merged = spec.config.params
        for (k, v) in options.paramOverrides {
            if let i = merged.firstIndex(where: { $0.0 == k }) { merged[i].1 = v } else { merged.append((k, v)) }
        }
        let parsed = EngineParamsFactory.parseOverrides(MiniJson.write(.object(merged)))
        if parsed.malformed || !parsed.rejected.isEmpty {
            errors.append("config error: params rejected \(parsed.rejected)")
        }
        self.params = parsed.params
        let c = spec.config
        let mode: AlarmMode = c.mode == "distance" ? .distance : c.mode == "time" ? .time : .smart
        let hint = VehicleKind(jsonName: (c.vehicleHint ?? trace.file.vehicle).uppercased()) ?? .unknown
        self.config = TripConfig(tripId: "\(trace.file.traceId)/\(spec.id)", destLat: trace.file.destLat,
                                 destLng: trace.file.destLng, mode: mode, distanceThresholdM: c.thresholdM,
                                 timeThresholdMin: c.thresholdMin, preAlertEnabled: c.preAlert, vehicleHint: hint)
        if spec.policyPhaseSweep {
            if parsed.params.samplingSparseIntervalS % interval != 0 {
                errors.append("config error: samplingSparseIntervalS not a multiple of I")
            }
            if c.actions.contains(where: { $0.action == "batteryMaxSaving" }) {
                errors.append("config error: policyPhaseSweep with batteryMaxSaving")
            }
            if spec.samplingModes == ["all"] { errors.append("config error: policyPhaseSweep with samplingModes [all]") }
        }
        if spec.killSweep != nil && (c.kill != nil || c.relaunch != nil || c.osDismissOffsetS != nil || !c.osSim) {
            errors.append("config error: killSweep with kill/relaunch/osDismiss/osSim false")
        }
        if c.relaunch != nil && c.kill == nil { errors.append("config error: relaunch without kill") }
        if spec.allowFallbackFirst {   // T11.2 §3 V15, V16
            if c.kill != nil || spec.killSweep != nil {
                errors.append("config error: allowFallbackFirst cannot be used with config.kill or killSweep")
            }
            if !spec.expect.contains(where: { $0.filter.event == "alarm" && $0.filter.ringNow == false }) {
                errors.append("config error: allowFallbackFirst needs an expect entry for alarm with ringNow false")
            }
        }
        for (at, _) in c.actions {
            if let a = at.anchor, at.t == nil, Anchors.isRun(a), at.offsetS < interval {
                errors.append("config error: action run anchor offsetS < I")
            }
        }
        if let r = c.relaunch, let a = r.at.anchor, r.at.t == nil, Anchors.isRun(a), r.at.offsetS < interval {
            errors.append("config error: relaunch run anchor offsetS < I")
        }
        let ticks = trace.file.durationS / trace.file.intervalS + 1
        self.fbOsAfterTick = [Int64?](repeating: nil, count: ticks)
        self.predictedAfterTick = [Int64?](repeating: nil, count: ticks)
        self.actionDone = [Bool](repeating: false, count: c.actions.count)
        self.os = OsSim(enabled: c.osSim, osRingMaxS: c.osRingMaxS, osDismissOffsetS: c.osDismissOffsetS)
        // Placeholder state; replaced by start() below.
        let placeholder = EngineState.initial(config: config, params: parsed.params, nowMs: startMs)
        self.state = placeholder
        self.lastView = TripEngine.endedStep(placeholder).view
        self.configErrors = errors
    }

    func nowMs(_ t: Int) -> Int64 { startMs + 1000 * Int64(t) }

    // MARK: recording

    mutating func record(_ t: Int, _ input: InRecord, _ step: Step) {
        let rec = StepRecord(t: t, input: input, events: step.events, view: step.view,
                             v: Transcript.view(step.view, startMs))
        records.append(rec)
        if keepStates { states.append(step.state) }
        for e in step.events {
            let key = "event:" + e.fixtureName
            if runAnchors[key] == nil { runAnchors[key] = t }
            if case .alarm = e, firstAlarmT == nil { firstAlarmT = t }
        }
        if !Runner.finite(step.state) { violations.append("state not finite at t=\(t)") }
    }

    mutating func apply(_ step: Step, t: Int, input: InRecord) {
        state = step.state
        lastView = step.view
        record(t, input, step)
        os.react(step.events, nowMs: nowMs(t), t: t)
        var rang = Runner.hasRingNow(step.events)
        while !os.queue.isEmpty {
            let x = os.queue.removeFirst()
            if state.phase == .ended { _ = TripEngine.reduce(state, x); continue }
            let sub = TripEngine.reduce(state, x)
            state = sub.state
            lastView = sub.view
            record(t, .input(x, fixIndex: nil), sub)
            os.react(sub.events, nowMs: nowMs(t), t: t)
            rang = rang || Runner.hasRingNow(sub.events)
        }
        if rang && os.enabled && os.ringing == .none {
            violations.append("P07(ii) t=\(t): Alarm(ringNow=true) without a ringing alarm")
        }
    }

    mutating func feed(_ x: EngineInput, t: Int, fixIndex: Int? = nil) {
        if state.phase == .ended {
            _ = TripEngine.reduce(state, x)   // not recorded (T12 §8.3)
            return
        }
        apply(TripEngine.reduce(state, x), t: t, input: .input(x, fixIndex: fixIndex))
    }

    static func hasRingNow(_ events: [TripEvent]) -> Bool {
        events.contains { if case let .alarm(a) = $0 { return a.ringNow } else { return false } }
    }

    static func finite(_ s: EngineState) -> Bool {
        func f(_ x: Double?) -> Bool { x?.isFinite ?? true }
        func fr(_ r: FixRec?) -> Bool { guard let r else { return true }; return r.lat.isFinite && r.lng.isFinite && r.accM.isFinite && r.d.isFinite && f(r.groundSample) }
        return f(s.dSmooth) && f(s.dStartM) && f(s.minD) && f(s.ground) && f(s.closing) && s.movingTimeS.isFinite
            && s.movingDistM.isFinite && s.last3.allSatisfy(\.isFinite) && s.cvGuard.allSatisfy(\.isFinite)
            && fr(s.last) && fr(s.stopAnchor) && s.recent.allSatisfy { fr($0) } && s.rejects.allSatisfy { fr($0) }
    }

    // MARK: run

    /// start + full tick loop. `onTickEnd` sees a copy of the runner after each tick (I8 capture).
    mutating func runAll(onTickEnd: ((Int, Runner) -> Void)? = nil) {
        guard configErrors.isEmpty else { return }
        do {
            let step = try TripEngine.start(config: config, params: params, nowMs: startMs)
            apply(step, t: 0, input: .start)
        } catch {
            configErrors.append("config error: start threw \(error)")
            return
        }
        started = true
        runTicks(fromIndex: 0, onTickEnd: onTickEnd)
        finishChecks()
    }

    mutating func runTicks(fromIndex: Int, onTickEnd: ((Int, Runner) -> Void)?) {
        let n = duration / interval
        var idx = fromIndex
        while idx <= n {
            let t = idx * interval
            tick(t)
            fbOsAfterTick[idx] = os.fbOs
            predictedAfterTick[idx] = lastView.predictedAlarmAtMs
            onTickEnd?(t, self)
            idx += 1
        }
    }

    func resolve(_ at: At) -> Int? { Anchors.resolve(at, trace: trace.file, killT: killT, run: runAnchors) }

    mutating func tick(_ t: Int) {
        let now = nowMs(t)
        let c = spec.config
        if let k = c.kill?.t, t == k {
            killSnapshot = state
            alive = false
            os.onKill()
            records.append(StepRecord(t: t, input: .kill, events: [], view: lastView, v: ""))
            if keepStates { states.append(nil) }
        }
        if let r = c.relaunch, relaunchT == nil, let b = resolve(r.at), b == t {
            doRelaunch(t, status: r.status)
        }
        for x in os.tick(t: t, nowMs: now, alive: alive) { feed(x, t: t) }
        if !alive && os.osFallbackFiredT != nil && runAnchors["osFallbackFired"] == nil {
            runAnchors["osFallbackFired"] = os.osFallbackFiredT
        }
        if !alive {
            for (i, a) in c.actions.enumerated() where !actionDone[i] {
                if let b = resolve(a.at), b == t {
                    actionDone[i] = true
                    configErrors.append("config error: action \(a.action) at t=\(t) while engine dead (j=\(j))")
                }
            }
            return
        }
        for (i, a) in c.actions.enumerated() where !actionDone[i] {
            guard let b = resolve(a.at), b == t else { continue }
            actionDone[i] = true
            switch a.action {
            case "dismiss": os.onUserStop(); feed(.userAction(atMs: now, action: .dismiss), t: t)
            case "snooze": feed(.userAction(atMs: now, action: .snooze), t: t)
            case "stop": os.onUserStop(); feed(.userAction(atMs: now, action: .stopTrip), t: t)
            case "batteryMaxSaving": feed(.userAction(atMs: now, action: .batteryMaxSaving), t: t)
            case "batteryAlarmAt5": feed(.userAction(atMs: now, action: .batteryAlarmAt5), t: t)
            case "batteryAlarmEarlier": feed(.userAction(atMs: now, action: .batteryAlarmEarlier), t: t)
            case "locationOff": locBlocked = true; feed(.locationAvailability(atMs: now, cause: .servicesOff), t: t)
            case "permissionRevoked": locBlocked = true; feed(.locationAvailability(atMs: now, cause: .permissionRevoked), t: t)
            case "locationOn": locBlocked = false; feed(.locationAvailability(atMs: now, cause: .available), t: t)
            default: configErrors.append("config error: unknown action \(a.action)")
            }
        }
        if let b = c.battery.first(where: { $0.t == t }) {
            feed(.batterySample(atMs: now, levelPct: b.levelPct, charging: b.charging), t: t)
        }
        if let si = trace.byTick[t / interval], !locBlocked, allow(t, lastView.samplingPolicy) {
            let s = trace.samples[si]
            feed(.locationFix(LocationFix(atMs: now, fixAtMs: now, lat: s.lat, lng: s.lng, accuracyM: s.accuracyM,
                                          speedMps: s.speedMps)), t: t, fixIndex: s.index)
            lastDelivered = t
        } else {
            feed(.tick(atMs: now), t: t)
        }
    }

    mutating func allow(_ t: Int, _ p: SamplingPolicy?) -> Bool {
        guard isPolicy else { return true }
        guard let last = lastDelivered, let p else { return true }
        let need = p.intervalS + (j > 0 && !sparseShifted && p.tier == .sparse ? j * interval : 0)
        let ok = t - last >= need
        if ok && need > p.intervalS { sparseShifted = true }
        return ok
    }

    mutating func doRelaunch(_ t: Int, status: String) {
        relaunchT = t
        runAnchors["relaunch"] = t
        guard !alive, let snap = killSnapshot else {
            configErrors.append("config error: relaunch at t=\(t) while engine alive")
            return
        }
        if let a = spec.config.relaunch?.at.anchor, a.hasPrefix("event:"), let k = killT, t <= k {
            configErrors.append("config error: relaunch event anchor B <= kill.t")
        }
        if let off = spec.config.osDismissOffsetS {
            guard let fired = os.osFallbackFiredT, fired + off < t else {
                configErrors.append("config error: osDismiss not before relaunch")
                return
            }
        }
        let firedBefore = os.osFallbackFiredT.map { $0 < t } ?? false
        var info: RestoreInfo
        if status == "auto" {
            if firedBefore {
                if let d = os.osDismissedAtMs {
                    info = RestoreInfo(status: .dismissed, firedAtMs: os.osFallbackFiredAtMs, dismissedAtMs: d)
                } else {
                    info = RestoreInfo(status: .rang, firedAtMs: os.osFallbackFiredAtMs)
                }
            } else {
                info = RestoreInfo(status: .pending)
            }
        } else {
            guard let st = FallbackRestoreStatus(jsonName: status) else {
                configErrors.append("config error: fallbackStatus \(status)")
                return
            }
            if st == .missing { os.dropForMissing() }
            info = RestoreInfo(status: st, firedAtMs: firedBefore ? os.osFallbackFiredAtMs : nil,
                               dismissedAtMs: st == .dismissed && spec.config.osDismissOffsetS != nil ? os.osDismissedAtMs : nil)
        }
        let decoded: EngineState
        do { decoded = try TripEngine.decodeSnapshot(TripEngine.encodeSnapshot(snap)) } catch {
            violations.append("snapshot round-trip failed: \(error)")
            return
        }
        let now = nowMs(t)
        let step = TripEngine.restore(decoded, nowMs: now, info: info)
        alive = true
        apply(step, t: t, input: .restore(nowMs: now, status: info.status, firedAtMs: info.firedAtMs,
                                          dismissedAtMs: info.dismissedAtMs))
        if state.phase == .alarming || state.phase == .overshot, os.enabled, os.ringing == .none {
            feed(.alarmSilenced(atMs: now, silencedAtMs: now), t: t)
        }
    }

    mutating func finishChecks() {
        let c = spec.config
        for (i, a) in c.actions.enumerated() where !actionDone[i] {
            if let b = resolve(a.at), b > duration {
                configErrors.append("config error: action \(a.action) B=\(b) > durationS")
            } else {
                configErrors.append("config error: action \(a.action) anchor never occurred (j=\(j))")
            }
        }
        if let r = c.relaunch, relaunchT == nil {
            configErrors.append("config error: relaunch \(r.at.anchor ?? "") never happened")
        }
    }

    func transcript() -> String { Transcript.render(run: run, records: records, startMs: startMs) }
}
