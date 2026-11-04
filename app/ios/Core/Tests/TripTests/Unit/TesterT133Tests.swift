import Foundation
import Testing
@testable import Trip

/// Tester T13.3 (T10.6, Swift): port of the Kotlin tester cases `unit/TesterT123Test.kt` (T12.3) — boundaries of W (`gpsLostLongS`
/// floor to the millisecond, `0` turns W off whatever `gpsLostLongHintFactor`), a real T12.2 snapshot (written by the Kotlin T12.2
/// engine, no `passAnchorD`, no T10.6 params) restored by the Swift T10.6 engine in the middle of a long loss, boundaries of the
/// slow-vehicle net (C27), Remote Config values out of range. Kotlin `T123 g` (U126 §9 numeric gate) is not ported: the Swift
/// `u126-longloss*.txt` are byte-identical to Kotlin's, where that gate runs.
@Suite("TesterT133Tests")
struct TesterT133Tests {
    static let S = KW.S

    static func alarms(_ s: Step) -> [TripEvent.Alarm] { s.events.alarms }

    static func estimateOf(_ s: EngineState) -> Estimate { Estimator.estimate(s, now: s.nowMs)! }

    /// Kotlin `crawlLost`: TRAIN hint (floor 12.73 m/s) but ground 4.8 / closing 4.0, last fix at S, 15 km left; the driver after
    /// the Step that declared GpsLost. lostLongAtS is exactly the floor gpsLostLongS; the ETA rule would wait until about S + 2 570 s.
    static func crawlLost(_ p: EngineParams = .defaults) -> KDriver {
        var e = KDriver(from: KW.trackingState(KW.cfg(.distance, thr: 1000, hint: .train), p: p, d: 15_000.0, ground: 4.8, closing: 4.0))
        let st = e.state
        let lost = e.tickMs(S + Int64(GpsMonitor.lostAfterS(st)) * 1000)
        #expect(!lost.events.compactMap(\.asGpsLost).isEmpty, "GpsLost")
        return e
    }

    /// Tick(view.wakeAtMs) until an Alarm (at most 500 wake-ups).
    static func dozeToAlarm(_ e: inout KDriver) {
        var g = 0
        while alarms(e.last).isEmpty && g < 500 {
            g += 1
            e.tickMs(e.view.wakeAtMs!)
        }
    }

    // MARK: - W: the gpsLostLongS floor, to the millisecond

    @Test("T133 a (Kotlin T123 a) W rings exactly at last fix + gpsLostLongS, not one millisecond earlier")
    func wFloorExact() throws {
        var e = Self.crawlLost()
        let est = Self.estimateOf(e.state)
        #expect(est.lostLongAtS == 1_800.0, "floor")
        let eta = try #require(est.etaS)
        #expect(eta > 1_200.0 + 700.0, "the ETA rule must not be the one ringing (etaS \(eta))")
        #expect(e.view.predictedAlarmAtMs == Self.S + 1_800_000, "predicted = lostLongAt")
        let before = e.tickMs(Self.S + 1_799_999)
        #expect(Self.alarms(before).isEmpty, "rang 1 ms before the floor: \(before.events)")
        #expect(before.view.phase == .tracking)
        let at = e.tickMs(Self.S + 1_800_000)
        let a = Self.alarms(at)
        #expect(a.count == 1)
        #expect(a.first?.reason == .gpsLost)
        #expect(a.first?.ringNow == true)
        #expect(a.first?.atMs == Self.S + 1_800_000)
    }

    @Test("T133 b (Kotlin T123 b) gpsLostLongS 1801 moves the floor by one second, 0 turns W off entirely (any hint factor)")
    func wFloorShiftAndOff() throws {
        var e = Self.crawlLost(KW.params(#"{"gpsLostLongS": 1801}"#))
        #expect(Self.estimateOf(e.state).lostLongAtS == 1_801.0)
        #expect(Self.alarms(e.tickMs(Self.S + 1_800_000)).isEmpty)
        #expect(Self.alarms(e.tickMs(Self.S + 1_800_999)).isEmpty)
        #expect(Self.alarms(e.tickMs(Self.S + 1_801_000)).map(\.reason) == [.gpsLost])

        // Off: no mark at any Step, nothing at the W time; the ETA rule (T10.5) rings later, with the wake-up loop only.
        var off = Self.crawlLost(KW.params(#"{"gpsLostLongS": 0, "gpsLostLongHintFactor": 2}"#))
        #expect(Self.estimateOf(off.state).lostLongAtS == nil)
        #expect(Self.alarms(off.tickMs(Self.S + 1_800_000)).isEmpty, "off rang at the W time")
        var guardN = 0
        while Self.alarms(off.last).isEmpty && guardN < 500 {
            guardN += 1
            #expect(Self.estimateOf(off.state).lostLongAtS == nil, "off: W mark at \(off.state.nowMs - Self.S)")
            off.tickMs(off.view.wakeAtMs!)
        }
        let offAlarms = Self.alarms(off.last)
        #expect(offAlarms.count == 1)
        let a = try #require(offAlarms.first)
        #expect(a.reason == .gpsLost)
        #expect((2_400_000...2_800_000).contains(a.atMs - Self.S), "off: ETA rule at \(Double(a.atMs - Self.S) / 1000.0) s")
        // gpsLostLongHintFactor has no effect while W is off (same alarm as factor 0 and 1).
        for f in ["0", "1"] {
            var o = Self.crawlLost(KW.params(#"{"gpsLostLongS": 0, "gpsLostLongHintFactor": "# + f + "}"))
            o.tickMs(Self.S + 1_800_000)
            Self.dozeToAlarm(&o)
            #expect(Self.alarms(o.last) == [a], "hint factor \(f) with W off")
        }
    }

    // MARK: - App update in the middle of a long loss: a real T12.2 snapshot (Kotlin-written)

    static func headSnapshot() throws -> EngineState { try TripEngine.decodeSnapshot(t122Snapshot) }

    @Test("T133 c (Kotlin T123 c) a T12.2 snapshot (no passAnchorD, no T10.6 params) decodes with the defaults and rings W early")
    func t122SnapshotRestore() throws {
        let st = try Self.headSnapshot()
        #expect(!Self.t122Snapshot.contains("passAnchorD"))
        #expect(!Self.t122Snapshot.contains("gpsLostLongS"))
        #expect(st.passAnchorD == nil)
        #expect(st.params.gpsLostLongS == 1_800)
        #expect(st.params.gpsLostLongHintFactor == 1.0)
        #expect(st.params.passedClosestSlowRiseM == 300)
        #expect(st.gps == .lost)
        #expect(st.nowMs == Self.S + 4_026_000)
        let lla = try #require(Self.estimateOf(st).lostLongAtS)
        let lostLongAt = st.last!.fixAtMs + TMath.floorMs(lla)
        #expect(lostLongAt > st.nowMs, "the mark is still ahead at the snapshot")

        // (1) Restore PENDING one minute later: no alarm yet, prediction = lostLongAt, then the wake-up loop rings at +1 s.
        let r1 = TripEngine.restore(st, nowMs: st.nowMs + 60_000, info: RestoreInfo(status: .pending))
        #expect(Self.alarms(r1).isEmpty)
        #expect(r1.view.predictedAlarmAtMs == lostLongAt)
        var s = r1
        var g = 0
        while Self.alarms(s).isEmpty && g < 500 {
            g += 1
            s = TripEngine.reduce(s.state, .tick(atMs: s.view.wakeAtMs!))
        }
        let a1s = Self.alarms(s)
        #expect(a1s.count == 1)
        let a1 = try #require(a1s.first)
        #expect(a1.reason == .gpsLost)
        #expect(a1.atMs == lostLongAt + 1_000)
        #expect(a1.atMs < Self.S + Self.t122AlarmMs, "T10.6 after an update rang later than T12.2 would have")

        // (2) Restore after the mark (process dead while the app was updated): GPS_LOST rings in the restore Step itself.
        for status in [FallbackRestoreStatus.pending, .missing, .unknown] {
            let r2 = TripEngine.restore(try Self.headSnapshot(), nowMs: lostLongAt + 120_000, info: RestoreInfo(status: status))
            let a2 = Self.alarms(r2)
            #expect(a2.count == 1, "\(status.jsonName): \(r2.events)")
            #expect(a2.first?.reason == .gpsLost, "\(status.jsonName)")
            #expect(a2.first?.ringNow == true, "\(status.jsonName)")
        }
        // Same text as Kotlin build/napstop/t123-c-update.txt (byte comparison by the tester).
        let line = "T12.2 snapshot at \(KW.kd(Double(st.nowMs - Self.S) / 1000.0)) s; lostLongAtS \(KW.kd(lla)); "
            + "T10.6 rings \(KW.kd(Double(a1.atMs - Self.S) / 1000.0)) s; T12.2 rang \(KW.kd(Double(Self.t122AlarmMs) / 1000.0)) s\n"
        Report.shared.write("unit/t123-c-update.txt", line)
    }

    // MARK: - Slow-vehicle net boundaries (C27)

    /// Gap open: minD 600, dStart 10 000 (open 9 400 >= 500), passedRadius 3 000 (> 600), openNeed max(500, 300) = 500.
    static func netState(_ d: Double, _ acc: Double, _ anchor: Double?, p: EngineParams = .defaults, gps: GpsStatus = .ok) -> EngineState {
        var st = KW.trackingState(KW.cfg(.distance, thr: 500), p: p, d: d, gps: gps, acc: acc, dStart: 10_000.0, minD: 600.0)
        st.passAnchorD = anchor
        return st
    }

    static func anchorAfter(_ st: EngineState) -> Double? {
        var s = st
        OvershootDetector.updatePassAnchor(&s, Estimator.estimate(s, now: s.nowMs))
        return s.passAnchorD
    }

    @Test("T133 d (Kotlin T123 d) passAnchorD boundaries: accuracy equal to speedSampleMaxAccM is good, open gap at exactly openNeedM")
    func passAnchorBoundaries() {
        #expect(Self.anchorAfter(Self.netState(1_200.0, 50.0, nil)) == 1_200.0, "acc == 50 is a good fix")
        #expect(Self.anchorAfter(Self.netState(1_200.0, 50.0.nextUp, nil)) == nil, "acc just above 50 sets no mark")
        #expect(Self.anchorAfter(Self.netState(1_200.0, 50.0.nextUp, 1_150.0)) == 1_150.0, "a poor fix keeps the mark")
        #expect(Self.anchorAfter(Self.netState(1_200.0, 8.0, 1_150.0)) == 1_150.0, "min")
        #expect(Self.anchorAfter(Self.netState(1_100.0, 8.0, nil)) == 1_100.0, "dSmooth - minD == openNeedM opens")
        #expect(Self.anchorAfter(Self.netState(1_100.0.nextDown, 8.0, 1_150.0)) == nil, "gap closed just below openNeedM clears the mark")
        #expect(Self.anchorAfter(Self.netState(1_200.0, 8.0, 1_150.0, gps: .lost)) == nil, "gps not OK clears the mark")
        #expect(Self.anchorAfter(Self.netState(1_200.0, 8.0, 1_150.0, p: KW.params(#"{"passedClosestSlowRiseM": 0}"#))) == nil,
                "0 turns the net off")
    }

    @Test("T133 e (Kotlin T123 e) slowAway boundaries: rise exactly passedClosestSlowRiseM counts, the second-to-last value decides")
    func slowAwayBoundaries() {
        func away(_ l3: [Double], acc: Double = 8.0, anchor: Double? = 1_000.0) -> Bool {
            var st = Self.netState(l3.last!, acc, anchor)
            st.last3 = l3
            return OvershootDetector.slowAway(st)
        }
        #expect(away([1_250.0, 1_300.0, 1_310.0]), "rise == 300")
        #expect(!away([1_250.0, 1_300.0.nextDown, 1_310.0]), "rise just under 300")
        #expect(!away([1_250.0, 1_290.0, 1_900.0]), "one far value (the last) is not enough")
        #expect(away([1_250.0, 1_300.0, 1_310.0], acc: 50.0), "acc == 50")
        #expect(!away([1_250.0, 1_300.0, 1_310.0], acc: 50.0.nextUp), "current fix poor")
        #expect(!away([1_300.0, 1_310.0]), "fewer than 3 values")
        #expect(!away([1_250.0, 1_300.0, 1_310.0], anchor: nil), "no mark")
    }

    // MARK: - Remote Config (T29 passes the JSON through)

    @Test("T133 f (Kotlin T123 f) Remote Config values out of range or of the wrong type are rejected one by one, default kept")
    func remoteConfigRejects() {
        let bad: [(String, [String])] = [
            ("gpsLostLongS", ["1e10", "-0.5", "21600.0001", #""1800""#, "null", "[1800]"]),
            ("gpsLostLongHintFactor", [#""1""#, "false", "1e309", "-1e-9", "2.0000001"]),
            ("passedClosestSlowRiseM", ["-1", "300.5", "3000.5", #""0""#]),
        ]
        var want = EngineParams.defaults
        want.etaStopPenaltyS = 30
        for (k, vs) in bad {
            for v in vs {
                let json = "{\"" + k + "\": " + v + ", \"etaStopPenaltyS\": 30}"
                let r = EngineParamsFactory.parseOverrides(json)
                #expect(!r.malformed, "\(k)=\(v)")
                #expect(r.rejected == [k], "\(k)=\(v)")
                #expect(r.params == want, "\(k)=\(v): other keys still applied, this one default")
            }
        }
        // Edge values that are valid: integral doubles for Int params, -0 as 0.
        #expect(EngineParamsFactory.parseOverrides(#"{"gpsLostLongS": 1800.0}"#).params.gpsLostLongS == 1_800)
        #expect(EngineParamsFactory.parseOverrides(#"{"gpsLostLongS": -0}"#).params.gpsLostLongS == 0)
        let hf = EngineParamsFactory.parseOverrides(#"{"gpsLostLongHintFactor": -0.0}"#).params.gpsLostLongHintFactor
        #expect(hf == 0.0)
        #expect(EngineParamsFactory.parseOverrides(#"{"passedClosestSlowRiseM": 1e3}"#).params.passedClosestSlowRiseM == 1_000)
    }

    /// Where the T12.2 engine (HEAD 1bea01e) rings when left alone from `t122Snapshot` (Tick-only wake-up loop), ms after S.
    static let t122AlarmMs: Int64 = 7_626_000

    /// Snapshot written by the Kotlin T12.2 engine (HEAD 1bea01e, default params), copied by script from
    /// `TesterT123Test.T122_SNAPSHOT`: TRAIN, DISTANCE 1 000, fixes every 5 s at 12.5 m/s from 110 km for 900 s, then no fix; first
    /// wake-up Tick at or after S + 3 000 s (S + 4 026 s). Synthetic coordinates.
    static let t122Snapshot = #"{"snapshotVersion":1,"params":{"fixMaxAgeS":60,"accAbsMaxM":100.0,"accRelMax":0.05,"accHardMaxM":2000.0,"maxPlausibleSpeedMps":55.0,"outlierResetSpanS":30,"smoothWindowS":12,"stationarySpeedMps":1.0,"motionAccFactor":1.0,"stopExitMinM":50,"speedEmaTauS":300,"shortStopIncludeS":60,"speedEstablishedMovingS":120,"speedEstablishedSamples":3,"maxSpeedSampleGapS":900,"speedSampleMaxAccM":50.0,"routeFactorPrior":1.2,"routeFactorMin":1.0,"routeFactorMax":2.0,"expectedSpeedKmhTrain":55,"expectedSpeedKmhCoach":60,"expectedSpeedKmhBus":20,"expectedSpeedKmhUnknown":60,"etaStopPenaltyS":20,"minSpeedForEtaMps":0.5,"etaUncertaintyFrac":0.1,"distanceModeFactor":1.0,"smartTargetS":600,"smartFloorM":1000,"smartSlowSpeedKmh":15,"smartSlowHysteresisKmh":2,"shortDistanceWarnS":240,"preAlertLeadS":1800,"preAlertDistanceFactor":5,"preAlertMinDistanceM":3000,"preAlertMinGapS":300,"gpsLostMinS":60,"gpsLostIntervalFactor":3,"gpsLostAlarmEtaS":1200,"acquireTimeoutS":120,"lostErrFrac":0.25,"lostSpeedGuardUpdates":2,"overshootNearMinM":1000,"overshootOpenM":1000,"overshootMinSpeedKmh":10,"passedClosestMinRadiusM":3000,"passedClosestReachFactor":2.0,"passedClosestOpenMinM":500,"passedClosestOpenFrac":0.5,"arrivedRadiusM":300,"snoozeS":60,"maxSnoozes":1,"alarmMaxActiveS":3600,"maxTripMinS":14400,"maxTripCapS":172800,"lowBatteryAlarmPct":5,"lowBatteryEarlierPct":15,"batteryPriorDrainPctPerH":2.0,"batteryMinRatePctPerH":0.5,"batteryMinRateWindowS":1200,"batteryReserveAfterAlarmS":900,"denseEnterS":900,"mediumEnterS":3600,"tierHysteresisFactor":1.25,"samplingSparseIntervalS":180,"samplingSparseMinIntervalS":90,"samplingMediumIntervalS":30,"samplingMediumMinIntervalS":15,"samplingDenseIntervalS":5,"samplingDenseMinIntervalS":2,"maxSavingIntervalFactor":2,"fallbackLagS":30,"fallbackEarlyFrac":0.25,"fallbackEarlyMaxS":3600,"fallbackHintSpeedFactor":1.0,"fallbackNearS":600,"fallbackNearSlackS":60,"fallbackMinLeadS":10,"fallbackQuietBeforeS":30,"fallbackMinShiftS":30,"fallbackMinIntervalS":60,"fallbackRetryS":60,"vehicleBusMaxAvgKmh":30},"config":{"tripId":"snap-1","destLat":16.2,"destLng":107.6,"mode":"DISTANCE","distanceThresholdM":1000,"timeThresholdMin":null,"preAlertEnabled":true,"vehicleHint":"TRAIN"},"nowMs":1800004026000,"startedAtMs":1800000000000,"phase":"TRACKING","gps":"LOST","locationCause":"AVAILABLE","last":{"fixAtMs":1800000900000,"lat":15.31291771469637,"lng":107.6,"accM":6.0,"d":98639.18588808276,"groundSample":12.5},"stopAnchor":null,"recent":[{"fixAtMs":1800000890000,"lat":15.311794825727631,"lng":107.6,"accM":6.0,"d":98764.04561705506,"groundSample":12.5},{"fixAtMs":1800000895000,"lat":15.312356270212002,"lng":107.6,"accM":6.0,"d":98701.61575256882,"groundSample":12.5},{"fixAtMs":1800000900000,"lat":15.31291771469637,"lng":107.6,"accM":6.0,"d":98639.18588808276,"groundSample":12.5}],"rejects":[],"dSmooth":98701.61575256882,"dStartM":109814.13163109969,"minD":98701.61575256882,"minDChord":false,"last3":[98826.47548154111,98764.04561705506,98701.61575256882],"ground":12.5,"closing":12.485972897224906,"movingTimeS":895.0,"movingSamples":179,"movingDistM":11187.5,"stopStartMs":null,"slow":false,"cvGuard":[12.485972897224752,12.485972897225142],"policy":{"tier":"MEDIUM","intervalS":30,"minIntervalS":15,"accuracy":"HIGH"},"policyIntervalAtLastFixS":180,"gpsLostAtMs":1800001440000,"lostEmittedBeforeFirstFix":false,"preAlertArmed":true,"preAlertFired":false,"arrivedFired":false,"alarm":{"atMs":null,"reason":null,"source":null,"lastRingAtMs":null,"lastReason":null,"ringing":false,"snoozeCount":0,"snoozeUntilMs":null,"dismissedAtMs":null},"overshootAtMs":null,"overshootPastM":null,"fallback":{"targetAtMs":1800006836133,"emittedAtMs":1800004026000,"status":"REQUESTED","confirmedAtMs":null,"resync":false,"near":false},"battery":{"levelPct":null,"charging":false,"segT0":null,"segL0":null,"armed":false,"riskEmitted":false,"choice":null,"choicePct":null},"maxTripDurationS":17291,"droppedFixes":0,"ended":null}"#
}
