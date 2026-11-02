package app.napstop.core.trip

// Snapshot JSON v1 (T10 §7.1, T12 §7.3). Keys in table order, every key always written (null as null).
// Doubles use Double.toString() and are read back with String.toDouble(): bit-exact round trip on the JVM.

internal object SnapshotCodec {
    fun encode(s: EngineState): String = MiniJson.write(toJson(s))

    fun toJson(s: EngineState): JObject = jObj(
        "snapshotVersion" to jNum(s.snapshotVersion),
        "params" to paramsJson(s.params),
        "config" to configJson(s.config),
        "nowMs" to jNum(s.nowMs),
        "startedAtMs" to jNum(s.startedAtMs),
        "phase" to jStr(s.phase.name),
        "gps" to jStr(s.gps.name),
        "locationCause" to jStr(s.locationCause.name),
        "last" to fixJson(s.last),
        "stopAnchor" to fixJson(s.stopAnchor),
        "recent" to JArray(s.recent.map { fixJson(it) }),
        "rejects" to JArray(s.rejects.map { fixJson(it) }),
        "dSmooth" to dbl(s.dSmooth),
        "dStartM" to dbl(s.dStartM),
        "minD" to dbl(s.minD),
        "last3" to JArray(s.last3.map { jDbl(it) }),
        "ground" to dbl(s.ground),
        "closing" to dbl(s.closing),
        "movingTimeS" to jDbl(s.movingTimeS),
        "movingSamples" to jNum(s.movingSamples),
        "movingDistM" to jDbl(s.movingDistM),
        "stopStartMs" to lng(s.stopStartMs),
        "slow" to jBool(s.slow),
        "cvGuard" to JArray(s.cvGuard.map { jDbl(it) }),
        "policy" to policyJson(s.policy),
        "policyIntervalAtLastFixS" to jNum(s.policyIntervalAtLastFixS),
        "gpsLostAtMs" to lng(s.gpsLostAtMs),
        "lostEmittedBeforeFirstFix" to jBool(s.lostEmittedBeforeFirstFix),
        "preAlertArmed" to jBool(s.preAlertArmed),
        "preAlertFired" to jBool(s.preAlertFired),
        "arrivedFired" to jBool(s.arrivedFired),
        "alarm" to s.alarm.let { a ->
            jObj(
                "atMs" to lng(a.atMs), "reason" to enm(a.reason), "source" to enm(a.source),
                "lastRingAtMs" to lng(a.lastRingAtMs), "lastReason" to enm(a.lastReason), "ringing" to jBool(a.ringing),
                "snoozeCount" to jNum(a.snoozeCount), "snoozeUntilMs" to lng(a.snoozeUntilMs),
                "dismissedAtMs" to lng(a.dismissedAtMs),
            )
        },
        "overshootAtMs" to lng(s.overshootAtMs),
        "overshootPastM" to int(s.overshootPastM),
        "fallback" to s.fallback.let { f ->
            jObj(
                "targetAtMs" to lng(f.targetAtMs), "emittedAtMs" to lng(f.emittedAtMs), "status" to jStr(f.status.name),
                "confirmedAtMs" to lng(f.confirmedAtMs), "resync" to jBool(f.resync), "near" to jBool(f.near),
            )
        },
        "battery" to s.battery.let { b ->
            jObj(
                "levelPct" to int(b.levelPct), "charging" to jBool(b.charging), "segT0" to lng(b.segT0),
                "segL0" to int(b.segL0), "armed" to jBool(b.armed), "riskEmitted" to jBool(b.riskEmitted),
                "choice" to enm(b.choice), "choicePct" to int(b.choicePct),
            )
        },
        "maxTripDurationS" to jNum(s.maxTripDurationS),
        "droppedFixes" to jNum(s.droppedFixes),
        "ended" to (s.ended?.let { jObj("outcome" to jStr(it.outcome.name), "endReason" to jStr(it.endReason.name), "atMs" to jNum(it.atMs)) } ?: JNull),
    )

    fun paramsJson(p: EngineParams): JObject {
        val m = LinkedHashMap<String, JsonValue>()
        for (spec in PARAM_SPECS) {
            val v = spec.get(p)
            m[spec.name] = if (spec.isInt) jNum(v.toInt()) else jDbl(v)
        }
        return JObject(m)
    }

    private fun configJson(c: TripConfig): JObject = jObj(
        "tripId" to jStr(c.tripId), "destLat" to jDbl(c.destLat), "destLng" to jDbl(c.destLng), "mode" to jStr(c.mode.name),
        "distanceThresholdM" to int(c.distanceThresholdM), "timeThresholdMin" to int(c.timeThresholdMin),
        "preAlertEnabled" to jBool(c.preAlertEnabled), "vehicleHint" to jStr(c.vehicleHint.name),
    )

    private fun fixJson(f: FixRec?): JsonValue = f?.let {
        jObj(
            "fixAtMs" to jNum(it.fixAtMs), "lat" to jDbl(it.lat), "lng" to jDbl(it.lng), "accM" to jDbl(it.accM),
            "d" to jDbl(it.d), "groundSample" to dbl(it.groundSample),
        )
    } ?: JNull

    private fun policyJson(p: SamplingPolicy?): JsonValue = p?.let {
        jObj("tier" to jStr(it.tier.name), "intervalS" to jNum(it.intervalS), "minIntervalS" to jNum(it.minIntervalS), "accuracy" to jStr(it.accuracy.name))
    } ?: JNull

    private fun dbl(x: Double?): JsonValue = x?.let { jDbl(it) } ?: JNull

    private fun lng(x: Long?): JsonValue = x?.let { jNum(it) } ?: JNull

    private fun int(x: Int?): JsonValue = x?.let { jNum(it) } ?: JNull

    private fun enm(x: Enum<*>?): JsonValue = x?.let { jStr(it.name) } ?: JNull

    // ---- decode ----

    private fun bad(field: String): Nothing = throw SnapshotFormatException("snapshot: $field invalid")

    fun decode(json: String): EngineState {
        val root = try {
            MiniJson.parse(json)
        } catch (_: JsonParseException) {
            throw SnapshotFormatException("snapshot: malformed json")
        }
        if (root !is JObject) throw SnapshotFormatException("snapshot: not an object")
        val ver = (root["snapshotVersion"] as? JNumber)?.asLongExact() ?: bad("snapshotVersion")
        if (ver > 1) throw SnapshotFormatException("snapshot: unsupported version")
        if (ver != 1L) bad("snapshotVersion")
        val r = Reader(root, "")
        val alarm = r.obj("alarm")
        val fb = r.obj("fallback")
        val bat = r.obj("battery")
        return EngineState(
            snapshotVersion = 1,
            params = decodeParams(r.obj("params")),
            config = decodeConfig(r.obj("config")),
            nowMs = r.long("nowMs"),
            startedAtMs = r.long("startedAtMs"),
            phase = r.enum("phase", TripPhase.entries),
            gps = r.enum("gps", GpsStatus.entries),
            locationCause = r.enum("locationCause", AvailabilityCause.entries),
            last = r.fixOrNull("last"),
            stopAnchor = r.fixOrNull("stopAnchor"),
            recent = r.array("recent").mapIndexed { i, v -> fix(v, "recent[$i]") },
            rejects = r.array("rejects").mapIndexed { i, v -> fix(v, "rejects[$i]") },
            dSmooth = r.doubleOrNull("dSmooth"),
            dStartM = r.doubleOrNull("dStartM"),
            minD = r.doubleOrNull("minD"),
            last3 = r.array("last3").mapIndexed { i, v -> dblValue(v, "last3[$i]") },
            ground = r.doubleOrNull("ground"),
            closing = r.doubleOrNull("closing"),
            movingTimeS = r.double("movingTimeS"),
            movingSamples = r.int("movingSamples"),
            movingDistM = r.double("movingDistM"),
            stopStartMs = r.longOrNull("stopStartMs"),
            slow = r.bool("slow"),
            cvGuard = r.array("cvGuard").mapIndexed { i, v -> dblValue(v, "cvGuard[$i]") },
            policy = r.objOrNull("policy")?.let { o ->
                val pr = Reader(o, "policy.")
                SamplingPolicy(pr.enum("tier", SamplingTier.entries), pr.int("intervalS"), pr.int("minIntervalS"), pr.enum("accuracy", AccuracyLevel.entries))
            },
            policyIntervalAtLastFixS = r.int("policyIntervalAtLastFixS"),
            gpsLostAtMs = r.longOrNull("gpsLostAtMs"),
            lostEmittedBeforeFirstFix = r.bool("lostEmittedBeforeFirstFix"),
            preAlertArmed = r.bool("preAlertArmed"),
            preAlertFired = r.bool("preAlertFired"),
            arrivedFired = r.bool("arrivedFired"),
            alarm = Reader(alarm, "alarm.").let { a ->
                AlarmState(
                    a.longOrNull("atMs"), a.enumOrNull("reason", AlarmReason.entries), a.enumOrNull("source", AlarmSource.entries),
                    a.longOrNull("lastRingAtMs"), a.enumOrNull("lastReason", AlarmReason.entries), a.bool("ringing"),
                    a.int("snoozeCount"), a.longOrNull("snoozeUntilMs"), a.longOrNull("dismissedAtMs"),
                )
            },
            overshootAtMs = r.longOrNull("overshootAtMs"),
            overshootPastM = r.intOrNull("overshootPastM"),
            fallback = Reader(fb, "fallback.").let { f ->
                FallbackState(
                    f.longOrNull("targetAtMs"), f.longOrNull("emittedAtMs"), f.enum("status", FallbackStatus.entries),
                    f.longOrNull("confirmedAtMs"), f.bool("resync"), f.bool("near"),
                )
            },
            battery = Reader(bat, "battery.").let { b ->
                BatteryState(
                    b.intOrNull("levelPct"), b.bool("charging"), b.longOrNull("segT0"), b.intOrNull("segL0"), b.bool("armed"),
                    b.bool("riskEmitted"), b.enumOrNull("choice", UserActionKind.entries), b.intOrNull("choicePct"),
                )
            },
            maxTripDurationS = r.int("maxTripDurationS"),
            droppedFixes = r.int("droppedFixes"),
            ended = r.objOrNull("ended")?.let { o ->
                val er = Reader(o, "ended.")
                EndedState(er.enum("outcome", TripOutcome.entries), er.enum("endReason", EndReason.entries), er.long("atMs"))
            },
        )
    }

    /** Params: a missing key takes its default (T10.2 "decode thiếu khoá này thì dùng mặc định"); wrong type is an error. */
    private fun decodeParams(o: JObject): EngineParams {
        val values = LinkedHashMap<String, Double>()
        for (spec in PARAM_SPECS) {
            val v = o[spec.name] ?: continue
            val n = v as? JNumber ?: bad("params.${spec.name}")
            values[spec.name] = if (spec.isInt) {
                val l = n.asLongExact() ?: bad("params.${spec.name}")
                if (l < Int.MIN_VALUE || l > Int.MAX_VALUE) bad("params.${spec.name}")
                l.toDouble()
            } else {
                val d = n.asDouble()
                if (!d.isFinite()) bad("params.${spec.name}")
                d
            }
        }
        return engineParamsOf(values)
    }

    private fun decodeConfig(o: JObject): TripConfig {
        val r = Reader(o, "config.")
        return TripConfig(
            tripId = r.string("tripId"),
            destLat = r.double("destLat"),
            destLng = r.double("destLng"),
            mode = r.enum("mode", AlarmMode.entries),
            distanceThresholdM = r.intOrNull("distanceThresholdM"),
            timeThresholdMin = r.intOrNull("timeThresholdMin"),
            preAlertEnabled = r.bool("preAlertEnabled"),
            vehicleHint = r.enum("vehicleHint", VehicleKind.entries),
        )
    }

    private fun dblValue(v: JsonValue, field: String): Double {
        val d = (v as? JNumber)?.asDouble() ?: bad(field)
        if (!d.isFinite()) bad(field)
        return d
    }

    private fun fix(v: JsonValue, field: String): FixRec {
        val o = v as? JObject ?: bad(field)
        val r = Reader(o, "$field.")
        return FixRec(r.long("fixAtMs"), r.double("lat"), r.double("lng"), r.double("accM"), r.double("d"), r.doubleOrNull("groundSample"))
    }

    private class Reader(val o: JObject, val prefix: String) {
        fun req(k: String): JsonValue = o[k] ?: bad(prefix + k)

        fun isNull(k: String): Boolean = req(k) === JNull

        fun long(k: String): Long = (req(k) as? JNumber)?.asLongExact() ?: bad(prefix + k)

        fun longOrNull(k: String): Long? = if (isNull(k)) null else long(k)

        fun int(k: String): Int {
            val l = long(k)
            if (l < Int.MIN_VALUE || l > Int.MAX_VALUE) bad(prefix + k)
            return l.toInt()
        }

        fun intOrNull(k: String): Int? = if (isNull(k)) null else int(k)

        fun double(k: String): Double = dblValue(req(k), prefix + k)

        fun doubleOrNull(k: String): Double? = if (isNull(k)) null else double(k)

        fun bool(k: String): Boolean = (req(k) as? JBool)?.value ?: bad(prefix + k)

        fun string(k: String): String = (req(k) as? JString)?.value ?: bad(prefix + k)

        fun <E : Enum<E>> enum(k: String, values: List<E>): E {
            val name = string(k)
            return values.firstOrNull { it.name == name } ?: bad(prefix + k)
        }

        fun <E : Enum<E>> enumOrNull(k: String, values: List<E>): E? = if (isNull(k)) null else enum(k, values)

        fun obj(k: String): JObject = req(k) as? JObject ?: bad(prefix + k)

        fun objOrNull(k: String): JObject? = if (isNull(k)) null else obj(k)

        fun array(k: String): List<JsonValue> = (req(k) as? JArray)?.items ?: bad(prefix + k)

        fun fixOrNull(k: String): FixRec? = if (isNull(k)) null else fix(req(k), prefix + k)
    }
}
