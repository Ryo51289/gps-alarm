import Foundation

/// Alarm channel of a run (S3 §5.1).
enum ProbeChannel: String, CaseIterable, Codable, Identifiable {
    /// AlarmKit (iOS 26+).
    case AK
    /// Time Sensitive notification + 29 s tone, 3 times 30 s apart.
    case TS
    /// Try to start audio from the background (H8), plus TS.
    case AU

    var id: String { rawValue }

    var label: String {
        switch self {
        case .AK: return "AlarmKit"
        case .TS: return "Thông báo Time Sensitive"
        case .AU: return "Thử âm thanh nền (+ thông báo)"
        }
    }
}

/// Scenario presets of S3 §5.2 (S3-0 and S3-13 have their own buttons).
struct ScenarioPreset: Identifiable, Hashable {
    let id: String
    let channel: ProbeChannel
    let longRun: Bool
    let hint: String

    static let all: [ScenarioPreset] = [
        ScenarioPreset(id: "S3-1", channel: .AK, longRun: false, hint: "Khoá máy, chuông bật"),
        ScenarioPreset(id: "S3-2", channel: .AK, longRun: false, hint: "Im lặng"),
        ScenarioPreset(id: "S3-3", channel: .AK, longRun: false, hint: "Im lặng + Không làm phiền"),
        ScenarioPreset(id: "S3-4", channel: .AK, longRun: false, hint: "Im lặng + Ngủ"),
        ScenarioPreset(id: "S3-5", channel: .AK, longRun: false, hint: "Im lặng + Không làm phiền + Nguồn điện thấp"),
        ScenarioPreset(id: "S3-6", channel: .AK, longRun: false, hint: "Bấm “Dừng vị trí (giữ lượt)” rồi khoá"),
        ScenarioPreset(id: "S3-7", channel: .AK, longRun: false, hint: "Bấm “Tự thoát sau 30 giây” rồi khoá"),
        ScenarioPreset(id: "S3-8", channel: .AK, longRun: false, hint: "Vuốt tắt app rồi khoá"),
        ScenarioPreset(id: "S3-9", channel: .TS, longRun: false, hint: "Thông báo, chuông bật"),
        ScenarioPreset(id: "S3-10", channel: .TS, longRun: false, hint: "Thông báo + Im lặng"),
        ScenarioPreset(id: "S3-11", channel: .TS, longRun: false, hint: "Thông báo + Không làm phiền"),
        ScenarioPreset(id: "S3-12", channel: .AK, longRun: true, hint: "Lượt dài qua đêm: Im lặng + Ngủ, rút sạc"),
        ScenarioPreset(id: "S3-14", channel: .AU, longRun: false, hint: "Thử âm thanh nền, chuông bật"),
        ScenarioPreset(id: "S3-15", channel: .AK, longRun: false, hint: "Không khoá máy, đang phát video có tiếng"),
    ]

    static func find(_ id: String) -> ScenarioPreset {
        all.first { $0.id == id } ?? all[0]
    }
}

/// The active run (persisted, no coordinates).
struct RunConfig: Codable, Equatable {
    var runId: String
    var scenario: String
    var channel: ProbeChannel
    var delayMin: Int
    var durationMin: Int
    var densePhaseMin: Int
    var prearm: Bool
    /// S3-13: location only arms the walk monitor; no alarm on the deadline.
    var walk: Bool
    var startedAt: Date
    var deadline: Date
}

/// Mutable state of the active run (persisted so a new process continues it).
struct RunState: Codable, Equatable {
    var fired = false
    var firedAt: Date?
    var lastReschedule: Date?
    var locSuspended = false
    var walkArmed = false
}

/// Which run/kind an AlarmKit alarm id belongs to (for ak_state lines).
struct AlarmRef: Codable, Equatable {
    var runId: String
    var kind: String
}

/// UserDefaults persistence (S3 §6.4). Thread-safe (UserDefaults is); read-modify-write helpers take a lock.
final class RunStore: @unchecked Sendable {
    static let shared = RunStore()

    private let defaults = UserDefaults.standard
    private let lock = NSLock()

    private enum Key {
        static let config = "probe.run.config"
        static let state = "probe.run.state"
        static let alarmRefs = "probe.ak.refs"
        static let prearmAlarm = "probe.ak.prearm"
        static let delivered = "probe.notif.loggedDelivered"
        static let cleanExit = "probe.proc.cleanExit"
    }

    func loadConfig() -> RunConfig? { decode(RunConfig.self, Key.config) }

    func saveConfig(_ config: RunConfig?) { encode(config, Key.config) }

    func loadState() -> RunState { decode(RunState.self, Key.state) ?? RunState() }

    func saveState(_ state: RunState) { encode(state, Key.state) }

    // MARK: AlarmKit ids

    func alarmRef(_ id: String) -> AlarmRef? {
        lock.lock()
        defer { lock.unlock() }
        return refs()[id]
    }

    func setAlarmRef(_ id: String, _ ref: AlarmRef?) {
        lock.lock()
        defer { lock.unlock() }
        var all = refs()
        all[id] = ref
        // Keep the map small (a run uses a handful of ids; old runs do not matter).
        if all.count > 200 {
            for key in all.keys.sorted().prefix(all.count - 200) { all[key] = nil }
        }
        encode(all, Key.alarmRefs)
    }

    func alarmIds(run: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return refs().filter { $0.value.runId == run }.map { $0.key }
    }

    var prearmAlarmId: String? {
        get { defaults.string(forKey: Key.prearmAlarm) }
        set { defaults.set(newValue, forKey: Key.prearmAlarm) }
    }

    private func refs() -> [String: AlarmRef] { decode([String: AlarmRef].self, Key.alarmRefs) ?? [:] }

    // MARK: Delivered notifications already logged

    /// Returns the ids not logged yet and marks them as logged.
    func claimDelivered(_ ids: [String]) -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        var logged = Set(defaults.stringArray(forKey: Key.delivered) ?? [])
        let fresh = Set(ids).subtracting(logged)
        if !fresh.isEmpty {
            logged.formUnion(fresh)
            var list = Array(logged)
            if list.count > 500 { list = Array(list.sorted().suffix(500)) }
            defaults.set(list, forKey: Key.delivered)
        }
        return fresh
    }

    // MARK: Clean exit flag (proc_start.prevCleanExit)

    /// Whether the previous process ended with run_stop / will_terminate / self_exit_now; resets the flag.
    func consumeCleanExit() -> Bool {
        let previous = defaults.object(forKey: Key.cleanExit) as? Bool ?? true
        defaults.set(false, forKey: Key.cleanExit)
        return previous
    }

    func markCleanExit(_ clean: Bool) {
        defaults.set(clean, forKey: Key.cleanExit)
    }

    // MARK: Codable helpers

    private func decode<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T?, _ key: String) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}
