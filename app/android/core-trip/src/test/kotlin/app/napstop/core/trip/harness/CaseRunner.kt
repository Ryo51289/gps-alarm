package app.napstop.core.trip.harness

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmMode
import app.napstop.core.trip.AlarmSilenced
import app.napstop.core.trip.AvailabilityCause
import app.napstop.core.trip.BatterySample
import app.napstop.core.trip.EngineInput
import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.EngineParamsFactory
import app.napstop.core.trip.EngineState
import app.napstop.core.trip.FallbackRestoreStatus
import app.napstop.core.trip.JObject
import app.napstop.core.trip.JsonValue
import app.napstop.core.trip.LocationAvailability
import app.napstop.core.trip.LocationFix
import app.napstop.core.trip.MiniJson
import app.napstop.core.trip.RestoreInfo
import app.napstop.core.trip.SamplingTier
import app.napstop.core.trip.Step
import app.napstop.core.trip.Tick
import app.napstop.core.trip.TripConfig
import app.napstop.core.trip.TripEngine
import app.napstop.core.trip.TripEvent
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.TripView
import app.napstop.core.trip.UserAction
import app.napstop.core.trip.UserActionKind
import app.napstop.core.trip.VehicleKind

/** One recorded Step (or the KILL marker). [inJson] is the P05 `in` array with relative times. */
internal class StepRecord(
    val t: Int,
    val input: EngineInput?,
    val inJson: String,
    val events: List<TripEvent>,
    val view: TripView?,
    val restoreInfo: RestoreInfo? = null,
    val diag: String? = null,
)

internal class RunOpts(
    val timeShiftMs: Long = 0,
    /** Extra params merged over case.config.params (TR36 / TR37 negative runs). */
    val paramOverrides: Map<String, JsonValue> = emptyMap(),
    /** Ticks after which a resumable fork is captured (I8). */
    val captureAt: Set<Int> = emptySet(),
)

/** Identity of one run: `<traceId>/<caseId>/<mode>`, mode = all | policy | policy-jNN. */
internal data class RunKey(val traceId: String, val caseId: String, val mode: String, val policy: Boolean, val j: Int) {
    val run: String get() = "$traceId/$caseId/$mode"
}

internal class RunResult(
    val key: RunKey,
    val startMs: Long,
    val params: EngineParams,
    val records: List<StepRecord>,
    val fbOsAfterTick: Array<Long?>,
    val predAfterTick: Array<Long?>,
    val firstAlarmT: Int?,
    val firstEventT: Map<String, Int>,
    val relaunchT: Int?,
    val osFallbackFiredT: Int?,
    val killT: Int?,
    val violations: List<String>,
    val forks: Map<Int, CaseRun>,
)

internal fun eventName(e: TripEvent): String = when (e) {
    is app.napstop.core.trip.PreAlert -> "preAlert"
    is Alarm -> "alarm"
    is app.napstop.core.trip.Snoozed -> "snoozed"
    is app.napstop.core.trip.GpsLost -> "gpsLost"
    is app.napstop.core.trip.GpsRecovered -> "gpsRecovered"
    is app.napstop.core.trip.LowBatteryRisk -> "lowBatteryRisk"
    is app.napstop.core.trip.Overshoot -> "overshoot"
    is app.napstop.core.trip.Arrived -> "arrived"
    is app.napstop.core.trip.FallbackAlarmChanged -> "fallbackAlarmChanged"
    is app.napstop.core.trip.SamplingPolicyChanged -> "samplingPolicyChanged"
    is app.napstop.core.trip.TripEnded -> "tripEnded"
}

/** Builds TripConfig and params for a case (T12 §8.2). Rejected params are a configuration error. */
internal fun caseSetup(trace: TraceModel, case: CaseModel, overrides: Map<String, JsonValue>): Pair<TripConfig, EngineParams> {
    val c = case.config
    val mode = when (c.mode) {
        "distance" -> AlarmMode.DISTANCE
        "time" -> AlarmMode.TIME
        "smart" -> AlarmMode.SMART
        else -> throw ConfigError("unknown mode ${c.mode}")
    }
    val hint = when (c.vehicleHint ?: trace.vehicle) {
        "train" -> VehicleKind.TRAIN
        "coach" -> VehicleKind.COACH
        "bus" -> VehicleKind.BUS
        "unknown" -> VehicleKind.UNKNOWN
        else -> throw ConfigError("unknown vehicle")
    }
    val cfg = TripConfig("${trace.id}/${case.id}", trace.destLat, trace.destLng, mode, c.thresholdM, c.thresholdMin, c.preAlert, hint)
    val merged = LinkedHashMap<String, JsonValue>()
    c.params?.fields?.let { merged.putAll(it) }
    merged.putAll(overrides)
    val parse = EngineParamsFactory.parseOverrides(MiniJson.write(JObject(merged)))
    if (parse.malformed || parse.rejected.isNotEmpty()) throw ConfigError("params rejected: ${parse.rejected}")
    return cfg to parse.params
}

/** Harness tick loop of T12 §8.3 (+ README §6). Mutable; [fork] copies all harness state for I8. */
internal class CaseRun private constructor(
    val trace: TraceModel,
    val case: CaseModel,
    val key: RunKey,
    val opts: RunOpts,
    val cfg: TripConfig,
    val params: EngineParams,
) {
    val startMs = trace.startMs + opts.timeShiftMs
    private val iS = trace.intervalS
    private val ticks = trace.durationS / iS + 1
    private val gpx = trace.gpx

    lateinit var state: EngineState
    private lateinit var lastView: TripView
    private var alive = true
    private var lastDelivered: Int? = null
    private var sparseShifted = false
    private var locBlocked = false
    var os = OsSim(case.config.osSim, case.config.osRingMaxS, case.config.osDismissOffsetS)
    private var killSnapshot: EngineState? = null
    private var relaunchT: Int? = null
    private val firstEventT = LinkedHashMap<String, Int>()
    private var firstAlarmT: Int? = null
    private var actionDone = BooleanArray(case.config.actions.size)
    val records = ArrayList<StepRecord>()
    private val violations = ArrayList<String>()
    private var fbOsAfterTick = arrayOfNulls<Long>(ticks)
    private var predAfterTick = arrayOfNulls<Long>(ticks)
    private val forks = LinkedHashMap<Int, CaseRun>()
    private val queue = ArrayDeque<EngineInput>()

    companion object {
        fun create(trace: TraceModel, case: CaseModel, key: RunKey, opts: RunOpts = RunOpts()): CaseRun {
            val (cfg, params) = caseSetup(trace, case, opts.paramOverrides)
            if (key.policy && case.policyPhaseSweep) {
                if (params.samplingSparseIntervalS % trace.intervalS != 0) throw ConfigError("samplingSparseIntervalS not a multiple of I")
                if (case.config.actions.any { it.action == "batteryMaxSaving" }) throw ConfigError("policyPhaseSweep with batteryMaxSaving")
                if (case.samplingModes == listOf("all")) throw ConfigError("policyPhaseSweep with samplingModes [all]")
            }
            return CaseRun(trace, case, key, opts, cfg, params)
        }

        /** Full run of one key. */
        fun run(trace: TraceModel, case: CaseModel, key: RunKey, opts: RunOpts = RunOpts()): RunResult {
            val r = create(trace, case, key, opts)
            r.begin()
            r.loop(0)
            return r.result()
        }
    }

    private fun where(t: Int) = "${key.run} t=$t j=${key.j}"

    fun begin() {
        val step = TripEngine.start(cfg, params, startMs)
        state = step.state
        lastView = step.view
        record(0, null, "[\"START\"]", step)
        drainFrom(0, step)
    }

    fun loop(fromT: Int) {
        var t = fromT
        while (t <= trace.durationS) {
            tick(t)
            fbOsAfterTick[t / iS] = os.fbOs
            predAfterTick[t / iS] = lastView.predictedAlarmAtMs
            if (t in opts.captureAt) forks[t] = fork()
            t += iS
        }
        val rel = case.config.relaunch
        if (rel != null && relaunchT == null) throw ConfigError("relaunch never happened (${where(t)})")
        for ((i, a) in case.config.actions.withIndex()) {
            if (!actionDone[i]) throw ConfigError("action ${a.action} never ran (${key.run} j=${key.j})")
        }
    }

    fun result(): RunResult = RunResult(
        key, startMs, params, records, fbOsAfterTick, predAfterTick, firstAlarmT, firstEventT, relaunchT,
        os.osFallbackFiredT, case.config.kill?.t, violations, forks,
    )

    /** Copy of the harness state at the end of the current tick (records empty). */
    fun fork(): CaseRun {
        val f = CaseRun(trace, case, key, opts, cfg, params)
        f.state = state
        f.lastView = lastView
        f.alive = alive
        f.lastDelivered = lastDelivered
        f.sparseShifted = sparseShifted
        f.locBlocked = locBlocked
        f.os = os.copy()
        f.killSnapshot = killSnapshot
        f.relaunchT = relaunchT
        f.firstEventT.putAll(firstEventT)
        f.firstAlarmT = firstAlarmT
        f.actionDone = actionDone.copyOf()
        f.fbOsAfterTick = fbOsAfterTick.copyOf()
        f.predAfterTick = predAfterTick.copyOf()
        return f
    }

    fun isAlive(): Boolean = alive

    /** I8: replace the engine state by restore(decode(encode(state)), now = t, PENDING); returns that Step. */
    fun restorePendingAt(t: Int): Step {
        val st = TripEngine.decodeSnapshot(TripEngine.encodeSnapshot(state))
        val step = TripEngine.restore(st, startMs + 1000L * t, RestoreInfo(FallbackRestoreStatus.PENDING))
        state = step.state
        lastView = step.view
        return step
    }

    /** Tick B of an `At` (null while a runtime anchor is unresolved). */
    private fun atT(a: At): Int? = Anchors.resolve(a, firstEventT, relaunchT, os.osFallbackFiredT, case.config.kill?.t)

    private fun tick(t: Int) {
        val nowMs = startMs + 1000L * t
        val kill = case.config.kill
        if (kill != null && t == kill.t) {
            killSnapshot = state
            alive = false
            os.onKill()
            records += StepRecord(t, null, "[\"KILL\"]", emptyList(), null)
        }
        val rel = case.config.relaunch
        if (rel != null && relaunchT == null && !alive) {
            val b = atT(rel.at)
            if (b != null) {
                if (rel.at.anchor?.startsWith("event:") == true && kill?.t != null && b <= kill.t!!) {
                    throw ConfigError("relaunch event anchor B <= kill (${where(t)})")
                }
                if (b > trace.durationS) throw ConfigError("relaunch B > durationS")
                if (b == t) relaunch(t, nowMs, rel)
            }
        }
        for (x in os.tick(t, nowMs, alive)) feed(t, x)
        val actions = case.config.actions
        if (!alive) {
            for ((i, a) in actions.withIndex()) {
                if (!actionDone[i] && atT(a.at) == t) throw ConfigError("action ${a.action} while the engine is dead (${where(t)})")
            }
            return
        }
        for ((i, a) in actions.withIndex()) {
            if (actionDone[i]) continue
            val b = atT(a.at) ?: continue
            if (b > trace.durationS) throw ConfigError("action B > durationS")
            if (b != t) continue
            actionDone[i] = true
            feed(t, mapAction(a.action, nowMs))
        }
        for (b in case.config.battery) if (b.t == t) feed(t, BatterySample(nowMs, b.levelPct, b.charging))
        val sample = gpx.at(t)
        if (sample != null && !locBlocked && allow(t)) {
            lastDelivered = t
            feed(t, LocationFix(nowMs, nowMs, sample.lat, sample.lng, sample.accuracyM, sample.speedMps), sample.index)
        } else {
            feed(t, Tick(nowMs))
        }
    }

    private fun allow(t: Int): Boolean {
        if (!key.policy) return true
        val last = lastDelivered ?: return true
        val p = lastView.samplingPolicy ?: return true
        val shift = if (key.j > 0 && !sparseShifted && p.tier == SamplingTier.SPARSE) key.j * iS else 0
        val need = p.intervalS + shift
        val ok = t - last >= need
        if (ok && need > p.intervalS) sparseShifted = true
        return ok
    }

    private fun mapAction(a: String, nowMs: Long): EngineInput = when (a) {
        "dismiss" -> UserAction(nowMs, UserActionKind.DISMISS)
        "snooze" -> UserAction(nowMs, UserActionKind.SNOOZE)
        "stop" -> UserAction(nowMs, UserActionKind.STOP_TRIP)
        "batteryMaxSaving" -> UserAction(nowMs, UserActionKind.BATTERY_MAX_SAVING)
        "batteryAlarmAt5" -> UserAction(nowMs, UserActionKind.BATTERY_ALARM_AT_5)
        "batteryAlarmEarlier" -> UserAction(nowMs, UserActionKind.BATTERY_ALARM_EARLIER)
        "locationOff" -> {
            locBlocked = true
            LocationAvailability(nowMs, AvailabilityCause.SERVICES_OFF)
        }
        "permissionRevoked" -> {
            locBlocked = true
            LocationAvailability(nowMs, AvailabilityCause.PERMISSION_REVOKED)
        }
        "locationOn" -> {
            locBlocked = false
            LocationAvailability(nowMs, AvailabilityCause.AVAILABLE)
        }
        else -> throw ConfigError("unknown action $a")
    }

    private fun relaunch(t: Int, nowMs: Long, rel: RelaunchSpec) {
        val off = case.config.osDismissOffsetS
        if (off != null) {
            val fired = os.osFallbackFiredT
            if (fired == null || fired + off >= t) throw ConfigError("osDismiss not before relaunch (${where(t)})")
        }
        if (rel.status == "MISSING") os.dropForMissing()
        val firedBefore = os.osFallbackFiredT?.let { it < t } ?: false
        val firedAt = if (firedBefore) os.osFallbackFiredAtMs else null
        val info = if (rel.status == "auto") {
            if (!firedBefore) {
                RestoreInfo(FallbackRestoreStatus.PENDING)
            } else if (os.osDismissedAtMs != null) {
                RestoreInfo(FallbackRestoreStatus.DISMISSED, firedAt, os.osDismissedAtMs)
            } else {
                RestoreInfo(FallbackRestoreStatus.RANG, firedAt)
            }
        } else {
            val st = FallbackRestoreStatus.valueOf(rel.status)
            RestoreInfo(st, firedAt, if (st == FallbackRestoreStatus.DISMISSED) os.osDismissedAtMs else null)
        }
        val snap = TripEngine.decodeSnapshot(TripEngine.encodeSnapshot(killSnapshot!!))
        val step = TripEngine.restore(snap, nowMs, info)
        alive = true
        relaunchT = t
        state = step.state
        lastView = step.view
        val inJson = "[\"RESTORE\",${nowMs - startMs},\"${info.status.name}\",${relMs(info.firedAtMs)},${relMs(info.dismissedAtMs)}]"
        record(t, null, inJson, step, info)
        drainFrom(t, step)
        if ((state.phase == TripPhase.ALARMING || state.phase == TripPhase.OVERSHOT) && os.enabled && os.ringing == Ringing.NONE) {
            feed(t, AlarmSilenced(nowMs, nowMs))
        }
    }

    private fun relMs(ms: Long?): String = ms?.let { (it - startMs).toString() } ?: "null"

    private fun feed(t: Int, x: EngineInput, sampleIndex: Int = -1) {
        if (x is UserAction && (x.action == UserActionKind.DISMISS || x.action == UserActionKind.STOP_TRIP)) os.onUserDismissOrStop()
        if (state.phase == TripPhase.ENDED) return // reduce is a no-op on ENDED; not recorded (§8.3)
        val step = TripEngine.reduce(state, x)
        state = step.state
        lastView = step.view
        record(t, x, Transcript.encodeInput(x, startMs, sampleIndex), step)
        drainFrom(t, step)
    }

    /** React to [first], then process queued OS inputs FIFO; P07(ii) once the queue is empty. */
    private fun drainFrom(t: Int, first: Step) {
        var ringNowSeen = first.events.any { it is Alarm && it.ringNow }
        os.react(first, queue, violations, where(t))
        while (queue.isNotEmpty()) {
            val x = queue.removeFirst()
            if (state.phase == TripPhase.ENDED) continue
            val step = TripEngine.reduce(state, x)
            state = step.state
            lastView = step.view
            record(t, x, Transcript.encodeInput(x, startMs, -1), step)
            if (step.events.any { it is Alarm && it.ringNow }) ringNowSeen = true
            os.react(step, queue, violations, where(t))
        }
        if (ringNowSeen && os.enabled && os.ringing == Ringing.NONE) violations += "P07(ii) no alarm sounding after Alarm(ringNow=true) at ${where(t)}"
    }

    private fun record(t: Int, x: EngineInput?, inJson: String, step: Step, info: RestoreInfo? = null) {
        records += StepRecord(t, x, inJson, step.events, step.view, info, if (Transcript.diagEnabled) Transcript.diag(step) else null)
        Checks.finiteStateViolation(step.state)?.let { violations += "$it at ${where(t)}" }
        for (e in step.events) {
            val n = eventName(e)
            if (!firstEventT.containsKey(n)) firstEventT[n] = t
            if (e is Alarm && firstAlarmT == null) firstAlarmT = t
        }
    }
}
