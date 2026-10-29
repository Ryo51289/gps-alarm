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
 * U03–U50 (docs/spikes/S1.md §7.1 + "Vòng 4" V4-8, docs/spikes/S2.md §5.5 + "Vòng 4" V4-3 + "Vòng 5" V5-7 + "Vòng 5b").
 * Times are seconds after run start.
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
        ev(36_000.6, "perm_snapshot", "zen" to 1, "ringer" to 0, "alarmVol" to 5, "alarmVolMax" to 7),
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
        fixAgeMs: Long? = 5,
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
        fixes.forEach {
            out += if (fixAgeMs == null) {
                ev(it, "fix", "acc" to 12.0, "spd" to null, "prov" to "fused", "dM" to 3.0)
            } else {
                ev(it, "fix", "acc" to 12.0, "spd" to null, "prov" to "fused", "ageMs" to fixAgeMs, "dM" to 3.0)
            }
        }
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
        vibrate: Boolean = false,
        soundFields: Map<String, Any?>? = null, // replaces every alarm_sound_start field except ok
        snapshot: Map<String, Any?>? = null, // perm_snapshot right after the trigger
        dismissBy: String = "activity",
        dismissAfterMs: Long = 42_000,
        sdk: Int = 35,
    ): List<ProbeEvent> {
        seq = 0
        val out = ArrayList<ProbeEvent>()
        out += ev(
            0, "run_start",
            "kind" to "S2", "label" to "S2-1", "durationMin" to 2, "densePhaseMin" to 2, "alarmAtEnd" to true,
            "watchdog" to true, "delayMin" to 2, "scenario" to "S2-1", "manufacturer" to "samsung",
            "model" to "SM-A546E", "sdk" to sdk, "release" to "15",
        )
        out += ev(0, "alarm_scheduled", "deadline" to iso(120.0), "fallbackExact" to true)
        out += ev(0.2, "phase_switch", "from" to "sparse", "to" to "dense", "boundary" to iso(0.0), "lateMs" to 0, "via" to "start")
        for (s in 0L..130L step 10) out += ev(s, "fix", "acc" to 8.0)
        if (triggerSrc != null) {
            val trig = 120.0 + lateMs / 1000.0
            out += ev(trig, "alarm_trigger", "src" to triggerSrc, "planned" to iso(120.0), "lateMs" to lateMs)
            snapshot?.let { out += ev(trig + 0.1, "perm_snapshot", *it.toList().toTypedArray()) }
            val sound = linkedMapOf<String, Any?>("ok" to soundOk)
            sound.putAll(soundFields ?: mapOf("focus" to "granted", "alarmVol" to 5, "alarmVolMax" to 7))
            out += ev(trig + 1, "alarm_sound_start", *sound.toList().toTypedArray())
            if (vibrate) out += ev(trig + 1.05, "alarm_vibrate", "ok" to true, "hasVibrator" to true)
            errors.forEach { out += ev(trig + 1.1, "alarm_error", "step" to it, "ex" to "java.lang.SecurityException") }
            if (notifPosted) {
                out += ev(
                    trig + 1.2, "alarm_notif_posted", "fsiAllowed" to true, "notifEnabled" to notifEnabled,
                    "chAlarmImp" to chAlarmImp,
                )
            }
            if (uiShown) out += ev(trig + 2, "alarm_ui_shown", "keyguardLocked" to true, "interactive" to true)
            out += ev(trig + 42, "alarm_dismissed", "by" to dismissBy, "afterMs" to dismissAfterMs)
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

    // ---- Vòng 4: audible alarm and DND (U35, S2 V4-2) ----

    @Test
    fun `U35a DND total silence with a playing player fails as not audible`() {
        val events = s2Run(
            uiShown = false,
            chAlarmImp = 4,
            vibrate = true,
            soundFields = mapOf("focus" to "granted", "alarmVol" to 0, "alarmVolMax" to 7, "muted" to true),
            snapshot = mapOf("zen" to 3, "ringer" to 0),
            dismissBy = "user_stop",
            stop = 170L to "user",
        )
        val s = analyzeRun(events)
        val a = s.alarm!!
        assertEquals(Verdict.FAIL, s.verdict)
        assertTrue(a.soundOk)
        assertFalse(a.audible)
        assertEquals(
            listOf("luồng báo thức bị tắt tiếng", "âm lượng báo thức 0", "Không làm phiền: hoàn toàn tắt tiếng"),
            a.silencedBy,
        )
        assertEquals(VibrationEvidence.BLOCKED, a.vibration)
        assertFalse(a.notifVisible)
        assertEquals(listOf("Không làm phiền chặn"), a.notifHiddenBy)
        assertTrue(s.reasons.toString(), s.reasons.any { it.startsWith("không nghe được:") })
        val text = RunAnalyzer.render(s)
        assertTrue(text, text.contains("TẮT TIẾNG"))
        assertTrue(text, text.contains("rung: bị Không làm phiền chặn"))
        assertTrue(text, text.contains("đủ điều kiện hiện: không"))
        assertFalse(text, text.contains("âm thanh OK"))
        assertFalse(text, text.contains("rung OK"))
        assertFalse(text, text.contains("hiện được: có"))
    }

    @Test
    fun `U35b DND priority whose applied policy blocks alarms fails`() {
        val s = analyzeRun(
            s2Run(
                vibrate = true,
                uiShown = false,
                soundFields = mapOf(
                    "focus" to "granted", "alarmVol" to 6, "alarmVolMax" to 7, "muted" to false, "zen" to 2,
                    "zenAlarms" to false, "zenAlarmsActive" to false,
                ),
            ),
        )
        val a = s.alarm!!
        assertEquals(Verdict.FAIL, s.verdict)
        assertTrue(s.reasons.toString(), s.reasons.contains("không nghe được: Không làm phiền chặn báo thức"))
        assertTrue(
            s.reasons.toString(),
            s.reasons.contains(
                "(thông tin) luồng báo thức không bị tắt tiếng dù Không làm phiền chặn báo thức, đối chiếu biên bản nghe",
            ),
        )
        assertFalse(a.notifVisible)
        assertEquals(listOf("Không làm phiền chặn"), a.notifHiddenBy)
        assertEquals(VibrationEvidence.BLOCKED, a.vibration)
        val text = RunAnalyzer.render(s)
        assertTrue(text, text.contains("DND PRIORITY (báo thức: chặn)"))
    }

    @Test
    fun `U35c DND priority that allows alarms passes`() {
        val s = analyzeRun(
            s2Run(
                vibrate = true,
                soundFields = mapOf(
                    "focus" to "granted", "alarmVol" to 6, "alarmVolMax" to 7, "muted" to false, "zen" to 2,
                    "zenAlarms" to true, "zenAlarmsActive" to true,
                ),
            ),
        )
        val a = s.alarm!!
        assertEquals(Verdict.PASS, s.verdict)
        assertTrue(a.audible)
        assertEquals(VibrationEvidence.REQUESTED, a.vibration)
        val text = RunAnalyzer.render(s)
        assertTrue(text, text.contains("rung: đã yêu cầu (không xác minh được)"))
        assertTrue(text, text.contains("DND PRIORITY (báo thức: cho phép)"))
        assertTrue(text, text.contains("âm thanh: đang phát (âm lượng 6/7, focus granted)"))
    }

    @Test
    fun `U35d DND alarms only passes`() {
        val s = analyzeRun(
            s2Run(soundFields = mapOf("focus" to "granted", "alarmVol" to 6, "alarmVolMax" to 7, "muted" to false, "zen" to 4)),
        )
        assertEquals(Verdict.PASS, s.verdict)
        assertTrue(s.alarm!!.audible)
    }

    @Test
    fun `U35e old log without the new fields still passes`() {
        val s = analyzeRun(s2Run(soundFields = mapOf("focus" to "granted"), snapshot = mapOf("zen" to 1, "ringer" to 2)))
        assertEquals(Verdict.PASS, s.verdict)
        assertTrue(s.alarm!!.silencedBy.isEmpty())
        assertTrue(s.alarm!!.audible)
    }

    @Test
    fun `U35f S1 run with a muted alarm stream fails`() {
        val alarm = alarmEvents().map {
            if (it.ev != "alarm_sound_start") {
                it
            } else {
                ev(
                    36_001.5, "alarm_sound_start", "ok" to true, "focus" to "granted", "alarmVol" to 0, "alarmVolMax" to 7,
                    "muted" to true,
                )
            }
        }
        val s = analyzeRun(s1Run(alarm = alarm))
        assertEquals(Verdict.FAIL, s.verdict)
        assertTrue(
            s.reasons.toString(),
            s.reasons.contains("không nghe được: luồng báo thức bị tắt tiếng, âm lượng báo thức 0"),
        )
    }

    // ---- Vòng 4: stale fixes (U36, S1 V4-3) ----

    /** X run, fresh fixes up to 3:00:00, death at 3:01:00, sticky restart at 3:01:02 (pid 200); [after] from 3:01:03. */
    private fun u36Events(after: List<ProbeEvent>, fixes: List<Long>, stop: Pair<Long, String>, label: String): List<ProbeEvent> {
        val extra = buildList {
            add(ev(10_862, "proc_start", "importance" to 125, pid = 200))
            add(
                ev(
                    10_862, "exit_info", "reason" to 2, "reasonName" to "REASON_SIGNALED", "exitTs" to epochMs(10_860.0),
                    pid = 200,
                ),
            )
            add(ev(10_862, "svc_start_cmd", "src" to "sticky", "flags" to 0, "startId" to 1, pid = 200))
            add(ev(10_862, "svc_fg_ok", pid = 200))
            addAll(after)
        }
        return s1Run(
            label = label,
            fixes = fixes,
            noSwitch = label == "X",
            alarmAtEnd = label != "X",
            stop = stop,
            extra = extra,
        )
    }

    @Test
    fun `U36a a cached fix after the restart is not a recovery`() {
        val events = u36Events(
            after = listOf(
                ev(10_863, "fix", "acc" to 20.0, "prov" to "fused", "ageMs" to 84_873, pid = 200),
                ev(10_864, "svc_destroy", pid = 200),
            ),
            fixes = defaultFixes().filter { it <= 10_800L },
            stop = 12_600L to "user",
            label = "X",
        )
        val s = analyzeRun(events)
        assertNull(s.exits.single().recoveryS)
        assertTrue(s.reasons.toString(), s.reasons.any { it.contains("process chết không hồi phục") })
        assertEquals(1, s.staleFixes)
        val text = RunAnalyzer.render(s)
        assertTrue(text, text.contains("· không hồi phục"))
        assertFalse(text, text.contains("có vị trí lại sau"))
        assertTrue(text, text.contains(" · bỏ qua 1 vị trí cũ"))
    }

    @Test
    fun `U36b a cached fix next to a fresh one does not change the recovery`() {
        val events = u36Events(
            after = listOf(
                ev(10_863, "fix", "acc" to 20.0, "prov" to "fused", "ageMs" to 130_589, pid = 200),
                ev(10_863, "fix", "acc" to 8.0, "prov" to "fused", "ageMs" to 3, pid = 200),
            ),
            fixes = defaultFixes(),
            stop = 36_042L to "alarm_dismissed",
            label = "A",
        )
        val s = analyzeRun(events)
        assertEquals(3L, s.exits.single().recoveryS)
        assertEquals(1, s.staleFixes)
        assertTrue(s.reasons.toString(), s.reasons.contains("(thông tin) bỏ qua 1 vị trí cũ (tuổi > 60 s)"))
    }

    @Test
    fun `U36c fixes without ageMs are fresh`() {
        val withAge = analyzeRun(s1Run())
        val s = analyzeRun(s1Run(fixAgeMs = null))
        assertEquals(withAge, s)
        assertEquals(Verdict.PASS, s.verdict)
        assertEquals(0, s.staleFixes)
    }

    @Test
    fun `U36d a cached fix inside a dense gap does not split it`() {
        val fixes = defaultFixes().filterNot { it in 33_010L..33_190L }
        val stale = listOf(ev(33_100, "fix", "acc" to 20.0, "prov" to "fused", "ageMs" to 120_000))
        val s = analyzeRun(s1Run(fixes = fixes, extra = stale))
        assertEquals(200L, s.fixGapMaxS["dense"])
        val gap = s.gapsOverPass.single()
        assertEquals(200L, gap.lengthS)
        assertEquals(Verdict.FAIL, gap.level)
        assertEquals(Verdict.FAIL, s.verdict)
        assertEquals(1, s.staleFixes)
    }

    // ---- Vòng 4: restart labels (U37, S1 V4-4) ----

    /** R2-2 shape: force-stopped while ringing (exit at T = TS + 3), the user opens the app 30 s later. */
    private fun u37Events(watchdogAfterS: Long? = null): List<ProbeEvent> {
        val exitT = TS + 3
        val after = buildList {
            add(ev(exitT + 30, "proc_start", "importance" to 100, pid = 200))
            add(
                ev(
                    exitT + 30, "exit_info", "reason" to 10, "reasonName" to "REASON_USER_REQUESTED",
                    "exitTs" to epochMs(exitT), "desc" to "[FORCE STOP]", pid = 200,
                ),
            )
            if (watchdogAfterS != null) {
                add(ev(exitT + watchdogAfterS, "svc_start_cmd", "src" to "watchdog", "flags" to 0, "startId" to 1, pid = 200))
            }
            add(ev(exitT + (watchdogAfterS ?: 0L) + 60, "run_stop", "by" to "user", pid = 200))
        }
        return s2Ringing(after)
    }

    @Test
    fun `U37a a new process opened by the user is not a restart`() {
        val s = analyzeRun(u37Events())
        val e = s.exits.single()
        assertEquals("app_opened", e.restartSrc)
        assertEquals(30L, e.restartS)
        val text = RunAnalyzer.render(s)
        assertTrue(text, text.contains("không tự khởi động lại (process mới do mở app sau 30 s)"))
        assertFalse(text, text.contains("(?)"))
    }

    @Test
    fun `U37b a sticky restart keeps its source and delay`() {
        val e = analyzeRun(u07Events()).exits.single()
        assertEquals(90L, e.restartS)
        assertEquals("sticky", e.restartSrc)
    }

    @Test
    fun `U37c a background process without a service start is process_only`() {
        val fixes = defaultFixes().apply {
            remove(10_980L)
            add(10_985L)
            sort()
        }
        val extra = listOf(
            ev(10_905, "proc_start", "importance" to 400, pid = 200),
            ev(10_905, "exit_info", "reason" to 13, "exitTs" to epochMs(10_860.0), pid = 200),
        )
        val s = analyzeRun(s1Run(fixes = fixes, extra = extra))
        val e = s.exits.single()
        assertEquals("process_only", e.restartSrc)
        assertEquals(45L, e.restartS)
        val text = RunAnalyzer.render(s)
        assertTrue(text, text.contains("process chạy lại sau 45 s nhưng service không khởi động"))
    }

    @Test
    fun `U37d a later service start wins over the opened app`() {
        val e = analyzeRun(u37Events(watchdogAfterS = 900L)).exits.single()
        assertEquals("watchdog", e.restartSrc)
        assertEquals(900L, e.restartS)
    }

    // ---- Vòng 4: fallback alarm from AlarmRingService (U38, S2 V4-1) ----

    /**
     * S2-11: fixes every 10 s, "Tắt service (giữ lượt)" at +20 s, fallback at deadline + 60.1 s from AlarmRingService
     * (same pid). [ringFg]: (type, ok, ex) of each alarm_ring_fg; [sound]: alarm_sound_start ok=true and the alarm screen.
     */
    private fun u38Events(ringFg: List<Triple<String, Boolean, String?>>, sound: Boolean = true): List<ProbeEvent> {
        seq = 0
        val out = ArrayList<ProbeEvent>()
        out += ev(
            0, "run_start",
            "kind" to "S2", "label" to "S2-11", "durationMin" to 2, "densePhaseMin" to 2, "alarmAtEnd" to true,
            "watchdog" to true, "delayMin" to 2, "scenario" to "S2-11", "manufacturer" to "Google",
            "model" to "sdk_gphone64_x86_64", "sdk" to 34, "release" to "14",
        )
        out += ev(0, "alarm_scheduled", "deadline" to iso(120.0), "fallbackExact" to true)
        out += ev(0.2, "phase_switch", "from" to "sparse", "to" to "dense", "boundary" to iso(0.0), "lateMs" to 0, "via" to "start")
        for (s in 0L..20L step 10) out += ev(s, "fix", "acc" to 8.0, "ageMs" to 50)
        out += ev(20.0, "svc_cmd", "action" to "sim_kill", "startId" to 3)
        out += ev(20.1, "svc_destroy")
        val trig = 180.1
        for ((type, ok, ex) in ringFg) {
            out += if (ok) {
                ev(trig, "alarm_ring_fg", "type" to type, "ok" to true)
            } else {
                ev(trig, "alarm_ring_fg", "type" to type, "ok" to false, "ex" to ex, "msg" to "not allowed")
            }
        }
        out += ev(
            trig, "alarm_trigger", "src" to "fallback", "svc" to "ring", "planned" to iso(120.0), "lateMs" to 60_100,
            "interactive" to false, "keyguardLocked" to true, "idle" to false,
        )
        out += ev(trig, "perm_snapshot", "zen" to 2, "ringer" to 0)
        if (ringFg.none { it.second }) {
            out += ev(trig + 0.1, "alarm_error", "step" to "ring_fg", "ex" to ringFg.lastOrNull()?.third)
            out += ev(trig + 0.2, "alarm_notif_posted", "fsiAllowed" to true, "notifEnabled" to true, "chAlarmImp" to 4)
            out += ev(400, "run_stop", "by" to "user")
            return out
        }
        out += ev(trig + 0.1, "alarm_vibrate", "ok" to true, "hasVibrator" to true)
        out += ev(trig + 0.2, "alarm_notif_posted", "fsiAllowed" to true, "notifEnabled" to true, "chAlarmImp" to 4)
        if (sound) {
            out += ev(
                trig + 1, "alarm_sound_start", "ok" to true, "focus" to "granted", "alarmVol" to 6, "alarmVolMax" to 7,
                "muted" to false, "zen" to 2, "zenAlarms" to true,
            )
            out += ev(trig + 1.5, "alarm_ui_shown", "keyguardLocked" to true, "interactive" to true, "viaFsi" to true)
        }
        out += ev(trig + 31, "alarm_dismissed", "by" to "activity", "afterMs" to 30_000)
        out += ev(trig + 31.1, "run_stop", "by" to "alarm_dismissed")
        return out
    }

    @Test
    fun `U38a fallback from the ring service after the simulated kill warns`() {
        val s = analyzeRun(u38Events(listOf(Triple("systemExempted", true, null))))
        val a = s.alarm!!
        assertEquals(Verdict.WARN, s.verdict)
        assertTrue(s.reasons.toString(), s.reasons.any { it.contains("kích hoạt bằng dự phòng") })
        assertTrue(s.reasons.toString(), s.reasons.any { it.contains("báo thức trễ 60 s") })
        assertTrue(s.reasons.none { it.contains("không kích hoạt") })
        assertEquals("ring", a.ringSvc)
        assertEquals("systemExempted", a.ringFgType)
        assertTrue(a.ringFgFails.isEmpty())
        val text = RunAnalyzer.render(s)
        assertTrue(text, text.contains("nguồn fallback (service báo thức riêng, systemExempted)"))
        assertTrue(text, text.contains("(thông tin) service bị tắt bằng nút giả lập lúc +0:00:20"))
        assertFalse(text, text.contains("FGS báo thức:"))
    }

    @Test
    fun `U38b systemExempted refused then mediaPlayback is recorded`() {
        val s = analyzeRun(
            u38Events(
                listOf(
                    Triple("systemExempted", false, "android.app.ForegroundServiceTypeNotAllowedException"),
                    Triple("mediaPlayback", true, null),
                ),
            ),
        )
        val a = s.alarm!!
        assertEquals("mediaPlayback", a.ringFgType)
        assertEquals(listOf("systemExempted: android.app.ForegroundServiceTypeNotAllowedException"), a.ringFgFails)
        assertEquals(Verdict.WARN, s.verdict)
        val text = RunAnalyzer.render(s)
        assertTrue(text, text.contains("systemExempted lỗi"))
        assertTrue(
            text,
            text.contains("FGS báo thức: mediaPlayback (systemExempted lỗi: ForegroundServiceTypeNotAllowedException)"),
        )
    }

    @Test
    fun `U38c no FGS type works so the fallback is silent and fails`() {
        val s = analyzeRun(
            u38Events(
                listOf(
                    Triple("systemExempted", false, "android.app.ForegroundServiceTypeNotAllowedException"),
                    Triple("mediaPlayback", false, "android.app.ForegroundServiceStartNotAllowedException"),
                ),
            ),
        )
        assertEquals(Verdict.FAIL, s.verdict)
        assertTrue(s.reasons.toString(), s.reasons.any { it.contains("báo thức không phát âm") })
        assertTrue(s.reasons.toString(), s.reasons.any { it.contains("lỗi báo thức ở bước: ring_fg") })
        assertNull(s.alarm!!.ringFgType)
        assertEquals(2, s.alarm!!.ringFgFails.size)
    }

    @Test
    fun `ringSvc defaults to probe for logs without svc`() {
        assertEquals("probe", analyzeRun(s2Run()).alarm!!.ringSvc)
    }

    @Test
    fun `S2 stopped by the user before the deadline is not evaluated`() {
        val s = analyzeRun(s2Run(triggerSrc = null, stop = 60L to "user"))
        assertEquals(Verdict.WARN, s.verdict)
    }

    // ---- Vòng 5: observed evidence beats the default DND policy (U40–U46, S2 V5-1) ----

    private fun dndSound(vararg extra: Pair<String, Any?>): Map<String, Any?> =
        linkedMapOf<String, Any?>("focus" to "granted", "alarmVol" to 6, "alarmVolMax" to 7, "muted" to false, "zen" to 2)
            .apply { putAll(extra) }

    private fun mutedDndSound(vararg extra: Pair<String, Any?>): Map<String, Any?> =
        linkedMapOf<String, Any?>("focus" to "granted", "alarmVol" to 0, "alarmVolMax" to 7, "muted" to true, "zen" to 2)
            .apply { putAll(extra) }

    private val maybeNotAudible = "có thể không nghe được: cài đặt Không làm phiền mặc định chặn báo thức, " +
        "luồng báo thức không bị tắt tiếng (chưa rõ chế độ đang bật)"

    @Test
    fun `U40 a mode that allows alarms beats the blocking default policy`() {
        val s = analyzeRun(s2Run(vibrate = true, soundFields = dndSound("zenAlarms" to false, "zenAlarmsActive" to true)))
        val a = s.alarm!!
        assertEquals(Verdict.PASS, s.verdict)
        assertTrue(a.audible)
        assertTrue(a.silencedBy.isEmpty())
        assertEquals(VibrationEvidence.REQUESTED, a.vibration)
        assertTrue(a.notifVisible)
        assertEquals(true, a.zenAlarmsActive)
        assertTrue(
            s.reasons.toString(),
            s.reasons.contains("(thông tin) cài đặt Không làm phiền mặc định chặn báo thức, chế độ đang bật cho phép"),
        )
        val text = RunAnalyzer.render(s)
        assertTrue(text, text.contains("DND PRIORITY (báo thức: cho phép; mặc định: chặn)"))
        assertTrue(text, text.contains("đủ điều kiện hiện: có (FSI: có)"))
        assertFalse(text, text.contains("TẮT TIẾNG"))
        assertFalse(text, text.contains("rung: bị Không làm phiền chặn"))
        assertFalse(text, text.contains("đủ điều kiện hiện: không"))
        assertFalse(text, text.contains("không nghe được"))
    }

    @Test
    fun `U41 old log with only the blocking default policy and an open stream warns`() {
        val s = analyzeRun(
            s2Run(
                lateMs = 4_545,
                vibrate = true,
                soundFields = dndSound("zenAlarms" to false),
                snapshot = mapOf("zen" to 2, "alarmVol" to 6),
                dismissAfterMs = 24_952,
            ),
        )
        val a = s.alarm!!
        assertEquals(Verdict.WARN, s.verdict)
        assertTrue(s.reasons.toString(), s.reasons.contains(maybeNotAudible))
        assertTrue(s.reasons.toString(), s.reasons.none { it.startsWith("không nghe được") })
        assertTrue(a.audible)
        assertEquals(VibrationEvidence.REQUESTED, a.vibration)
        assertTrue(a.notifVisible)
        val text = RunAnalyzer.render(s)
        assertTrue(text, text.contains("âm thanh: đang phát (âm lượng 6/7, focus granted)"))
        assertTrue(text, text.contains("DND PRIORITY (báo thức mặc định: chặn)"))
        assertTrue(text, text.contains("màn báo thức hiện trên màn khoá: có"))
        assertFalse(text, text.contains("đủ điều kiện hiện: không"))
    }

    @Test
    fun `U42 a blocking default policy confirmed by the muted stream fails, with or without the applied policy`() {
        val variants = listOf(
            "a" to mutedDndSound("zenAlarms" to false),
            "b" to mutedDndSound("zenAlarms" to false, "zenAlarmsActive" to false),
        )
        for ((variant, sound) in variants) {
            val s = analyzeRun(
                s2Run(
                    vibrate = true,
                    uiShown = false,
                    soundFields = sound,
                    dismissBy = "user_stop",
                    stop = 170L to "user",
                ),
            )
            val a = s.alarm!!
            assertEquals(variant, Verdict.FAIL, s.verdict)
            assertTrue(
                s.reasons.toString(),
                s.reasons.contains(
                    "không nghe được: luồng báo thức bị tắt tiếng, âm lượng báo thức 0, Không làm phiền chặn báo thức",
                ),
            )
            assertEquals(variant, VibrationEvidence.BLOCKED, a.vibration)
            assertEquals(variant, listOf("Không làm phiền chặn"), a.notifHiddenBy)
            assertTrue(s.reasons.toString(), s.reasons.none { it.contains("đối chiếu biên bản nghe") })
            val text = RunAnalyzer.render(s)
            val dnd = if (variant == "a") "DND PRIORITY (báo thức mặc định: chặn)" else "DND PRIORITY (báo thức: chặn)"
            assertTrue(text, text.contains(dnd))
        }
    }

    @Test
    fun `U43 a mode that blocks alarms while the default allows them fails`() {
        val s = analyzeRun(
            s2Run(vibrate = true, uiShown = false, soundFields = mutedDndSound("zenAlarms" to true, "zenAlarmsActive" to false)),
        )
        val a = s.alarm!!
        assertEquals(Verdict.FAIL, s.verdict)
        assertEquals(
            listOf("luồng báo thức bị tắt tiếng", "âm lượng báo thức 0", "Không làm phiền chặn báo thức"),
            a.silencedBy,
        )
        assertEquals(VibrationEvidence.BLOCKED, a.vibration)
        val text = RunAnalyzer.render(s)
        assertTrue(text, text.contains("DND PRIORITY (báo thức: chặn; mặc định: cho phép)"))
    }

    @Test
    fun `U44a the alarm screen shown overrides the predicted hidden notification`() {
        val s = analyzeRun(
            s2Run(
                chAlarmImp = 4,
                vibrate = true,
                soundFields = mapOf("focus" to "granted", "alarmVol" to 0, "alarmVolMax" to 7, "muted" to true),
                snapshot = mapOf("zen" to 3, "ringer" to 0),
            ),
        )
        val a = s.alarm!!
        assertEquals(Verdict.FAIL, s.verdict)
        assertEquals(
            listOf("luồng báo thức bị tắt tiếng", "âm lượng báo thức 0", "Không làm phiền: hoàn toàn tắt tiếng"),
            a.silencedBy,
        )
        assertTrue(s.reasons.toString(), s.reasons.any { it.startsWith("không nghe được:") })
        assertEquals(VibrationEvidence.BLOCKED, a.vibration)
        assertTrue(a.notifHiddenBy.isEmpty())
        assertTrue(a.notifVisible)
        assertTrue(
            s.reasons.toString(),
            s.reasons.contains("(thông tin) màn báo thức đã hiện dù dự đoán thông báo bị ẩn (Không làm phiền chặn)"),
        )
        val text = RunAnalyzer.render(s)
        assertTrue(text, text.contains("thông báo: đã gửi, đủ điều kiện hiện: có"))
        assertFalse(text, text.contains("đủ điều kiện hiện: không"))
    }

    @Test
    fun `U44b the alarm screen shown with app notifications off passes`() {
        val s = analyzeRun(s2Run(vibrate = true, notifEnabled = false))
        assertEquals(Verdict.PASS, s.verdict)
        assertTrue(s.alarm!!.notifVisible)
        assertTrue(
            s.reasons.toString(),
            s.reasons.contains("(thông tin) màn báo thức đã hiện dù dự đoán thông báo bị ẩn (thông báo của app đang tắt)"),
        )
    }

    @Test
    fun `U45 old log with the default policy allowing alarms passes`() {
        val s = analyzeRun(s2Run(vibrate = true, soundFields = dndSound("zenAlarms" to true)))
        assertEquals(Verdict.PASS, s.verdict)
        assertTrue(s.reasons.toString(), s.reasons.none { it.contains("có thể không nghe được") })
        val text = RunAnalyzer.render(s)
        assertTrue(text, text.contains("DND PRIORITY (báo thức mặc định: cho phép)"))
    }

    @Test
    fun `U46 an unreadable applied policy warns and names the exception`() {
        val s = analyzeRun(
            s2Run(vibrate = true, soundFields = dndSound("zenAlarms" to false, "zenActiveErr" to "SecurityException")),
        )
        assertEquals(Verdict.WARN, s.verdict)
        assertTrue(s.reasons.toString(), s.reasons.contains(maybeNotAudible))
        assertTrue(
            s.reasons.toString(),
            s.reasons.contains("(thông tin) không đọc được chính sách Không làm phiền đang áp dụng (SecurityException)"),
        )
    }

    // ---- Vòng 5b: an unknown applied policy never passes (U50, S2 V5b-1) ----

    private val activeUnknownWarn = "có thể không nghe được: không đọc được chính sách Không làm phiền đang áp dụng, " +
        "chế độ đang bật có thể chặn báo thức"

    @Test
    fun `U50a an applied policy that fails to read warns even when the default allows alarms`() {
        val s = analyzeRun(
            s2Run(sdk = 34, vibrate = true, soundFields = dndSound("zenAlarms" to true, "zenActiveErr" to "SecurityException")),
        )
        assertEquals(Verdict.WARN, s.verdict)
        assertTrue(s.reasons.toString(), s.reasons.contains(activeUnknownWarn))
        assertTrue(
            s.reasons.toString(),
            s.reasons.contains("(thông tin) không đọc được chính sách Không làm phiền đang áp dụng (SecurityException)"),
        )
        assertTrue(s.alarm!!.audible)
        assertTrue(s.reasons.toString(), s.reasons.none { it.startsWith("không nghe được") })
    }

    @Test
    fun `U50b API 29 without the applied policy warns`() {
        val s = analyzeRun(s2Run(sdk = 29, vibrate = true, soundFields = dndSound("zenAlarms" to true)))
        assertEquals(Verdict.WARN, s.verdict)
        assertTrue(s.reasons.toString(), s.reasons.contains(activeUnknownWarn))
        assertTrue(s.reasons.toString(), s.reasons.none { it.contains("(thông tin) không đọc được") })
    }

    @Test
    fun `U50c API 28 without the applied policy passes`() {
        val s = analyzeRun(s2Run(sdk = 28, vibrate = true, soundFields = dndSound("zenAlarms" to true)))
        assertEquals(s.reasons.toString(), Verdict.PASS, s.verdict)
    }

    @Test
    fun `U50d a log from before round 5 on API 34 still passes`() {
        val s = analyzeRun(s2Run(sdk = 34, vibrate = true, soundFields = dndSound("zenAlarms" to true)))
        assertEquals(s.reasons.toString(), Verdict.PASS, s.verdict)
    }

    @Test
    fun `U50e at most one maybe-not-audible reason per run`() {
        val s = analyzeRun(s2Run(sdk = 29, vibrate = true, soundFields = dndSound("zenAlarms" to false)))
        assertEquals(Verdict.WARN, s.verdict)
        assertEquals(listOf(maybeNotAudible), s.reasons.filter { it.startsWith("có thể không nghe được:") })
    }

    // ---- Vòng 5: gaps after svc_destroy (U47, S2 V5-2) ----

    /** M-FB1 shape: S1 X 18 min (dense 9), one cached fix, service stopped by the button at +37.9 s, fallback at +19:00. */
    private fun u47Events(): List<ProbeEvent> {
        seq = 0
        val out = ArrayList<ProbeEvent>()
        out += ev(
            0, "run_start",
            "run" to "20261029-151900-S1-X",
            "kind" to "S1", "label" to "X", "durationMin" to 18, "densePhaseMin" to 9, "alarmAtEnd" to true,
            "watchdog" to false, "delayMin" to null, "scenario" to null, "manufacturer" to "Google",
            "model" to "sdk_gphone64_x86_64", "sdk" to 34, "release" to "14",
        )
        out += ev(0, "phase_alarm_scheduled", "boundary" to iso(540.0), "exact" to true)
        out += ev(0, "alarm_scheduled", "deadline" to iso(1_080.0), "fallbackExact" to true)
        out += ev(0, "svc_start_cmd", "src" to "user", "flags" to 0, "startId" to 1)
        out += ev(0, "svc_fg_ok")
        out += ev(1, "battery", "lvl" to 100, "chg" to false)
        out += ev(1, "fix", "acc" to 5.0, "prov" to "fused", "ageMs" to 100_946)
        out += ev(37, "svc_cmd", "action" to "sim_kill", "startId" to 2)
        out += ev(37.9, "svc_destroy")
        out += ev(540, "phase_alarm", "lateMs" to 18, "alive" to false, "action" to "none")
        val trig = 1_140.1
        out += ev(trig, "alarm_ring_fg", "type" to "systemExempted", "ok" to true)
        out += ev(
            trig, "alarm_trigger", "src" to "fallback", "svc" to "ring", "planned" to iso(1_080.0), "lateMs" to 60_100,
            "interactive" to false, "keyguardLocked" to true, "idle" to false,
        )
        out += ev(trig, "perm_snapshot", "zen" to 1, "ringer" to 2)
        out += ev(trig + 0.1, "alarm_vibrate", "ok" to true, "hasVibrator" to true)
        out += ev(trig + 0.2, "alarm_notif_posted", "fsiAllowed" to true, "notifEnabled" to true, "chAlarmImp" to 4)
        out += ev(trig + 0.6, "alarm_ui_shown", "keyguardLocked" to true, "interactive" to true, "viaFsi" to true)
        out += ev(
            trig + 1, "alarm_sound_start", "ok" to true, "focus" to "granted", "alarmVol" to 6, "alarmVolMax" to 7,
            "muted" to false, "zen" to 1,
        )
        out += ev(trig + 23, "alarm_dismissed", "by" to "activity", "afterMs" to 22_733)
        out += ev(trig + 23.1, "run_stop", "by" to "alarm_dismissed")
        return out
    }

    @Test
    fun `U47 gaps after the service was stopped do not say the service is alive`() {
        val s = analyzeRun(u47Events())
        assertEquals(2, s.gapsOverPass.size)
        val sparse = s.gapsOverPass.single { it.phase == "sparse" }
        val dense = s.gapsOverPass.single { it.phase == "dense" }
        assertEquals(epochMs(0.0), sparse.startWallMs)
        for (gap in listOf(sparse, dense)) {
            assertFalse(gap.serviceAlive)
            assertEquals(epochMs(37.9), gap.serviceStoppedWallMs)
        }
        // Levels as before the fix: 540 s sparse (> 7 min) warns, 540 s dense (> 3 min) fails.
        assertEquals(Verdict.WARN, sparse.level)
        assertEquals(Verdict.FAIL, dense.level)
        assertTrue(s.reasons.toString(), s.reasons.any { it.contains("(service vị trí đã dừng lúc +0:00:37)") })
        val text = RunAnalyzer.render(s)
        val gapLine = text.lines().single { it.startsWith("Khoảng trống > ngưỡng:") }
        assertTrue(gapLine, gapLine.contains("service vị trí đã dừng lúc +0:00:37"))
        assertFalse(text, text.contains("service sống"))
    }

    @Test
    fun `U47c a gap with the service alive and no svc_destroy is unchanged`() {
        val s = analyzeRun(u23Events('d'))
        val gap = s.gapsOverPass.single()
        assertTrue(gap.serviceAlive)
        assertNull(gap.serviceStoppedWallMs)
        assertTrue(s.reasons.toString(), s.reasons.any { it.contains("service sống, không nhận vị trí") })
    }

    // ---- Vòng 5: fallback reason by ringing service (U48, S2 V5-3) ----

    @Test
    fun `U48 the fallback reason follows the ringing service`() {
        val ring = analyzeRun(u38Events(listOf(Triple("systemExempted", true, null))))
        assertTrue(ring.reasons.toString(), ring.reasons.contains("kích hoạt bằng dự phòng (service vị trí không chạy)"))
        assertTrue(ring.reasons.toString(), ring.reasons.none { it.contains("FLP không giao vị trí đúng hạn") })
        val probe = analyzeRun(s2Run(triggerSrc = "fallback", lateMs = 61_000))
        assertTrue(probe.reasons.toString(), probe.reasons.contains("kích hoạt bằng dự phòng (FLP không giao vị trí đúng hạn)"))
    }

    // ---- Vòng 5: a new process started for the fallback ring service (U49, S2 V5-4) ----

    /**
     * M-FB3 shape: S2-11 1 min, pid 100 stopped by the button at +23 s, killed at +31 s; pid 200 starts at +2:00 and the
     * ring service (alarm_ring_fg + alarm_trigger) runs [ringAfterS] later; dismissed by the 5 min timeout.
     */
    private fun u49Events(ringAfterS: Double = 0.1, importance: Int = 300): List<ProbeEvent> {
        seq = 0
        val out = ArrayList<ProbeEvent>()
        out += ev(
            0, "run_start",
            "kind" to "S2", "label" to "S2-11", "durationMin" to 1, "densePhaseMin" to 1, "alarmAtEnd" to true,
            "watchdog" to true, "delayMin" to 1, "scenario" to "S2-11", "manufacturer" to "Google",
            "model" to "sdk_gphone64_x86_64", "sdk" to 34, "release" to "14",
        )
        out += ev(0, "alarm_scheduled", "deadline" to iso(60.0), "fallbackExact" to true)
        out += ev(0, "svc_start_cmd", "src" to "user", "flags" to 0, "startId" to 1)
        out += ev(0.2, "phase_switch", "from" to "sparse", "to" to "dense", "boundary" to iso(0.0), "lateMs" to 0, "via" to "start")
        for (s in 4L..14L step 10) out += ev(s, "fix", "acc" to 5.0, "ageMs" to 12)
        out += ev(23, "svc_cmd", "action" to "sim_kill", "startId" to 2)
        out += ev(23.1, "svc_destroy")
        out += ev(120, "proc_start", "importance" to importance, pid = 200)
        out += ev(
            120.03, "exit_info", "reason" to 10, "reasonName" to "REASON_USER_REQUESTED", "exitTs" to epochMs(31.0),
            "desc" to "[KILL BACKGROUND] kill background", pid = 200,
        )
        val trig = 120 + ringAfterS
        out += ev(trig, "alarm_ring_fg", "type" to "systemExempted", "ok" to true, pid = 200)
        out += ev(
            trig + 0.02, "alarm_trigger", "src" to "fallback", "svc" to "ring", "planned" to iso(60.0), "lateMs" to 60_000,
            "interactive" to false, "keyguardLocked" to true, "idle" to false, pid = 200,
        )
        out += ev(trig + 0.1, "alarm_vibrate", "ok" to true, "hasVibrator" to true, pid = 200)
        out += ev(trig + 0.2, "alarm_notif_posted", "fsiAllowed" to true, "notifEnabled" to true, "chAlarmImp" to 4, pid = 200)
        out += ev(trig + 0.7, "alarm_ui_shown", "keyguardLocked" to true, "interactive" to true, "viaFsi" to true, pid = 200)
        out += ev(
            trig + 1.1, "alarm_sound_start", "ok" to true, "focus" to "granted", "alarmVol" to 6, "alarmVolMax" to 7,
            "muted" to false, "zen" to 2, "zenAlarms" to true, pid = 200,
        )
        out += ev(trig + 301, "alarm_dismissed", "by" to "timeout", "afterMs" to 300_150, pid = 200)
        out += ev(trig + 301.1, "run_stop", "by" to "alarm_timeout", pid = 200)
        return out
    }

    @Test
    fun `U49a a new process that runs the fallback ring service is alarm_ring`() {
        val s = analyzeRun(u49Events())
        val e = s.exits.single()
        assertEquals("alarm_ring", e.restartSrc)
        assertEquals(89L, e.restartS)
        assertNull(s.restartsBySrc["alarm_ring"])
        val text = RunAnalyzer.render(s)
        assertTrue(
            text,
            text.contains(" · process chạy lại sau 1 ph 29 s (service báo thức dự phòng), service vị trí không khởi động"),
        )
        assertFalse(text, text.contains("nhưng service không khởi động"))
    }

    @Test
    fun `U49b a ring service later than the window is process_only`() {
        assertEquals("process_only", analyzeRun(u49Events(ringAfterS = 15.0)).exits.single().restartSrc)
    }

    @Test
    fun `U49c a foreground new process stays app_opened`() {
        assertEquals("app_opened", analyzeRun(u49Events(importance = 100)).exits.single().restartSrc)
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
