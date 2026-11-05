import Foundation
@testable import Trip
@testable import TripRuntime

/// Thread-safe box for the fakes (all are `@unchecked Sendable` behind one lock).
class Locked: @unchecked Sendable {
    let lock = NSLock()
    func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

/// Ordered log of port calls (persistNow-before-ringNow checks, IU15 order).
final class OpLog: Locked, @unchecked Sendable {
    private var items: [String] = []
    func add(_ s: String) { locked { items.append(s) } }
    var ops: [String] { locked { items } }
    func clear() { locked { items.removeAll() } }
}

/// Virtual time: `v` ms since the world started; wall and elapsed move together unless the test changes the wall.
final class VirtualTime: Locked, TimeSource, @unchecked Sendable {
    private var vMs: Int64 = 0
    private var wallBase: Int64
    private var elapsedBase: Int64
    private var boot: String?
    var vMsValue: Int64 { vMs }
    var wallBaseValue: Int64 { wallBase }
    var elapsedBaseValue: Int64 { elapsedBase }
    var bootValue: String? { boot }
    func setAll(_ v: Int64, _ w: Int64, _ e: Int64, _ b: String?) { vMs = v; wallBase = w; elapsedBase = e; boot = b }

    init(wallBase: Int64, elapsedBase: Int64 = 1_000_000, boot: String? = "A") {
        self.wallBase = wallBase
        self.elapsedBase = elapsedBase
        self.boot = boot
    }

    var v: Int64 {
        get { locked { vMs } }
        set { locked { vMs = newValue } }
    }

    func wallMs() -> Int64 { locked { wallBase + vMs } }
    func elapsedMs() -> Int64 { locked { elapsedBase + vMs } }
    func bootSessionId() -> String? { locked { boot } }
    func shiftWall(_ ms: Int64) { locked { wallBase += ms } }
    func setBoot(_ b: String?) { locked { boot = b } }
    /// Reboot: elapsed restarts near 0, new boot id.
    func reboot(_ b: String?) { locked { elapsedBase = -vMs + 10_000; boot = b } }
    func setWall(_ w: Int64) { locked { wallBase = w - vMs } }
    func setElapsed(_ e: Int64) { locked { elapsedBase = e - vMs } }
}

/// Sleeps on virtual time; resumed by `advance` or `releaseAll`.
final class ManualSleeper: Locked, RuntimeSleeper, @unchecked Sendable {
    private var waiters: [(due: Int64, c: CheckedContinuation<Void, Never>)] = []
    let time: VirtualTime
    init(time: VirtualTime) { self.time = time }

    func sleep(ms: Int64) async {
        await withCheckedContinuation { c in locked { waiters.append((time.v + ms, c)) } }
    }

    var pendingCount: Int { locked { waiters.count } }

    func fireDue() {
        let due: [CheckedContinuation<Void, Never>] = locked {
            let now = time.v
            let d = waiters.filter { $0.due <= now }.map(\.c)
            waiters.removeAll { $0.due <= now }
            return d
        }
        for c in due { c.resume() }
    }

    func releaseAll() {
        let all: [CheckedContinuation<Void, Never>] = locked { let a = waiters.map(\.c); waiters = []; return a }
        for c in all { c.resume() }
    }
}

final class FakeLocationSession: Locked, LocationSession, @unchecked Sendable {
    let log: OpLog
    private(set) var running = false
    private(set) var spec: LocationRequestSpec?
    private(set) var starts = 0
    private(set) var retunes = 0
    weak var sinkRef: AnyObject?
    var startError: LocationStartError?
    var lastKnownFix: RawFix?
    /// Suspends start until `resumeStart` (IU16).
    var holdStart = false
    private var held: CheckedContinuation<Void, Never>?

    init(log: OpLog) { self.log = log }

    var sink: LocationSink? { locked { sinkRef as? LocationSink } }
    var isRunningNow: Bool { locked { running } }
    var currentSpec: LocationRequestSpec? { locked { spec } }
    var startCount: Int { locked { starts } }

    func start(_ spec: LocationRequestSpec, sink: LocationSink) async throws {
        locked { starts += 1 }
        log.add("location.start")
        if locked({ holdStart }) {
            await withCheckedContinuation { c in locked { held = c } }
        }
        if let e = locked({ startError }) { throw e }
        locked {
            running = true
            self.spec = spec
            sinkRef = sink
        }
    }

    func resumeStart() {
        let c: CheckedContinuation<Void, Never>? = locked { let h = held; held = nil; holdStart = false; return h }
        c?.resume()
    }

    var isHeld: Bool { locked { held != nil } }

    func retune(_ spec: LocationRequestSpec) async { locked { self.spec = spec; retunes += 1 } }
    func stop() async {
        log.add("location.stop")
        locked { running = false; spec = nil }
    }
    func kill() { locked { running = false; spec = nil; sinkRef = nil } }
    func isRunning() async -> Bool { locked { running } }
    func lastKnown() async -> RawFix? { locked { lastKnownFix } }
}

struct ScheduleFailure: Error {}

/// System alarms with AlarmKit-like behaviour: scheduled → alerting at fireAt; alerting → gone after `silenceAfterMs`.
final class FakeSystemAlarms: Locked, SystemAlarms, @unchecked Sendable {
    struct Entry {
        var info: SystemAlarmInfo
        var alertingSinceWall: Int64?
        var title: String
    }

    let log: OpLog
    let time: VirtualTime
    private var entries: [String: Entry] = [:]
    private var order: [String] = []
    private(set) var version = 0
    var silenceAfterMs: Int64?
    /// Throws for matching requests.
    var fail: ((SystemAlarmRequest) -> Bool)?
    var listUnreadable = false
    private(set) var scheduled: [SystemAlarmRequest] = []
    private(set) var cancels: [String] = []
    private(set) var stops: [String] = []
    private(set) var alertingTransitions = 0
    /// Every scheduled → alerting change (spec R4: recorded even without a process).
    private(set) var transitions: [(id: String, tripId: String, kind: SystemAlarmKind, wall: Int64)] = []
    /// Every schedule() with the wall time it happened.
    private(set) var scheduleLog: [(kind: SystemAlarmKind, wall: Int64)] = []
    private(set) var doubleRings = 0
    typealias State = (entries: [String: Entry], order: [String], version: Int, silence: Int64?, scheduled: [SystemAlarmRequest],
                       cancels: [String], stops: [String], alerting: Int, transitions: [(id: String, tripId: String, kind: SystemAlarmKind, wall: Int64)],
                       log: [(kind: SystemAlarmKind, wall: Int64)], doubles: Int)
    var stateTuple: State {
        (entries, order, version, silenceAfterMs, scheduled, cancels, stops, alertingTransitions, transitions, scheduleLog, doubleRings)
    }
    func restore(_ s: State) {
        entries = s.entries; order = s.order; version = s.version; silenceAfterMs = s.silence; scheduled = s.scheduled
        cancels = s.cancels; stops = s.stops; alertingTransitions = s.alerting; transitions = s.transitions; scheduleLog = s.log
        doubleRings = s.doubles
    }
    /// Called between schedule() and its return (IU23).
    var onSchedule: ((SystemAlarmRequest) -> Void)?

    init(log: OpLog, time: VirtualTime) {
        self.log = log
        self.time = time
    }

    func schedule(_ r: SystemAlarmRequest) async throws {
        log.add("schedule.\(r.kind.rawValue).\(r.channel.rawValue)")
        if let f = locked({ fail }), f(r) { throw ScheduleFailure() }
        locked {
            scheduled.append(r)
            scheduleLog.append((r.kind, time.wallMs()))
            entries[r.id] = Entry(info: SystemAlarmInfo(id: r.id, tripId: r.tripId, kind: r.kind, generation: r.generation,
                                                         state: .scheduled, fireAtWallMs: r.fireAtWallMs, channel: r.channel),
                                  alertingSinceWall: nil, title: r.title)
            order.append(r.id)
            version += 1
        }
        locked { onSchedule }?(r)
    }

    func cancel(id: String, channel: AlarmChannelKind) async {
        log.add("cancel")
        locked {
            cancels.append(id)
            if entries.removeValue(forKey: id) != nil { version += 1 }
        }
    }

    func stop(id: String, channel: AlarmChannelKind) async {
        log.add("stop")
        locked {
            stops.append(id)
            if entries.removeValue(forKey: id) != nil { version += 1 }
        }
    }

    func list() async -> [SystemAlarmInfo]? { locked { listUnreadable ? nil : snapshotLocked() } }

    private func snapshotLocked() -> [SystemAlarmInfo] { order.compactMap { entries[$0]?.info } }

    var all: [SystemAlarmInfo] { locked { snapshotLocked() } }

    func scheduledRequests() -> [SystemAlarmRequest] { locked { scheduled } }

    /// Next virtual ms at which a transition happens.
    func nextTransitionV(wallBaseOffset: Int64) -> Int64? {
        locked {
            var best: Int64?
            for e in entries.values {
                var w: Int64?
                if e.info.state == .scheduled { w = e.info.fireAtWallMs }
                if e.info.state == .alerting, let s = silenceAfterMs, let since = e.alertingSinceWall { w = since + s }
                if let w { best = min(best ?? w, w) }
            }
            return best.map { $0 - wallBaseOffset }
        }
    }

    /// Applies due transitions at the current virtual time.
    func tick() {
        locked {
            let wall = time.wallMs()
            var changed = false
            for id in order {
                guard var e = entries[id] else { continue }
                if e.info.state == .scheduled, let f = e.info.fireAtWallMs, f <= wall {
                    e.info = SystemAlarmInfo(id: id, tripId: e.info.tripId, kind: e.info.kind, generation: e.info.generation,
                                             state: .alerting, fireAtWallMs: f, channel: e.info.channel)
                    e.alertingSinceWall = f
                    entries[id] = e
                    alertingTransitions += 1
                    transitions.append((id, e.info.tripId, e.info.kind, f))
                    changed = true
                } else if e.info.state == .alerting, let s = silenceAfterMs, let since = e.alertingSinceWall, since + s <= wall {
                    entries[id] = nil
                    changed = true
                }
            }
            order.removeAll { entries[$0] == nil }
            let ringing = Dictionary(grouping: entries.values.filter { $0.info.state == .alerting }, by: { $0.info.tripId })
            if ringing.values.contains(where: { $0.count > 1 }) { doubleRings += 1 }
            if changed { version += 1 }
        }
    }

    /// Test hook: force a state (IU23, IU26).
    func setState(_ id: String, _ s: SystemAlarmState?) {
        locked {
            guard var e = entries[id] else { return }
            if let s {
                e.info = SystemAlarmInfo(id: id, tripId: e.info.tripId, kind: e.info.kind, generation: e.info.generation,
                                         state: s, fireAtWallMs: e.info.fireAtWallMs, channel: e.info.channel)
                if s == .alerting { e.alertingSinceWall = time.wallMs(); alertingTransitions += 1; transitions.append((id, e.info.tripId, e.info.kind, time.wallMs())) }
                entries[id] = e
            } else {
                entries[id] = nil
                order.removeAll { $0 == id }
            }
            version += 1
        }
    }
}

final class FakeStore: Locked, RuntimeStore, @unchecked Sendable {
    let log: OpLog
    private var active: Data?
    private var ledger = AlarmLedger.empty
    private var events: [RingEventRec] = []
    private(set) var finished: [String: FinishedRecord] = [:]
    typealias State = (active: Data?, ledger: AlarmLedger, events: [RingEventRec], finished: [String: FinishedRecord])
    var stateTuple: State { (active, ledger, events, finished) }
    func restore(_ s: State) { active = s.active; ledger = s.ledger; events = s.events; finished = s.finished }
    var failWriteActive: (() -> Error?)?
    var failWriteFinished = false
    /// Blocks writeActive until signalled (IU20).
    var writeGate: DispatchSemaphore?
    private(set) var writeActiveCount = 0

    init(log: OpLog) { self.log = log }

    func readActive() throws -> StoredTrip? {
        guard let d = locked({ active }) else { return nil }
        do { return try StoredTripCodec.decode(d) } catch {
            locked { active = nil }
            throw error
        }
    }

    func writeActive(_ t: StoredTrip) throws {
        if let g = locked({ writeGate }) { g.wait() }
        if let e = locked({ failWriteActive })?() { throw e }
        locked { active = StoredTripCodec.encode(t); writeActiveCount += 1 }
        log.add("writeActive")
    }

    func deleteActive() { locked { active = nil }; log.add("deleteActive") }
    func setActiveRaw(_ d: Data?) { locked { active = d } }
    var activeTrip: StoredTrip? { locked { active.flatMap { try? StoredTripCodec.decode($0) } } }
    func readLedger() -> AlarmLedger { locked { ledger } }
    func writeLedger(_ l: AlarmLedger) throws { locked { ledger = l } }
    var currentLedger: AlarmLedger { locked { ledger } }
    func readRingEvents() -> [RingEventRec] { locked { events } }
    func appendRingEvent(_ e: RingEventRec) throws { locked { events.append(e); if events.count > 16 { events.removeFirst() } } }
    func removeRingEvents(tripId: String) { locked { events.removeAll { $0.tripId == tripId } } }

    func writeFinished(_ r: FinishedRecord) throws {
        if locked({ failWriteFinished }) { throw ScheduleFailure() }
        locked { finished[r.tripId] = r }
        log.add("writeFinished")
    }

    func readFinished() -> [FinishedRecord] { locked { Array(finished.values) } }
    func deleteFinished(_ ids: [String]) { locked { for i in ids { finished[i] = nil } } }

    // T17.2: launch_action.json (survives newProcess() like the other files; forkKilled() does not copy it).
    private var launch: LaunchActionRec?
    func readLaunchAction() -> LaunchActionRec? { locked { launch } }
    func writeLaunchAction(_ r: LaunchActionRec) throws { locked { launch = r }; log.add("writeLaunchAction") }
    func deleteLaunchAction() { locked { launch = nil } }
}

final class FakeEnv: Locked, DeviceEnv, @unchecked Sendable {
    var access = LocationAccess(whenInUseOrAlways: true, fullAccuracy: true, servicesEnabled: true)
    var channels = ChannelAccess(alarmKit: .authorized, notifications: true)
    var batteryReading: BatteryReading?
    func locationAccess() async -> LocationAccess { locked { access } }
    func channelAccess() async -> ChannelAccess { locked { channels } }
    func battery() async -> BatteryReading? { locked { batteryReading } }
}

final class FakeApp: Locked, AppStatePort, @unchecked Sendable {
    var state: AppActivity = .active
    func activity() async -> AppActivity { locked { state } }
}

final class FakeNotifier: Locked, TripNotifier, @unchecked Sendable {
    private(set) var shown: [TripNotice] = []
    private(set) var cleared: [TripNotice] = []
    private(set) var clearAllCount = 0
    func show(tripId: String, _ notice: TripNotice, destinationName: String?) async { locked { shown.append(notice) } }
    func clear(tripId: String, _ notice: TripNotice) async { locked { cleared.append(notice) } }
    func clearAll(tripId: String) async { locked { clearAllCount += 1 } }
    var shownNow: [TripNotice] { locked { shown } }
    var clearedNow: [TripNotice] { locked { cleared } }
}

final class FakeTimer: Locked, WakeTimer, @unchecked Sendable {
    let time: VirtualTime
    private(set) var dueV: Int64?
    private(set) var generation: Int64 = 0
    private(set) var sets: [(atV: Int64, delay: Int64)] = []
    init(time: VirtualTime) { self.time = time }
    func set(delayMs: Int64, generation: Int64) {
        locked {
            dueV = time.v + delayMs
            self.generation = generation
            sets.append((time.v, delayMs))
        }
    }
    func cancel() { locked { dueV = nil } }
    var due: (v: Int64, gen: Int64)? { locked { dueV.map { ($0, generation) } } }
    func consume() { locked { dueV = nil } }
}

final class FakeBg: Locked, BackgroundTasks, @unchecked Sendable {
    private var next = 1
    private(set) var open: Set<Int> = []
    func begin(_ name: String) -> Int { locked { let t = next; next += 1; open.insert(t); return t } }
    func end(_ token: Int) { locked { _ = open.remove(token) } }
    var openCount: Int { locked { open.count } }
}

final class RecordingJournal: Locked, RuntimeJournal, @unchecked Sendable {
    private(set) var lines: [(ev: String, fields: [String: String])] = []
    func record(_ event: String, _ fields: [String: String]) { locked { lines.append((event, fields)) } }
    var all: [(ev: String, fields: [String: String])] { locked { lines } }
}

/// What the listener received (one entry per Publish).
final class Seen: Locked, @unchecked Sendable {
    struct Entry { let view: TripView; let choice: UserActionKind?; let events: [TripEvent] }
    private var items: [Entry] = []
    func add(_ e: Entry) { locked { items.append(e) } }
    var entries: [Entry] { locked { items } }
    var events: [TripEvent] { entries.flatMap(\.events) }
    func firstAlarm() -> TripEvent.Alarm? {
        for case let .alarm(a) in events { return a }
        return nil
    }
}

final class Counter: Locked, @unchecked Sendable {
    private var n = 0
    func inc() { locked { n += 1 } }
    var value: Int { locked { n } }
}

extension FakeSystemAlarms {
    var transitionList: [(id: String, tripId: String, kind: SystemAlarmKind, wall: Int64)] { locked { transitions } }
    var schedules: [(kind: SystemAlarmKind, wall: Int64)] { locked { scheduleLog } }
}

// MARK: - Forking a dead process state (ITR31: one prefix run, many branches)

extension VirtualTime {
    func copyState(from o: VirtualTime) {
        let s: (Int64, Int64, Int64, String?) = o.locked { (o.vMsValue, o.wallBaseValue, o.elapsedBaseValue, o.bootValue) }
        locked { setAll(s.0, s.1, s.2, s.3) }
    }
}

extension FakeSystemAlarms {
    func copyState(from o: FakeSystemAlarms) {
        let s = o.locked { o.stateTuple }
        locked { restore(s) }
    }
}

extension FakeStore {
    func copyState(from o: FakeStore) {
        let s = o.locked { o.stateTuple }
        locked { restore(s) }
    }
}
