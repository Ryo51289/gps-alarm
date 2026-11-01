package app.napstop.core.bridge.stub

import android.util.Log
import app.napstop.core.bridge.AlarmModeMsg
import app.napstop.core.bridge.AlarmReasonMsg
import app.napstop.core.bridge.AlarmSettingsMsg
import app.napstop.core.bridge.BatteryChoiceMsg
import app.napstop.core.bridge.DismissMethodMsg
import app.napstop.core.bridge.EndReasonMsg
import app.napstop.core.bridge.FinishedTripMsg
import app.napstop.core.bridge.GpsStatusMsg
import app.napstop.core.bridge.TripConfigMsg
import app.napstop.core.bridge.TripOutcomeMsg
import app.napstop.core.bridge.TripPhaseMsg
import app.napstop.core.bridge.VehicleKindMsg
import app.napstop.core.bridge.VibrationMsg
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.Properties

/**
 * Stub snapshot on disk (spec T14 §5.3), `java.util.Properties` so it runs in JVM unit
 * tests. Layout under [dir] (prod: noBackupFilesDir/napstop_stub):
 * - `active_trip.properties`: the running StubTripState, `version=1`. No coordinates.
 * - `finished/<tripId>.properties`: one FinishedTripMsg per ended, not yet acked trip.
 *
 * Blocking IO: call from an IO dispatcher. [warn] receives error codes only.
 */
class StubStore(
    private val dir: File,
    private val warn: (String) -> Unit = { Log.w(TAG, it) },
) {
    private val activeFile get() = File(dir, ACTIVE_FILE)
    private val finishedDir get() = File(dir, FINISHED_DIR)

    /** The saved trip, or null. A corrupt or unknown-version file is deleted (T10 RK8). */
    fun readActive(): StubTripState? {
        val file = activeFile
        if (!file.exists()) return null
        return try {
            val p = load(file)
            if (p.getProperty(K_VERSION) != VERSION) {
                warn("stub snapshot: unsupported version")
                file.delete()
                null
            } else {
                decodeState(p)
            }
        } catch (e: Exception) {
            warn("stub snapshot: invalid (${e.javaClass.simpleName})")
            file.delete()
            null
        }
    }

    fun writeActive(s: StubTripState) {
        writeAtomic(activeFile, encodeState(s))
    }

    fun deleteActive() {
        activeFile.delete()
    }

    fun writeFinished(f: FinishedTripMsg) {
        writeAtomic(File(finishedDir, f.tripId + SUFFIX), encodeFinished(f))
    }

    /** Ended trips, oldest endedAtMs first. Corrupt records are deleted. */
    fun readFinished(): List<FinishedTripMsg> {
        val files = finishedDir.listFiles { f -> f.isFile && f.name.endsWith(SUFFIX) } ?: return emptyList()
        return files
            .mapNotNull { file ->
                try {
                    val p = load(file)
                    require(p.getProperty(K_VERSION) == VERSION) { "version" }
                    decodeFinished(p)
                } catch (e: Exception) {
                    warn("stub finished record: invalid (${e.javaClass.simpleName})")
                    file.delete()
                    null
                }
            }.sortedWith(compareBy<FinishedTripMsg> { it.endedAtMs }.thenBy { it.tripId })
    }

    fun deleteFinished(tripIds: List<String>) {
        for (id in tripIds) {
            // Ids come from Dart: only touch plain file names inside finished/.
            if (!SAFE_ID.matches(id)) continue
            File(finishedDir, id + SUFFIX).delete()
        }
    }

    // ------------------------------------------------------------- encoding

    private fun encodeState(s: StubTripState): Properties {
        val p = Properties()
        p[K_VERSION] = VERSION
        encodeConfig(p, s.config)
        p["scenario"] = s.scenario.name
        p["speedFactor"] = s.speedFactor.toString()
        p["simulated"] = s.simulated.toString()
        p["startedAtMs"] = s.startedAtMs.toString()
        p["nowMs"] = s.nowMs.toString()
        p["phase"] = s.phase.name
        p["gps"] = s.gps.name
        p["preAlertFired"] = s.preAlertFired.toString()
        p["arrivedFired"] = s.arrivedFired.toString()
        p["lowBatteryEmitted"] = s.lowBatteryEmitted.toString()
        p.putOpt("gpsLostAtMs", s.gpsLostAtMs)
        p["neverAcquiredEmitted"] = s.neverAcquiredEmitted.toString()
        p.putOpt("alarmAtMs", s.alarmAtMs)
        p.putOpt("firstAlarmReason", s.firstAlarmReason?.name)
        p.putOpt("lastAlarmReason", s.lastAlarmReason?.name)
        p["ringing"] = s.ringing.toString()
        p.putOpt("lastRingAtMs", s.lastRingAtMs)
        p["snoozeCount"] = s.snoozeCount.toString()
        p.putOpt("snoozeUntilMs", s.snoozeUntilMs)
        p["overshot"] = s.overshot.toString()
        p.putOpt("batteryChoice", s.batteryChoice?.name)
        p.putOpt("outcome", s.outcome?.name)
        p.putOpt("endReason", s.endReason?.name)
        p.putOpt("endedAtMs", s.endedAtMs)
        p.putOpt("dismissedAtMs", s.dismissedAtMs)
        return p
    }

    private fun decodeState(p: Properties): StubTripState =
        StubTripState(
            config = decodeConfig(p),
            scenario = StubScenario.valueOf(p.req("scenario")),
            speedFactor = p.req("speedFactor").toDouble(),
            simulated = p.bool("simulated"),
            startedAtMs = p.req("startedAtMs").toLong(),
            nowMs = p.req("nowMs").toLong(),
            phase = TripPhaseMsg.valueOf(p.req("phase")),
            gps = GpsStatusMsg.valueOf(p.req("gps")),
            preAlertFired = p.bool("preAlertFired"),
            arrivedFired = p.bool("arrivedFired"),
            lowBatteryEmitted = p.bool("lowBatteryEmitted"),
            gpsLostAtMs = p.optLong("gpsLostAtMs"),
            neverAcquiredEmitted = p.bool("neverAcquiredEmitted"),
            alarmAtMs = p.optLong("alarmAtMs"),
            firstAlarmReason = p.getProperty("firstAlarmReason")?.let(AlarmReasonMsg::valueOf),
            lastAlarmReason = p.getProperty("lastAlarmReason")?.let(AlarmReasonMsg::valueOf),
            ringing = p.bool("ringing"),
            lastRingAtMs = p.optLong("lastRingAtMs"),
            snoozeCount = p.req("snoozeCount").toInt(),
            snoozeUntilMs = p.optLong("snoozeUntilMs"),
            overshot = p.bool("overshot"),
            batteryChoice = p.getProperty("batteryChoice")?.let(BatteryChoiceMsg::valueOf),
            outcome = p.getProperty("outcome")?.let(TripOutcomeMsg::valueOf),
            endReason = p.getProperty("endReason")?.let(EndReasonMsg::valueOf),
            endedAtMs = p.optLong("endedAtMs"),
            dismissedAtMs = p.optLong("dismissedAtMs"),
        )

    private fun encodeConfig(p: Properties, c: TripConfigMsg) {
        p["config.tripId"] = c.tripId
        p["config.destinationName"] = c.destinationName
        p["config.mode"] = c.mode.name
        p.putOpt("config.distanceThresholdM", c.distanceThresholdM)
        p.putOpt("config.timeThresholdMin", c.timeThresholdMin)
        p["config.preAlertEnabled"] = c.preAlertEnabled.toString()
        p["config.vehicleHint"] = c.vehicleHint.name
        p["config.alarm.soundId"] = c.alarm.soundId
        p["config.alarm.volume"] = c.alarm.volume.toString()
        p["config.alarm.rampUp"] = c.alarm.rampUp.toString()
        p["config.alarm.vibration"] = c.alarm.vibration.name
        p["config.alarm.flash"] = c.alarm.flash.toString()
        p["config.alarm.preferHeadphones"] = c.alarm.preferHeadphones.toString()
        p["config.alarm.dismissMethod"] = c.alarm.dismissMethod.name
    }

    private fun decodeConfig(p: Properties): TripConfigMsg =
        TripConfigMsg(
            tripId = p.req("config.tripId"),
            destinationName = p.req("config.destinationName"),
            mode = AlarmModeMsg.valueOf(p.req("config.mode")),
            distanceThresholdM = p.optLong("config.distanceThresholdM"),
            timeThresholdMin = p.optLong("config.timeThresholdMin"),
            preAlertEnabled = p.bool("config.preAlertEnabled"),
            vehicleHint = VehicleKindMsg.valueOf(p.req("config.vehicleHint")),
            alarm =
                AlarmSettingsMsg(
                    soundId = p.req("config.alarm.soundId"),
                    volume = p.req("config.alarm.volume").toDouble(),
                    rampUp = p.bool("config.alarm.rampUp"),
                    vibration = VibrationMsg.valueOf(p.req("config.alarm.vibration")),
                    flash = p.bool("config.alarm.flash"),
                    preferHeadphones = p.bool("config.alarm.preferHeadphones"),
                    dismissMethod = DismissMethodMsg.valueOf(p.req("config.alarm.dismissMethod")),
                ),
        )

    private fun encodeFinished(f: FinishedTripMsg): Properties {
        val p = Properties()
        p[K_VERSION] = VERSION
        p["tripId"] = f.tripId
        p["outcome"] = f.outcome.name
        p["endReason"] = f.endReason.name
        p["endedAtMs"] = f.endedAtMs.toString()
        p["startedAtMs"] = f.startedAtMs.toString()
        p.putOpt("alarmAtMs", f.alarmAtMs)
        p.putOpt("alarmReason", f.alarmReason?.name)
        p.putOpt("dismissedAtMs", f.dismissedAtMs)
        p["snoozeCount"] = f.snoozeCount.toString()
        p["travelledM"] = f.travelledM.toString()
        p["vehicleGuess"] = f.vehicleGuess.name
        return p
    }

    private fun decodeFinished(p: Properties): FinishedTripMsg =
        FinishedTripMsg(
            tripId = p.req("tripId"),
            outcome = TripOutcomeMsg.valueOf(p.req("outcome")),
            endReason = EndReasonMsg.valueOf(p.req("endReason")),
            endedAtMs = p.req("endedAtMs").toLong(),
            startedAtMs = p.req("startedAtMs").toLong(),
            alarmAtMs = p.optLong("alarmAtMs"),
            alarmReason = p.getProperty("alarmReason")?.let(AlarmReasonMsg::valueOf),
            dismissedAtMs = p.optLong("dismissedAtMs"),
            snoozeCount = p.req("snoozeCount").toLong(),
            travelledM = p.req("travelledM").toLong(),
            vehicleGuess = VehicleKindMsg.valueOf(p.req("vehicleGuess")),
        )

    // ------------------------------------------------------------------ io

    private fun load(file: File): Properties = Properties().apply { file.inputStream().use { load(it) } }

    /** Write to a temp file, then replace the target in one move. */
    private fun writeAtomic(target: File, p: Properties) {
        val parent = target.parentFile ?: throw IOException("no parent")
        if (!parent.isDirectory && !parent.mkdirs()) throw IOException("mkdirs failed")
        val tmp = File(parent, target.name + ".tmp")
        tmp.outputStream().use { out ->
            p.store(out, null)
            out.fd.sync()
        }
        try {
            Files.move(tmp.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
        } catch (e: java.nio.file.AtomicMoveNotSupportedException) {
            Files.move(tmp.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING)
        }
    }

    private fun Properties.req(key: String): String = getProperty(key) ?: throw IllegalArgumentException("missing")

    private fun Properties.optLong(key: String): Long? = getProperty(key)?.toLong()

    private fun Properties.bool(key: String): Boolean =
        when (req(key)) {
            "true" -> true
            "false" -> false
            else -> throw IllegalArgumentException("bool")
        }

    private fun Properties.putOpt(key: String, value: Any?) {
        if (value != null) this[key] = value.toString()
    }

    companion object {
        const val DIR_NAME = "napstop_stub"
        const val ACTIVE_FILE = "active_trip.properties"
        const val FINISHED_DIR = "finished"
        private const val SUFFIX = ".properties"
        private const val K_VERSION = "version"
        private const val VERSION = "1"
        private const val TAG = "NapStopStub"
        private val SAFE_ID = Regex("^[A-Za-z0-9_-]{1,64}$")
    }
}
