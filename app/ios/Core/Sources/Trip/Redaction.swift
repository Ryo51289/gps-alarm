// Privacy (T10 §10, U80): types holding coordinates never print them through description, debugDescription,
// String(reflecting:), dump() or Mirror.

extension TripConfig: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "TripConfig(tripId: \(tripId), mode: \(mode.jsonName), dest: <redacted>, distanceThresholdM: "
            + "\(distanceThresholdM.map(String.init) ?? "nil"), timeThresholdMin: \(timeThresholdMin.map(String.init) ?? "nil"), "
            + "preAlertEnabled: \(preAlertEnabled), vehicleHint: \(vehicleHint.jsonName))"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["tripId": tripId, "mode": mode, "destination": "<redacted>",
                                "distanceThresholdM": distanceThresholdM as Any, "timeThresholdMin": timeThresholdMin as Any,
                                "preAlertEnabled": preAlertEnabled, "vehicleHint": vehicleHint], displayStyle: .struct)
    }
}

extension LocationFix: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "LocationFix(atMs: \(atMs), fixAtMs: \(fixAtMs), position: <redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["atMs": atMs, "fixAtMs": fixAtMs, "position": "<redacted>"], displayStyle: .struct)
    }
}

extension FixRec: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    var description: String { "FixRec(<redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: ["value": "<redacted>"], displayStyle: .struct) }
}

extension EngineState: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "EngineState(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["value": "<redacted>"], displayStyle: .struct) }
}

extension EngineInput: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        switch self {
        case let .locationFix(f): "locationFix(\(f.description))"
        case let .tick(a): "tick(atMs: \(a))"
        case let .batterySample(a, l, c): "batterySample(atMs: \(a), levelPct: \(l), charging: \(c))"
        case let .locationAvailability(a, c): "locationAvailability(atMs: \(a), cause: \(c.jsonName))"
        case let .fallbackScheduled(a, f, ok): "fallbackScheduled(atMs: \(a), fallbackAtMs: \(f), ok: \(ok))"
        case let .fallbackFired(a, f): "fallbackFired(atMs: \(a), firedAtMs: \(f))"
        case let .alarmSilenced(a, s): "alarmSilenced(atMs: \(a), silencedAtMs: \(s))"
        case let .userAction(a, k): "userAction(atMs: \(a), action: \(k.jsonName))"
        }
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["input": description], displayStyle: .enum) }
}

extension Step: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "Step(state: <redacted>, events: \(events.count), phase: \(view.phase.jsonName))" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["state": "<redacted>", "events": events, "view": view], displayStyle: .struct)
    }
}
