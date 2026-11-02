package app.napstop.core.trip.harness

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmSilenced
import app.napstop.core.trip.Arrived
import app.napstop.core.trip.BatterySample
import app.napstop.core.trip.EngineInput
import app.napstop.core.trip.FallbackAlarmChanged
import app.napstop.core.trip.FallbackFired
import app.napstop.core.trip.FallbackScheduled
import app.napstop.core.trip.GpsLost
import app.napstop.core.trip.GpsRecovered
import app.napstop.core.trip.LocationAvailability
import app.napstop.core.trip.LocationFix
import app.napstop.core.trip.LowBatteryRisk
import app.napstop.core.trip.Overshoot
import app.napstop.core.trip.PreAlert
import app.napstop.core.trip.SamplingPolicy
import app.napstop.core.trip.SamplingPolicyChanged
import app.napstop.core.trip.Snoozed
import app.napstop.core.trip.Tick
import app.napstop.core.trip.TripEnded
import app.napstop.core.trip.TripEvent
import app.napstop.core.trip.TripView
import app.napstop.core.trip.UserAction
import java.security.MessageDigest

/** P05 canonical transcript (T12 §9). Times are relative to startMs; no coordinates. */
internal object Transcript {
    private fun r(ms: Long, startMs: Long) = (ms - startMs).toString()

    private fun rn(ms: Long?, startMs: Long) = ms?.let { r(it, startMs) } ?: "null"

    private fun n(x: Int?) = x?.toString() ?: "null"

    private fun e(x: Enum<*>?) = x?.let { "\"${it.name}\"" } ?: "null"

    fun hex(x: Double): String = java.lang.Long.toHexString(java.lang.Double.doubleToRawLongBits(x)).padStart(16, '0')

    private fun hexN(x: Double?) = x?.let { "\"${hex(it)}\"" } ?: "null"

    /** `in` array of §9.2. [sampleIndex] = trkpt index for fixes. */
    fun encodeInput(x: EngineInput, s: Long, sampleIndex: Int): String = when (x) {
        is LocationFix -> "[\"FIX\",${r(x.atMs, s)},$sampleIndex]"
        is Tick -> "[\"TICK\",${r(x.atMs, s)}]"
        is BatterySample -> "[\"BATTERY\",${r(x.atMs, s)},${x.levelPct},${x.charging}]"
        is LocationAvailability -> "[\"AVAIL\",${r(x.atMs, s)},\"${x.cause.name}\"]"
        is FallbackScheduled -> "[\"FB_SCHEDULED\",${r(x.atMs, s)},${r(x.fallbackAtMs, s)},${x.ok}]"
        is FallbackFired -> "[\"FB_FIRED\",${r(x.atMs, s)},${r(x.firedAtMs, s)}]"
        is AlarmSilenced -> "[\"SILENCED\",${r(x.atMs, s)},${r(x.silencedAtMs, s)}]"
        is UserAction -> "[\"USER\",${r(x.atMs, s)},\"${x.action.name}\"]"
    }

    private fun policy(p: SamplingPolicy?): String = p?.let {
        "{\"tier\":\"${it.tier.name}\",\"intervalS\":${it.intervalS},\"minIntervalS\":${it.minIntervalS},\"accuracy\":\"${it.accuracy.name}\"}"
    } ?: "null"

    fun encodeEvent(ev: TripEvent, s: Long): String = when (ev) {
        is PreAlert -> "{\"e\":\"preAlert\",\"atMs\":${r(ev.atMs, s)},\"distanceM\":${ev.distanceM},\"etaS\":${n(ev.etaS)}}"
        is Alarm -> "{\"e\":\"alarm\",\"atMs\":${r(ev.atMs, s)},\"reason\":${e(ev.reason)},\"ringNow\":${ev.ringNow}," +
            "\"snoozeAllowed\":${ev.snoozeAllowed},\"distanceM\":${n(ev.distanceM)},\"etaS\":${n(ev.etaS)},\"batteryPct\":${n(ev.batteryPct)}}"
        is Snoozed -> "{\"e\":\"snoozed\",\"atMs\":${r(ev.atMs, s)},\"untilMs\":${r(ev.untilMs, s)}}"
        is GpsLost -> "{\"e\":\"gpsLost\",\"atMs\":${r(ev.atMs, s)},\"cause\":${e(ev.cause)},\"lastFixAgeS\":${n(ev.lastFixAgeS)}}"
        is GpsRecovered -> "{\"e\":\"gpsRecovered\",\"atMs\":${r(ev.atMs, s)},\"lostForS\":${ev.lostForS}}"
        is LowBatteryRisk -> "{\"e\":\"lowBatteryRisk\",\"atMs\":${r(ev.atMs, s)},\"levelPct\":${ev.levelPct}," +
            "\"availableMin\":${ev.availableMin},\"neededMin\":${ev.neededMin}}"
        is Overshoot -> "{\"e\":\"overshoot\",\"atMs\":${r(ev.atMs, s)},\"pastM\":${ev.pastM}}"
        is Arrived -> "{\"e\":\"arrived\",\"atMs\":${r(ev.atMs, s)},\"distanceM\":${ev.distanceM}}"
        is FallbackAlarmChanged ->
            "{\"e\":\"fallbackAlarmChanged\",\"atMs\":${r(ev.atMs, s)},\"fallbackAtMs\":${rn(ev.fallbackAtMs, s)},\"cause\":${e(ev.cause)}}"
        is SamplingPolicyChanged -> "{\"e\":\"samplingPolicyChanged\",\"atMs\":${r(ev.atMs, s)},\"policy\":${policy(ev.policy)}}"
        is TripEnded -> {
            val m = ev.summary
            "{\"e\":\"tripEnded\",\"atMs\":${r(ev.atMs, s)},\"outcome\":${e(ev.outcome)},\"endReason\":${e(ev.endReason)}," +
                "\"summary\":{\"startedAtMs\":${r(m.startedAtMs, s)},\"alarmAtMs\":${rn(m.alarmAtMs, s)},\"alarmReason\":${e(m.alarmReason)}," +
                "\"dismissedAtMs\":${rn(m.dismissedAtMs, s)},\"snoozeCount\":${m.snoozeCount},\"travelledM\":${m.travelledM}," +
                "\"vehicleGuess\":${e(m.vehicleGuess)}}}"
        }
    }

    /** View fields without (*) of T10 §4.16, minus tripId/atMs, in §9.2 order. */
    fun encodeView(v: TripView, s: Long): String =
        "{\"phase\":${e(v.phase)},\"gps\":${e(v.gps)},\"locationCause\":${e(v.locationCause)},\"distanceM\":${n(v.distanceM)}," +
            "\"isEstimated\":${v.isEstimated},\"etaS\":${n(v.etaS)},\"predictedAlarmAtMs\":${rn(v.predictedAlarmAtMs, s)}," +
            "\"samplingPolicy\":${policy(v.samplingPolicy)},\"fallbackAtMs\":${rn(v.fallbackAtMs, s)},\"fallbackStatus\":${e(v.fallbackStatus)}," +
            "\"batteryPct\":${n(v.batteryPct)},\"batteryRisk\":${v.batteryRisk},\"preAlertFired\":${v.preAlertFired}," +
            "\"alarmAtMs\":${rn(v.alarmAtMs, s)},\"alarmReason\":${e(v.alarmReason)},\"alarmRinging\":${v.alarmRinging}," +
            "\"snoozeCount\":${v.snoozeCount},\"snoozeUntilMs\":${rn(v.snoozeUntilMs, s)},\"overshootPastM\":${n(v.overshootPastM)}," +
            "\"outcome\":${e(v.outcome)},\"vehicleGuess\":${e(v.vehicleGuess)},\"travelledM\":${v.travelledM}," +
            "\"droppedFixes\":${v.droppedFixes},\"wakeAtMs\":${rn(v.wakeAtMs, s)}}"

    private fun events(rec: StepRecord, s: Long): String = rec.events.joinToString(",", "[", "]") { encodeEvent(it, s) }

    /** Full line (view always present): used by I8 to compare records. */
    fun fullLine(rec: StepRecord, s: Long): String {
        val v = rec.view ?: return "{\"t\":${rec.t},\"in\":${rec.inJson}}"
        val ev = if (rec.events.isEmpty()) "" else ",\"ev\":${events(rec, s)}"
        return "{\"t\":${rec.t},\"in\":${rec.inJson}$ev,\"v\":${encodeView(v, s)}}"
    }

    fun build(run: String, startMs: Long, records: List<StepRecord>): String {
        val sb = StringBuilder(records.size * 120)
        sb.append("{\"p05\":1,\"run\":\"").append(run).append("\"}\n")
        var lastV: String? = null
        for (rec in records) {
            val view = rec.view
            if (view == null) {
                sb.append("{\"t\":").append(rec.t).append(",\"in\":").append(rec.inJson).append("}\n")
                continue
            }
            sb.append("{\"t\":").append(rec.t).append(",\"in\":").append(rec.inJson)
            if (rec.events.isNotEmpty()) sb.append(",\"ev\":").append(events(rec, startMs))
            val v = encodeView(view, startMs)
            if (v != lastV) {
                sb.append(",\"v\":").append(v)
                lastV = v
            }
            sb.append("}\n")
        }
        return sb.toString()
    }

    /** Set by the suite when -Pnapstop.dumpTranscripts=true: records then carry a §9.5 diagnostic line. */
    @Volatile
    var diagEnabled = false

    /** §9.5 diagnostic object for one Step (hex doubles of state + view). Not part of P05. */
    fun diag(step: app.napstop.core.trip.Step): String {
        val st = step.state
        val v = step.view
        val sb = StringBuilder()
        sb.append("{\"dSmooth\":").append(hexN(st.dSmooth))
        sb.append(",\"dStartM\":").append(hexN(st.dStartM))
        sb.append(",\"minD\":").append(hexN(st.minD))
        sb.append(",\"ground\":").append(hexN(st.ground))
        sb.append(",\"closing\":").append(hexN(st.closing))
        sb.append(",\"movingTimeS\":").append(hexN(st.movingTimeS))
        sb.append(",\"movingDistM\":").append(hexN(st.movingDistM))
        sb.append(",\"cvGuard\":").append(st.cvGuard.joinToString(",", "[", "]") { "\"${hex(it)}\"" })
        sb.append(",\"speedKmh\":").append(hexN(v.speedKmh))
        sb.append(",\"progress\":").append(hexN(v.progress))
        sb.append(",\"alarmMarkerProgress\":").append(hexN(v.alarmMarkerProgress))
        sb.append(",\"routeDistanceEstM\":").append(n(v.routeDistanceEstM))
        sb.append(",\"distanceErrorM\":").append(n(v.distanceErrorM))
        sb.append(",\"etaMinS\":").append(n(v.etaMinS))
        sb.append(",\"etaMaxS\":").append(n(v.etaMaxS))
        sb.append("}")
        return sb.toString()
    }

    fun buildDiag(records: List<StepRecord>): String {
        val sb = StringBuilder()
        for (rec in records) {
            val d = rec.diag ?: continue
            sb.append("{\"t\":").append(rec.t).append(",\"s\":").append(d).append("}\n")
        }
        return sb.toString()
    }

    fun sha256(text: String): String {
        val d = MessageDigest.getInstance("SHA-256").digest(text.toByteArray(Charsets.UTF_8))
        return d.joinToString("") { "%02x".format(it) }
    }

    fun lineCount(text: String): Int = text.count { it == '\n' }
}
