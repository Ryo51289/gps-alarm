import Foundation
@testable import Trip
@testable import TripRuntime

/// One test world: virtual time + fakes + a runtime "process". `newProcess()` simulates a process death and relaunch
/// (store and system alarms survive, runtime memory does not).
final class World: @unchecked Sendable {
    let log = OpLog()
    let time: VirtualTime
    let location: FakeLocationSession
    let alarms: FakeSystemAlarms
    let store: FakeStore
    let env = FakeEnv()
    let app = FakeApp()
    let notifier = FakeNotifier()
    let timer: FakeTimer
    let sleeper: ManualSleeper
    let bg = FakeBg()
    let journal = RecordingJournal()
    let seen = Seen()
    let warnings = Locked()
    private var warningList: [String] = []
    var constants: RuntimeConstants
    var locale = "vi"
    private(set) var runtime: TripRuntime!
    private var emittedVersion = -1
    let startWall: Int64

    init(startWall: Int64 = 1_700_000_000_000, constants: RuntimeConstants = .default) {
        self.startWall = startWall
        self.constants = constants
        time = VirtualTime(wallBase: startWall)
        location = FakeLocationSession(log: log)
        alarms = FakeSystemAlarms(log: log, time: time)
        store = FakeStore(log: log)
        timer = FakeTimer(time: time)
        sleeper = ManualSleeper(time: time)
        runtime = makeRuntime()
    }

    var warns: [String] { warnings.locked { warningList } }

    private func makeRuntime() -> TripRuntime {
        let ports = RuntimePorts(time: time, location: location, alarms: alarms, store: store, env: env, app: app,
                                 notifier: notifier, timer: timer, sleeper: sleeper, bgTasks: bg, journal: journal,
                                 localeTag: { [weak self] in self?.locale ?? "vi" })
        return TripRuntime(ports: ports, constants: constants, warn: { [weak self] s in
            guard let self else { return }
            self.warnings.locked { self.warningList.append(s) }
        })
    }

    /// Process death: memory lost, location stops (iOS kills the session with the process), timer gone.
    func newProcess() {
        runtime = makeRuntime()
        location.kill()
        timer.cancel()
        emittedVersion = -1
    }

    /// No process (spec R4): the runtime gets nothing until `relaunch`; system alarms keep changing.
    private(set) var dead = false
    /// Process frozen (ITR32): nothing delivered; the timer stays armed.
    var suspended = false

    func kill() {
        dead = true
        location.kill()
        timer.cancel()
    }

    /// A new process (P2) launched with the given app state; its alarmUpdates start with the next change.
    func relaunch(_ state: AppActivity) {
        app.state = state
        runtime = makeRuntime()
        dead = false
        emittedVersion = alarms.version
    }

    private var asleep: Bool { dead || suspended }

    /// A copy of what survives a process death right now (store, system alarms, clock); the copy has no process.
    func forkKilled() -> World {
        let f = World(startWall: startWall, constants: constants)
        f.time.copyState(from: time)
        f.alarms.copyState(from: alarms)
        f.store.copyState(from: store)
        f.kill()
        return f
    }

    func listen() async {
        let seen = self.seen
        _ = await runtime.addListener { _, view, choice, events in seen.add(.init(view: view, choice: choice, events: events)) }
    }

    /// Waits for the queue, then reports changed system alarms (alarmUpdates) until stable.
    func settle() async {
        if asleep { return }
        await runtime.drain()
        var guardCount = 0
        while alarms.version != emittedVersion && guardCount < 20 {
            emittedVersion = alarms.version
            await runtime.onSystemAlarms(alarms.all)
            await runtime.drain()
            guardCount += 1
        }
    }

    /// Moves virtual time to `v`, delivering system alarm transitions and the in-process timer on time.
    func advance(to v: Int64) async {
        var spins = 0
        while spins < 200_000 {
            spins += 1
            let tNext = asleep ? nil : timer.due?.v
            let aNext = alarms.nextTransitionV(wallBaseOffset: time.wallMs() - time.v)
            let next = [tNext, aNext].compactMap { $0 }.filter { $0 <= v }.min()
            guard let n = next else { break }
            if n > time.v { time.v = n }
            alarms.tick()
            await settle()
            if !asleep, let d = timer.due, d.v <= time.v {
                timer.consume()
                await runtime.onTimer(generation: d.gen)
                await settle()
            }
        }
        if v > time.v { time.v = v }
        alarms.tick()
        await settle()
    }

    func advance(by ms: Int64) async { await advance(to: time.v + ms) }

    func emit(_ fix: RawFix) async {
        location.sink?.locationSession(didReceive: fix)
        await settle()
    }

    /// Trip-clock ms of virtual time `v` for a trip started at v = 0.
    func tripMs(atV v: Int64) -> Int64 { startWall + v }
}

enum TestData {
    static let settings = RingSettings(soundId: "default", volume: 0.8, rampUp: true, vibration: "medium", flash: false,
                                       preferHeadphones: false, dismissMethod: "swipe")

    static func meta(_ tripId: String = "t1", mode: AlarmMode = .distance, distanceM: Int? = 1000, timeMin: Int? = nil,
                     name: String = "Ga Đông Hà", params: String? = nil) -> TripMeta {
        TripMeta(tripId: tripId, destinationName: name, mode: mode, distanceThresholdM: distanceM, timeThresholdMin: timeMin,
                 preAlertEnabled: false, vehicleHint: .train, alarm: settings, engineParamsJson: params)
    }

    /// Destination used by the synthetic unit tests (Đông Hà) and a point ≈ `km` km south of it.
    static let destLat = 16.8163
    static let destLng = 107.1003
    static func fix(kmSouth km: Double, wall: Int64, acc: Double = 8, speed: Double = 15) -> RawFix {
        RawFix(lat: destLat - km / 111.2, lng: destLng, horizontalAccuracyM: acc, speedMps: speed, timestampWallMs: wall)
    }
}
