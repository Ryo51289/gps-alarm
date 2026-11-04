package app.napstop.core.trip

// Generated once from the T10 §5 table (86 parameters after T10.6, table order). PARAM_SPECS is the single source of
// names, types, defaults and ranges; EngineParams fields follow the same order.

/** Engine parameters of T10 §5. Fixed for a trip and stored in the snapshot. */
data class EngineParams(
    val fixMaxAgeS: Int = 60,
    val accAbsMaxM: Double = 100.0,
    val accRelMax: Double = 0.05,
    val accHardMaxM: Double = 2000.0,
    val maxPlausibleSpeedMps: Double = 55.0,
    val outlierResetSpanS: Int = 30,
    val smoothWindowS: Int = 12,
    val stationarySpeedMps: Double = 1.0,
    val motionAccFactor: Double = 1.0,
    val stopExitMinM: Int = 50,
    val speedEmaTauS: Int = 300,
    val shortStopIncludeS: Int = 60,
    val speedEstablishedMovingS: Int = 120,
    val speedEstablishedSamples: Int = 3,
    val maxSpeedSampleGapS: Int = 900,
    val speedSampleMaxAccM: Double = 50.0,
    val routeFactorPrior: Double = 1.2,
    val routeFactorMin: Double = 1.0,
    val routeFactorMax: Double = 2.0,
    val expectedSpeedKmhTrain: Int = 55,
    val expectedSpeedKmhCoach: Int = 60,
    val expectedSpeedKmhBus: Int = 20,
    val expectedSpeedKmhUnknown: Int = 60,
    val etaStopPenaltyS: Int = 20,
    val minSpeedForEtaMps: Double = 0.5,
    val etaUncertaintyFrac: Double = 0.1,
    val distanceModeFactor: Double = 1.0,
    val smartTargetS: Int = 600,
    val smartFloorM: Int = 1000,
    val smartSlowSpeedKmh: Int = 15,
    val smartSlowHysteresisKmh: Int = 2,
    val shortDistanceWarnS: Int = 240,
    val preAlertLeadS: Int = 1800,
    val preAlertDistanceFactor: Int = 5,
    val preAlertMinDistanceM: Int = 3000,
    val preAlertMinGapS: Int = 300,
    val gpsLostMinS: Int = 60,
    val gpsLostIntervalFactor: Int = 3,
    val gpsLostAlarmEtaS: Int = 1200,
    val acquireTimeoutS: Int = 120,
    val lostErrFrac: Double = 0.25,
    val lostSpeedGuardUpdates: Int = 2,
    val gpsLostLongS: Int = 1800,
    val gpsLostLongHintFactor: Double = 1.0,
    val overshootNearMinM: Int = 1000,
    val overshootOpenM: Int = 1000,
    val overshootMinSpeedKmh: Int = 10,
    val passedClosestMinRadiusM: Int = 3000,
    val passedClosestReachFactor: Double = 2.0,
    val passedClosestOpenMinM: Int = 500,
    val passedClosestOpenFrac: Double = 0.5,
    val passedClosestSlowRiseM: Int = 300,
    val arrivedRadiusM: Int = 300,
    val snoozeS: Int = 60,
    val maxSnoozes: Int = 1,
    val alarmMaxActiveS: Int = 3600,
    val maxTripMinS: Int = 14400,
    val maxTripCapS: Int = 172800,
    val lowBatteryAlarmPct: Int = 5,
    val lowBatteryEarlierPct: Int = 15,
    val batteryPriorDrainPctPerH: Double = 2.0,
    val batteryMinRatePctPerH: Double = 0.5,
    val batteryMinRateWindowS: Int = 1200,
    val batteryReserveAfterAlarmS: Int = 900,
    val denseEnterS: Int = 900,
    val mediumEnterS: Int = 3600,
    val tierHysteresisFactor: Double = 1.25,
    val samplingSparseIntervalS: Int = 180,
    val samplingSparseMinIntervalS: Int = 90,
    val samplingMediumIntervalS: Int = 30,
    val samplingMediumMinIntervalS: Int = 15,
    val samplingDenseIntervalS: Int = 5,
    val samplingDenseMinIntervalS: Int = 2,
    val maxSavingIntervalFactor: Int = 2,
    val fallbackLagS: Int = 30,
    val fallbackEarlyFrac: Double = 0.25,
    val fallbackEarlyMaxS: Int = 3600,
    val fallbackHintSpeedFactor: Double = 1.0,
    val fallbackNearS: Int = 600,
    val fallbackNearSlackS: Int = 60,
    val fallbackMinLeadS: Int = 10,
    val fallbackQuietBeforeS: Int = 30,
    val fallbackMinShiftS: Int = 30,
    val fallbackMinIntervalS: Int = 60,
    val fallbackRetryS: Int = 60,
    val vehicleBusMaxAvgKmh: Int = 30,
)

/** One row of the T10 §5 table. [min]/[max] are inclusive. */
internal class ParamSpec(
    val name: String,
    val isInt: Boolean,
    val default: Double,
    val min: Double,
    val max: Double,
    val get: (EngineParams) -> Double,
)

internal val PARAM_SPECS: List<ParamSpec> = listOf(
    ParamSpec("fixMaxAgeS", true, 60.0, 10.0, 300.0, { it.fixMaxAgeS.toDouble() }),
    ParamSpec("accAbsMaxM", false, 100.0, 20.0, 500.0, { it.accAbsMaxM }),
    ParamSpec("accRelMax", false, 0.05, 0.0, 0.2, { it.accRelMax }),
    ParamSpec("accHardMaxM", false, 2000.0, 200.0, 5000.0, { it.accHardMaxM }),
    ParamSpec("maxPlausibleSpeedMps", false, 55.0, 30.0, 100.0, { it.maxPlausibleSpeedMps }),
    ParamSpec("outlierResetSpanS", true, 30.0, 10.0, 300.0, { it.outlierResetSpanS.toDouble() }),
    ParamSpec("smoothWindowS", true, 12.0, 0.0, 60.0, { it.smoothWindowS.toDouble() }),
    ParamSpec("stationarySpeedMps", false, 1.0, 0.3, 3.0, { it.stationarySpeedMps }),
    ParamSpec("motionAccFactor", false, 1.0, 0.5, 3.0, { it.motionAccFactor }),
    ParamSpec("stopExitMinM", true, 50.0, 20.0, 300.0, { it.stopExitMinM.toDouble() }),
    ParamSpec("speedEmaTauS", true, 300.0, 30.0, 1800.0, { it.speedEmaTauS.toDouble() }),
    ParamSpec("shortStopIncludeS", true, 60.0, 0.0, 300.0, { it.shortStopIncludeS.toDouble() }),
    ParamSpec("speedEstablishedMovingS", true, 120.0, 0.0, 600.0, { it.speedEstablishedMovingS.toDouble() }),
    ParamSpec("speedEstablishedSamples", true, 3.0, 1.0, 20.0, { it.speedEstablishedSamples.toDouble() }),
    ParamSpec("maxSpeedSampleGapS", true, 900.0, 60.0, 3600.0, { it.maxSpeedSampleGapS.toDouble() }),
    ParamSpec("speedSampleMaxAccM", false, 50.0, 10.0, 200.0, { it.speedSampleMaxAccM }),
    ParamSpec("routeFactorPrior", false, 1.2, 1.0, 2.0, { it.routeFactorPrior }),
    ParamSpec("routeFactorMin", false, 1.0, 1.0, 1.5, { it.routeFactorMin }),
    ParamSpec("routeFactorMax", false, 2.0, 1.2, 4.0, { it.routeFactorMax }),
    ParamSpec("expectedSpeedKmhTrain", true, 55.0, 5.0, 150.0, { it.expectedSpeedKmhTrain.toDouble() }),
    ParamSpec("expectedSpeedKmhCoach", true, 60.0, 5.0, 150.0, { it.expectedSpeedKmhCoach.toDouble() }),
    ParamSpec("expectedSpeedKmhBus", true, 20.0, 5.0, 150.0, { it.expectedSpeedKmhBus.toDouble() }),
    ParamSpec("expectedSpeedKmhUnknown", true, 60.0, 5.0, 150.0, { it.expectedSpeedKmhUnknown.toDouble() }),
    ParamSpec("etaStopPenaltyS", true, 20.0, 0.0, 120.0, { it.etaStopPenaltyS.toDouble() }),
    ParamSpec("minSpeedForEtaMps", false, 0.5, 0.1, 3.0, { it.minSpeedForEtaMps }),
    ParamSpec("etaUncertaintyFrac", false, 0.1, 0.0, 0.5, { it.etaUncertaintyFrac }),
    ParamSpec("distanceModeFactor", false, 1.0, 1.0, 1.5, { it.distanceModeFactor }),
    ParamSpec("smartTargetS", true, 600.0, 300.0, 1200.0, { it.smartTargetS.toDouble() }),
    ParamSpec("smartFloorM", true, 1000.0, 500.0, 3000.0, { it.smartFloorM.toDouble() }),
    ParamSpec("smartSlowSpeedKmh", true, 15.0, 5.0, 30.0, { it.smartSlowSpeedKmh.toDouble() }),
    ParamSpec("smartSlowHysteresisKmh", true, 2.0, 0.0, 10.0, { it.smartSlowHysteresisKmh.toDouble() }),
    ParamSpec("shortDistanceWarnS", true, 240.0, 60.0, 600.0, { it.shortDistanceWarnS.toDouble() }),
    ParamSpec("preAlertLeadS", true, 1800.0, 600.0, 3600.0, { it.preAlertLeadS.toDouble() }),
    ParamSpec("preAlertDistanceFactor", true, 5.0, 2.0, 10.0, { it.preAlertDistanceFactor.toDouble() }),
    ParamSpec("preAlertMinDistanceM", true, 3000.0, 1000.0, 10000.0, { it.preAlertMinDistanceM.toDouble() }),
    ParamSpec("preAlertMinGapS", true, 300.0, 0.0, 900.0, { it.preAlertMinGapS.toDouble() }),
    ParamSpec("gpsLostMinS", true, 60.0, 20.0, 300.0, { it.gpsLostMinS.toDouble() }),
    ParamSpec("gpsLostIntervalFactor", true, 3.0, 2.0, 5.0, { it.gpsLostIntervalFactor.toDouble() }),
    ParamSpec("gpsLostAlarmEtaS", true, 1200.0, 300.0, 3600.0, { it.gpsLostAlarmEtaS.toDouble() }),
    ParamSpec("acquireTimeoutS", true, 120.0, 30.0, 600.0, { it.acquireTimeoutS.toDouble() }),
    ParamSpec("lostErrFrac", false, 0.25, 0.0, 1.0, { it.lostErrFrac }),
    ParamSpec("lostSpeedGuardUpdates", true, 2.0, 0.0, 5.0, { it.lostSpeedGuardUpdates.toDouble() }),
    ParamSpec("gpsLostLongS", true, 1800.0, 0.0, 21600.0, { it.gpsLostLongS.toDouble() }),
    ParamSpec("gpsLostLongHintFactor", false, 1.0, 0.0, 2.0, { it.gpsLostLongHintFactor }),
    ParamSpec("overshootNearMinM", true, 1000.0, 300.0, 3000.0, { it.overshootNearMinM.toDouble() }),
    ParamSpec("overshootOpenM", true, 1000.0, 300.0, 3000.0, { it.overshootOpenM.toDouble() }),
    ParamSpec("overshootMinSpeedKmh", true, 10.0, 3.0, 30.0, { it.overshootMinSpeedKmh.toDouble() }),
    ParamSpec("passedClosestMinRadiusM", true, 3000.0, 1000.0, 10000.0, { it.passedClosestMinRadiusM.toDouble() }),
    ParamSpec("passedClosestReachFactor", false, 2.0, 1.0, 4.0, { it.passedClosestReachFactor }),
    ParamSpec("passedClosestOpenMinM", true, 500.0, 200.0, 3000.0, { it.passedClosestOpenMinM.toDouble() }),
    ParamSpec("passedClosestOpenFrac", false, 0.5, 0.2, 2.0, { it.passedClosestOpenFrac }),
    ParamSpec("passedClosestSlowRiseM", true, 300.0, 0.0, 3000.0, { it.passedClosestSlowRiseM.toDouble() }),
    ParamSpec("arrivedRadiusM", true, 300.0, 50.0, 1000.0, { it.arrivedRadiusM.toDouble() }),
    ParamSpec("snoozeS", true, 60.0, 30.0, 600.0, { it.snoozeS.toDouble() }),
    ParamSpec("maxSnoozes", true, 1.0, 0.0, 3.0, { it.maxSnoozes.toDouble() }),
    ParamSpec("alarmMaxActiveS", true, 3600.0, 600.0, 14400.0, { it.alarmMaxActiveS.toDouble() }),
    ParamSpec("maxTripMinS", true, 14400.0, 3600.0, 259200.0, { it.maxTripMinS.toDouble() }),
    ParamSpec("maxTripCapS", true, 172800.0, 3600.0, 259200.0, { it.maxTripCapS.toDouble() }),
    ParamSpec("lowBatteryAlarmPct", true, 5.0, 2.0, 20.0, { it.lowBatteryAlarmPct.toDouble() }),
    ParamSpec("lowBatteryEarlierPct", true, 15.0, 5.0, 40.0, { it.lowBatteryEarlierPct.toDouble() }),
    ParamSpec("batteryPriorDrainPctPerH", false, 2.0, 0.5, 10.0, { it.batteryPriorDrainPctPerH }),
    ParamSpec("batteryMinRatePctPerH", false, 0.5, 0.1, 5.0, { it.batteryMinRatePctPerH }),
    ParamSpec("batteryMinRateWindowS", true, 1200.0, 300.0, 7200.0, { it.batteryMinRateWindowS.toDouble() }),
    ParamSpec("batteryReserveAfterAlarmS", true, 900.0, 0.0, 3600.0, { it.batteryReserveAfterAlarmS.toDouble() }),
    ParamSpec("denseEnterS", true, 900.0, 300.0, 1800.0, { it.denseEnterS.toDouble() }),
    ParamSpec("mediumEnterS", true, 3600.0, 1200.0, 7200.0, { it.mediumEnterS.toDouble() }),
    ParamSpec("tierHysteresisFactor", false, 1.25, 1.0, 2.0, { it.tierHysteresisFactor }),
    ParamSpec("samplingSparseIntervalS", true, 180.0, 60.0, 600.0, { it.samplingSparseIntervalS.toDouble() }),
    ParamSpec("samplingSparseMinIntervalS", true, 90.0, 60.0, 600.0, { it.samplingSparseMinIntervalS.toDouble() }),
    ParamSpec("samplingMediumIntervalS", true, 30.0, 10.0, 120.0, { it.samplingMediumIntervalS.toDouble() }),
    ParamSpec("samplingMediumMinIntervalS", true, 15.0, 10.0, 120.0, { it.samplingMediumMinIntervalS.toDouble() }),
    ParamSpec("samplingDenseIntervalS", true, 5.0, 1.0, 15.0, { it.samplingDenseIntervalS.toDouble() }),
    ParamSpec("samplingDenseMinIntervalS", true, 2.0, 1.0, 15.0, { it.samplingDenseMinIntervalS.toDouble() }),
    ParamSpec("maxSavingIntervalFactor", true, 2.0, 1.0, 4.0, { it.maxSavingIntervalFactor.toDouble() }),
    ParamSpec("fallbackLagS", true, 30.0, 10.0, 120.0, { it.fallbackLagS.toDouble() }),
    ParamSpec("fallbackEarlyFrac", false, 0.25, 0.0, 0.5, { it.fallbackEarlyFrac }),
    ParamSpec("fallbackEarlyMaxS", true, 3600.0, 0.0, 7200.0, { it.fallbackEarlyMaxS.toDouble() }),
    ParamSpec("fallbackHintSpeedFactor", false, 1.0, 0.0, 2.0, { it.fallbackHintSpeedFactor }),
    ParamSpec("fallbackNearS", true, 600.0, 120.0, 1800.0, { it.fallbackNearS.toDouble() }),
    ParamSpec("fallbackNearSlackS", true, 60.0, 10.0, 300.0, { it.fallbackNearSlackS.toDouble() }),
    ParamSpec("fallbackMinLeadS", true, 10.0, 5.0, 60.0, { it.fallbackMinLeadS.toDouble() }),
    ParamSpec("fallbackQuietBeforeS", true, 30.0, 30.0, 120.0, { it.fallbackQuietBeforeS.toDouble() }),
    ParamSpec("fallbackMinShiftS", true, 30.0, 10.0, 300.0, { it.fallbackMinShiftS.toDouble() }),
    ParamSpec("fallbackMinIntervalS", true, 60.0, 10.0, 300.0, { it.fallbackMinIntervalS.toDouble() }),
    ParamSpec("fallbackRetryS", true, 60.0, 10.0, 300.0, { it.fallbackRetryS.toDouble() }),
    ParamSpec("vehicleBusMaxAvgKmh", true, 30.0, 10.0, 50.0, { it.vehicleBusMaxAvgKmh.toDouble() }),
)

internal val PARAM_SPEC_BY_NAME: Map<String, ParamSpec> = PARAM_SPECS.associateBy { it.name }

/** Builds params from values by name; missing names take the default. Int values must be integral. */
internal fun engineParamsOf(values: Map<String, Double>): EngineParams {
    fun i(n: String): Int = (values[n] ?: PARAM_SPEC_BY_NAME.getValue(n).default).toInt()
    fun d(n: String): Double = values[n] ?: PARAM_SPEC_BY_NAME.getValue(n).default
    return EngineParams(
        fixMaxAgeS = i("fixMaxAgeS"),
        accAbsMaxM = d("accAbsMaxM"),
        accRelMax = d("accRelMax"),
        accHardMaxM = d("accHardMaxM"),
        maxPlausibleSpeedMps = d("maxPlausibleSpeedMps"),
        outlierResetSpanS = i("outlierResetSpanS"),
        smoothWindowS = i("smoothWindowS"),
        stationarySpeedMps = d("stationarySpeedMps"),
        motionAccFactor = d("motionAccFactor"),
        stopExitMinM = i("stopExitMinM"),
        speedEmaTauS = i("speedEmaTauS"),
        shortStopIncludeS = i("shortStopIncludeS"),
        speedEstablishedMovingS = i("speedEstablishedMovingS"),
        speedEstablishedSamples = i("speedEstablishedSamples"),
        maxSpeedSampleGapS = i("maxSpeedSampleGapS"),
        speedSampleMaxAccM = d("speedSampleMaxAccM"),
        routeFactorPrior = d("routeFactorPrior"),
        routeFactorMin = d("routeFactorMin"),
        routeFactorMax = d("routeFactorMax"),
        expectedSpeedKmhTrain = i("expectedSpeedKmhTrain"),
        expectedSpeedKmhCoach = i("expectedSpeedKmhCoach"),
        expectedSpeedKmhBus = i("expectedSpeedKmhBus"),
        expectedSpeedKmhUnknown = i("expectedSpeedKmhUnknown"),
        etaStopPenaltyS = i("etaStopPenaltyS"),
        minSpeedForEtaMps = d("minSpeedForEtaMps"),
        etaUncertaintyFrac = d("etaUncertaintyFrac"),
        distanceModeFactor = d("distanceModeFactor"),
        smartTargetS = i("smartTargetS"),
        smartFloorM = i("smartFloorM"),
        smartSlowSpeedKmh = i("smartSlowSpeedKmh"),
        smartSlowHysteresisKmh = i("smartSlowHysteresisKmh"),
        shortDistanceWarnS = i("shortDistanceWarnS"),
        preAlertLeadS = i("preAlertLeadS"),
        preAlertDistanceFactor = i("preAlertDistanceFactor"),
        preAlertMinDistanceM = i("preAlertMinDistanceM"),
        preAlertMinGapS = i("preAlertMinGapS"),
        gpsLostMinS = i("gpsLostMinS"),
        gpsLostIntervalFactor = i("gpsLostIntervalFactor"),
        gpsLostAlarmEtaS = i("gpsLostAlarmEtaS"),
        acquireTimeoutS = i("acquireTimeoutS"),
        lostErrFrac = d("lostErrFrac"),
        lostSpeedGuardUpdates = i("lostSpeedGuardUpdates"),
        gpsLostLongS = i("gpsLostLongS"),
        gpsLostLongHintFactor = d("gpsLostLongHintFactor"),
        overshootNearMinM = i("overshootNearMinM"),
        overshootOpenM = i("overshootOpenM"),
        overshootMinSpeedKmh = i("overshootMinSpeedKmh"),
        passedClosestMinRadiusM = i("passedClosestMinRadiusM"),
        passedClosestReachFactor = d("passedClosestReachFactor"),
        passedClosestOpenMinM = i("passedClosestOpenMinM"),
        passedClosestOpenFrac = d("passedClosestOpenFrac"),
        passedClosestSlowRiseM = i("passedClosestSlowRiseM"),
        arrivedRadiusM = i("arrivedRadiusM"),
        snoozeS = i("snoozeS"),
        maxSnoozes = i("maxSnoozes"),
        alarmMaxActiveS = i("alarmMaxActiveS"),
        maxTripMinS = i("maxTripMinS"),
        maxTripCapS = i("maxTripCapS"),
        lowBatteryAlarmPct = i("lowBatteryAlarmPct"),
        lowBatteryEarlierPct = i("lowBatteryEarlierPct"),
        batteryPriorDrainPctPerH = d("batteryPriorDrainPctPerH"),
        batteryMinRatePctPerH = d("batteryMinRatePctPerH"),
        batteryMinRateWindowS = i("batteryMinRateWindowS"),
        batteryReserveAfterAlarmS = i("batteryReserveAfterAlarmS"),
        denseEnterS = i("denseEnterS"),
        mediumEnterS = i("mediumEnterS"),
        tierHysteresisFactor = d("tierHysteresisFactor"),
        samplingSparseIntervalS = i("samplingSparseIntervalS"),
        samplingSparseMinIntervalS = i("samplingSparseMinIntervalS"),
        samplingMediumIntervalS = i("samplingMediumIntervalS"),
        samplingMediumMinIntervalS = i("samplingMediumMinIntervalS"),
        samplingDenseIntervalS = i("samplingDenseIntervalS"),
        samplingDenseMinIntervalS = i("samplingDenseMinIntervalS"),
        maxSavingIntervalFactor = i("maxSavingIntervalFactor"),
        fallbackLagS = i("fallbackLagS"),
        fallbackEarlyFrac = d("fallbackEarlyFrac"),
        fallbackEarlyMaxS = i("fallbackEarlyMaxS"),
        fallbackHintSpeedFactor = d("fallbackHintSpeedFactor"),
        fallbackNearS = i("fallbackNearS"),
        fallbackNearSlackS = i("fallbackNearSlackS"),
        fallbackMinLeadS = i("fallbackMinLeadS"),
        fallbackQuietBeforeS = i("fallbackQuietBeforeS"),
        fallbackMinShiftS = i("fallbackMinShiftS"),
        fallbackMinIntervalS = i("fallbackMinIntervalS"),
        fallbackRetryS = i("fallbackRetryS"),
        vehicleBusMaxAvgKmh = i("vehicleBusMaxAvgKmh"),
    )
}

/** Result of parsing Remote Config `trip_engine_params` (T12 §7.2). */
internal data class ParamsParse(val params: EngineParams, val malformed: Boolean, val rejected: List<String>)

/** Cross-field groups G1–G6 of T10 §5 (G7 is applied after them). */
private val CROSS_GROUPS: List<Pair<List<String>, (Map<String, Double>) -> Boolean>> = listOf(
    listOf("routeFactorMin", "routeFactorPrior", "routeFactorMax") to { v ->
        v.getValue("routeFactorMin") <= v.getValue("routeFactorPrior") &&
            v.getValue("routeFactorPrior") <= v.getValue("routeFactorMax")
    },
    listOf("denseEnterS", "mediumEnterS") to { v -> v.getValue("denseEnterS") < v.getValue("mediumEnterS") },
    listOf("maxTripMinS", "maxTripCapS") to { v -> v.getValue("maxTripMinS") <= v.getValue("maxTripCapS") },
    listOf("lowBatteryAlarmPct", "lowBatteryEarlierPct") to { v ->
        v.getValue("lowBatteryAlarmPct") < v.getValue("lowBatteryEarlierPct")
    },
    listOf("fallbackQuietBeforeS", "fallbackNearS") to { v ->
        v.getValue("fallbackQuietBeforeS") + 60.0 <= v.getValue("fallbackNearS")
    },
    listOf(
        "samplingSparseIntervalS", "samplingSparseMinIntervalS", "samplingMediumIntervalS",
        "samplingMediumMinIntervalS", "samplingDenseIntervalS", "samplingDenseMinIntervalS",
    ) to { v ->
        v.getValue("samplingSparseMinIntervalS") <= v.getValue("samplingSparseIntervalS") &&
            v.getValue("samplingMediumMinIntervalS") <= v.getValue("samplingMediumIntervalS") &&
            v.getValue("samplingDenseMinIntervalS") <= v.getValue("samplingDenseIntervalS") &&
            v.getValue("samplingDenseIntervalS") <= v.getValue("samplingMediumIntervalS") &&
            v.getValue("samplingMediumIntervalS") <= v.getValue("samplingSparseIntervalS")
    },
)

object EngineParamsFactory {
    /** Remote Config JSON → params; invalid keys fall back to defaults (T10 §5). Never throws, never logs values. */
    fun fromOverrides(json: String?): EngineParams = parseOverrides(json).params

    internal fun parseOverrides(json: String?): ParamsParse {
        if (json == null || json.isBlank()) return ParamsParse(EngineParams(), false, emptyList())
        val tree = try {
            MiniJson.parse(json)
        } catch (_: JsonParseException) {
            return ParamsParse(EngineParams(), true, emptyList())
        }
        if (tree !is JObject) return ParamsParse(EngineParams(), true, emptyList())

        val overrides = LinkedHashMap<String, Double>()
        val rejected = ArrayList<String>()
        for ((key, v) in tree.fields) {
            val spec = PARAM_SPEC_BY_NAME[key] ?: continue
            val d = if (v is JNumber) v.asDouble() else Double.NaN
            val ok = d.isFinite() && (!spec.isInt || d == kotlin.math.floor(d)) && d >= spec.min && d <= spec.max
            if (ok) overrides[key] = d + 0.0 else rejected += key
        }
        val keyOrder = tree.fields.keys.toList()

        fun effective(): Map<String, Double> {
            val m = LinkedHashMap<String, Double>()
            for (s in PARAM_SPECS) m[s.name] = overrides[s.name] ?: s.default
            return m
        }

        fun dropGroup(names: List<String>) {
            for (k in keyOrder) {
                if (k in names && overrides.containsKey(k)) {
                    overrides.remove(k)
                    rejected += k
                }
            }
        }

        for ((names, holds) in CROSS_GROUPS) {
            if (!holds(effective())) dropGroup(names)
        }
        val eff = effective()
        if (!(eff.getValue("fallbackLagS") > eff.getValue("samplingDenseIntervalS"))) dropGroup(listOf("fallbackLagS"))
        return ParamsParse(engineParamsOf(overrides), false, rejected)
    }
}
