// EngineParams: the 86 parameters of T10 §5 (after T10.6) (names, kinds, defaults, ranges), PARAM_SPECS and the Remote Config
// override parser (T12 §7.2, C12). Generated from the T10 §5 table; PARAM_SPECS is the single source of truth.

public struct EngineParams: Sendable, Equatable {
    public internal(set) var fixMaxAgeS: Int = 60
    public internal(set) var accAbsMaxM: Double = 100.0
    public internal(set) var accRelMax: Double = 0.05
    public internal(set) var accHardMaxM: Double = 2000.0
    public internal(set) var maxPlausibleSpeedMps: Double = 55.0
    public internal(set) var outlierResetSpanS: Int = 30
    public internal(set) var smoothWindowS: Int = 12
    public internal(set) var stationarySpeedMps: Double = 1.0
    public internal(set) var motionAccFactor: Double = 1.0
    public internal(set) var stopExitMinM: Int = 50
    public internal(set) var speedEmaTauS: Int = 300
    public internal(set) var shortStopIncludeS: Int = 60
    public internal(set) var speedEstablishedMovingS: Int = 120
    public internal(set) var speedEstablishedSamples: Int = 3
    public internal(set) var maxSpeedSampleGapS: Int = 900
    public internal(set) var speedSampleMaxAccM: Double = 50.0
    public internal(set) var routeFactorPrior: Double = 1.2
    public internal(set) var routeFactorMin: Double = 1.0
    public internal(set) var routeFactorMax: Double = 2.0
    public internal(set) var expectedSpeedKmhTrain: Int = 55
    public internal(set) var expectedSpeedKmhCoach: Int = 60
    public internal(set) var expectedSpeedKmhBus: Int = 20
    public internal(set) var expectedSpeedKmhUnknown: Int = 60
    public internal(set) var etaStopPenaltyS: Int = 20
    public internal(set) var minSpeedForEtaMps: Double = 0.5
    public internal(set) var etaUncertaintyFrac: Double = 0.1
    public internal(set) var distanceModeFactor: Double = 1.0
    public internal(set) var smartTargetS: Int = 600
    public internal(set) var smartFloorM: Int = 1000
    public internal(set) var smartSlowSpeedKmh: Int = 15
    public internal(set) var smartSlowHysteresisKmh: Int = 2
    public internal(set) var shortDistanceWarnS: Int = 240
    public internal(set) var preAlertLeadS: Int = 1800
    public internal(set) var preAlertDistanceFactor: Int = 5
    public internal(set) var preAlertMinDistanceM: Int = 3000
    public internal(set) var preAlertMinGapS: Int = 300
    public internal(set) var gpsLostMinS: Int = 60
    public internal(set) var gpsLostIntervalFactor: Int = 3
    public internal(set) var gpsLostAlarmEtaS: Int = 1200
    public internal(set) var acquireTimeoutS: Int = 120
    public internal(set) var lostErrFrac: Double = 0.25
    public internal(set) var lostSpeedGuardUpdates: Int = 2
    public internal(set) var gpsLostLongS: Int = 1800
    public internal(set) var gpsLostLongHintFactor: Double = 1.0
    public internal(set) var overshootNearMinM: Int = 1000
    public internal(set) var overshootOpenM: Int = 1000
    public internal(set) var overshootMinSpeedKmh: Int = 10
    public internal(set) var passedClosestMinRadiusM: Int = 3000
    public internal(set) var passedClosestReachFactor: Double = 2.0
    public internal(set) var passedClosestOpenMinM: Int = 500
    public internal(set) var passedClosestOpenFrac: Double = 0.5
    public internal(set) var passedClosestSlowRiseM: Int = 300
    public internal(set) var arrivedRadiusM: Int = 300
    public internal(set) var snoozeS: Int = 60
    public internal(set) var maxSnoozes: Int = 1
    public internal(set) var alarmMaxActiveS: Int = 3600
    public internal(set) var maxTripMinS: Int = 14400
    public internal(set) var maxTripCapS: Int = 172800
    public internal(set) var lowBatteryAlarmPct: Int = 5
    public internal(set) var lowBatteryEarlierPct: Int = 15
    public internal(set) var batteryPriorDrainPctPerH: Double = 2.0
    public internal(set) var batteryMinRatePctPerH: Double = 0.5
    public internal(set) var batteryMinRateWindowS: Int = 1200
    public internal(set) var batteryReserveAfterAlarmS: Int = 900
    public internal(set) var denseEnterS: Int = 900
    public internal(set) var mediumEnterS: Int = 3600
    public internal(set) var tierHysteresisFactor: Double = 1.25
    public internal(set) var samplingSparseIntervalS: Int = 180
    public internal(set) var samplingSparseMinIntervalS: Int = 90
    public internal(set) var samplingMediumIntervalS: Int = 30
    public internal(set) var samplingMediumMinIntervalS: Int = 15
    public internal(set) var samplingDenseIntervalS: Int = 5
    public internal(set) var samplingDenseMinIntervalS: Int = 2
    public internal(set) var maxSavingIntervalFactor: Int = 2
    public internal(set) var fallbackLagS: Int = 30
    public internal(set) var fallbackEarlyFrac: Double = 0.25
    public internal(set) var fallbackEarlyMaxS: Int = 3600
    public internal(set) var fallbackHintSpeedFactor: Double = 1.0
    public internal(set) var fallbackNearS: Int = 600
    public internal(set) var fallbackNearSlackS: Int = 60
    public internal(set) var fallbackMinLeadS: Int = 10
    public internal(set) var fallbackQuietBeforeS: Int = 30
    public internal(set) var fallbackMinShiftS: Int = 30
    public internal(set) var fallbackMinIntervalS: Int = 60
    public internal(set) var fallbackRetryS: Int = 60
    public internal(set) var vehicleBusMaxAvgKmh: Int = 30

    public static let defaults = EngineParams()

    init() {}

    /// Value of parameter `index` (PARAM_SPECS order).
    func value(at index: Int) -> ParamValue {
        switch index {
        case 0: .int(fixMaxAgeS)
        case 1: .double(accAbsMaxM)
        case 2: .double(accRelMax)
        case 3: .double(accHardMaxM)
        case 4: .double(maxPlausibleSpeedMps)
        case 5: .int(outlierResetSpanS)
        case 6: .int(smoothWindowS)
        case 7: .double(stationarySpeedMps)
        case 8: .double(motionAccFactor)
        case 9: .int(stopExitMinM)
        case 10: .int(speedEmaTauS)
        case 11: .int(shortStopIncludeS)
        case 12: .int(speedEstablishedMovingS)
        case 13: .int(speedEstablishedSamples)
        case 14: .int(maxSpeedSampleGapS)
        case 15: .double(speedSampleMaxAccM)
        case 16: .double(routeFactorPrior)
        case 17: .double(routeFactorMin)
        case 18: .double(routeFactorMax)
        case 19: .int(expectedSpeedKmhTrain)
        case 20: .int(expectedSpeedKmhCoach)
        case 21: .int(expectedSpeedKmhBus)
        case 22: .int(expectedSpeedKmhUnknown)
        case 23: .int(etaStopPenaltyS)
        case 24: .double(minSpeedForEtaMps)
        case 25: .double(etaUncertaintyFrac)
        case 26: .double(distanceModeFactor)
        case 27: .int(smartTargetS)
        case 28: .int(smartFloorM)
        case 29: .int(smartSlowSpeedKmh)
        case 30: .int(smartSlowHysteresisKmh)
        case 31: .int(shortDistanceWarnS)
        case 32: .int(preAlertLeadS)
        case 33: .int(preAlertDistanceFactor)
        case 34: .int(preAlertMinDistanceM)
        case 35: .int(preAlertMinGapS)
        case 36: .int(gpsLostMinS)
        case 37: .int(gpsLostIntervalFactor)
        case 38: .int(gpsLostAlarmEtaS)
        case 39: .int(acquireTimeoutS)
        case 40: .double(lostErrFrac)
        case 41: .int(lostSpeedGuardUpdates)
        case 42: .int(gpsLostLongS)
        case 43: .double(gpsLostLongHintFactor)
        case 44: .int(overshootNearMinM)
        case 45: .int(overshootOpenM)
        case 46: .int(overshootMinSpeedKmh)
        case 47: .int(passedClosestMinRadiusM)
        case 48: .double(passedClosestReachFactor)
        case 49: .int(passedClosestOpenMinM)
        case 50: .double(passedClosestOpenFrac)
        case 51: .int(passedClosestSlowRiseM)
        case 52: .int(arrivedRadiusM)
        case 53: .int(snoozeS)
        case 54: .int(maxSnoozes)
        case 55: .int(alarmMaxActiveS)
        case 56: .int(maxTripMinS)
        case 57: .int(maxTripCapS)
        case 58: .int(lowBatteryAlarmPct)
        case 59: .int(lowBatteryEarlierPct)
        case 60: .double(batteryPriorDrainPctPerH)
        case 61: .double(batteryMinRatePctPerH)
        case 62: .int(batteryMinRateWindowS)
        case 63: .int(batteryReserveAfterAlarmS)
        case 64: .int(denseEnterS)
        case 65: .int(mediumEnterS)
        case 66: .double(tierHysteresisFactor)
        case 67: .int(samplingSparseIntervalS)
        case 68: .int(samplingSparseMinIntervalS)
        case 69: .int(samplingMediumIntervalS)
        case 70: .int(samplingMediumMinIntervalS)
        case 71: .int(samplingDenseIntervalS)
        case 72: .int(samplingDenseMinIntervalS)
        case 73: .int(maxSavingIntervalFactor)
        case 74: .int(fallbackLagS)
        case 75: .double(fallbackEarlyFrac)
        case 76: .int(fallbackEarlyMaxS)
        case 77: .double(fallbackHintSpeedFactor)
        case 78: .int(fallbackNearS)
        case 79: .int(fallbackNearSlackS)
        case 80: .int(fallbackMinLeadS)
        case 81: .int(fallbackQuietBeforeS)
        case 82: .int(fallbackMinShiftS)
        case 83: .int(fallbackMinIntervalS)
        case 84: .int(fallbackRetryS)
        case 85: .int(vehicleBusMaxAvgKmh)
        default: preconditionFailure("param index")
        }
    }

    /// Sets parameter `index`; the value kind must match PARAM_SPECS.
    mutating func set(at index: Int, _ v: ParamValue) {
        switch (index, v) {
        case let (0, .int(x)): fixMaxAgeS = x
        case let (1, .double(x)): accAbsMaxM = x
        case let (2, .double(x)): accRelMax = x
        case let (3, .double(x)): accHardMaxM = x
        case let (4, .double(x)): maxPlausibleSpeedMps = x
        case let (5, .int(x)): outlierResetSpanS = x
        case let (6, .int(x)): smoothWindowS = x
        case let (7, .double(x)): stationarySpeedMps = x
        case let (8, .double(x)): motionAccFactor = x
        case let (9, .int(x)): stopExitMinM = x
        case let (10, .int(x)): speedEmaTauS = x
        case let (11, .int(x)): shortStopIncludeS = x
        case let (12, .int(x)): speedEstablishedMovingS = x
        case let (13, .int(x)): speedEstablishedSamples = x
        case let (14, .int(x)): maxSpeedSampleGapS = x
        case let (15, .double(x)): speedSampleMaxAccM = x
        case let (16, .double(x)): routeFactorPrior = x
        case let (17, .double(x)): routeFactorMin = x
        case let (18, .double(x)): routeFactorMax = x
        case let (19, .int(x)): expectedSpeedKmhTrain = x
        case let (20, .int(x)): expectedSpeedKmhCoach = x
        case let (21, .int(x)): expectedSpeedKmhBus = x
        case let (22, .int(x)): expectedSpeedKmhUnknown = x
        case let (23, .int(x)): etaStopPenaltyS = x
        case let (24, .double(x)): minSpeedForEtaMps = x
        case let (25, .double(x)): etaUncertaintyFrac = x
        case let (26, .double(x)): distanceModeFactor = x
        case let (27, .int(x)): smartTargetS = x
        case let (28, .int(x)): smartFloorM = x
        case let (29, .int(x)): smartSlowSpeedKmh = x
        case let (30, .int(x)): smartSlowHysteresisKmh = x
        case let (31, .int(x)): shortDistanceWarnS = x
        case let (32, .int(x)): preAlertLeadS = x
        case let (33, .int(x)): preAlertDistanceFactor = x
        case let (34, .int(x)): preAlertMinDistanceM = x
        case let (35, .int(x)): preAlertMinGapS = x
        case let (36, .int(x)): gpsLostMinS = x
        case let (37, .int(x)): gpsLostIntervalFactor = x
        case let (38, .int(x)): gpsLostAlarmEtaS = x
        case let (39, .int(x)): acquireTimeoutS = x
        case let (40, .double(x)): lostErrFrac = x
        case let (41, .int(x)): lostSpeedGuardUpdates = x
        case let (42, .int(x)): gpsLostLongS = x
        case let (43, .double(x)): gpsLostLongHintFactor = x
        case let (44, .int(x)): overshootNearMinM = x
        case let (45, .int(x)): overshootOpenM = x
        case let (46, .int(x)): overshootMinSpeedKmh = x
        case let (47, .int(x)): passedClosestMinRadiusM = x
        case let (48, .double(x)): passedClosestReachFactor = x
        case let (49, .int(x)): passedClosestOpenMinM = x
        case let (50, .double(x)): passedClosestOpenFrac = x
        case let (51, .int(x)): passedClosestSlowRiseM = x
        case let (52, .int(x)): arrivedRadiusM = x
        case let (53, .int(x)): snoozeS = x
        case let (54, .int(x)): maxSnoozes = x
        case let (55, .int(x)): alarmMaxActiveS = x
        case let (56, .int(x)): maxTripMinS = x
        case let (57, .int(x)): maxTripCapS = x
        case let (58, .int(x)): lowBatteryAlarmPct = x
        case let (59, .int(x)): lowBatteryEarlierPct = x
        case let (60, .double(x)): batteryPriorDrainPctPerH = x
        case let (61, .double(x)): batteryMinRatePctPerH = x
        case let (62, .int(x)): batteryMinRateWindowS = x
        case let (63, .int(x)): batteryReserveAfterAlarmS = x
        case let (64, .int(x)): denseEnterS = x
        case let (65, .int(x)): mediumEnterS = x
        case let (66, .double(x)): tierHysteresisFactor = x
        case let (67, .int(x)): samplingSparseIntervalS = x
        case let (68, .int(x)): samplingSparseMinIntervalS = x
        case let (69, .int(x)): samplingMediumIntervalS = x
        case let (70, .int(x)): samplingMediumMinIntervalS = x
        case let (71, .int(x)): samplingDenseIntervalS = x
        case let (72, .int(x)): samplingDenseMinIntervalS = x
        case let (73, .int(x)): maxSavingIntervalFactor = x
        case let (74, .int(x)): fallbackLagS = x
        case let (75, .double(x)): fallbackEarlyFrac = x
        case let (76, .int(x)): fallbackEarlyMaxS = x
        case let (77, .double(x)): fallbackHintSpeedFactor = x
        case let (78, .int(x)): fallbackNearS = x
        case let (79, .int(x)): fallbackNearSlackS = x
        case let (80, .int(x)): fallbackMinLeadS = x
        case let (81, .int(x)): fallbackQuietBeforeS = x
        case let (82, .int(x)): fallbackMinShiftS = x
        case let (83, .int(x)): fallbackMinIntervalS = x
        case let (84, .int(x)): fallbackRetryS = x
        case let (85, .int(x)): vehicleBusMaxAvgKmh = x
        default: preconditionFailure("param kind")
        }
    }
}

enum ParamKind: Sendable, Equatable { case int, double }

enum ParamValue: Sendable, Equatable {
    case int(Int)
    case double(Double)
}

struct ParamSpec: Sendable, Equatable {
    let name: String
    let kind: ParamKind
    let defaultValue: Double
    let min: Double
    let max: Double
}

enum ParamTable {
    // swiftlint:disable:next identifier_name
    static let PARAM_SPECS: [ParamSpec] = [
        ParamSpec(name: "fixMaxAgeS", kind: .int, defaultValue: 60.0, min: 10.0, max: 300.0),
        ParamSpec(name: "accAbsMaxM", kind: .double, defaultValue: 100.0, min: 20.0, max: 500.0),
        ParamSpec(name: "accRelMax", kind: .double, defaultValue: 0.05, min: 0.0, max: 0.2),
        ParamSpec(name: "accHardMaxM", kind: .double, defaultValue: 2000.0, min: 200.0, max: 5000.0),
        ParamSpec(name: "maxPlausibleSpeedMps", kind: .double, defaultValue: 55.0, min: 30.0, max: 100.0),
        ParamSpec(name: "outlierResetSpanS", kind: .int, defaultValue: 30.0, min: 10.0, max: 300.0),
        ParamSpec(name: "smoothWindowS", kind: .int, defaultValue: 12.0, min: 0.0, max: 60.0),
        ParamSpec(name: "stationarySpeedMps", kind: .double, defaultValue: 1.0, min: 0.3, max: 3.0),
        ParamSpec(name: "motionAccFactor", kind: .double, defaultValue: 1.0, min: 0.5, max: 3.0),
        ParamSpec(name: "stopExitMinM", kind: .int, defaultValue: 50.0, min: 20.0, max: 300.0),
        ParamSpec(name: "speedEmaTauS", kind: .int, defaultValue: 300.0, min: 30.0, max: 1800.0),
        ParamSpec(name: "shortStopIncludeS", kind: .int, defaultValue: 60.0, min: 0.0, max: 300.0),
        ParamSpec(name: "speedEstablishedMovingS", kind: .int, defaultValue: 120.0, min: 0.0, max: 600.0),
        ParamSpec(name: "speedEstablishedSamples", kind: .int, defaultValue: 3.0, min: 1.0, max: 20.0),
        ParamSpec(name: "maxSpeedSampleGapS", kind: .int, defaultValue: 900.0, min: 60.0, max: 3600.0),
        ParamSpec(name: "speedSampleMaxAccM", kind: .double, defaultValue: 50.0, min: 10.0, max: 200.0),
        ParamSpec(name: "routeFactorPrior", kind: .double, defaultValue: 1.2, min: 1.0, max: 2.0),
        ParamSpec(name: "routeFactorMin", kind: .double, defaultValue: 1.0, min: 1.0, max: 1.5),
        ParamSpec(name: "routeFactorMax", kind: .double, defaultValue: 2.0, min: 1.2, max: 4.0),
        ParamSpec(name: "expectedSpeedKmhTrain", kind: .int, defaultValue: 55.0, min: 5.0, max: 150.0),
        ParamSpec(name: "expectedSpeedKmhCoach", kind: .int, defaultValue: 60.0, min: 5.0, max: 150.0),
        ParamSpec(name: "expectedSpeedKmhBus", kind: .int, defaultValue: 20.0, min: 5.0, max: 150.0),
        ParamSpec(name: "expectedSpeedKmhUnknown", kind: .int, defaultValue: 60.0, min: 5.0, max: 150.0),
        ParamSpec(name: "etaStopPenaltyS", kind: .int, defaultValue: 20.0, min: 0.0, max: 120.0),
        ParamSpec(name: "minSpeedForEtaMps", kind: .double, defaultValue: 0.5, min: 0.1, max: 3.0),
        ParamSpec(name: "etaUncertaintyFrac", kind: .double, defaultValue: 0.1, min: 0.0, max: 0.5),
        ParamSpec(name: "distanceModeFactor", kind: .double, defaultValue: 1.0, min: 1.0, max: 1.5),
        ParamSpec(name: "smartTargetS", kind: .int, defaultValue: 600.0, min: 300.0, max: 1200.0),
        ParamSpec(name: "smartFloorM", kind: .int, defaultValue: 1000.0, min: 500.0, max: 3000.0),
        ParamSpec(name: "smartSlowSpeedKmh", kind: .int, defaultValue: 15.0, min: 5.0, max: 30.0),
        ParamSpec(name: "smartSlowHysteresisKmh", kind: .int, defaultValue: 2.0, min: 0.0, max: 10.0),
        ParamSpec(name: "shortDistanceWarnS", kind: .int, defaultValue: 240.0, min: 60.0, max: 600.0),
        ParamSpec(name: "preAlertLeadS", kind: .int, defaultValue: 1800.0, min: 600.0, max: 3600.0),
        ParamSpec(name: "preAlertDistanceFactor", kind: .int, defaultValue: 5.0, min: 2.0, max: 10.0),
        ParamSpec(name: "preAlertMinDistanceM", kind: .int, defaultValue: 3000.0, min: 1000.0, max: 10000.0),
        ParamSpec(name: "preAlertMinGapS", kind: .int, defaultValue: 300.0, min: 0.0, max: 900.0),
        ParamSpec(name: "gpsLostMinS", kind: .int, defaultValue: 60.0, min: 20.0, max: 300.0),
        ParamSpec(name: "gpsLostIntervalFactor", kind: .int, defaultValue: 3.0, min: 2.0, max: 5.0),
        ParamSpec(name: "gpsLostAlarmEtaS", kind: .int, defaultValue: 1200.0, min: 300.0, max: 3600.0),
        ParamSpec(name: "acquireTimeoutS", kind: .int, defaultValue: 120.0, min: 30.0, max: 600.0),
        ParamSpec(name: "lostErrFrac", kind: .double, defaultValue: 0.25, min: 0.0, max: 1.0),
        ParamSpec(name: "lostSpeedGuardUpdates", kind: .int, defaultValue: 2.0, min: 0.0, max: 5.0),
        ParamSpec(name: "gpsLostLongS", kind: .int, defaultValue: 1800.0, min: 0.0, max: 21600.0),
        ParamSpec(name: "gpsLostLongHintFactor", kind: .double, defaultValue: 1.0, min: 0.0, max: 2.0),
        ParamSpec(name: "overshootNearMinM", kind: .int, defaultValue: 1000.0, min: 300.0, max: 3000.0),
        ParamSpec(name: "overshootOpenM", kind: .int, defaultValue: 1000.0, min: 300.0, max: 3000.0),
        ParamSpec(name: "overshootMinSpeedKmh", kind: .int, defaultValue: 10.0, min: 3.0, max: 30.0),
        ParamSpec(name: "passedClosestMinRadiusM", kind: .int, defaultValue: 3000.0, min: 1000.0, max: 10000.0),
        ParamSpec(name: "passedClosestReachFactor", kind: .double, defaultValue: 2.0, min: 1.0, max: 4.0),
        ParamSpec(name: "passedClosestOpenMinM", kind: .int, defaultValue: 500.0, min: 200.0, max: 3000.0),
        ParamSpec(name: "passedClosestOpenFrac", kind: .double, defaultValue: 0.5, min: 0.2, max: 2.0),
        ParamSpec(name: "passedClosestSlowRiseM", kind: .int, defaultValue: 300.0, min: 0.0, max: 3000.0),
        ParamSpec(name: "arrivedRadiusM", kind: .int, defaultValue: 300.0, min: 50.0, max: 1000.0),
        ParamSpec(name: "snoozeS", kind: .int, defaultValue: 60.0, min: 30.0, max: 600.0),
        ParamSpec(name: "maxSnoozes", kind: .int, defaultValue: 1.0, min: 0.0, max: 3.0),
        ParamSpec(name: "alarmMaxActiveS", kind: .int, defaultValue: 3600.0, min: 600.0, max: 14400.0),
        ParamSpec(name: "maxTripMinS", kind: .int, defaultValue: 14400.0, min: 3600.0, max: 259200.0),
        ParamSpec(name: "maxTripCapS", kind: .int, defaultValue: 172800.0, min: 3600.0, max: 259200.0),
        ParamSpec(name: "lowBatteryAlarmPct", kind: .int, defaultValue: 5.0, min: 2.0, max: 20.0),
        ParamSpec(name: "lowBatteryEarlierPct", kind: .int, defaultValue: 15.0, min: 5.0, max: 40.0),
        ParamSpec(name: "batteryPriorDrainPctPerH", kind: .double, defaultValue: 2.0, min: 0.5, max: 10.0),
        ParamSpec(name: "batteryMinRatePctPerH", kind: .double, defaultValue: 0.5, min: 0.1, max: 5.0),
        ParamSpec(name: "batteryMinRateWindowS", kind: .int, defaultValue: 1200.0, min: 300.0, max: 7200.0),
        ParamSpec(name: "batteryReserveAfterAlarmS", kind: .int, defaultValue: 900.0, min: 0.0, max: 3600.0),
        ParamSpec(name: "denseEnterS", kind: .int, defaultValue: 900.0, min: 300.0, max: 1800.0),
        ParamSpec(name: "mediumEnterS", kind: .int, defaultValue: 3600.0, min: 1200.0, max: 7200.0),
        ParamSpec(name: "tierHysteresisFactor", kind: .double, defaultValue: 1.25, min: 1.0, max: 2.0),
        ParamSpec(name: "samplingSparseIntervalS", kind: .int, defaultValue: 180.0, min: 60.0, max: 600.0),
        ParamSpec(name: "samplingSparseMinIntervalS", kind: .int, defaultValue: 90.0, min: 60.0, max: 600.0),
        ParamSpec(name: "samplingMediumIntervalS", kind: .int, defaultValue: 30.0, min: 10.0, max: 120.0),
        ParamSpec(name: "samplingMediumMinIntervalS", kind: .int, defaultValue: 15.0, min: 10.0, max: 120.0),
        ParamSpec(name: "samplingDenseIntervalS", kind: .int, defaultValue: 5.0, min: 1.0, max: 15.0),
        ParamSpec(name: "samplingDenseMinIntervalS", kind: .int, defaultValue: 2.0, min: 1.0, max: 15.0),
        ParamSpec(name: "maxSavingIntervalFactor", kind: .int, defaultValue: 2.0, min: 1.0, max: 4.0),
        ParamSpec(name: "fallbackLagS", kind: .int, defaultValue: 30.0, min: 10.0, max: 120.0),
        ParamSpec(name: "fallbackEarlyFrac", kind: .double, defaultValue: 0.25, min: 0.0, max: 0.5),
        ParamSpec(name: "fallbackEarlyMaxS", kind: .int, defaultValue: 3600.0, min: 0.0, max: 7200.0),
        ParamSpec(name: "fallbackHintSpeedFactor", kind: .double, defaultValue: 1.0, min: 0.0, max: 2.0),
        ParamSpec(name: "fallbackNearS", kind: .int, defaultValue: 600.0, min: 120.0, max: 1800.0),
        ParamSpec(name: "fallbackNearSlackS", kind: .int, defaultValue: 60.0, min: 10.0, max: 300.0),
        ParamSpec(name: "fallbackMinLeadS", kind: .int, defaultValue: 10.0, min: 5.0, max: 60.0),
        ParamSpec(name: "fallbackQuietBeforeS", kind: .int, defaultValue: 30.0, min: 30.0, max: 120.0),
        ParamSpec(name: "fallbackMinShiftS", kind: .int, defaultValue: 30.0, min: 10.0, max: 300.0),
        ParamSpec(name: "fallbackMinIntervalS", kind: .int, defaultValue: 60.0, min: 10.0, max: 300.0),
        ParamSpec(name: "fallbackRetryS", kind: .int, defaultValue: 60.0, min: 10.0, max: 300.0),
        ParamSpec(name: "vehicleBusMaxAvgKmh", kind: .int, defaultValue: 30.0, min: 10.0, max: 50.0),
    ]

    static func index(of name: String) -> Int? {
        for i in 0..<PARAM_SPECS.count where PARAM_SPECS[i].name == name { return i }
        return nil
    }
}

/// Result of `parseOverrides`: params, whether the JSON was malformed, and the rejected keys (bad kind/range or reset by
/// G1–G7), in order of appearance; unknown keys are not rejected (T12 §4).
struct ParamsParse: Sendable, Equatable {
    let params: EngineParams
    let malformed: Bool
    let rejected: [String]
}

public enum EngineParamsFactory {
    /// T10 §5: Remote Config `trip_engine_params` → params (invalid keys fall back to defaults).
    public static func fromOverrides(_ json: String?) -> EngineParams { parseOverrides(json).params }

    /// T13 §6.3 / T12 §7.2, verbatim.
    static func parseOverrides(_ json: String?) -> ParamsParse {
        let defaults = EngineParams.defaults
        guard let json, !isBlank(json) else { return ParamsParse(params: defaults, malformed: false, rejected: []) }
        let tree: JsonValue
        do { tree = try MiniJson.parse(json) } catch { return ParamsParse(params: defaults, malformed: true, rejected: []) }
        guard case let .object(pairs) = tree else { return ParamsParse(params: defaults, malformed: true, rejected: []) }
        let specs = ParamTable.PARAM_SPECS
        var p = defaults
        var overridden = [Bool](repeating: false, count: specs.count)
        var rejected: [String] = []
        for (key, v) in pairs {
            guard let i = ParamTable.index(of: key) else { continue }
            let spec = specs[i]
            guard let d = v.asDouble(), d >= spec.min, d <= spec.max else { rejected.append(key); continue }
            switch spec.kind {
            case .int:
                guard d == d.rounded(.down) else { rejected.append(key); continue }
                p.set(at: i, .int(TMath.kotlinToInt(d + 0.0)))
            case .double:
                p.set(at: i, .double(d + 0.0))
            }
            overridden[i] = true
        }
        func idx(_ n: String) -> Int { ParamTable.index(of: n)! }
        // Within a group, rejected keys are listed in JSON order (as T12).
        func jsonOrder(_ n: String) -> Int { pairs.firstIndex { $0.0 == n } ?? Int.max }
        func resetGroup(_ names: [String]) {
            for n in names.sorted(by: { jsonOrder($0) < jsonOrder($1) }) {
                let i = idx(n)
                guard overridden[i] else { continue }
                p.set(at: i, defaults.value(at: i))
                overridden[i] = false
                if !rejected.contains(n) { rejected.append(n) }
            }
        }
        // G1
        if !(p.routeFactorMin <= p.routeFactorPrior && p.routeFactorPrior <= p.routeFactorMax) {
            resetGroup(["routeFactorPrior", "routeFactorMin", "routeFactorMax"])
        }
        // G2
        if !(p.denseEnterS < p.mediumEnterS) { resetGroup(["denseEnterS", "mediumEnterS"]) }
        // G3
        if !(p.maxTripMinS <= p.maxTripCapS) { resetGroup(["maxTripMinS", "maxTripCapS"]) }
        // G4
        if !(p.lowBatteryAlarmPct < p.lowBatteryEarlierPct) { resetGroup(["lowBatteryAlarmPct", "lowBatteryEarlierPct"]) }
        // G5
        if !(p.fallbackQuietBeforeS + 60 <= p.fallbackNearS) { resetGroup(["fallbackQuietBeforeS", "fallbackNearS"]) }
        // G6
        if !(p.samplingSparseMinIntervalS <= p.samplingSparseIntervalS
             && p.samplingMediumMinIntervalS <= p.samplingMediumIntervalS
             && p.samplingDenseMinIntervalS <= p.samplingDenseIntervalS
             && p.samplingDenseIntervalS <= p.samplingMediumIntervalS
             && p.samplingMediumIntervalS <= p.samplingSparseIntervalS) {
            resetGroup(["samplingSparseIntervalS", "samplingSparseMinIntervalS", "samplingMediumIntervalS",
                        "samplingMediumMinIntervalS", "samplingDenseIntervalS", "samplingDenseMinIntervalS"])
        }
        // G7 (after G6)
        if !(p.fallbackLagS > p.samplingDenseIntervalS) { resetGroup(["fallbackLagS"]) }
        return ParamsParse(params: p, malformed: false, rejected: rejected)
    }

    /// Kotlin `CharSequence.isBlank()` on the JVM: `Character.isWhitespace || Character.isSpaceChar`, i.e. U+0009–U+000D,
    /// U+001C–U+001F and the separators Zs/Zl/Zp (incl. U+00A0, U+2007, U+202F). U+0085 is not blank.
    static func isBlank(_ s: String) -> Bool {
        for u in s.unicodeScalars {
            let v = u.value
            if (0x09...0x0D).contains(v) || (0x1C...0x1F).contains(v) { continue }
            switch u.properties.generalCategory {
            case .spaceSeparator, .lineSeparator, .paragraphSeparator: continue
            default: return false
            }
        }
        return true
    }
}
