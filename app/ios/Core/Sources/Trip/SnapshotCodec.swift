// Snapshot JSON v1 (T10 §7.1, T12 §7.3, T13 §6.2). Every key is always written (null as `null`), in state order.
// Doubles use Swift `description` (shortest round-trip); decode uses `Double(String)` (correctly rounded).

enum SnapshotCodec {
    // MARK: encode

    static func encode(_ s: EngineState) -> String {
        var o: [(String, JsonValue)] = []
        o.append(("snapshotVersion", int(s.snapshotVersion)))
        o.append(("params", encodeParams(s.params)))
        o.append(("config", encodeConfig(s.config)))
        o.append(("nowMs", long(s.nowMs)))
        o.append(("startedAtMs", long(s.startedAtMs)))
        o.append(("phase", .string(s.phase.jsonName)))
        o.append(("gps", .string(s.gps.jsonName)))
        o.append(("locationCause", .string(s.locationCause.jsonName)))
        o.append(("last", s.last.map(encodeFix) ?? .null))
        o.append(("stopAnchor", s.stopAnchor.map(encodeFix) ?? .null))
        o.append(("recent", .array(s.recent.map(encodeFix))))
        o.append(("rejects", .array(s.rejects.map(encodeFix))))
        o.append(("dSmooth", optDouble(s.dSmooth)))
        o.append(("dStartM", optDouble(s.dStartM)))
        o.append(("minD", optDouble(s.minD)))
        o.append(("minDChord", .bool(s.minDChord)))
        o.append(("passAnchorD", optDouble(s.passAnchorD)))
        o.append(("alarmedChordD", optDouble(s.alarmedChordD)))
        o.append(("last3", .array(s.last3.map(double))))
        o.append(("ground", optDouble(s.ground)))
        o.append(("closing", optDouble(s.closing)))
        o.append(("movingTimeS", double(s.movingTimeS)))
        o.append(("movingSamples", int(s.movingSamples)))
        o.append(("movingDistM", double(s.movingDistM)))
        o.append(("stopStartMs", optLong(s.stopStartMs)))
        o.append(("slow", .bool(s.slow)))
        o.append(("cvGuard", .array(s.cvGuard.map(double))))
        o.append(("policy", s.policy.map(encodePolicy) ?? .null))
        o.append(("policyIntervalAtLastFixS", int(s.policyIntervalAtLastFixS)))
        o.append(("gpsLostAtMs", optLong(s.gpsLostAtMs)))
        o.append(("lostEmittedBeforeFirstFix", .bool(s.lostEmittedBeforeFirstFix)))
        o.append(("preAlertArmed", .bool(s.preAlertArmed)))
        o.append(("preAlertFired", .bool(s.preAlertFired)))
        o.append(("arrivedFired", .bool(s.arrivedFired)))
        let a = s.alarm
        o.append(("alarm", .object([
            ("atMs", optLong(a.atMs)), ("reason", optEnum(a.reason?.jsonName)), ("source", optEnum(a.source?.jsonName)),
            ("lastRingAtMs", optLong(a.lastRingAtMs)), ("lastReason", optEnum(a.lastReason?.jsonName)),
            ("ringing", .bool(a.ringing)), ("snoozeCount", int(a.snoozeCount)), ("snoozeUntilMs", optLong(a.snoozeUntilMs)),
            ("dismissedAtMs", optLong(a.dismissedAtMs)),
        ])))
        o.append(("overshootAtMs", optLong(s.overshootAtMs)))
        o.append(("overshootPastM", s.overshootPastM.map(int) ?? .null))
        let f = s.fallback
        o.append(("fallback", .object([
            ("targetAtMs", optLong(f.targetAtMs)), ("emittedAtMs", optLong(f.emittedAtMs)), ("status", .string(f.status.jsonName)),
            ("confirmedAtMs", optLong(f.confirmedAtMs)), ("resync", .bool(f.resync)), ("near", .bool(f.near)),
        ])))
        let b = s.battery
        o.append(("battery", .object([
            ("levelPct", b.levelPct.map(int) ?? .null), ("charging", .bool(b.charging)), ("segT0", optLong(b.segT0)),
            ("segL0", b.segL0.map(int) ?? .null), ("armed", .bool(b.armed)), ("riskEmitted", .bool(b.riskEmitted)),
            ("choice", optEnum(b.choice?.jsonName)), ("choicePct", b.choicePct.map(int) ?? .null),
        ])))
        o.append(("maxTripDurationS", int(s.maxTripDurationS)))
        o.append(("droppedFixes", int(s.droppedFixes)))
        if let e = s.ended {
            o.append(("ended", .object([("outcome", .string(e.outcome.jsonName)), ("endReason", .string(e.endReason.jsonName)),
                                        ("atMs", long(e.atMs))])))
        } else {
            o.append(("ended", .null))
        }
        return MiniJson.write(.object(o))
    }

    static func encodeParams(_ p: EngineParams) -> JsonValue {
        var o: [(String, JsonValue)] = []
        for (i, spec) in ParamTable.PARAM_SPECS.enumerated() {
            switch p.value(at: i) {
            case let .int(v): o.append((spec.name, int(v)))
            case let .double(v): o.append((spec.name, double(v)))
            }
        }
        return .object(o)
    }

    static func encodeConfig(_ c: TripConfig) -> JsonValue {
        .object([
            ("tripId", .string(c.tripId)), ("destLat", double(c.destLat)), ("destLng", double(c.destLng)),
            ("mode", .string(c.mode.jsonName)), ("distanceThresholdM", c.distanceThresholdM.map(int) ?? .null),
            ("timeThresholdMin", c.timeThresholdMin.map(int) ?? .null), ("preAlertEnabled", .bool(c.preAlertEnabled)),
            ("vehicleHint", .string(c.vehicleHint.jsonName)),
        ])
    }

    static func encodeFix(_ f: FixRec) -> JsonValue {
        .object([("fixAtMs", long(f.fixAtMs)), ("lat", double(f.lat)), ("lng", double(f.lng)), ("accM", double(f.accM)),
                 ("d", double(f.d)), ("groundSample", optDouble(f.groundSample))])
    }

    static func encodePolicy(_ p: SamplingPolicy) -> JsonValue {
        .object([("tier", .string(p.tier.jsonName)), ("intervalS", int(p.intervalS)), ("minIntervalS", int(p.minIntervalS)),
                 ("accuracy", .string(p.accuracy.jsonName))])
    }

    private static func int(_ v: Int) -> JsonValue { .number(String(v)) }
    private static func long(_ v: Int64) -> JsonValue { .number(String(v)) }
    private static func double(_ v: Double) -> JsonValue { .number(v.description) }
    private static func optLong(_ v: Int64?) -> JsonValue { v.map(long) ?? .null }
    private static func optDouble(_ v: Double?) -> JsonValue { v.map(double) ?? .null }
    private static func optEnum(_ v: String?) -> JsonValue { v.map { .string($0) } ?? .null }

    // MARK: decode

    static func decode(_ json: String) throws(SnapshotError) -> EngineState {
        let root: JsonValue
        do { root = try MiniJson.parse(json) } catch { throw SnapshotError(rule: "malformed") }
        guard case .object = root else { throw SnapshotError(rule: "malformed") }
        guard let version = root["snapshotVersion"]?.asLongExact() else { throw SnapshotError(rule: "snapshotVersion invalid") }
        if version > 1 { throw SnapshotError(rule: "unsupported version") }
        if version != 1 { throw SnapshotError(rule: "snapshotVersion invalid") }
        let r = Reader(obj: root, path: "")
        let alarm = try r.object("alarm")
        let fb = try r.object("fallback")
        let bat = try r.object("battery")
        var ended: EndedState? = nil
        if let eo = try r.optObject("ended") {
            ended = EndedState(outcome: try eo.enumValue("outcome", TripOutcome.init(jsonName:)),
                               endReason: try eo.enumValue("endReason", EndReason.init(jsonName:)),
                               atMs: try eo.long("atMs"))
        }
        return EngineState(
            snapshotVersion: 1,
            params: try decodeParams(try r.object("params")),
            config: try decodeConfig(try r.object("config")),
            nowMs: try r.long("nowMs"), startedAtMs: try r.long("startedAtMs"),
            phase: try r.enumValue("phase", TripPhase.init(jsonName:)),
            gps: try r.enumValue("gps", GpsStatus.init(jsonName:)),
            locationCause: try r.enumValue("locationCause", AvailabilityCause.init(jsonName:)),
            last: try r.optObject("last").map(decodeFix), stopAnchor: try r.optObject("stopAnchor").map(decodeFix),
            recent: try r.array("recent").map { v throws(SnapshotError) in try decodeFix(try Reader.wrap(v, "recent")) },
            rejects: try r.array("rejects").map { v throws(SnapshotError) in try decodeFix(try Reader.wrap(v, "rejects")) },
            dSmooth: try r.optDouble("dSmooth"), dStartM: try r.optDouble("dStartM"), minD: try r.optDouble("minD"),
            minDChord: try r.boolOrFalse("minDChord"),
            passAnchorD: try r.optDoubleIfMissing("passAnchorD"),
            alarmedChordD: try r.optDoubleIfMissing("alarmedChordD"),   // T10.7 round 2: third named exception to C20
            last3: try r.doubleArray("last3"),
            ground: try r.optDouble("ground"), closing: try r.optDouble("closing"),
            movingTimeS: try r.double("movingTimeS"), movingSamples: try r.int("movingSamples"),
            movingDistM: try r.double("movingDistM"), stopStartMs: try r.optLong("stopStartMs"), slow: try r.bool("slow"),
            cvGuard: try r.doubleArray("cvGuard"),
            policy: try r.optObject("policy").map(decodePolicy),
            policyIntervalAtLastFixS: try r.int("policyIntervalAtLastFixS"),
            gpsLostAtMs: try r.optLong("gpsLostAtMs"), lostEmittedBeforeFirstFix: try r.bool("lostEmittedBeforeFirstFix"),
            preAlertArmed: try r.bool("preAlertArmed"), preAlertFired: try r.bool("preAlertFired"),
            arrivedFired: try r.bool("arrivedFired"),
            alarm: AlarmState(
                atMs: try alarm.optLong("atMs"), reason: try alarm.optEnum("reason", AlarmReason.init(jsonName:)),
                source: try alarm.optEnum("source", AlarmSource.init(jsonName:)),
                lastRingAtMs: try alarm.optLong("lastRingAtMs"),
                lastReason: try alarm.optEnum("lastReason", AlarmReason.init(jsonName:)),
                ringing: try alarm.bool("ringing"), snoozeCount: try alarm.int("snoozeCount"),
                snoozeUntilMs: try alarm.optLong("snoozeUntilMs"), dismissedAtMs: try alarm.optLong("dismissedAtMs")),
            overshootAtMs: try r.optLong("overshootAtMs"), overshootPastM: try r.optInt("overshootPastM"),
            fallback: FallbackState(
                targetAtMs: try fb.optLong("targetAtMs"), emittedAtMs: try fb.optLong("emittedAtMs"),
                status: try fb.enumValue("status", FallbackStatus.init(jsonName:)),
                confirmedAtMs: try fb.optLong("confirmedAtMs"), resync: try fb.bool("resync"), near: try fb.bool("near")),
            battery: BatteryState(
                levelPct: try bat.optInt("levelPct"), charging: try bat.bool("charging"), segT0: try bat.optLong("segT0"),
                segL0: try bat.optInt("segL0"), armed: try bat.bool("armed"), riskEmitted: try bat.bool("riskEmitted"),
                choice: try bat.optEnum("choice", UserActionKind.init(jsonName:)), choicePct: try bat.optInt("choicePct")),
            maxTripDurationS: try r.int("maxTripDurationS"), droppedFixes: try r.int("droppedFixes"), ended: ended)
    }

    /// Missing parameter keys take the default (T10.2: snapshots written before a parameter existed).
    static func decodeParams(_ r: Reader) throws(SnapshotError) -> EngineParams {
        var p = EngineParams.defaults
        for (i, spec) in ParamTable.PARAM_SPECS.enumerated() {
            guard let v = r.obj[spec.name] else { continue }
            switch spec.kind {
            case .int:
                guard let x = v.asIntExact() else { throw SnapshotError(rule: "params.\(spec.name) invalid") }
                p.set(at: i, .int(x))
            case .double:
                guard let x = v.asDouble() else { throw SnapshotError(rule: "params.\(spec.name) invalid") }
                p.set(at: i, .double(x))
            }
        }
        return p
    }

    static func decodeConfig(_ r: Reader) throws(SnapshotError) -> TripConfig {
        TripConfig(tripId: try r.string("tripId"), destLat: try r.double("destLat"), destLng: try r.double("destLng"),
                   mode: try r.enumValue("mode", AlarmMode.init(jsonName:)),
                   distanceThresholdM: try r.optInt("distanceThresholdM"), timeThresholdMin: try r.optInt("timeThresholdMin"),
                   preAlertEnabled: try r.bool("preAlertEnabled"),
                   vehicleHint: try r.enumValue("vehicleHint", VehicleKind.init(jsonName:)))
    }

    static func decodeFix(_ r: Reader) throws(SnapshotError) -> FixRec {
        FixRec(fixAtMs: try r.long("fixAtMs"), lat: try r.double("lat"), lng: try r.double("lng"), accM: try r.double("accM"),
               d: try r.double("d"), groundSample: try r.optDouble("groundSample"))
    }

    static func decodePolicy(_ r: Reader) throws(SnapshotError) -> SamplingPolicy {
        SamplingPolicy(tier: try r.enumValue("tier", SamplingTier.init(jsonName:)), intervalS: try r.int("intervalS"),
                       minIntervalS: try r.int("minIntervalS"),
                       accuracy: try r.enumValue("accuracy", AccuracyLevel.init(jsonName:)))
    }

    /// Typed field access; every failure is `snapshot: <field> invalid` (no content).
    struct Reader {
        let obj: JsonValue
        let path: String

        static func wrap(_ v: JsonValue, _ path: String) throws(SnapshotError) -> Reader {
            guard case .object = v else { throw SnapshotError(rule: "\(path) invalid") }
            return Reader(obj: v, path: path)
        }

        func name(_ k: String) -> String { path.isEmpty ? k : "\(path).\(k)" }
        func bad(_ k: String) -> SnapshotError { SnapshotError(rule: "\(name(k)) invalid") }

        func raw(_ k: String) throws(SnapshotError) -> JsonValue {
            guard let v = obj[k] else { throw bad(k) }
            return v
        }

        func long(_ k: String) throws(SnapshotError) -> Int64 {
            guard let v = try raw(k).asLongExact() else { throw bad(k) }
            return v
        }
        func optLong(_ k: String) throws(SnapshotError) -> Int64? {
            let v = try raw(k)
            if v.isNull { return nil }
            guard let x = v.asLongExact() else { throw bad(k) }
            return x
        }
        func int(_ k: String) throws(SnapshotError) -> Int {
            guard let v = try raw(k).asIntExact() else { throw bad(k) }
            return v
        }
        func optInt(_ k: String) throws(SnapshotError) -> Int? {
            let v = try raw(k)
            if v.isNull { return nil }
            guard let x = v.asIntExact() else { throw bad(k) }
            return x
        }
        func double(_ k: String) throws(SnapshotError) -> Double {
            guard let v = try raw(k).asDouble() else { throw bad(k) }
            return v
        }
        func optDouble(_ k: String) throws(SnapshotError) -> Double? {
            let v = try raw(k)
            if v.isNull { return nil }
            guard let x = v.asDouble() else { throw bad(k) }
            return x
        }
        func bool(_ k: String) throws(SnapshotError) -> Bool {
            guard let v = try raw(k).boolValue else { throw bad(k) }
            return v
        }
        /// T10.5 round 3e, named exception to C20: a missing key reads as false; a present key (even `null`) must be a bool.
        func boolOrFalse(_ k: String) throws(SnapshotError) -> Bool {
            if obj[k] == nil { return false }
            return try bool(k)
        }
        /// T10.6 (C28), second named exception to C20: a missing key reads as nil; a present key must be null or a finite number.
        func optDoubleIfMissing(_ k: String) throws(SnapshotError) -> Double? {
            if obj[k] == nil { return nil }
            return try optDouble(k)
        }
        func string(_ k: String) throws(SnapshotError) -> String {
            guard let v = try raw(k).stringValue else { throw bad(k) }
            return v
        }
        func enumValue<T>(_ k: String, _ make: (String) -> T?) throws(SnapshotError) -> T {
            guard let s = try raw(k).stringValue, let v = make(s) else { throw bad(k) }
            return v
        }
        func optEnum<T>(_ k: String, _ make: (String) -> T?) throws(SnapshotError) -> T? {
            let v = try raw(k)
            if v.isNull { return nil }
            guard let s = v.stringValue, let x = make(s) else { throw bad(k) }
            return x
        }
        func object(_ k: String) throws(SnapshotError) -> Reader {
            let v = try raw(k)
            guard case .object = v else { throw bad(k) }
            return Reader(obj: v, path: name(k))
        }
        func optObject(_ k: String) throws(SnapshotError) -> Reader? {
            let v = try raw(k)
            if v.isNull { return nil }
            guard case .object = v else { throw bad(k) }
            return Reader(obj: v, path: name(k))
        }
        func array(_ k: String) throws(SnapshotError) -> [JsonValue] {
            guard let a = try raw(k).arrayValue else { throw bad(k) }
            return a
        }
        func doubleArray(_ k: String) throws(SnapshotError) -> [Double] {
            var out: [Double] = []
            for v in try array(k) {
                guard let x = v.asDouble() else { throw bad(k) }
                out.append(x)
            }
            return out
        }
    }
}
