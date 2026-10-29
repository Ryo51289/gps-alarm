package app.napstop.probe.analysis

import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.max
import kotlin.math.min

enum class Verdict { PASS, WARN, FAIL }

/**
 * A gap between consecutive location marks (S1 §4.5, §5.8); [startWallMs] is epoch ms (wall clock, survives reboots).
 * [level] comes from the phase thresholds only; the cause annotations never change it (R2-3).
 */
data class Gap(
    val startWallMs: Long,
    val lengthS: Long,
    val phase: String,
    val level: Verdict,
    val serviceAlive: Boolean,
    val locUnavailable: Boolean,
    val powerSaveOn: Boolean,
    val excluded: Boolean,
)

/** One process death (S1 §4.5, §5.8). [phase]: "sparse"/"dense"/"alarm" (after the planned end), by the planned boundary. */
data class ExitDetail(
    val exitWallMs: Long,
    val offsetS: Long,
    val phase: String,
    val reason: Int,
    val reasonName: String,
    val desc: String?,
    val restartS: Long?,
    val restartSrc: String?,
    val recoveryS: Long?,
    val causedByReinstall: Boolean,
)

/** S2 §5.5. [ringSUpperBound]: ringS came from the next proc_start / last event of the ringing pid ("≤"). */
data class AlarmSummary(
    val plannedWall: String,
    val triggeredWall: String?,
    val lateS: Long?,
    val src: String?,
    val soundOk: Boolean,
    val focus: String?,
    val alarmVol: Int?,
    val alarmVolMax: Int?,
    val vibrateOk: Boolean,
    val notifPosted: Boolean,
    val notifVisible: Boolean,
    val fsiAllowed: Boolean?,
    val uiShown: Boolean,
    val uiOnLockscreen: Boolean?,
    val dismissedBy: String?,
    val dismissAfterS: Long?,
    val interrupted: Boolean,
    val ringS: Long?,
    val ringSUpperBound: Boolean,
    val zen: Int?,
    val ringer: Int?,
    val errors: List<String>,
)

/**
 * S1 §5.8. Additions to the designed signature (needed by [RunAnalyzer.render]): [device], [scenario], [delayMin],
 * [startWallMs].
 */
data class RunSummary(
    val runId: String,
    val kind: String,
    val label: String,
    val device: String,
    val scenario: String?,
    val delayMin: Long?,
    val startWallMs: Long,
    val plannedDurationS: Long,
    val actualDurationS: Long,
    val stoppedBy: String?,
    val stoppedEarly: Boolean,
    val fixCount: Map<String, Int>,
    val fixGapMaxS: Map<String, Long>,
    val gapsOverPass: List<Gap>,
    val phaseBoundaryWallMs: Long?,
    val phaseSwitchWallMs: Long?,
    val phaseSwitchDelayS: Long?,
    val phaseSwitchVia: String?,
    val phaseSwitchMissing: Boolean,
    val aliveS: Long?,
    val procStarts: Int,
    val exits: List<ExitDetail>,
    val restartsBySrc: Map<String, Int>,
    val maxRecoveryS: Long?,
    val fgFails: Int,
    val batteryStart: Int?,
    val batteryEnd: Int?,
    val batteryPerHour: Double?,
    val chargedDuringRun: Boolean,
    val invalidRun: Boolean,
    val invalidSinceWallMs: Long?,
    val countsForGo: Boolean,
    val stillRunning: Boolean,
    val alarm: AlarmSummary?,
    val verdict: Verdict,
    val reasons: List<String>,
)

object Thresholds {
    const val SPARSE_PASS_S = 420L
    const val SPARSE_WARN_S = 900L
    const val DENSE_PASS_S = 60L
    const val DENSE_WARN_S = 180L
    const val RECOVERY_PASS_S = 300L
    const val RECOVERY_WARN_S = 900L
    const val PHASE_SWITCH_PASS_S = 60L
    const val EARLY_STOP_TOLERANCE_S = 60L
    const val ALARM_INTERRUPT_FAIL_S = 60L
    const val ALARM_PENDING_GRACE_S = 120L
    const val REINSTALL_EXIT_WINDOW_S = 120L

    /** S2 §5.5: alarm PASS needs lateS <= this. */
    const val ALARM_LATE_PASS_S = 30L
}

object RunAnalyzer {
    const val SPARSE = "sparse"
    const val DENSE = "dense"
    const val ALARM_PHASE = "alarm"
    const val KIND_S1 = "S1"
    const val KIND_S2 = "S2"

    /** First line of the conclusion of an invalid (non-FAIL) A/B run (S1 §4.5). */
    const val INVALID_HEADER = "LƯỢT KHÔNG HỢP LỆ — chạy lại: "

    private val VALID_STOPS = setOf("user", "auto", "alarm_dismissed", "alarm_timeout")
    private val AB_LABELS = setOf("A", "B")
    private val LIVE_EVENTS = setOf("loc_avail", "screen", "idle", "power_save", "battery", "fix_stall")
    private val VI = Locale.forLanguageTag("vi-VN")
    private val HMS: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm:ss")

    /** Collects reasons by severity; the verdict is the worst non-empty bucket. */
    private class Findings {
        val fail = ArrayList<String>()
        val warn = ArrayList<String>()
        val info = ArrayList<String>()

        fun add(level: Verdict, reason: String) {
            when (level) {
                Verdict.FAIL -> fail += reason
                Verdict.WARN -> warn += reason
                Verdict.PASS -> info += reason
            }
        }

        fun verdict(): Verdict = when {
            fail.isNotEmpty() -> Verdict.FAIL
            warn.isNotEmpty() -> Verdict.WARN
            else -> Verdict.PASS
        }
    }

    /**
     * @param nowMs wall clock at analysis time (tests pass it in).
     * @param active this run is the active run in RunStore (S1 §5.8 "Đang chạy và báo thức").
     */
    fun analyze(events: List<ProbeEvent>, nowMs: Long, active: Boolean): RunSummary {
        val sorted = events.sortedWith(compareBy<ProbeEvent>({ it.wallMs }, { it.seq }))
        val start = sorted.firstOrNull { it.ev == "run_start" } ?: return noRunStart(sorted)

        val startMs = start.wallMs
        val stop = sorted.firstOrNull { it.ev == "run_stop" && it.wallMs >= startMs }
        val endMs = stop?.wallMs ?: sorted.last().wallMs
        // Everything except exit_info is limited to t <= runEnd (S1 §4.5 "Phạm vi sự kiện").
        val inRun = sorted.filter { it.wallMs in startMs..endMs }
        // R2-1: exit_info is scanned asynchronously, its line may come after run_stop: whole file, filtered by exitTs.
        val exitInfos = sorted.filter { it.ev == "exit_info" && it.long("exitTs") != null }

        val kind = start.str("kind") ?: KIND_S1
        val label = start.str("label") ?: ""
        val isAB = kind == KIND_S1 && label in AB_LABELS
        val durationMin = max(0L, start.long("durationMin") ?: 0L)
        val denseMin = (start.long("densePhaseMin") ?: 0L).coerceIn(0L, durationMin)
        val plannedEndMs = startMs + durationMin * 60_000L
        val boundaryMs: Long? = if (denseMin < durationMin) plannedEndMs - denseMin * 60_000L else null
        val stoppedBy = stop?.str("by")

        // R2-8: still running only while the alarm (if any) is not overdue.
        val alarmApplies = kind == KIND_S2 || start.bool("alarmAtEnd") == true
        val alarmDueMs: Long? = when {
            kind == KIND_S2 -> startMs + (start.long("delayMin") ?: durationMin) * 60_000L
            alarmApplies -> plannedEndMs
            else -> null
        }
        val stillRunning = active && (alarmDueMs == null || nowMs < alarmDueMs + Thresholds.ALARM_PENDING_GRACE_S * 1000L)

        val loc = Findings()
        fun offset(wallMs: Long) = "+" + fmtHms((wallMs - startMs) / 1000L)

        // ---- phase switch (R2-5, R2-6, R2-7) ----
        val switch = sorted.firstOrNull { it.ev == "phase_switch" && it.str("to") == DENSE }
        val switchDelayS = if (boundaryMs != null && switch != null) max(0L, (switch.wallMs - boundaryMs) / 1000L) else null
        val switchMissing = boundaryMs != null && endMs > boundaryMs && switch == null
        val denseStartMs = when {
            boundaryMs == null -> startMs
            switch == null || switch.str("via") == VIA_START -> boundaryMs
            else -> max(switch.wallMs, boundaryMs)
        }
        if (switchDelayS != null && switchDelayS > Thresholds.PHASE_SWITCH_PASS_S) {
            loc.warn += "chuyển pha trễ $switchDelayS s (via ${switch?.str("via") ?: "?"})"
        }
        if (switchMissing) loc.warn += "không chuyển sang pha dày"

        // ---- exits (exitTs within the run), reinstall attribution ----
        val pkgReplacedT = inRun.firstOrNull { it.ev == "svc_start_cmd" && it.str("src") == SRC_PKG_REPLACED }?.wallMs
        val runExits = LinkedHashMap<String, ProbeEvent>()
        for (e in exitInfos) {
            val ts = e.long("exitTs")!!
            if (ts < startMs || ts > endMs) continue
            runExits.putIfAbsent("$ts/${e.int("reason") ?: 0}", e)
        }
        val reinstallExitTs = pkgReplacedT?.let { tPkg ->
            runExits.values.mapNotNull { it.long("exitTs") }
                .filter { it in (tPkg - Thresholds.REINSTALL_EXIT_WINDOW_S * 1000L)..tPkg }
                .maxOrNull()
        }
        val fixTimes = inRun.filter { it.ev == "fix" }.map { it.wallMs }
        val exits = runExits.values.map { e ->
            val exitTs = e.long("exitTs")!!
            val reason = e.int("reason") ?: 0
            ExitDetail(
                exitWallMs = exitTs,
                offsetS = (exitTs - startMs) / 1000L,
                phase = when {
                    boundaryMs != null && exitTs < boundaryMs -> SPARSE
                    exitTs < plannedEndMs -> DENSE
                    else -> ALARM_PHASE
                },
                reason = reason,
                reasonName = e.str("reasonName") ?: AndroidNames.exitReason(reason),
                desc = e.str("desc"),
                restartS = inRun.firstOrNull { it.ev == "proc_start" && it.wallMs > exitTs }
                    ?.let { (it.wallMs - exitTs) / 1000L },
                restartSrc = inRun.firstOrNull { it.ev == "svc_start_cmd" && it.wallMs > exitTs }?.str("src"),
                recoveryS = fixTimes.firstOrNull { it > exitTs }?.let { (it - exitTs) / 1000L },
                causedByReinstall = reinstallExitTs != null && exitTs == reinstallExitTs,
            )
        }.sortedBy { it.exitWallMs }

        // ---- location gaps per phase window (wall clock: `et` resets on reboot); no downgrade by cause (R2-3) ----
        val fixCount = LinkedHashMap<String, Int>()
        val fixGapMax = LinkedHashMap<String, Long>()
        val gaps = ArrayList<Gap>()
        val windows = ArrayList<Triple<String, Long, Long>>()
        if (boundaryMs != null) windows += Triple(SPARSE, startMs, min(denseStartMs, endMs))
        windows += Triple(DENSE, denseStartMs, min(plannedEndMs, endMs))
        for ((phase, winStart, winEnd) in windows) {
            if (winEnd <= winStart) continue
            val inPhase = fixTimes.filter {
                it >= winStart && (if (phase == SPARSE) it < winEnd else it <= winEnd)
            }
            val marks = listOf(winStart) + inPhase + listOf(winEnd)
            val passS = if (phase == SPARSE) Thresholds.SPARSE_PASS_S else Thresholds.DENSE_PASS_S
            val warnS = if (phase == SPARSE) Thresholds.SPARSE_WARN_S else Thresholds.DENSE_WARN_S
            var maxGap = 0L
            for (i in 1 until marks.size) {
                val gapS = (marks[i] - marks[i - 1]) / 1000L
                maxGap = max(maxGap, gapS)
                if (gapS <= passS) continue
                val level = if (gapS > warnS) Verdict.FAIL else Verdict.WARN
                val gap = buildGap(inRun, exitInfos, marks[i - 1], marks[i], gapS, phase, level, reinstallExitTs)
                gaps += gap
                val name = phaseName(phase)
                val what = if (level == Verdict.FAIL) "mất vị trí" else "có khoảng trống"
                val limit = fmtDur(if (level == Verdict.FAIL) warnS else passS)
                val text = "pha $name $what ${fmtDur(gapS)} (> $limit) lúc ${offset(gap.startWallMs)}" + annotation(gap)
                if (gap.excluded) loc.info += "$text — do cài lại app, không tính" else loc.add(level, text)
            }
            fixCount[phase] = inPhase.size
            fixGapMax[phase] = maxGap
        }

        // ---- process deaths and recovery ----
        val procStarts = 1 + inRun.count { it.ev == "proc_start" && it.wallMs > startMs }
        // Counted: not caused by the reinstall, not after the planned end (the alarm rules judge that phase).
        val counted = exits.filter { !it.causedByReinstall && it.phase != ALARM_PHASE }
        for (e in counted) {
            val where = "${exitPhaseName(e.phase)}, ${e.reasonName}"
            val rec = e.recoveryS
            when {
                rec == null -> loc.fail += "process chết không hồi phục (+${fmtHms(e.offsetS)}, $where)"
                rec > Thresholds.RECOVERY_WARN_S ->
                    loc.fail += "process chết +${fmtHms(e.offsetS)} ($where), hồi phục sau ${fmtDur(rec)} (> 15 ph)"
                rec > Thresholds.RECOVERY_PASS_S ->
                    loc.warn += "process chết +${fmtHms(e.offsetS)} ($where), hồi phục sau $rec s"
            }
        }
        exits.filter { it.causedByReinstall }.forEach {
            loc.info += "lần chết +${fmtHms(it.offsetS)} do cài lại app, không tính"
        }
        val maxRecovery = counted.mapNotNull { it.recoveryS }.maxOrNull()

        val restartsBySrc = inRun.filter { it.ev == "svc_start_cmd" }
            .groupingBy { it.str("src") ?: "?" }.eachCount()
        val fgFails = inRun.count { it.ev == "svc_fg_fail" }
        if (fgFails > 0) loc.info += "startForeground lỗi $fgFails lần"

        when {
            stoppedBy == null && stillRunning -> loc.info += "lượt đang chạy"
            stoppedBy == null -> loc.fail += "không có run_stop: lượt dừng ngoài ý muốn"
            stoppedBy !in VALID_STOPS -> loc.fail += "kết thúc bất thường: $stoppedBy"
        }
        val stoppedEarly = stop != null && stoppedBy == "user" &&
            stop.wallMs < plannedEndMs - Thresholds.EARLY_STOP_TOLERANCE_S * 1000L

        // ---- battery ----
        val battery = inRun.filter { it.ev == "battery" && it.int("lvl") != null }
        val batteryStart = battery.firstOrNull()?.int("lvl")
        val batteryEnd = battery.lastOrNull()?.int("lvl")
        val batteryHours = battery.firstOrNull()?.let { (endMs - it.wallMs) / 3_600_000.0 } ?: 0.0
        val batteryPerHour = if (batteryStart != null && batteryEnd != null && batteryHours > 0.0) {
            (batteryStart - batteryEnd) / batteryHours
        } else {
            null
        }
        val firstCharge = inRun.firstOrNull { it.ev == "battery" && it.bool("chg") == true }

        // ---- alarm (S2 §5.5) ----
        val alarmFindings = Findings()
        val alarm = if (alarmApplies && alarmDueMs != null) {
            analyzeAlarm(start, sorted, inRun, exitInfos, stop, endMs, alarmDueMs, active, stillRunning, alarmFindings)
        } else {
            null
        }

        // ---- verdict ----
        var verdict: Verdict
        val reasons = ArrayList<String>()
        if (kind == KIND_S2) {
            // An S2 run is judged on the alarm only; location/process findings are informational.
            verdict = alarmFindings.verdict()
            reasons += alarmFindings.fail + alarmFindings.warn
            reasons += (loc.fail + loc.warn + loc.info + alarmFindings.info).map { "(thông tin) $it" }
        } else {
            loc.fail += alarmFindings.fail
            loc.warn += alarmFindings.warn
            loc.info += alarmFindings.info
            verdict = loc.verdict()
            reasons += loc.fail + loc.warn
            reasons += loc.info.map { "(thông tin) $it" }
        }

        // ---- invalid run (S1 §4.5, R2-4): verdict on the whole run first, then the adjustment ----
        val invalidEvents = listOfNotNull(
            if (stoppedEarly) stop.wallMs to "dừng trước kế hoạch" else null,
            firstCharge?.let { it.wallMs to "có sạc" },
            pkgReplacedT?.let { it to "cài lại app giữa lượt" },
        )
        val invalidRun = isAB && invalidEvents.isNotEmpty()
        val invalidSince = if (invalidRun) invalidEvents.minOf { it.first } else null
        var countsForGo = true
        val causes = invalidEvents.joinToString(", ") { it.second }
        when {
            invalidRun && verdict == Verdict.FAIL ->
                reasons += "(lượt cũng không hợp lệ từ ${offset(invalidSince!!)} vì $causes; FAIL vẫn tính)"
            invalidRun -> {
                verdict = Verdict.WARN
                countsForGo = false
                reasons.add(0, INVALID_HEADER + causes)
                reasons.addAll(1, invalidEvents.map { "lượt không hợp lệ: ${it.second} — chạy lại" })
            }
            invalidEvents.isNotEmpty() -> reasons += invalidEvents.map { "(thông tin) lượt $label: ${it.second}" }
        }

        return RunSummary(
            runId = start.str("run") ?: "",
            kind = kind,
            label = label,
            device = deviceOf(start),
            scenario = start.str("scenario"),
            delayMin = start.long("delayMin"),
            startWallMs = startMs,
            plannedDurationS = durationMin * 60L,
            actualDurationS = (endMs - startMs) / 1000L,
            stoppedBy = stoppedBy,
            stoppedEarly = stoppedEarly,
            fixCount = fixCount,
            fixGapMaxS = fixGapMax,
            gapsOverPass = gaps,
            phaseBoundaryWallMs = boundaryMs,
            phaseSwitchWallMs = switch?.wallMs,
            phaseSwitchDelayS = switchDelayS,
            phaseSwitchVia = switch?.str("via"),
            phaseSwitchMissing = switchMissing,
            aliveS = fixTimes.lastOrNull()?.let { (it - startMs) / 1000L },
            procStarts = procStarts,
            exits = exits,
            restartsBySrc = restartsBySrc,
            maxRecoveryS = maxRecovery,
            fgFails = fgFails,
            batteryStart = batteryStart,
            batteryEnd = batteryEnd,
            batteryPerHour = batteryPerHour,
            chargedDuringRun = firstCharge != null,
            invalidRun = invalidRun,
            invalidSinceWallMs = invalidSince,
            countsForGo = countsForGo,
            stillRunning = stillRunning,
            alarm = alarm,
            verdict = verdict,
            reasons = reasons,
        )
    }

    /** S1 §4.5 cause annotations of the gap [a, b] (for reading only) and the reinstall exclusion. */
    private fun buildGap(
        inRun: List<ProbeEvent>,
        exitInfos: List<ProbeEvent>,
        a: Long,
        b: Long,
        lengthS: Long,
        phase: String,
        level: Verdict,
        reinstallExitTs: Long?,
    ): Gap {
        val died = exitInfos.any { (it.long("exitTs") ?: Long.MIN_VALUE).let { ts -> ts > a && ts < b } } ||
            inRun.any { it.ev == "proc_start" && it.wallMs > a && it.wallMs < b }
        val pidAtStart = inRun.lastOrNull { it.wallMs <= a }?.pid
        val liveInside = inRun.any {
            it.wallMs > a && it.wallMs < b && it.pid == pidAtStart &&
                ((it.ev == "wd_tick" && it.bool("alive") == true) || it.ev in LIVE_EVENTS)
        }
        val availFalseInside = inRun.any {
            it.ev == "loc_avail" && it.wallMs >= a && it.wallMs <= b && it.bool("avail") == false
        }
        val lastAvailBefore = inRun.lastOrNull { it.ev == "loc_avail" && it.wallMs < a }
        val powerSaveInside = inRun.any {
            it.ev == "power_save" && it.wallMs >= a && it.wallMs <= b && it.bool("on") == true
        }
        val lastPowerSaveBefore = inRun.lastOrNull { it.ev == "power_save" && it.wallMs < a }
        return Gap(
            startWallMs = a,
            lengthS = lengthS,
            phase = phase,
            level = level,
            serviceAlive = !died && liveInside,
            locUnavailable = availFalseInside || lastAvailBefore?.bool("avail") == false,
            powerSaveOn = powerSaveInside || lastPowerSaveBefore?.bool("on") == true,
            excluded = reinstallExitTs != null && reinstallExitTs > a && reinstallExitTs < b,
        )
    }

    /** " (service sống, FLP báo không có vị trí, tiết kiệm pin bật)" or "" when nothing is known. */
    private fun annotation(gap: Gap): String {
        val parts = ArrayList<String>()
        if (gap.serviceAlive) parts += "service sống"
        when {
            gap.locUnavailable -> parts += "FLP báo không có vị trí"
            gap.serviceAlive -> parts += "không nhận vị trí"
        }
        if (gap.powerSaveOn) parts += "tiết kiệm pin bật"
        return if (parts.isEmpty()) "" else " (${parts.joinToString(", ")})"
    }

    private fun analyzeAlarm(
        start: ProbeEvent,
        sorted: List<ProbeEvent>,
        inRun: List<ProbeEvent>,
        exitInfos: List<ProbeEvent>,
        stop: ProbeEvent?,
        endMs: Long,
        dueMs: Long,
        active: Boolean,
        stillRunning: Boolean,
        f: Findings,
    ): AlarmSummary {
        val trigger = inRun.firstOrNull { it.ev == "alarm_trigger" }
        val plannedIso = inRun.firstOrNull { it.ev == "alarm_scheduled" }?.str("deadline")
            ?: trigger?.str("planned")
            ?: OffsetDateTime.parse(start.t).plusSeconds((dueMs - start.wallMs) / 1000L).toString()
        val plannedMs = runCatching { OffsetDateTime.parse(plannedIso).toInstant().toEpochMilli() }.getOrDefault(dueMs)

        val sound = inRun.firstOrNull { it.ev == "alarm_sound_start" }
        val s = inRun.firstOrNull { it.ev == "alarm_sound_start" && it.bool("ok") == true }
        val vibrate = inRun.firstOrNull { it.ev == "alarm_vibrate" }
        val notif = inRun.firstOrNull { it.ev == "alarm_notif_posted" }
        val notifVisible = notif != null && notif.bool("notifEnabled") == true && (notif.int("chAlarmImp") ?: 4) >= 3
        val ui = inRun.firstOrNull { it.ev == "alarm_ui_shown" }
        val errors = inRun.filter { it.ev == "alarm_error" }.map { it.str("step") ?: "?" }
        val snapshot = trigger?.let { tr ->
            inRun.firstOrNull {
                it.ev == "perm_snapshot" && (it.wallMs > tr.wallMs || (it.wallMs == tr.wallMs && it.seq >= tr.seq))
            }
        }
        val lateS = trigger?.let { tr -> tr.long("lateMs")?.let { it / 1000L } ?: ((tr.wallMs - plannedMs) / 1000L) }

        // Valid dismissal vs interruption (S2 §5.5): S = sound ok, P = S.pid. run_stop never counts as a dismissal.
        var dismissal: ProbeEvent? = null
        var interrupted = false
        var ringS: Long? = null
        var ringUpper = false
        if (s != null) {
            val sMs = s.wallMs
            fun deathBefore(tMs: Long): Boolean =
                exitInfos.any { (it.long("exitTs") ?: Long.MIN_VALUE).let { ts -> ts > sMs && ts < tMs } } ||
                    sorted.any { it.ev == "proc_start" && it.wallMs > sMs && it.wallMs < tMs }
            dismissal = sorted.firstOrNull {
                it.ev == "alarm_dismissed" && it.pid == s.pid && it.wallMs > sMs && !deathBefore(it.wallMs)
            }
            val judged = stop != null || !stillRunning
            if (dismissal != null) {
                ringS = (dismissal.wallMs - sMs) / 1000L
            } else if (judged) {
                interrupted = true
                val firstExit = exitInfos.mapNotNull { it.long("exitTs") }.filter { it > sMs }.minOrNull()
                val untilMs = firstExit ?: run {
                    ringUpper = true
                    sorted.firstOrNull { it.ev == "proc_start" && it.wallMs > sMs }?.wallMs
                        ?: sorted.lastOrNull { it.pid == s.pid }?.wallMs
                        ?: sMs
                }
                ringS = (untilMs - sMs) / 1000L
            }
        }

        if (trigger == null) {
            when {
                // Overdue: the run ended after the due time, or is still active past due + grace (R2-8).
                (!active && endMs >= plannedMs) || (active && !stillRunning) -> f.fail += "báo thức không kích hoạt"
                stillRunning -> Unit
                else -> f.warn += "lượt dừng trước giờ báo, chưa đánh giá được báo thức"
            }
        } else {
            if (s == null) f.fail += "báo thức không phát âm (isPlaying = false hoặc không có alarm_sound_start)"
            if (interrupted) {
                val text = "báo thức bị ngắt sau ${if (ringUpper) "≤ " else ""}${ringS ?: "?"} s"
                if ((ringS ?: 0L) < Thresholds.ALARM_INTERRUPT_FAIL_S) f.fail += text else f.warn += text
            }
            if (trigger.str("src") == "fallback") f.warn += "kích hoạt bằng dự phòng (FLP không giao vị trí đúng hạn)"
            if (lateS != null && lateS > Thresholds.ALARM_LATE_PASS_S) f.warn += "báo thức trễ $lateS s (> 30 s)"
            if (ui == null && !notifVisible) f.warn += "không có màn báo thức/thông báo"
        }
        val otherErrors = errors.filter { it != "interrupted" }
        if (otherErrors.isNotEmpty()) f.warn += "lỗi báo thức ở bước: ${otherErrors.joinToString()}"

        return AlarmSummary(
            plannedWall = plannedIso,
            triggeredWall = trigger?.t,
            lateS = lateS,
            src = trigger?.str("src"),
            soundOk = s != null,
            focus = sound?.str("focus"),
            alarmVol = sound?.int("alarmVol") ?: snapshot?.int("alarmVol"),
            alarmVolMax = sound?.int("alarmVolMax") ?: snapshot?.int("alarmVolMax"),
            vibrateOk = vibrate?.bool("ok") == true,
            notifPosted = notif != null,
            notifVisible = notifVisible,
            fsiAllowed = notif?.bool("fsiAllowed"),
            uiShown = ui != null,
            uiOnLockscreen = ui?.bool("keyguardLocked"),
            dismissedBy = dismissal?.str("by"),
            dismissAfterS = dismissal?.long("afterMs")?.let { it / 1000L },
            interrupted = interrupted,
            ringS = ringS,
            ringSUpperBound = ringUpper,
            zen = snapshot?.int("zen"),
            ringer = snapshot?.int("ringer"),
            errors = errors,
        )
    }

    private fun noRunStart(sorted: List<ProbeEvent>): RunSummary {
        val first = sorted.firstOrNull()
        return RunSummary(
            runId = first?.str("run") ?: "",
            kind = "?",
            label = "",
            device = "",
            scenario = null,
            delayMin = null,
            startWallMs = first?.wallMs ?: 0L,
            plannedDurationS = 0L,
            actualDurationS = 0L,
            stoppedBy = null,
            stoppedEarly = false,
            fixCount = emptyMap(),
            fixGapMaxS = emptyMap(),
            gapsOverPass = emptyList(),
            phaseBoundaryWallMs = null,
            phaseSwitchWallMs = null,
            phaseSwitchDelayS = null,
            phaseSwitchVia = null,
            phaseSwitchMissing = false,
            aliveS = null,
            procStarts = 0,
            exits = emptyList(),
            restartsBySrc = emptyMap(),
            maxRecoveryS = null,
            fgFails = 0,
            batteryStart = null,
            batteryEnd = null,
            batteryPerHour = null,
            chargedDuringRun = false,
            invalidRun = false,
            invalidSinceWallMs = null,
            countsForGo = true,
            stillRunning = false,
            alarm = null,
            verdict = Verdict.FAIL,
            reasons = listOf("không có sự kiện run_start trong log"),
        )
    }

    private fun deviceOf(start: ProbeEvent): String {
        val manufacturer = start.str("manufacturer").orEmpty()
        val model = start.str("model").orEmpty()
        val name = if (model.startsWith(manufacturer, ignoreCase = true)) model else "$manufacturer $model".trim()
        return "$name · Android ${start.str("release").orEmpty()} (SDK ${start.long("sdk") ?: "?"})"
    }

    // ---- render (Vietnamese text for SummaryActivity) ----

    fun render(summary: RunSummary): String {
        val s = summary
        fun offset(wallMs: Long) = "+" + fmtHms((wallMs - s.startWallMs) / 1000L)
        val lines = ArrayList<String>()
        lines += "Lượt ${s.runId} · ${s.device}"
        if (s.kind == KIND_S2) lines += "Kịch bản ${s.scenario ?: s.label} · trễ ${s.delayMin ?: "?"} ph"
        val ending = s.stoppedBy ?: if (s.stillRunning) "đang chạy" else "chưa có run_stop"
        lines += "Kế hoạch ${fmtHms(s.plannedDurationS)} · Thực tế ${fmtHms(s.actualDurationS)} · Kết thúc: $ending"

        val phaseParts = s.fixCount.keys.map { phase ->
            "${phaseName(phase)} ${s.fixCount[phase]} (khoảng trống lớn nhất ${fmtDur(s.fixGapMaxS[phase] ?: 0L)})"
        }
        val alive = s.aliveS?.let { " · có vị trí tới +${fmtHms(it)}" } ?: " · chưa có vị trí nào"
        lines += "Vị trí: " + (if (phaseParts.isEmpty()) "không có pha nào" else phaseParts.joinToString(" · ")) + alive

        s.phaseBoundaryWallMs?.let { boundary ->
            lines += "Chuyển pha: ranh giới ${offset(boundary)} · " + when {
                s.phaseSwitchWallMs != null ->
                    "thật ${offset(s.phaseSwitchWallMs)} (trễ ${s.phaseSwitchDelayS ?: 0} s, via ${s.phaseSwitchVia ?: "?"})"
                s.phaseSwitchMissing -> "không chuyển sang pha dày"
                else -> "chưa tới"
            }
        }
        if (s.gapsOverPass.isNotEmpty()) {
            lines += "Khoảng trống > ngưỡng: " + s.gapsOverPass.joinToString("; ") {
                val tag = if (it.excluded) "không tính, do cài lại app" else it.level.name
                val cause = annotation(it).ifEmpty { if (it.serviceAlive) "" else " (không thấy service sống)" }
                "${offset(it.startWallMs)} ${phaseName(it.phase)} ${fmtDur(it.lengthS)} — $tag$cause"
            }
        }

        val restarts = s.restartsBySrc.filterKeys { it != "user" }
        val restartText = if (restarts.isEmpty()) "không" else restarts.entries.joinToString { "${it.key} ${it.value}" }
        lines += "Process: ${s.procStarts} lần khởi động · Chết: ${s.exits.size} · Khởi động lại: $restartText"
        for (e in s.exits) {
            val desc = e.desc?.let { " \"$it\"" } ?: ""
            val restart = e.restartS?.let { " · khởi động lại sau ${fmtDur(it)} (${e.restartSrc ?: "?"})" }
                ?: " · không khởi động lại"
            val recovery = e.recoveryS?.let { " · có vị trí lại sau ${fmtDur(it)}" } ?: " · không hồi phục"
            val reinstall = if (e.causedByReinstall) " · do cài lại app, không tính" else ""
            lines += "  Chết +${fmtHms(e.offsetS)} (${exitPhaseName(e.phase)}) ${e.reasonName} ${e.reason}$desc" +
                "$restart$recovery$reinstall"
        }
        if (s.fgFails > 0) lines += "startForeground lỗi: ${s.fgFails} lần"

        val perHour = s.batteryPerHour?.let { " (${String.format(VI, "%.1f", it)}%/giờ)" } ?: ""
        lines += "Pin: ${s.batteryStart ?: "?"}% → ${s.batteryEnd ?: "?"}%$perHour · " +
            "Có cắm sạc: ${yesNo(s.chargedDuringRun)}"

        s.alarm?.let { lines += renderAlarm(it) }

        val header = s.reasons.firstOrNull { it.startsWith(INVALID_HEADER) }
        if (header != null) lines += header
        val others = s.reasons.filter { it != header }
        val reasonText = if (others.isEmpty()) "" else " — " + others.joinToString("; ")
        lines += "Kết luận tự động: ${s.verdict}$reasonText"
        return lines.joinToString("\n")
    }

    private fun renderAlarm(a: AlarmSummary): String {
        val planned = fmtClock(a.plannedWall)
        if (a.triggeredWall == null) return "Báo thức: không kích hoạt (mốc $planned)"
        val parts = ArrayList<String>()
        val late = a.lateS ?: 0L
        parts += "mốc $planned, lệch ${if (late >= 0) "+" else ""}$late s"
        parts += "nguồn ${a.src ?: "?"}"
        parts += "âm thanh ${if (a.soundOk) "OK" else "KHÔNG"}" +
            (a.alarmVol?.let { " (âm lượng $it/${a.alarmVolMax ?: "?"}, focus ${a.focus ?: "?"})" } ?: "")
        parts += "rung ${if (a.vibrateOk) "OK" else "không"}"
        parts += "thông báo: ${yesNo(a.notifPosted)}, hiện được: ${yesNo(a.notifVisible)}" +
            (a.fsiAllowed?.let { " (FSI: ${yesNo(it)})" } ?: "")
        parts += if (a.uiShown) {
            "màn báo thức hiện trên màn khoá: ${a.uiOnLockscreen?.let { yesNo(it) } ?: "?"}"
        } else {
            "màn báo thức: không hiện"
        }
        a.zen?.let { parts += "DND ${AndroidNames.interruptionFilter(it)}" }
        a.ringer?.let { parts += "chuông ${AndroidNames.ringerMode(it)}" }
        if (a.interrupted) {
            parts += "bị ngắt sau ${if (a.ringSUpperBound) "≤ " else ""}${a.ringS ?: "?"} s"
        } else if (a.dismissedBy != null) {
            parts += "tắt sau ${a.ringS?.let { fmtDur(it) } ?: "?"} (${a.dismissedBy})"
        }
        return "Báo thức: " + parts.joinToString(" · ")
    }

    private const val VIA_START = "start"
    private const val SRC_PKG_REPLACED = "pkg_replaced"

    private fun phaseName(phase: String) = if (phase == SPARSE) "thưa" else "dày"

    private fun exitPhaseName(phase: String) = when (phase) {
        SPARSE -> "pha thưa"
        DENSE -> "pha dày"
        else -> "sau giờ báo"
    }

    private fun yesNo(b: Boolean) = if (b) "có" else "không"

    private fun fmtClock(iso: String): String =
        runCatching { OffsetDateTime.parse(iso).format(HMS) }.getOrDefault(iso)

    /** 36000 -> "10:00:00". */
    fun fmtHms(seconds: Long): String {
        val s = max(0L, seconds)
        return String.format(Locale.ROOT, "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    /** 41 -> "41 s", 372 -> "6 ph 12 s", 3725 -> "1 giờ 02 ph 05 s". */
    fun fmtDur(seconds: Long): String {
        val s = max(0L, seconds)
        return when {
            s < 60 -> "$s s"
            s < 3600 -> String.format(Locale.ROOT, "%d ph %02d s", s / 60, s % 60)
            else -> String.format(Locale.ROOT, "%d giờ %02d ph %02d s", s / 3600, (s % 3600) / 60, s % 60)
        }
    }
}
