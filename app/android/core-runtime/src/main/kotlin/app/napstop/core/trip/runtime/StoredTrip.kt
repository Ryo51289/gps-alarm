package app.napstop.core.trip.runtime

import app.napstop.core.alarm.RingSettings
import app.napstop.core.trip.AlarmMode
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.EndReason
import app.napstop.core.trip.EngineState
import app.napstop.core.trip.TripEngine
import app.napstop.core.trip.TripOutcome
import app.napstop.core.trip.VehicleKind
import java.util.Properties

/** Coordinate-free copy of TripConfigMsg (survives process death; also ActiveTripMsg.config). */
data class TripMeta(
    val tripId: String,
    val destinationName: String,
    val mode: AlarmMode,
    val distanceThresholdM: Int?,
    val timeThresholdMin: Int?,
    val preAlertEnabled: Boolean,
    val vehicleHint: VehicleKind,
    val alarm: RingSettings,
    val engineParamsJson: String?,
) {
    override fun toString(): String =
        "TripMeta(tripId=$tripId, mode=$mode, distanceThresholdM=$distanceThresholdM, timeThresholdMin=$timeThresholdMin, " +
            "preAlertEnabled=$preAlertEnabled, vehicleHint=$vehicleHint, destination=<redacted>)"
}

/** active_trip.properties (spec T15 §5.7). [engine] holds the destination and ≤ 3 fixes: never logged. */
data class StoredTrip(
    val runtimeVersion: Int,
    val meta: TripMeta,
    val anchor: ClockAnchor,
    val engine: EngineState,
    val savedAtWallMs: Long,
) {
    override fun toString() = "StoredTrip(<redacted>)"

    companion object {
        const val VERSION = 1
    }
}

/** ring_config.properties: what a ring needs without the engine (T16 reads it from the :ring process). */
data class RingConfig(
    val tripId: String,
    val destinationName: String,
    val settings: RingSettings,
    val snoozeCount: Int,
    val maxSnoozes: Int,
) {
    override fun toString(): String =
        "RingConfig(tripId=$tripId, snoozeCount=$snoozeCount, maxSnoozes=$maxSnoozes, destination=<redacted>)"
}

/** Thrown by [RuntimeCodec] decoders; the message names the key or rule only, never a value. */
class StoreFormatException(message: String) : RuntimeException(message)

/**
 * java.util.Properties encoding of the runtime files (spec T15 §5.7). Pure; [FileRuntimeStore] does the IO.
 * Keys of `meta.*` follow `config.*` of the T14 StubStore; finished records use the StubStore keys.
 */
object RuntimeCodec {
    private const val K_RUNTIME_VERSION = "runtimeVersion"
    private const val K_VERSION = "version"
    private const val V1 = "1"

    fun encodeTrip(t: StoredTrip): Properties {
        val p = Properties()
        p[K_RUNTIME_VERSION] = t.runtimeVersion.toString()
        encodeMeta(p, t.meta)
        p["anchor.wallMs"] = t.anchor.wallMs.toString()
        p["anchor.elapsedMs"] = t.anchor.elapsedMs.toString()
        p.putOpt("anchor.bootCount", t.anchor.bootCount)
        p["savedAtWallMs"] = t.savedAtWallMs.toString()
        p["engine"] = TripEngine.encodeSnapshot(t.engine)
        return p
    }

    /** Throws [StoreFormatException] (bad keys, runtimeVersion ≠ 1) or SnapshotFormatException (engine JSON). */
    fun decodeTrip(p: Properties): StoredTrip {
        val version = p.req(K_RUNTIME_VERSION).toIntOrNull()
        if (version != StoredTrip.VERSION) throw StoreFormatException("runtimeVersion unsupported")
        return StoredTrip(
            runtimeVersion = version,
            meta = decodeMeta(p),
            anchor = ClockAnchor(p.long("anchor.wallMs"), p.long("anchor.elapsedMs"), p.optInt("anchor.bootCount")),
            engine = TripEngine.decodeSnapshot(p.req("engine")),
            savedAtWallMs = p.long("savedAtWallMs"),
        )
    }

    fun encodeMeta(p: Properties, m: TripMeta, prefix: String = "meta.") {
        p[prefix + "tripId"] = m.tripId
        p[prefix + "destinationName"] = m.destinationName
        p[prefix + "mode"] = m.mode.name
        p.putOpt(prefix + "distanceThresholdM", m.distanceThresholdM)
        p.putOpt(prefix + "timeThresholdMin", m.timeThresholdMin)
        p[prefix + "preAlertEnabled"] = m.preAlertEnabled.toString()
        p[prefix + "vehicleHint"] = m.vehicleHint.name
        encodeSettings(p, m.alarm, prefix + "alarm.")
        p.putOpt(prefix + "engineParamsJson", m.engineParamsJson)
    }

    fun decodeMeta(p: Properties, prefix: String = "meta."): TripMeta =
        TripMeta(
            tripId = p.req(prefix + "tripId"),
            destinationName = p.req(prefix + "destinationName"),
            mode = p.enumOf(prefix + "mode", AlarmMode.entries),
            distanceThresholdM = p.optInt(prefix + "distanceThresholdM"),
            timeThresholdMin = p.optInt(prefix + "timeThresholdMin"),
            preAlertEnabled = p.bool(prefix + "preAlertEnabled"),
            vehicleHint = p.enumOf(prefix + "vehicleHint", VehicleKind.entries),
            alarm = decodeSettings(p, prefix + "alarm."),
            engineParamsJson = p.getProperty(prefix + "engineParamsJson"),
        )

    private fun encodeSettings(p: Properties, s: RingSettings, prefix: String) {
        p[prefix + "soundId"] = s.soundId
        p[prefix + "volume"] = s.volume.toString()
        p[prefix + "rampUp"] = s.rampUp.toString()
        p[prefix + "vibration"] = s.vibration
        p[prefix + "flash"] = s.flash.toString()
        p[prefix + "preferHeadphones"] = s.preferHeadphones.toString()
        p[prefix + "dismissMethod"] = s.dismissMethod
    }

    private fun decodeSettings(p: Properties, prefix: String): RingSettings =
        RingSettings(
            soundId = p.req(prefix + "soundId"),
            volume = p.req(prefix + "volume").toDoubleOrNull() ?: throw StoreFormatException(prefix + "volume invalid"),
            rampUp = p.bool(prefix + "rampUp"),
            vibration = p.req(prefix + "vibration"),
            flash = p.bool(prefix + "flash"),
            preferHeadphones = p.bool(prefix + "preferHeadphones"),
            dismissMethod = p.req(prefix + "dismissMethod"),
        )

    fun encodeRingConfig(c: RingConfig): Properties {
        val p = Properties()
        p[K_VERSION] = V1
        p["tripId"] = c.tripId
        p["destinationName"] = c.destinationName
        encodeSettings(p, c.settings, "alarm.")
        p["snoozeCount"] = c.snoozeCount.toString()
        p["maxSnoozes"] = c.maxSnoozes.toString()
        return p
    }

    fun decodeRingConfig(p: Properties): RingConfig {
        if (p.getProperty(K_VERSION) != V1) throw StoreFormatException("ring config version unsupported")
        return RingConfig(
            tripId = p.req("tripId"),
            destinationName = p.req("destinationName"),
            settings = decodeSettings(p, "alarm."),
            snoozeCount = p.int("snoozeCount"),
            maxSnoozes = p.int("maxSnoozes"),
        )
    }

    fun encodeLedger(l: FallbackLedger): Properties {
        val p = Properties()
        p["ledgerVersion"] = l.ledgerVersion.toString()
        p.putOpt("activeTripId", l.activeTripId)
        p["nextGeneration"] = l.nextGeneration.toString()
        encodeSlot(p, "current.", l.current)
        encodeSlot(p, "stale.", l.stale)
        l.lastFired?.let { f ->
            p["lastFired.generation"] = f.generation.toString()
            p["lastFired.targetAtMs"] = f.targetAtMs.toString()
            p.putOpt("lastFired.firedAtMs", f.firedAtMs)
            p["lastFired.firedAtWallMs"] = f.firedAtWallMs.toString()
        }
        if (l.endedTripIds.isNotEmpty()) p["endedTripIds"] = l.endedTripIds.joinToString(",")
        if (l.interruptedAlerted) p["interruptedAlerted"] = "true"
        return p
    }

    fun decodeLedger(p: Properties): FallbackLedger {
        if (p.getProperty("ledgerVersion") != V1) throw StoreFormatException("ledgerVersion unsupported")
        val fired =
            if (p.getProperty("lastFired.generation") == null) {
                null
            } else {
                FiredRec(
                    generation = p.long("lastFired.generation"),
                    targetAtMs = p.long("lastFired.targetAtMs"),
                    firedAtMs = p.optLong("lastFired.firedAtMs"),
                    firedAtWallMs = p.long("lastFired.firedAtWallMs"),
                )
            }
        return FallbackLedger(
            ledgerVersion = 1,
            activeTripId = p.getProperty("activeTripId"),
            nextGeneration = p.long("nextGeneration"),
            current = decodeSlot(p, "current."),
            stale = decodeSlot(p, "stale."),
            lastFired = fired,
            endedTripIds = p.getProperty("endedTripIds")?.split(',')?.filter { it.isNotEmpty() } ?: emptyList(),
            interruptedAlerted = p.getProperty("interruptedAlerted") == "true",
        )
    }

    private fun encodeSlot(p: Properties, prefix: String, s: FallbackSlotRec?) {
        if (s == null) return
        p[prefix + "slot"] = s.slot.toString()
        p[prefix + "generation"] = s.generation.toString()
        p[prefix + "targetAtMs"] = s.targetAtMs.toString()
        p[prefix + "setAtWallMs"] = s.setAtWallMs.toString()
        p[prefix + "kind"] = s.kind.name
        p[prefix + "targetAtWallMs"] = s.targetAtWallMs.toString()
    }

    private fun decodeSlot(p: Properties, prefix: String): FallbackSlotRec? {
        if (p.getProperty(prefix + "slot") == null) return null
        val slot = p.int(prefix + "slot")
        if (slot != 0 && slot != 1) throw StoreFormatException(prefix + "slot invalid")
        val target = p.long(prefix + "targetAtMs")
        return FallbackSlotRec(
            slot = slot,
            generation = p.long(prefix + "generation"),
            targetAtMs = target,
            setAtWallMs = p.long(prefix + "setAtWallMs"),
            // Ledgers written before round 4: ENGINE, wall target = trip target.
            kind = p.getProperty(prefix + "kind")?.let { k -> SlotKind.entries.firstOrNull { it.name == k } } ?: SlotKind.ENGINE,
            targetAtWallMs = p.optLong(prefix + "targetAtWallMs") ?: target,
        )
    }

    fun encodeFinished(f: FinishedRecord): Properties {
        val p = Properties()
        p[K_VERSION] = V1
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

    fun decodeFinished(p: Properties): FinishedRecord {
        if (p.getProperty(K_VERSION) != V1) throw StoreFormatException("finished version unsupported")
        return FinishedRecord(
            tripId = p.req("tripId"),
            outcome = p.enumOf("outcome", TripOutcome.entries),
            endReason = p.enumOf("endReason", EndReason.entries),
            endedAtMs = p.long("endedAtMs"),
            startedAtMs = p.long("startedAtMs"),
            alarmAtMs = p.optLong("alarmAtMs"),
            alarmReason = if (p.getProperty("alarmReason") == null) null else p.enumOf("alarmReason", AlarmReason.entries),
            dismissedAtMs = p.optLong("dismissedAtMs"),
            snoozeCount = p.int("snoozeCount"),
            travelledM = p.int("travelledM"),
            vehicleGuess = p.enumOf("vehicleGuess", VehicleKind.entries),
        )
    }

    // ------------------------------------------------------------------ helpers

    private fun Properties.req(key: String): String = getProperty(key) ?: throw StoreFormatException("$key missing")

    private fun Properties.long(key: String): Long = req(key).toLongOrNull() ?: throw StoreFormatException("$key invalid")

    private fun Properties.int(key: String): Int = req(key).toIntOrNull() ?: throw StoreFormatException("$key invalid")

    private fun Properties.optLong(key: String): Long? =
        getProperty(key)?.let { it.toLongOrNull() ?: throw StoreFormatException("$key invalid") }

    private fun Properties.optInt(key: String): Int? =
        getProperty(key)?.let { it.toIntOrNull() ?: throw StoreFormatException("$key invalid") }

    private fun Properties.bool(key: String): Boolean =
        when (req(key)) {
            "true" -> true
            "false" -> false
            else -> throw StoreFormatException("$key invalid")
        }

    private fun <E : Enum<E>> Properties.enumOf(key: String, values: List<E>): E {
        val v = req(key)
        return values.firstOrNull { it.name == v } ?: throw StoreFormatException("$key invalid")
    }

    private fun Properties.putOpt(key: String, value: Any?) {
        if (value != null) this[key] = value.toString()
    }
}
