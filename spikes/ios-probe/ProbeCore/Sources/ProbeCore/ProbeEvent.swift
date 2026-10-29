import Foundation

/// One line of `events.jsonl` (S3 §6.6). `fields` holds the whole decoded object, common fields included.
public struct ProbeEvent: Equatable, Sendable {
    public let ev: String
    public let t: Date
    public let run: String
    public let pid: Int
    public let seq: Int
    public let launch: String
    public let fields: [String: JSONScalar]

    public init(ev: String, t: Date, run: String, pid: Int, seq: Int, launch: String, fields: [String: JSONScalar]) {
        self.ev = ev
        self.t = t
        self.run = run
        self.pid = pid
        self.seq = seq
        self.launch = launch
        self.fields = fields
    }

    /// Throws `FlatJsonError.malformed` when `ev` or a parsable `t` is missing.
    public static func parse(_ line: String) throws -> ProbeEvent {
        let map = try FlatJson.decode(line)
        guard let ev = map["ev"]?.stringValue else { throw FlatJsonError.malformed("missing ev") }
        guard let tText = map["t"]?.stringValue, let t = IsoTime.parse(tText) else {
            throw FlatJsonError.malformed("missing or bad t")
        }
        return ProbeEvent(
            ev: ev,
            t: t,
            run: map["run"]?.stringValue ?? "",
            pid: Int(map["pid"]?.intValue ?? 0),
            seq: Int(map["seq"]?.intValue ?? 0),
            launch: map["launch"]?.stringValue ?? "",
            fields: map
        )
    }

    /// Parses a whole file; blank lines are ignored, corrupt lines (e.g. cut by a process kill) are counted.
    public static func parseLines(_ text: String) -> (events: [ProbeEvent], corrupt: Int) {
        var events: [ProbeEvent] = []
        var corrupt = 0
        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if let e = try? parse(trimmed) {
                events.append(e)
            } else {
                corrupt += 1
            }
        }
        return (events, corrupt)
    }

    public func str(_ key: String) -> String? { fields[key]?.stringValue }

    public func int(_ key: String) -> Int64? { fields[key]?.intValue }

    public func double(_ key: String) -> Double? { fields[key]?.doubleValue }

    public func bool(_ key: String) -> Bool? { fields[key]?.boolValue }

    /// ISO field parsed as a date.
    public func date(_ key: String) -> Date? { str(key).flatMap { IsoTime.parse($0) } }
}
