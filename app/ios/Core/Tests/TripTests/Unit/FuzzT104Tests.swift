import Testing
@testable import Trip

/// U105 (T10.4 §7.1): the T12 tester's seeded fuzz (`TesterT12Test`: GPS jumps, poor accuracy, stale fixes, clock going back,
/// battery, permission loss, fallback failed/fired, `restore` mid-trip), ported to Swift with the same generator, the same draw
/// order and the same input mix (so the trips are the Kotlin trips), without the old GAP-1 / GAP-2 exemptions, plus I13 and I14.
@Suite("FuzzT104Tests")
struct FuzzT104Tests {
    static let S = TesterT13Tests.S

    /// splitmix64 seeded with `seed xor 0x5DEECE66D`, exactly as Kotlin `TesterT12Test.Fuzz`.
    struct Fuzz {
        var x: UInt64
        init(_ seed: Int64) { x = UInt64(bitPattern: seed) ^ 0x5DEECE66D }

        mutating func next() -> UInt64 {
            x &+= 0x9E3779B97F4A7C15
            var z = x
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }

        mutating func int(_ n: Int) -> Int { Int((next() >> 1) % UInt64(n)) }
        mutating func dbl() -> Double { Double(next() >> 11) / 9007199254740992.0 }
        mutating func chance(_ p: Double) -> Bool { dbl() < p }
    }

    /// Violations by kind; every kind is a defect (U105: no GAP-1 / GAP-2 exemption).
    struct Findings {
        var counts: [String: Int] = [:]
        var firstOf: [String: String] = [:]

        mutating func add(_ kind: String, _ at: String) {
            counts[kind, default: 0] += 1
            if firstOf[kind] == nil { firstOf[kind] = at }
        }

        var summary: String { counts.keys.sorted().map { "\($0)=\(counts[$0]!) first: \(firstOf[$0]!)" }.joined(separator: "\n") }
    }

    static func checkStep(_ prev: EngineState, _ s: Step, _ at: String, _ f: inout Findings) {
        func fail(_ kind: String, _ ok: Bool) { if !ok { f.add(kind, at) } }
        fail("finite", Runner.finite(s.state))
        fail("C16", (s.view.phase == .snoozed) == (s.view.snoozeUntilMs != nil))
        let enc = TripEngine.encodeSnapshot(s.state)
        let dec = try? TripEngine.decodeSnapshot(enc)
        fail("snapshot round-trip", dec == s.state && dec.map(TripEngine.encodeSnapshot) == enc)
        let ph = s.view.phase
        if ph == .acquiring || ph == .tracking {
            // Wake-up safety net: while the engine has not alarmed, a backup OS alarm is always requested.
            fail("active without fallback target", s.state.fallback.targetAtMs != nil)
            fail("active without predicted", s.view.predictedAlarmAtMs != nil)
        }
        // I13 (T10.4): not ENDED ⇒ wakeAtMs ≠ nil and > now; ENDED ⇒ nil.
        let w = s.view.wakeAtMs
        if ph == .ended {
            fail("I13 ENDED with wakeAt", w == nil)
        } else {
            fail("I13 wakeAt nil while \(ph.jsonName)", w != nil)
            fail("I13 wakeAt not after now", w.map { $0 > s.state.nowMs } ?? true)
        }
        if s.events.alarms.contains(where: \.ringNow) {
            fail("ringNow alarm outside ALARMING/OVERSHOT", ph == .alarming || ph == .overshot)
            fail("ringNow alarm not ringing", s.state.alarm.ringing)
        }
        if prev.alarm.atMs != nil { fail("first alarm time changed", prev.alarm.atMs == s.state.alarm.atMs) }
        if ph != .ended {
            // I14 (T10.4): reduce(s, Tick(s.nowMs)) emits nothing and returns an equal state.
            let again = TripEngine.reduce(s.state, .tick(atMs: s.state.nowMs))
            if !again.events.isEmpty { f.add("I14 Tick(now) emitted \(again.events.map(\.fixtureName))", at) }
            fail("I14 Tick(now) changed the state", again.state == s.state)
        }
    }

    /// One random trip (draw order = Kotlin `fuzzTrip`); returns the final state and the number of inputs.
    static func fuzzTrip(_ seed: Int64, _ f: inout Findings, limit: Int = .max) throws -> (EngineState, Int) {
        var r = Fuzz(seed)
        let mode = AlarmMode.allCases[r.int(3)]
        let thr: Int? = mode == .distance || r.chance(0.3) ? 200 + r.int(9801) : nil
        let thrMin: Int? = mode == .time || (mode != .distance && r.chance(0.3)) ? 5 + r.int(56) : nil
        let preAlert = r.chance(0.7)
        let hint = VehicleKind.allCases[r.int(4)]
        let config = TripConfig(tripId: "fuzz-\(seed)", destLat: 0.0, destLng: 106.0, mode: mode, distanceThresholdM: thr,
                                timeThresholdMin: thrMin, preAlertEnabled: preAlert, vehicleHint: hint)
        var step = try TripEngine.start(config: config, params: .defaults, nowMs: S)
        checkStep(step.state, step, "seed=\(seed) START", &f)
        var t = S
        var d = 2_000.0 + r.dbl() * 120_000.0
        let v = 3.0 + r.dbl() * 25.0
        var lastFb = step.state.fallback.targetAtMs
        let n = min(300 + r.int(500), limit)
        var count = 0
        for i in 0..<n {
            let prev = step.state
            if prev.phase == .ended { break }
            let dt: Int64
            switch r.int(10) {
            case 0: dt = 0
            case 1: dt = -Int64(r.int(30_000))   // clock jumps back (input atMs < state now)
            case 2: dt = 60_000 + Int64(r.int(1_200_000))
            default: dt = 1_000 + Int64(r.int(30_000))
            }
            t += dt
            let k = r.int(100)
            let x: EngineInput
            if k < 55 {
                d = Swift.max(d - v * (Double(Swift.max(dt, 0)) / 1000.0) * (0.5 + r.dbl()), -3_000.0)
                var dd = d.magnitude
                if r.chance(0.08) { dd += 5_000.0 * (r.dbl() - 0.3) }   // GPS jump
                dd = Swift.max(dd, 0.0)
                // Kotlin TestGeo.jitter(TestGeo.pointOnMeridian(DEST, dd), east, 0.0) with DEST = (0, 106).
                let lat0 = 0.0 - dd / Geo.kMetresPerDegLat
                let east = (r.dbl() - 0.5) * 40.0
                let lat = lat0 + 0.0 / Geo.kMetresPerDegLat
                let lng = 106.0 + east / (Geo.kMetresPerDegLat * Geo.cosDeg(lat0))
                let acc = r.chance(0.15) ? 100.0 + r.dbl() * 2_000.0 : 3.0 + r.dbl() * 30.0
                let age = Int64(r.chance(0.1) ? r.int(200_000) : r.int(3_000))
                let spd: Double?
                switch r.int(4) {
                case 0: spd = nil
                case 1: spd = 0.0
                default: spd = v * (0.5 + r.dbl())
                }
                x = .locationFix(LocationFix(atMs: t, fixAtMs: t - age, lat: lat, lng: lng, accuracyM: acc, speedMps: spd))
            } else if k < 75 {
                x = .tick(atMs: t)
            } else if k < 79 {
                let level = r.int(101)
                x = .batterySample(atMs: t, levelPct: level, charging: r.chance(0.2))
            } else if k < 82 {
                x = .locationAvailability(atMs: t, cause: AvailabilityCause.allCases[r.int(3)])
            } else if k < 88 {
                let at: Int64
                if r.chance(0.8), let lf = lastFb { at = lf } else { at = t + Int64(r.int(3_600_000)) }
                x = .fallbackScheduled(atMs: t, fallbackAtMs: at, ok: r.chance(0.85))
            } else if k < 90 {
                x = .fallbackFired(atMs: t, firedAtMs: t - Int64(r.int(60_000)))
            } else if k < 93 {
                x = .alarmSilenced(atMs: t, silencedAtMs: t)
            } else {
                let a = UserActionKind.allCases[r.int(UserActionKind.allCases.count)]
                // DISMISS / STOP rarely, so most trips run long.
                x = (a == .dismiss || a == .stopTrip) && !r.chance(0.15) ? .tick(atMs: t) : .userAction(atMs: t, action: a)
            }
            let label: String
            if r.chance(0.03) {
                // Process restart mid-trip: snapshot → restore with a random OS status.
                let st = try TripEngine.decodeSnapshot(TripEngine.encodeSnapshot(prev))
                let status = FallbackRestoreStatus.allCases[r.int(5)]
                let fired: Int64? = status == .rang || status == .dismissed ? t - Int64(r.int(60_000)) : nil
                let dismissed: Int64? = status == .dismissed ? t : nil
                label = "RESTORE \(status.jsonName)"
                step = TripEngine.restore(st, nowMs: t, info: RestoreInfo(status: status, firedAtMs: fired, dismissedAtMs: dismissed))
            } else {
                label = "\(x)"
                step = TripEngine.reduce(prev, x)
            }
            count += 1
            checkStep(prev, step, "seed=\(seed) i=\(i) after \(label)", &f)
            lastFb = step.state.fallback.targetAtMs ?? lastFb
        }
        return (step.state, count)
    }

    @Test("U105 a fuzz: 1 000 seeded trips keep the safety invariants, I13 and I14 at every Step (no GAP exemption)")
    func u105a() throws {
        var f = Findings()
        var steps = 0
        for seed in Int64(1)...1000 { steps += try Self.fuzzTrip(seed, &f).1 }
        #expect(steps > 50_000, "fuzz too small: \(steps)")
        #expect(f.counts.isEmpty, "defects:\n\(f.summary)")
        Report.shared.write("unit/u105-fuzz.txt", "steps=\(steps) defects=\(f.counts.count)\n\(f.summary)\n")
    }

    @Test("U105 a fuzz is deterministic (seeds 7, 77, 777)")
    func u105Deterministic() throws {
        for seed: Int64 in [7, 77, 777] {
            var f1 = Findings(), f2 = Findings()
            let a = try Self.fuzzTrip(seed, &f1), b = try Self.fuzzTrip(seed, &f2)
            #expect(TripEngine.encodeSnapshot(a.0) == TripEngine.encodeSnapshot(b.0) && a.1 == b.1)
        }
    }

    /// U105 b (T10.4; T12 tester's liveness test): after a fuzz prefix the platform delivers only Ticks at view.wakeAtMs and the OS
    /// fallback alarm (FallbackFired at fallbackAtMs when the status is not FAILED); no fix, nobody answers. Something must ring no
    /// later than deadline + fallbackLagS, and the trip must then end. The first alarm of a prefix that has not rung yet comes from
    /// a wake-up Tick, not from FallbackFired, unless the fallback was already overdue when the prefix ended. A second loop with
    /// Ticks only (no FallbackFired) must ring from the engine as well.
    @Test("U105 b Doze loop from 200 fuzz prefixes rings before the deadline from a wake-up Tick, and the trip ends")
    func u105b() throws {
        var viaFallbackFirst = 0, overdueAtStart = 0, engineFirst = 0
        var failures: [String] = []
        // Full fuzz trips (nearly all have rung already) and short prefixes of 5–44 inputs (mostly silent).
        for seed in Int64(1)...200 {
            for limit in [Int.max, 5 + Int(seed % 40)] {
                var unused = Findings()
                let s0 = try Self.fuzzTrip(seed, &unused, limit: limit).0
                if s0.phase == .ended { continue }
                let deadline = s0.startedAtMs + TMath.ms(s0.maxTripDurationS) + TMath.ms(s0.params.fallbackLagS)
                let overdue = s0.fallback.status != .failed && (s0.fallback.targetAtMs.map { $0 <= s0.nowMs } ?? false)
                for withFallback in [true, false] {
                    let tag = "seed=\(seed) limit=\(limit) fallback=\(withFallback)"
                    var step = TripEngine.reduce(s0, .tick(atMs: s0.nowMs))
                    var rang = s0.alarm.atMs != nil || !step.events.alarms.isEmpty
                    var guardCount = 0
                    loop: while step.state.phase != .ended {
                        let now = step.state.nowMs
                        let fb = withFallback && step.state.fallback.status != .failed ? step.state.fallback.targetAtMs : nil
                        let w = step.view.wakeAtMs
                        let fbAt = fb.map { Swift.max($0, now) }
                        guard let next = TMath.minOrNull(array: [w, fbAt]) else {
                            failures.append("\(tag): nothing will ever run again in \(step.state.phase.jsonName)")
                            break loop
                        }
                        if !rang && next > deadline {
                            failures.append("\(tag): still silent after the deadline")
                            break loop
                        }
                        let viaFallback = fb != nil && next == fbAt && (w == nil || fb! <= w!)
                        step = viaFallback ? TripEngine.reduce(step.state, .fallbackFired(atMs: next, firedAtMs: fb!))
                            : TripEngine.reduce(step.state, .tick(atMs: next))
                        if !rang && !step.events.alarms.isEmpty {
                            rang = true
                            if viaFallback {
                                if overdue { overdueAtStart += 1 } else { viaFallbackFirst += 1 }
                            } else if withFallback {
                                engineFirst += 1
                                if step.events.alarms.count != 1 || !step.events.alarms[0].ringNow {
                                    failures.append("\(tag): engine alarm without ringNow")
                                }
                            }
                        }
                        guardCount += 1
                        if guardCount > 20_000 {
                            failures.append("\(tag): no end after 20 000 wake-ups")
                            break loop
                        }
                    }
                    if !rang { failures.append("\(tag): ended without any alarm") }
                }
            }
        }
        Report.shared.write("unit/u105-liveness.txt",
                            "engineFirst=\(engineFirst) viaFallbackFirst=\(viaFallbackFirst) overdueAtStart=\(overdueAtStart)\n")
        #expect(failures.isEmpty, "\(failures.prefix(20))")
        #expect(viaFallbackFirst == 0, "first alarm via FallbackFired: \(viaFallbackFirst) (overdue at start \(overdueAtStart))")
        #expect(engineFirst > 0)
    }
}
