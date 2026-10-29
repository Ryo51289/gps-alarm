package app.napstop.probe.analysis

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import kotlin.random.Random

/**
 * U03–U27 (docs/spikes/S1.md §7.1, docs/spikes/S2.md §5.5). Times are seconds after run start.
 * The S1 base fixture (U03) has 10 h, boundary at 9 h (32 400 s) with `phase_switch via=alarm lateMs=0`.
 */
class RunAnalyzerTest {

    private val t0: OffsetDateTime = OffsetDateTime.parse("2026-11-02T21:30:05.000+07:00")
    private val fmt: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSSXXX")
    private val runId = "20261102-213005-S1-A"
    private val boundary = 32_400L
    private val end = 36_000L
    private var seq = 0L

    private fun iso(sec: Double): String = t0.plusNanos((sec * 1e9).toLong()).format(fmt)

    private fun epochMs(sec: Double): Long = t0.toInstant().toEpochMilli() + (sec * 1000).toLong()

    private fun ev(sec: Double, ev: String, vararg fields: Pair<String, Any?>, pid: Int = 100): ProbeEvent {
        val map = linkedMapOf<String, Any?>(
            "ev" to ev, "t" to iso(sec), "et" to (sec * 1000).toLong(), "run" to runId, "pid" to pid, "seq" to ++seq,
        )
        map.putAll(fields)
        return ProbeEventParser.toEvent(map)!!
    }

    private fun ev(sec: Long, ev: String, vararg fields: Pair<String, Any?>, pid: Int = 100) =
        ev(sec.toDouble(), ev, *fields, pid = pid)

    /** S1 7.1 defaults: active = false, nowMs = t of the last event + 1 h. */
    private fun analyzeRun(events: List<ProbeEvent>, active: Boolean = false, nowMs: Long? = null): RunSummary =
        RunAnalyzer.analyze(events, nowMs ?: ((events.maxOfOrNull { it.wallMs } ?: 0L) + 3_600_000L), active)

    // ---- S1 fixtures ----

    /** Sparse fixes every 180 s before 9 h, dense every 10 s from 9 h to 10 h. */
    private fun defaultFixes(): MutableList<Long> {
        val out = ArrayList<Long>()
        var s = 180L
        while (s < boundary) {
            out += s
            s += 180
        }
        s = boundary
        while (s <= end) {
            out += s
            s += 10
        }
        return out
    }

    /** Alarm at the end: trigger 36 000.5, sound 36 001.5, UI, dismissed by the activity at 36 042. */
    private fun alarmEvents(): List<ProbeEvent> = listOf(
        ev(36_000.5, "alarm_trigger", "src" to "fix", "planned" to iso(36_000.0), "lateMs" to 500),
        ev(36_000.6, "perm_snapshot", "zen" to 3, "ringer" to 0, "alarmVol" to 5, "alarmVolMax" to 7),
        ev(36_001.5, "alarm_sound_start", "ok" to true, "focus" to "granted", "alarmVol" to 5, "alarmVolMax" to 7, "muted" to false),
        ev(36_001.6, "alarm_vibrate", "ok" to true, "hasVibrator" to true),
        ev(36_001.7, "alarm_notif_posted", "fsiAllowed" to true, "notifEnabled" to true, "chAlarmImp" to 4),
        ev(36_003.0, "alarm_ui_shown", "keyguardLocked" to true, "interactive" to true, "viaFsi" to true),
        ev(36_042.0, "alarm_dismissed", "by" to "activity", "afterMs" to 41_500),
    )

    private fun s1Run(
        label: String = "A",
        fixes: List<Long> = defaultFixes(),
        switch: ProbeEvent? = null,
        noSwitch: Boolean = false,
        alarmAtEnd: Boolean = true,
        alarm: List<ProbeEvent>? = null,
        noAlarm: Boolean = false,
        stop: Pair<Long, String>? = 36_042L to "alarm_dismissed",
        extra: List<ProbeEvent> = emptyList(),
        battery: List<ProbeEvent>? = null,
    ): List<ProbeEvent> {
        seq = 0
        val out = ArrayList<ProbeEvent>()
        out += ev(
            0, "run_start",
            "run" to "20261102-213005-S1-$label",
            "kind" to "S1", "label" to label, "durationMin" to 600, "densePhaseMin" to 60, "alarmAtEnd" to alarmAtEnd,
            "watchdog" to true, "delayMin" to null, "scenario" to null, "manufacturer" to "Xiaomi", "brand" to "Redmi",
            "model" to "Redmi Note 13", "sdk" to 34, "release" to "14", "display" to "x", "secPatch" to "2026-09-01",
            "gms" to "OK",
        )
        out += ev(0, "perm_snapshot", "zen" to 1, "ringer" to 2)
        out += ev(0, "svc_start_cmd", "src" to "user", "flags" to 0, "startId" to 1)
        out += ev(0, "svc_fg_ok")
        out += ev(0, "phase_alarm_scheduled", "boundary" to iso(boundary.toDouble()), "exact" to true)
        if (alarmAtEnd) out += ev(0, "alarm_scheduled", "deadline" to iso(36_000.0), "fallbackExact" to true)
        out += battery ?: listOf(ev(1, "battery", "lvl" to 96, "chg" to false))
        fixes.forEach { out += ev(it, "fix", "acc" to 12.0, "spd" to null, "prov" to "fused", "ageMs" to 5, "dM" to 3.0) }
        if (!noSwitch) {
            out += switch ?: ev(
                boundary.toDouble(), "phase_switch", "from" to "sparse", "to" to "dense",
                "boundary" to iso(boundary.toDouble()), "lateMs" to 0, "via" to "alarm",
            )
        }
        if (alarmAtEnd && !noAlarm) out += alarm ?: alarmEvents()
        out += extra
        if (stop != null) out += ev(stop.first, "run_stop", "by" to stop.second)
        return out
    }

    // ---- S2 fixtures ----

    private fun s2Run(
        triggerSrc: String? = "fix",
        lateMs: Long = 8_000,
        soundOk: Boolean = true,
        uiShown: Boolean = true,
        notifPosted: Boolean = true,
        notifEnabled: Boolean = true,
        chAlarmImp: Int? = null,
        errors: List<String> = emptyList(),
        stop: Pair<Long, String>? = null, // default: right after the alarm is dismissed
    ): List<ProbeEvent> {
        seq = 0
        val out = ArrayList<ProbeEvent>()
        out += ev(
            0, "run_start",
            "kind" to "S2", "label" to "S2-1", "durationMin" to 2, "densePhaseMin" to 2, "alarmAtEnd" to true,
            "watchdog" to true, "delayMin" to 2, "scenario" to "S2-1", "manufacturer" to "samsung",
            "model" to "SM-A546E", "sdk" to 35, "release" to "15",
        )
        out += ev(0, "alarm_scheduled", "deadline" to iso(120.0), "fallbackExact" to true)
        out += ev(0.2, "phase_switch", "from" to "sparse", "to" to "dense", "boundary" to iso(0.0), "lateMs" to 0, "via" to "start")
        for (s in 0L..130L step 10) out += ev(s, "fix", "acc" to 8.0)
        if (triggerSrc != null) {
            val trig = 120.0 + lateMs / 1000.0
            out += ev(trig, "alarm_trigger", "src" to triggerSrc, "planned" to iso(120.0), "lateMs" to lateMs)
            out += ev(trig + 1, "alarm_sound_start", "ok" to soundOk, "focus" to "granted", "alarmVol" to 5, "alarmVolMax" to 7)
            errors.forEach { out += ev(trig + 1.1, "alarm_error", "step" to it, "ex" to "java.lang.SecurityException") }
            if (notifPosted) {
                out += ev(
                    trig + 1.2, "alarm_notif_posted", "fsiAllowed" to true, "notifEnabled" to notifEnabled,
                    "chAlarmImp" to chAlarmImp,
                )
            }
            if (uiShown) out += ev(trig + 2, "alarm_ui_shown", "keyguardLocked" to true, "interactive" to true)
            out += ev(trig + 42, "alarm_dismissed", "by" to "activity", "afterMs" to 42_000)
        }
        val runStop = stop ?: (120L + lateMs / 1000L + 42L to "alarm_dismissed")
        out += ev(runStop.first, "run_stop", "by" to runStop.second)
        return out
    }

    // ---- S1 tests ----

    @Test
    fun `U03 clean 10 h run passes`() {
        val s = analyzeRun(s1Run())
        assertEquals(Verdict.PASS, s.verdict)
        assertEquals(180L, s.fixGapMaxS["sparse"])
        assertEquals(10L, s.fixGapMaxS["dense"])
        assertEquals(1, s.procStarts)
        assertEquals(179, s.fixCount["sparse"])
        assertEquals(361, s.fixCount["dense"])
        assertEquals(0L, s.phaseSwitchDelayS)
        assertEquals("alarm", s.phaseSwitchVia)
        assertFalse(s.phaseSwitchMissing)
        assertEquals(36_000L, s.aliveS)
        assertEquals("alarm_dismissed", s.stoppedBy)
        assertEquals(36_000L, s.plannedDurationS)
        assertEquals(36_042L, s.actualDurationS)
        assertFalse(s.invalidRun)
        assertTrue(s.reasons.toString(), s.reasons.isEmpty())
    }

    @Test
    fun `U04 600 s sparse gap warns and is listed as not alive`() {
        val fixes = defaultFixes().apply {
            removeAll(listOf(3_780L, 3_960L, 4_140L))
            add(4_200L)
            sort()
        }
        val s = analyzeRun(s1Run(fixes = fixes))
        assertEquals(Verdict.WARN, s.verdict)
        assertEquals(1, s.gapsOverPass.size)
        val gap = s.gapsOverPass[0]
        assertEquals(600L, gap.lengthS)
        assertEquals("sparse", gap.phase)
        assertEquals(epochMs(3_600.0), gap.startWallMs)
        assertFalse(gap.serviceAlive)
    }

    @Test
    fun `U05 120 s dense gap warns`() {
        val fixes = defaultFixes().filterNot { it in 33_010L..33_110L }
        val s = analyzeRun(s1Run(fixes = fixes))
        assertEquals(120L, s.fixGapMaxS["dense"])
        assertEquals(Verdict.WARN, s.verdict)
    }

    @Test
    fun `U06 200 s dense gap fails and mentions the dense phase`() {
        val fixes = defaultFixes().filterNot { it in 33_010L..33_190L }
        val s = analyzeRun(s1Run(fixes = fixes))
        assertEquals(200L, s.fixGapMaxS["dense"])
        assertEquals(Verdict.FAIL, s.verdict)
        assertTrue(s.reasons.toString(), s.reasons.any { it.contains("pha dày") })
    }

    private fun u07Events(src: String = "sticky"): List<ProbeEvent> {
        val fixes = defaultFixes().apply {
            remove(10_980L)
            add(10_985L)
            sort()
        }
        // The new process logs proc_start + exit_info at 3:02:30; the process died at 3:01:00.
        val extra = listOf(
            ev(10_950, "proc_start", "importance" to 125, pid = 200),
            ev(
                10_950, "exit_info", "reason" to 13, "reasonName" to "REASON_OTHER", "exitTs" to epochMs(10_860.0),
                "desc" to "MemoryLimiter:AnonSwap", "importance" to 125, "status" to 0, pid = 200,
            ),
            ev(10_950, "svc_start_cmd", "src" to src, "flags" to 0, "startId" to 1, pid = 200),
            ev(10_950, "svc_fg_ok", pid = 200),
        )
        return s1Run(fixes = fixes, extra = extra)
    }

    @Test
    fun `U07 process death recovered in 125 s passes with exit details`() {
        val s = analyzeRun(u07Events())
        assertEquals(125L, s.maxRecoveryS)
        assertEquals(1, s.restartsBySrc["sticky"])
        assertEquals(1, s.restartsBySrc["user"])
        assertEquals(2, s.procStarts)
        assertEquals(185L, s.fixGapMaxS["sparse"])
        assertEquals(1, s.exits.size)
        val e = s.exits[0]
        assertEquals(10_860L, e.offsetS)
        assertEquals("sparse", e.phase)
        assertEquals("REASON_OTHER", e.reasonName)
        assertEquals(90L, e.restartS)
        assertEquals("sticky", e.restartSrc)
        assertEquals(125L, e.recoveryS)
        assertEquals(Verdict.PASS, s.verdict)
        assertTrue(RunAnalyzer.render(s).contains("Chết +3:01:00 (pha thưa)"))
    }

    @Test
    fun `U08 death without recovery and without run_stop fails`() {
        val fixes = defaultFixes().filter { it <= 10_800L }
        val extra = listOf(
            ev(10_900, "proc_start", "importance" to 125, pid = 200),
            ev(10_900, "exit_info", "reason" to 3, "exitTs" to epochMs(10_830.0), pid = 200),
        )
        val s = analyzeRun(s1Run(fixes = fixes, noSwitch = true, noAlarm = true, stop = null, extra = extra))
        assertEquals(Verdict.FAIL, s.verdict)
        assertTrue(s.reasons.toString(), s.reasons.any { it.contains("chết không hồi phục") })
        assertNull(s.stoppedBy)
        assertFalse(s.phaseSwitchMissing) // the run never reached the boundary
        assertEquals("REASON_LOW_MEMORY", s.exits[0].reasonName)
        assertNull(s.exits[0].recoveryS)
    }

    @Test
    fun `U09 end-of-phase gap counts`() {
        val fixes = defaultFixes().filter { it <= 35_930L }
        val s = analyzeRun(s1Run(fixes = fixes, alarmAtEnd = false, stop = 36_000L to "auto"))
        assertEquals(70L, s.fixGapMaxS["dense"])
        assertEquals(Verdict.WARN, s.verdict)
    }

    @Test
    fun `U10 battery drain per hour`() {
        val battery = listOf(
            ev(0, "battery", "lvl" to 96, "chg" to false),
            ev(18_000, "battery", "lvl" to 90, "chg" to false),
            ev(36_000, "battery", "lvl" to 83, "chg" to false),
        )
        val s = analyzeRun(s1Run(battery = battery))
        assertEquals(96, s.batteryStart)
        assertEquals(83, s.batteryEnd)
        assertEquals(1.3, s.batteryPerHour!!, 0.01)
        assertFalse(s.chargedDuringRun)
    }

    private fun chargingBattery() = listOf(
        ev(0, "battery", "lvl" to 96, "chg" to false),
        ev(5_000, "battery", "lvl" to 96, "chg" to true),
        ev(5_600, "battery", "lvl" to 97, "chg" to false),
    )

    @Test
    fun `U11a charging makes an A run invalid (WARN)`() {
        val s = analyzeRun(s1Run(battery = chargingBattery()))
        assertTrue(s.chargedDuringRun)
        assertTrue(s.invalidRun)
        assertEquals(Verdict.WARN, s.verdict)
        assertTrue(s.reasons.toString(), s.reasons.any { it.contains("lượt không hợp lệ: có sạc") })
        assertTrue(RunAnalyzer.render(s).contains("LƯỢT KHÔNG HỢP LỆ — chạy lại: có sạc"))
    }

    @Test
    fun `U11b charging in an R1 run is information only`() {
        val s = analyzeRun(s1Run(label = "R1", battery = chargingBattery()))
        assertTrue(s.chargedDuringRun)
        assertFalse(s.invalidRun)
        assertEquals(Verdict.PASS, s.verdict)
        assertTrue(s.reasons.toString(), s.reasons.any { it.startsWith("(thông tin)") && it.contains("sạc") })
    }

    @Test
    fun `U12 alarmAtEnd without a playing alarm fails`() {
        val alarm = alarmEvents().filterNot { it.ev == "alarm_sound_start" }
        val s = analyzeRun(s1Run(alarm = alarm))
        assertEquals(Verdict.FAIL, s.verdict)
        assertFalse(s.alarm!!.soundOk)
    }

    @Test
    fun `U12b alarmAtEnd and no trigger at all fails`() {
        val s = analyzeRun(s1Run(noAlarm = true, stop = 36_300L to "user"))
        assertEquals(Verdict.FAIL, s.verdict)
        assertTrue(s.reasons.toString(), s.reasons.any { it.contains("không kích hoạt") })
        assertFalse(s.stoppedEarly)
    }

    @Test
    fun `U13 out-of-order lines give the same result as sorted lines`() {
        val events = u07Events()
        val shuffled = events.shuffled(Random(42))
        assertEquals(analyzeRun(events), analyzeRun(shuffled))
    }

    @Test
    fun `U14 render never contains coordinate words`() {
        val summaries = listOf(
            analyzeRun(u07Events()),
            analyzeRun(s1Run(battery = chargingBattery())),
            analyzeRun(u23Events('a')),
            analyzeRun(u26Events(exitAfterS = 20, withExit = true)),
            analyzeRun(s2Run()),
            analyzeRun(emptyList()),
        )
        for (s in summaries) {
            val text = RunAnalyzer.render(s).lowercase()
            for (word in listOf("lat", "lng", "latitude", "longitude")) {
                assertFalse("'$word' in:\n$text", text.contains(word))
            }
        }
    }

    @Test
    fun `render shows the main figures`() {
        val text = RunAnalyzer.render(analyzeRun(u07Events()))
        assertTrue(text, text.contains("Lượt $runId · Xiaomi Redmi Note 13 · Android 14 (SDK 34)"))
        assertTrue(text, text.contains("Kế hoạch 10:00:00 · Thực tế 10:00:42 · Kết thúc: alarm_dismissed"))
        assertTrue(text, text.contains("thưa 179 (khoảng trống lớn nhất 3 ph 05 s)"))
        assertTrue(text, text.contains("có vị trí tới +10:00:00"))
        assertTrue(text, text.contains("Chuyển pha: ranh giới +9:00:00 · thật +9:00:00 (trễ 0 s, via alarm)"))
        assertTrue(text, text.contains("Khởi động lại: sticky 1"))
        assertTrue(text, text.contains("khởi động lại sau 1 ph 30 s (sticky) · có vị trí lại sau 2 ph 05 s"))
        assertTrue(text, text.contains("Báo thức: mốc 07:30:05, lệch +0 s"))
        assertTrue(text, text.contains("Kết luận tự động: PASS"))
    }

    @Test
    fun `no run_start gives FAIL instead of throwing`() {
        val s = analyzeRun(listOf(ev(0, "proc_start")))
        assertEquals(Verdict.FAIL, s.verdict)
    }

    // ---- phase switch (U20–U22) ----

    @Test
    fun `U20 late phase switch is reported once and not as a dense gap`() {
        val fixes = ArrayList<Long>()
        var t = 180L
        while (t < boundary) {
            fixes += t
            t += 180
        }
        fixes += boundary - 5
        fixes += boundary + 175
        t = boundary + 180
        while (t <= end) {
            fixes += t
            t += 10
        }
        val switch = ev(
            (boundary + 175).toDouble(), "phase_switch", "from" to "sparse", "to" to "dense",
            "boundary" to iso(boundary.toDouble()), "lateMs" to 175_000, "via" to "fix",
        )
        val s = analyzeRun(s1Run(fixes = fixes, switch = switch))
        assertEquals(175L, s.phaseSwitchDelayS)
        assertEquals("fix", s.phaseSwitchVia)
        assertEquals(180L, s.fixGapMaxS["sparse"])
        assertEquals(10L, s.fixGapMaxS["dense"])
        assertEquals(Verdict.WARN, s.verdict)
        assertEquals(s.reasons.toString(), 1, s.reasons.size)
        assertTrue(s.reasons[0], s.reasons[0].contains("chuyển pha trễ 175 s"))
        assertTrue(s.reasons.none { it.contains("pha dày") })
    }

    @Test
    fun `U21 phase switch 2 s late passes`() {
        val fixes = defaultFixes().filter { it < boundary }.toMutableList()
        var t = boundary + 8
        while (t <= end) {
            fixes += t
            t += 10
        }
        val switch = ev(
            (boundary + 2).toDouble(), "phase_switch", "from" to "sparse", "to" to "dense",
            "boundary" to iso(boundary.toDouble()), "lateMs" to 2_000, "via" to "alarm",
        )
        val s = analyzeRun(s1Run(fixes = fixes, switch = switch))
        assertEquals(2L, s.phaseSwitchDelayS)
        assertEquals(Verdict.PASS, s.verdict)
    }

    @Test
    fun `U22a missing phase switch with the service alive warns`() {
        val fixes = ArrayList<Long>()
        var t = 180L
        while (t <= end) {
            fixes += t
            t += 180
        }
        val s = analyzeRun(s1Run(fixes = fixes, noSwitch = true))
        assertTrue(s.phaseSwitchMissing)
        assertEquals(180L, s.fixGapMaxS["dense"])
        assertEquals(Verdict.WARN, s.verdict)
        assertTrue(s.reasons.toString(), s.reasons.any { it.contains("không chuyển sang pha dày") })
    }

    @Test
    fun `U22b missing phase switch after the service stopped keeps the full dense thresholds`() {
        val fixes = defaultFixes().filter { it < boundary - 60 }
        val alive = ArrayList<ProbeEvent>()
        alive += ev(boundary - 60, "svc_destroy")
        var t = boundary
        var lvl = 80
        while (t <= end) {
            alive += ev(t, "battery", "lvl" to lvl--, "chg" to false)
            alive += ev(t + 1, "screen", "on" to false)
            t += 600
        }
        val s = analyzeRun(s1Run(fixes = fixes, noSwitch = true, alarmAtEnd = false, stop = end to "auto", extra = alive))
        assertTrue(s.phaseSwitchMissing)
        val dense = s.gapsOverPass.single { it.phase == "dense" }
        assertEquals(3_600L, dense.lengthS)
        assertEquals(Verdict.FAIL, dense.level)
        assertEquals(Verdict.FAIL, s.verdict)
    }

    // ---- gap cause annotations never change the level (U23, R2-3) ----

    /** (a) sparse 1 000 s + avail=false; (b) dense 240 s + avail=false + power save on just before; (c) sparse 600 s +
     * avail=false; (d) like (a) without avail=false. Every variant has one wd_tick alive=true from the same pid. */
    private fun u23Events(variant: Char): List<ProbeEvent> {
        val (from, to) = when (variant) {
            'b' -> 33_000L to 33_240L
            'c' -> 3_600L to 4_200L
            else -> 3_600L to 4_600L
        }
        val fixes = defaultFixes().filterNot { it in (from + 1) until to }.toMutableList().apply {
            if (!contains(to)) add(to)
            sort()
        }
        val extra = buildList {
            if (variant == 'b') add(ev(from - 10, "power_save", "on" to true))
            if (variant != 'd') add(ev(from + 100, "loc_avail", "avail" to false))
            add(ev(from + 120, "wd_tick", "alive" to true, "lastFixAgeS" to 120, "action" to "none"))
        }
        return s1Run(fixes = fixes, extra = extra)
    }

    @Test
    fun `U23a sparse gap with the service alive and FLP unavailable still fails`() {
        val s = analyzeRun(u23Events('a'))
        val gap = s.gapsOverPass.single()
        assertEquals(1_000L, gap.lengthS)
        assertEquals(Verdict.FAIL, gap.level)
        assertTrue(gap.serviceAlive)
        assertTrue(gap.locUnavailable)
        assertEquals(Verdict.FAIL, s.verdict)
        assertTrue(s.reasons.toString(), s.reasons.any { it.contains("service sống, FLP báo không có vị trí") })
    }

    @Test
    fun `U23b dense gap with power save on fails and is annotated`() {
        val s = analyzeRun(u23Events('b'))
        val gap = s.gapsOverPass.single()
        assertEquals("dense", gap.phase)
        assertEquals(240L, gap.lengthS)
        assertTrue(gap.powerSaveOn)
        assertEquals(Verdict.FAIL, s.verdict)
        assertTrue(s.reasons.toString(), s.reasons.any { it.contains("tiết kiệm pin bật") })
    }

    @Test
    fun `U23c 600 s sparse gap with FLP unavailable warns`() {
        val s = analyzeRun(u23Events('c'))
        val gap = s.gapsOverPass.single()
        assertEquals(Verdict.WARN, gap.level)
        assertEquals(Verdict.WARN, s.verdict)
        assertTrue(s.reasons.toString(), s.reasons.any { it.contains("service sống, FLP báo không có vị trí") })
    }

    @Test
    fun `U23d gap with the service alive but no unavailability report fails`() {
        val s = analyzeRun(u23Events('d'))
        val gap = s.gapsOverPass.single()
        assertTrue(gap.serviceAlive)
        assertFalse(gap.locUnavailable)
        assertEquals(Verdict.FAIL, s.verdict)
        assertTrue(s.reasons.toString(), s.reasons.any { it.contains("service sống, không nhận vị trí") })
        assertTrue(RunAnalyzer.render(s).contains("service sống, không nhận vị trí"))
    }

    // ---- early stop / invalid run (U24) ----

    @Test
    fun `U24a B run stopped early by the user is invalid (WARN, never PASS or FAIL)`() {
        val fixes = defaultFixes().filter { it <= 10_800L }
        val s = analyzeRun(s1Run(label = "B", fixes = fixes, alarmAtEnd = false, stop = 10_800L to "user"))
        assertTrue(s.stoppedEarly)
        assertTrue(s.invalidRun)
        assertEquals(Verdict.WARN, s.verdict)
        assertTrue(s.reasons.toString(), s.reasons.any { it.contains("lượt không hợp lệ: dừng trước kế hoạch — chạy lại") })
        assertFalse(s.countsForGo)
        assertTrue(RunAnalyzer.render(s).contains("LƯỢT KHÔNG HỢP LỆ — chạy lại"))
    }

    @Test
    fun `U24b R1 run stopped early by the user is information only`() {
        val fixes = defaultFixes().filter { it <= 10_800L }
        val s = analyzeRun(s1Run(label = "R1", fixes = fixes, alarmAtEnd = false, stop = 10_800L to "user"))
        assertTrue(s.stoppedEarly)
        assertFalse(s.invalidRun)
        assertEquals(Verdict.PASS, s.verdict)
        assertTrue(s.reasons.toString(), s.reasons.any { it.startsWith("(thông tin)") })
    }

    @Test
    fun `U24c user stop within 60 s of the planned end is not early`() {
        val fixes = defaultFixes().filter { it <= end - 30 }
        val s = analyzeRun(s1Run(label = "B", fixes = fixes, alarmAtEnd = false, stop = end - 30 to "user"))
        assertFalse(s.stoppedEarly)
        assertFalse(s.invalidRun)
    }

    @Test
    fun `U24d reinstall during an A run is invalid and counted as pkg_replaced`() {
        val extra = listOf(
            ev(20_000, "proc_start", "importance" to 125, pid = 300),
            ev(20_000, "svc_start_cmd", "src" to "pkg_replaced", "flags" to 0, "startId" to 1, pid = 300),
        )
        val s = analyzeRun(s1Run(extra = extra))
        assertEquals(1, s.restartsBySrc["pkg_replaced"])
        assertNull(s.restartsBySrc["boot"])
        assertTrue(s.invalidRun)
        assertEquals(Verdict.WARN, s.verdict)
        assertFalse(s.countsForGo)
        assertTrue(RunAnalyzer.render(s).contains("LƯỢT KHÔNG HỢP LỆ — chạy lại"))
    }

    @Test
    fun `U24d2 the death caused by the reinstall and its gap are not counted`() {
        val tPkg = 20_000L
        val fixes = defaultFixes().filterNot { it in 19_441L until 20_440L }.toMutableList().apply {
            add(20_440L)
            sort()
        }
        val extra = listOf(
            ev(tPkg, "proc_start", "importance" to 125, pid = 300),
            ev(tPkg, "exit_info", "reason" to 16, "exitTs" to epochMs((tPkg - 5).toDouble()), pid = 300),
            ev(tPkg, "svc_start_cmd", "src" to "pkg_replaced", "flags" to 0, "startId" to 1, pid = 300),
        )
        val s = analyzeRun(s1Run(fixes = fixes, extra = extra))
        assertTrue(s.exits.single().causedByReinstall)
        val gap = s.gapsOverPass.single()
        assertEquals(1_000L, gap.lengthS)
        assertTrue(gap.excluded)
        assertTrue(s.invalidRun)
        assertEquals(Verdict.WARN, s.verdict)
        assertFalse(s.countsForGo)
    }

    // ---- alarm interrupted (U26, U27) ----

    /** S1 A run, alarm sound at T = 36 001.5; the process dies at T + exitAfterS and restarts at T + restartAfterS. */
    private fun u26Events(exitAfterS: Long, withExit: Boolean, restartAfterS: Long = 40): List<ProbeEvent> {
        val soundT = 36_001.5
        val alarm = listOf(
            ev(36_000.5, "alarm_trigger", "src" to "fix", "planned" to iso(36_000.0), "lateMs" to 500),
            ev(soundT, "alarm_sound_start", "ok" to true, "focus" to "granted", "alarmVol" to 5, "alarmVolMax" to 7),
            ev(36_001.7, "alarm_notif_posted", "fsiAllowed" to true, "notifEnabled" to true, "chAlarmImp" to 4),
            ev(36_003.0, "alarm_ui_shown", "keyguardLocked" to true, "interactive" to true),
        )
        val restartT = soundT + restartAfterS
        val extra = buildList {
            add(ev(restartT, "proc_start", "importance" to 125, pid = 200))
            if (withExit) {
                add(ev(restartT, "exit_info", "reason" to 13, "exitTs" to epochMs(soundT + exitAfterS), pid = 200))
            }
            add(ev(restartT, "svc_start_cmd", "src" to "sticky", "flags" to 0, "startId" to 1, pid = 200))
            add(ev(restartT, "alarm_error", "step" to "interrupted", "ex" to "restart_after_fire", pid = 200))
        }
        return s1Run(alarm = alarm, extra = extra, stop = (restartT + 1).toLong() to "auto")
    }

    @Test
    fun `U26 alarm interrupted after 20 s fails and the exit belongs to the run`() {
        val s = analyzeRun(u26Events(exitAfterS = 20, withExit = true))
        val a = s.alarm!!
        assertTrue(a.interrupted)
        assertEquals(20L, a.ringS)
        assertFalse(a.ringSUpperBound)
        assertEquals(Verdict.FAIL, s.verdict)
        assertTrue(s.reasons.toString(), s.reasons.any { it.contains("báo thức bị ngắt sau 20 s") })
        assertEquals("alarm", s.exits.single().phase)
    }

    @Test
    fun `U27 alarm interrupted after 150 s warns`() {
        val s = analyzeRun(u26Events(exitAfterS = 150, withExit = true, restartAfterS = 160))
        assertTrue(s.alarm!!.interrupted)
        assertEquals(150L, s.alarm!!.ringS)
        assertEquals(Verdict.WARN, s.verdict)
        assertTrue(s.reasons.toString(), s.reasons.any { it.contains("báo thức bị ngắt sau 150 s") })
    }

    @Test
    fun `U27b without exit_info the next proc_start gives an upper bound`() {
        val s = analyzeRun(u26Events(exitAfterS = 0, withExit = false, restartAfterS = 150))
        assertTrue(s.alarm!!.interrupted)
        assertEquals(150L, s.alarm!!.ringS)
        assertTrue(s.alarm!!.ringSUpperBound)
        assertEquals(Verdict.WARN, s.verdict)
        assertTrue(RunAnalyzer.render(s).contains("≤ 150 s"))
    }

    // ---- invalid runs that FAIL still count (U30, R2-4) ----

    @Test
    fun `U30a a B run stopped early after an unrecovered death is FAIL and counts`() {
        val fixes = defaultFixes().filter { it <= 7_200L }
        val extra = listOf(
            ev(10_790, "proc_start", "importance" to 100, pid = 200),
            ev(10_790, "exit_info", "reason" to 13, "exitTs" to epochMs(7_200.0), pid = 200),
        )
        val s = analyzeRun(s1Run(label = "B", fixes = fixes, noSwitch = true, extra = extra, stop = 10_800L to "user"))
        assertTrue(s.stoppedEarly)
        assertTrue(s.invalidRun)
        assertEquals(Verdict.FAIL, s.verdict)
        assertTrue(s.countsForGo)
        assertTrue(s.reasons.toString(), s.reasons.any { it.contains("chết không hồi phục") })
        assertTrue(
            s.reasons.toString(),
            s.reasons.contains("(lượt cũng không hợp lệ từ +3:00:00 vì dừng trước kế hoạch; FAIL vẫn tính)"),
        )
        assertFalse(RunAnalyzer.render(s).contains("LƯỢT KHÔNG HỢP LỆ — chạy lại"))
    }

    @Test
    fun `U30b an A run with a slow recovery then charging is FAIL and counts`() {
        val fixes = defaultFixes().filterNot { it in 7_201L until 8_400L }.toMutableList().apply {
            add(8_400L)
            sort()
        }
        val extra = listOf(
            ev(8_340, "proc_start", "importance" to 125, pid = 200),
            ev(8_340, "exit_info", "reason" to 13, "exitTs" to epochMs(7_200.0), pid = 200),
            ev(8_340, "svc_start_cmd", "src" to "sticky", "flags" to 0, "startId" to 1, pid = 200),
        )
        val battery = listOf(ev(1, "battery", "lvl" to 96, "chg" to false), ev(21_600, "battery", "lvl" to 90, "chg" to true))
        val s = analyzeRun(s1Run(fixes = fixes, extra = extra, battery = battery))
        assertEquals(1_200L, s.exits.single().recoveryS)
        assertTrue(s.invalidRun)
        assertEquals(epochMs(21_600.0), s.invalidSinceWallMs)
        assertEquals(Verdict.FAIL, s.verdict)
        assertTrue(s.countsForGo)
    }

    // ---- restart via=start: blind time after B is dense (U31, R2-5) ----

    @Test
    fun `U31 switch via start measures the dense phase from the boundary`() {
        val fixes = defaultFixes().filter { it <= boundary - 180 }.toMutableList()
        var t = boundary + 485
        while (t <= end) {
            fixes += t
            t += 10
        }
        val switch = ev(
            (boundary + 480).toDouble(), "phase_switch", "from" to "sparse", "to" to "dense",
            "boundary" to iso(boundary.toDouble()), "lateMs" to 480_000, "via" to "start", pid = 200,
        )
        val extra = listOf(
            ev(boundary + 480, "proc_start", "importance" to 125, pid = 200),
            ev(boundary + 480, "exit_info", "reason" to 13, "exitTs" to epochMs((boundary - 180).toDouble()), pid = 200),
            ev(boundary + 480, "svc_start_cmd", "src" to "watchdog", "flags" to 0, "startId" to 1, pid = 200),
        )
        val s = analyzeRun(s1Run(fixes = fixes, switch = switch, extra = extra))
        val dense = s.gapsOverPass.single { it.phase == "dense" }
        assertEquals(epochMs(boundary.toDouble()), dense.startWallMs) // denseStart = B
        assertEquals(485L, dense.lengthS)
        assertEquals(Verdict.FAIL, dense.level)
        assertEquals("sparse", s.exits.single().phase)
        assertEquals(665L, s.exits.single().recoveryS)
        assertEquals(480L, s.phaseSwitchDelayS)
        assertEquals("start", s.phaseSwitchVia)
        assertEquals(Verdict.FAIL, s.verdict)
    }

    // ---- phase_switch slightly before B in wall clock (U32, R2-7) ----

    @Test
    fun `U32 phase switch 3 s before the boundary in wall clock is still the switch`() {
        val switch = ev(
            (boundary - 3).toDouble(), "phase_switch", "from" to "sparse", "to" to "dense",
            "boundary" to iso(boundary.toDouble()), "lateMs" to 0, "via" to "alarm",
        )
        val s = analyzeRun(s1Run(switch = switch))
        assertFalse(s.phaseSwitchMissing)
        assertEquals(0L, s.phaseSwitchDelayS)
        assertEquals(Verdict.PASS, s.verdict)
        assertEquals(10L, s.fixGapMaxS["dense"])
    }

    // ---- active run vs overdue alarm (U33, R2-8) ----

    private fun u33Events() = s1Run(noAlarm = true, stop = null)

    @Test
    fun `U33a active run within the alarm grace is still running`() {
        val s = analyzeRun(u33Events(), active = true, nowMs = epochMs(end + 30.0))
        assertTrue(s.stillRunning)
        assertTrue(s.reasons.none { it.contains("không kích hoạt") || it.contains("ngoài ý muốn") })
        assertEquals(Verdict.PASS, s.verdict)
        assertTrue(RunAnalyzer.render(s).contains("Kết thúc: đang chạy"))
    }

    @Test
    fun `U33b active run past the alarm grace without a trigger fails`() {
        val s = analyzeRun(u33Events(), active = true, nowMs = epochMs(end + 180.0))
        assertFalse(s.stillRunning)
        assertEquals(Verdict.FAIL, s.verdict)
        assertTrue(s.reasons.toString(), s.reasons.any { it.contains("báo thức không kích hoạt") })
        assertTrue(s.reasons.none { it.contains("chưa đánh giá") })
    }

    @Test
    fun `U33c ended run without run_stop and without a trigger fails twice`() {
        val s = analyzeRun(u33Events(), active = false, nowMs = epochMs(end + 180.0))
        assertFalse(s.stillRunning)
        assertEquals(Verdict.FAIL, s.verdict)
        assertTrue(s.reasons.toString(), s.reasons.any { it.contains("báo thức không kích hoạt") })
        assertTrue(s.reasons.toString(), s.reasons.any { it.contains("dừng ngoài ý muốn") })
    }

    // ---- restart sources (U34, R2-9) ----

    @Test
    fun `U34 restart sources are counted separately`() {
        val phase = analyzeRun(u07Events(src = "phase_alarm"))
        assertEquals(1, phase.restartsBySrc["phase_alarm"])
        assertNull(phase.restartsBySrc["watchdog"])
        assertEquals("phase_alarm", phase.exits.single().restartSrc)
        val fallback = analyzeRun(u07Events(src = "alarm_fallback"))
        assertEquals(1, fallback.restartsBySrc["alarm_fallback"])
        assertNull(fallback.restartsBySrc["watchdog"])
    }

    // ---- S2 dismissal / interruption (U28, U29) ----

    /** S2-1 run with the alarm ringing from pid 100 at T = 121.5 s (trigger 120.5 s). */
    private fun s2Ringing(after: List<ProbeEvent>): List<ProbeEvent> {
        seq = 0
        val out = ArrayList<ProbeEvent>()
        out += ev(
            0, "run_start",
            "kind" to "S2", "label" to "S2-1", "durationMin" to 2, "densePhaseMin" to 2, "alarmAtEnd" to true,
            "watchdog" to true, "delayMin" to 2, "scenario" to "S2-1", "manufacturer" to "Xiaomi",
            "model" to "Redmi Note 13", "sdk" to 34, "release" to "14",
        )
        out += ev(0, "alarm_scheduled", "deadline" to iso(120.0), "fallbackExact" to true)
        out += ev(0.2, "phase_switch", "from" to "sparse", "to" to "dense", "boundary" to iso(0.0), "lateMs" to 0, "via" to "start")
        for (s in 0L..120L step 10) out += ev(s, "fix", "acc" to 8.0)
        out += ev(120.5, "alarm_trigger", "src" to "fix", "planned" to iso(120.0), "lateMs" to 500)
        out += ev(TS, "alarm_sound_start", "ok" to true, "focus" to "granted", "alarmVol" to 5, "alarmVolMax" to 7)
        out += ev(TS + 0.2, "alarm_notif_posted", "fsiAllowed" to true, "notifEnabled" to true, "chAlarmImp" to 4)
        out += ev(TS + 1, "alarm_ui_shown", "keyguardLocked" to true, "interactive" to true)
        out += after
        return out
    }

    private val TS = 121.5

    @Test
    fun `U28 exit_info written after run_stop still counts and gives the ring time`() {
        val events = s2Ringing(
            listOf(
                ev(TS + 55, "proc_start", "importance" to 125, pid = 200),
                ev(TS + 64.9, "alarm_error", "step" to "interrupted", "ex" to "restart_after_fire", pid = 200),
                ev(TS + 65, "run_stop", "by" to "auto", pid = 200),
                ev(TS + 65.05, "exit_info", "reason" to 13, "exitTs" to epochMs(TS + 10), pid = 200),
            ),
        )
        val s = analyzeRun(events)
        assertEquals(1, s.exits.size)
        assertTrue(s.alarm!!.interrupted)
        assertEquals(10L, s.alarm!!.ringS)
        assertFalse(s.alarm!!.ringSUpperBound)
        assertEquals(Verdict.FAIL, s.verdict)
        assertTrue(s.reasons.toString(), s.reasons.any { it.contains("báo thức bị ngắt sau 10 s") })
    }

    @Test
    fun `U29a run_stop by user from a new pid is not a dismissal`() {
        val events = s2Ringing(
            listOf(
                ev(TS + 300, "proc_start", "importance" to 100, pid = 200),
                ev(TS + 300.1, "exit_info", "reason" to 10, "exitTs" to epochMs(TS + 3), pid = 200),
                ev(TS + 360, "run_stop", "by" to "user", pid = 200),
            ),
        )
        val s = analyzeRun(events)
        assertTrue(s.alarm!!.interrupted)
        assertEquals(3L, s.alarm!!.ringS)
        assertEquals(Verdict.FAIL, s.verdict)
    }

    @Test
    fun `U29b user_stop dismissal from the ringing pid is valid`() {
        val events = s2Ringing(
            listOf(
                ev(TS + 90, "alarm_dismissed", "by" to "user_stop", "afterMs" to 90_000),
                ev(TS + 90.1, "run_stop", "by" to "user"),
            ),
        )
        val s = analyzeRun(events)
        val a = s.alarm!!
        assertFalse(a.interrupted)
        assertEquals("user_stop", a.dismissedBy)
        assertEquals(90L, a.ringS)
        assertEquals(Verdict.PASS, s.verdict)
    }

    @Test
    fun `U29c a dismissal after a death of the ringing process is not valid`() {
        val events = s2Ringing(
            listOf(
                ev(TS + 90, "alarm_dismissed", "by" to "user_stop", "afterMs" to 90_000),
                ev(TS + 90.1, "run_stop", "by" to "user"),
                ev(TS + 100, "exit_info", "reason" to 13, "exitTs" to epochMs(TS + 40), pid = 200),
            ),
        )
        val s = analyzeRun(events)
        assertTrue(s.alarm!!.interrupted)
        assertEquals(40L, s.alarm!!.ringS)
        assertEquals(Verdict.FAIL, s.verdict)
    }

    // ---- S2 tests ----

    @Test
    fun `U15 S2 alarm on time with UI passes`() {
        val s = analyzeRun(s2Run())
        val a = s.alarm!!
        assertEquals(8L, a.lateS)
        assertTrue(a.uiShown)
        assertEquals(true, a.uiOnLockscreen)
        assertEquals(42L, a.dismissAfterS)
        assertEquals("activity", a.dismissedBy)
        assertFalse(a.interrupted)
        assertEquals(Verdict.PASS, s.verdict)
        assertEquals(setOf("dense"), s.fixCount.keys)
        assertNull(s.phaseSwitchDelayS)
    }

    @Test
    fun `U16 fallback trigger warns`() {
        val s = analyzeRun(s2Run(triggerSrc = "fallback", lateMs = 61_000))
        assertEquals(Verdict.WARN, s.verdict)
        assertTrue(s.reasons.toString(), s.reasons.any { it.contains("kích hoạt bằng dự phòng") })
        assertEquals("fallback", s.alarm!!.src)
    }

    @Test
    fun `U17 no trigger after the deadline fails`() {
        val s = analyzeRun(s2Run(triggerSrc = null, stop = 200L to "user"))
        assertEquals(Verdict.FAIL, s.verdict)
        assertTrue(s.reasons.toString(), s.reasons.any { it.contains("không kích hoạt") })
        assertNull(s.alarm!!.triggeredWall)
    }

    @Test
    fun `U18 sound not playing fails`() {
        val s = analyzeRun(s2Run(soundOk = false))
        assertEquals(Verdict.FAIL, s.verdict)
    }

    @Test
    fun `U19 notification error with sound OK and no UI warns`() {
        val s = analyzeRun(s2Run(uiShown = false, notifPosted = false, errors = listOf("notif")))
        assertEquals(Verdict.WARN, s.verdict)
        assertEquals(listOf("notif"), s.alarm!!.errors)
    }

    @Test
    fun `U25 notification posted but not visible does not count as UI`() {
        val disabled = analyzeRun(s2Run(uiShown = false, notifEnabled = false, chAlarmImp = 4))
        assertTrue(disabled.alarm!!.notifPosted)
        assertFalse(disabled.alarm!!.notifVisible)
        assertEquals(Verdict.WARN, disabled.verdict)
        assertTrue(disabled.reasons.toString(), disabled.reasons.any { it.contains("không có màn báo thức/thông báo") })

        val lowChannel = analyzeRun(s2Run(uiShown = false, notifEnabled = true, chAlarmImp = 2))
        assertFalse(lowChannel.alarm!!.notifVisible)
        assertEquals(Verdict.WARN, lowChannel.verdict)

        val visible = analyzeRun(s2Run(uiShown = false, notifEnabled = true, chAlarmImp = null))
        assertTrue(visible.alarm!!.notifVisible)
        assertEquals(Verdict.PASS, visible.verdict)
    }

    @Test
    fun `S2 stopped by the user before the deadline is not evaluated`() {
        val s = analyzeRun(s2Run(triggerSrc = null, stop = 60L to "user"))
        assertEquals(Verdict.WARN, s.verdict)
    }

    @Test
    fun `duration formatting`() {
        assertEquals("41 s", RunAnalyzer.fmtDur(41))
        assertEquals("6 ph 12 s", RunAnalyzer.fmtDur(372))
        assertEquals("2 ph 05 s", RunAnalyzer.fmtDur(125))
        assertEquals("1 giờ 02 ph 05 s", RunAnalyzer.fmtDur(3_725))
        assertEquals("10:00:00", RunAnalyzer.fmtHms(36_000))
        assertEquals("0:00:00", RunAnalyzer.fmtHms(-5))
    }
}
