// iOS trip runtime (docs/specs/T17.md §4.4, §5): one actor, one FIFO command queue (D2). Every public entry point
// enqueues a command and waits for it; awaits inside a command (AlarmKit, disk, listeners) never let another command
// start. Feeds produced by a command run right after it, before the next external command.
import Foundation
import Trip

public enum StartOutcome: Sendable, Equatable {
    case started
    /// BridgeErrors wire codes (T14 §4).
    case rejected(code: String, message: String?, details: [String]?)
}

public struct RuntimePorts: Sendable {
    public let time: TimeSource
    public let location: LocationSession
    public let alarms: SystemAlarms
    public let store: RuntimeStore
    public let env: DeviceEnv
    public let app: AppStatePort
    public let notifier: TripNotifier
    public let timer: WakeTimer
    public let sleeper: RuntimeSleeper
    public let bgTasks: BackgroundTasks
    public let journal: RuntimeJournal
    /// "vi" | "en": UserDefaults napstop.appLocale, else device (D19).
    public let localeTag: @Sendable () -> String

    public init(time: TimeSource, location: LocationSession, alarms: SystemAlarms, store: RuntimeStore, env: DeviceEnv,
                app: AppStatePort, notifier: TripNotifier, timer: WakeTimer, sleeper: RuntimeSleeper,
                bgTasks: BackgroundTasks, journal: RuntimeJournal, localeTag: @escaping @Sendable () -> String) {
        self.time = time
        self.location = location
        self.alarms = alarms
        self.store = store
        self.env = env
        self.app = app
        self.notifier = notifier
        self.timer = timer
        self.sleeper = sleeper
        self.bgTasks = bgTasks
        self.journal = journal
        self.localeTag = localeTag
    }
}

/// Synchronous start gate (§5.1, review T25 round 2): a second start is refused at once.
final class StartGate: @unchecked Sendable {
    private let lock = NSLock()
    private var busy = false
    func tryAcquire() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if busy { return false }
        busy = true
        return true
    }
    func force() { lock.lock(); busy = true; lock.unlock() }
    func release() { lock.lock(); busy = false; lock.unlock() }
}

/// Copy of the latest committed state outside the queue, for `applicationWillTerminate` on the main thread (review #8:
/// the main thread must not wait for a queue that may itself wait for main).
final class TerminateCache: @unchecked Sendable {
    private let lock = NSLock()
    private var value: (meta: TripMeta, anchor: ClockAnchor, engine: EngineState, phase: TripPhase)?
    func set(_ v: (meta: TripMeta, anchor: ClockAnchor, engine: EngineState, phase: TripPhase)?) {
        lock.lock(); value = v; lock.unlock()
    }
    func get() -> (meta: TripMeta, anchor: ClockAnchor, engine: EngineState, phase: TripPhase)? {
        lock.lock(); defer { lock.unlock() }; return value
    }
}

public actor TripRuntime: LocationSink {
    struct Job: Sendable { let run: @Sendable (isolated TripRuntime) async -> Void }

    struct Active {
        var meta: TripMeta
        var engine: EngineState
        var view: TripView?
        var params: EngineParams
    }

    enum DeferredKind: Equatable {
        case restoreSettle
        case goneCheck(id: String, goneAtWallMs: Int64)
        case endBgTask(token: Int)
    }

    struct Deferred: Equatable { let dueWallMs: Int64; let kind: DeferredKind }

    let ports: RuntimePorts
    let constants: RuntimeConstants
    let warn: @Sendable (String) -> Void
    private nonisolated let queue: AsyncStream<Job>.Continuation
    private nonisolated let gate = StartGate()
    private nonisolated let terminateCache = TerminateCache()
    private let writer: SnapshotWriter

    private var loaded = false
    private var active: Active?
    private var clock: TripClock?
    private var ledger = AlarmLedger.empty
    private var trackingMode: TrackingMode = .idle
    private var restorePending = false
    private var throttle: FixThrottle
    private var currentSpec: LocationRequestSpec?
    private var engineDueTripMs: Int64?
    private var deferred: [Deferred] = []
    private var timerGen: Int64 = 0
    private var armedWallMs: Int64?
    private var listeners: [Int: RuntimeListener] = [:]
    private var nextListener = 1
    private var feeds: [EngineInput] = []
    private var lastList: [SystemAlarmInfo] = []
    private var prevUpdates: [SystemAlarmInfo] = []
    private var expectedStops: Set<String> = []
    private var pendingFinishedMem: [FinishedRecord] = []
    private var ringRetryPending = false
    private var lastRingRetryWallMs: Int64 = 0
    private var lastBattery: BatteryReading?
    private var lastAvailability: AvailabilityCause = .available
    private var lastPersistWallMs: Int64 = 0
    private var batteryChoiceMem: UserActionKind?
    private var droppedPlatform = 0
    /// Reads the engine-state facts at restore. Tests replace it (`setFactsReaderForTesting`) to check review #9.
    private var factsReader: @Sendable (EngineState) -> EngineFacts? = { EngineFacts.read($0) }
    /// Ring events handed over by a StopIntent in memory (also used when its disk write failed, tester T17 #2).
    private var memoryRingEvents: [RingEventRec] = []
    /// Flutter calls made while a background restore waits for D13 (spec R2 "D13 (#6)").
    private var restoreWaiters: [CheckedContinuation<Void, Never>] = []

    public init(ports: RuntimePorts, constants: RuntimeConstants = .default, warn: @escaping @Sendable (String) -> Void) {
        self.ports = ports
        self.constants = constants
        self.warn = warn
        throttle = FixThrottle(slackMs: constants.fixThrottleSlackMs)
        writer = SnapshotWriter(store: ports.store, warn: warn, journal: ports.journal)
        let (stream, cont) = AsyncStream<Job>.makeStream()
        queue = cont
        Task { [weak self] in
            for await job in stream {
                guard let self else { return }
                await self.runJob(job)
            }
        }
    }

    private func runJob(_ job: Job) async {
        await job.run(self)
        await drainFeeds()
        rearm()
    }

    private nonisolated func enqueue(_ body: @escaping @Sendable (isolated TripRuntime) async -> Void) {
        queue.yield(Job(run: body))
    }

    private nonisolated func submit<T: Sendable>(_ body: @escaping @Sendable (isolated TripRuntime) async -> T) async -> T {
        await withCheckedContinuation { (c: CheckedContinuation<T, Never>) in
            queue.yield(Job { rt in c.resume(returning: await body(rt)) })
        }
    }

    // MARK: - Public API

    public func ensureLoaded() async { await submit { rt in await rt.load() } }

    public func start(meta: TripMeta, destLat: Double, destLng: Double) async -> StartOutcome {
        if !gate.tryAcquire() { return .rejected(code: "trip-active", message: nil, details: nil) }
        return await submit { rt in await rt.doStart(meta, destLat, destLng) }
    }

    public func userAction(tripId: String, _ kind: UserActionKind) async {
        await waitRestoreIfBackground()
        await submit { rt in await rt.doUserAction(tripId, kind) }
    }

    public func current() async -> (meta: TripMeta, view: TripView)? {
        await waitRestoreIfBackground()
        let r: CurrentBox = await submit { rt in await rt.doCurrent() }
        return r.value
    }

    public func batteryChoice() async -> UserActionKind? { await submit { rt in rt.batteryChoiceMem } }

    public func pendingFinished() async -> [FinishedRecord] { await submit { rt in await rt.doPendingFinished() } }

    public func ackFinished(_ ids: [String]) async { await submit { rt in rt.doAck(ids) } }

    public nonisolated func locationSession(didReceive fix: RawFix) { enqueue { rt in await rt.handleFix(fix) } }

    public nonisolated func locationSession(availabilityChanged cause: AvailabilityCause) {
        enqueue { rt in await rt.handleAvailability(cause) }
    }

    public nonisolated func submitBattery(_ b: BatteryReading) { enqueue { rt in await rt.handleBattery(b) } }

    public func onTimer(generation: Int64) async { await submit { rt in await rt.handleTimer(generation) } }

    public func onSystemAlarms(_ alarms: [SystemAlarmInfo]) async { await submit { rt in await rt.handleSystemAlarms(alarms) } }

    public func onStopIntent(_ e: RingEventRec) async { await submit { rt in await rt.handleStopIntent(e) } }

    public func onAppActive() async { await submit { rt in await rt.handleAppActive() } }

    public func onAppBackground() async { await submit { rt in rt.ports.journal.record("app", ["state": "background"]) } }

    public func onWillTerminate() async { await submit { rt in await rt.handleWillTerminate() } }

    public func onClockChanged() async { await submit { rt in await rt.handleClockChanged() } }

    public func addListener(_ l: @escaping RuntimeListener) async -> Int {
        await waitRestoreIfBackground()
        return await submit { rt in await rt.doAddListener(l) }
    }

    public func removeListener(_ token: Int) async { await submit { rt in rt.listeners[token] = nil } }

    public func mode() async -> TrackingMode { await submit { rt in rt.trackingMode } }

    /// For `applicationWillTerminate` (main thread, never waits for the queue): the last committed trip as a snapshot,
    /// its id, and whether the "interrupted" notice applies (phase ACQUIRING/TRACKING). nil = no trip.
    public nonisolated func terminateSnapshot(wallMs: Int64) -> (trip: StoredTrip, tripId: String, interrupted: Bool)? {
        guard let v = terminateCache.get() else { return nil }
        let t = StoredTrip(meta: v.meta, anchor: v.anchor, engineSnapshot: TripEngine.encodeSnapshot(v.engine), savedAtWallMs: wallMs)
        return (t, v.meta.tripId, v.phase == .acquiring || v.phase == .tracking)
    }

    /// D13 (spec R2): while the app is not active and a restore waits for StopIntent / app active / the settle time,
    /// a Flutter call waits too instead of completing the restore early.
    private nonisolated func waitRestoreIfBackground() async {
        let wait: Bool = await submit { rt in
            await rt.load()
            guard rt.restorePending else { return false }
            return await rt.ports.app.activity() != .active
        }
        guard wait else { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            enqueue { rt in
                if rt.restorePending { rt.restoreWaiters.append(c) } else { c.resume() }
            }
        }
    }

    /// Test seam (internal): review #9, an unreadable engine state at restore.
    func setFactsReaderForTesting(_ r: @escaping @Sendable (EngineState) -> EngineFacts?) async {
        await submit { rt in rt.factsReader = r }
    }

    /// Test seam (internal): a listener attached at once, without the D13 wait, so a test sees the restore Step itself.
    func addListenerWithoutRestoreWait(_ l: @escaping RuntimeListener) async -> Int {
        await submit { rt in
            let token = rt.nextListener
            rt.nextListener += 1
            rt.listeners[token] = l
            return token
        }
    }

    /// Waits until every command enqueued before this call (and its feeds) has run. Tests and the host use it.
    public func drain() async { await submit { _ in } }

    struct CurrentBox: @unchecked Sendable { let value: (meta: TripMeta, view: TripView)? }

    // MARK: - Clock helpers

    private func nowWall() -> Int64 { ports.time.wallMs() }

    private func nowTrip() -> Int64 {
        if clock == nil { clock = TripClock(anchor: .now(ports.time)) }
        return clock!.now(ports.time)
    }

    private func toWall(_ trip: Int64) -> Int64 {
        if clock == nil { return nowWall() }
        return clock!.toWall(trip, ports.time)
    }

    private func toTrip(_ wall: Int64) -> Int64 {
        if clock == nil { return wall }
        return clock!.toTrip(wall: wall, ports.time)
    }

    private func setMode(_ m: TrackingMode) {
        if m != trackingMode { ports.journal.record("mode", ["from": "\(trackingMode)", "to": "\(m)"]) }
        trackingMode = m
    }

    private func writeLedger() {
        do { try ports.store.writeLedger(ledger) } catch { warn("ledger write failed (\(type(of: error)))") }
    }

    private func storedTrip() -> StoredTrip? {
        guard let a = active, let c = clock else { return nil }
        return StoredTrip(meta: a.meta, anchor: c.anchor, engineSnapshot: TripEngine.encodeSnapshot(a.engine),
                          savedAtWallMs: nowWall())
    }

    // MARK: - Load and restore (§5.8)

    private func load() async {
        if loaded { return }
        loaded = true
        ledger = ports.store.readLedger()
        var stored: StoredTrip?
        do { stored = try ports.store.readActive() } catch {
            warn("active trip unreadable (\(error))")
            stored = nil
        }
        var engine: EngineState?
        if let s = stored {
            do { engine = try TripEngine.decodeSnapshot(s.engineSnapshot) } catch {
                warn("engine snapshot unreadable (\(error))")
                ports.store.deleteActive()
                stored = nil
            }
        }
        guard let s = stored, let e = engine, s.meta.tripId == ledger.activeTripId || ledger.activeTripId == nil else {
            if let lost = ledger.activeTripId {
                // F2 of T15: the trip is gone; tell the user once, keep its alarms (they still ring).
                await ports.notifier.show(tripId: lost, .interrupted, destinationName: nil)
                ledger.activeTripId = nil
                writeLedger()
            }
            ports.journal.record("proc_start", ["trip": "none"])
            return
        }
        // Ended snapshot (writeFinished failed last time): rebuild the record (§5.7).
        if let f = EngineFacts.read(e), f.phase == .ended {
            if let r = FinishedRecordBuilder.fromEnded(f) {
                do { try ports.store.writeFinished(r); ports.store.deleteActive() } catch { pendingFinishedMem.append(r) }
            }
            ledger.activeTripId = nil
            ledger.markEnded(s.meta.tripId, max: constants.endedTripIdsMax)
            writeLedger()
            return
        }
        let valid = TripClock.anchorValid(s.anchor, ports.time, driftMaxMs: constants.clockDriftMaxMs)
        clock = TripClock(anchor: valid ? s.anchor : .now(ports.time))
        ledger.activeTripId = s.meta.tripId
        active = Active(meta: s.meta, engine: e, view: nil,
                        params: EngineParamsFactory.fromOverrides(s.meta.engineParamsJson))
        batteryChoiceMem = EngineFacts.batteryChoice(e)
        gate.force()
        restorePending = true
        let appState = await ports.app.activity()
        ports.journal.record("proc_start", ["appState": "\(appState)", "bootChanged": valid ? "false" : "true"])
        let list = await readList()
        if let list { lastList = list; prevUpdates = list }
        let r = LedgerReconciler.reconcile(ledger, list: list, activeTripId: s.meta.tripId, nowWallMs: nowWall(),
                                           toTrip: { [self] w in self.toTripSync(w) })
        ledger = r.ledger
        writeLedger()
        for act in r.actions { await perform(act) }
        if appState == .active {
            await completeRestore()
        } else {
            addDeferred(nowWall() + constants.restoreSettleMs, .restoreSettle)  // D13
        }
    }

    /// toTrip usable from a non-async closure inside the actor.
    private func toTripSync(_ wall: Int64) -> Int64 { toTrip(wall) }

    private func completeRestore() async {
        guard restorePending, var a = active else { return }
        restorePending = false
        defer {
            let w = restoreWaiters
            restoreWaiters = []
            for c in w { c.resume() }
        }
        deferred.removeAll { $0.kind == .restoreSettle }
        // An unreadable snapshot field must not lock the trip (review #9): restore as UNKNOWN instead.
        let facts = factsReader(a.engine)
        if facts == nil { warn("engine facts unreadable") }
        let events = ringEvents()
        let list = await readList()
        if let list { lastList = list; prevUpdates = list }
        let now = nowTrip()
        let info = facts.map { f in
            RestorePlanner.plan(f, ledger: ledger, events: events, list: list, nowTripMs: now,
                                toTrip: { [self] w in self.toTripSync(w) })
        } ?? RestoreInfo(status: .unknown)
        ports.journal.record("restore", ["status": info.status.jsonName])
        let step = TripEngine.restore(a.engine, nowMs: now, info: info)
        // Mode first (§5.8 step 3): only an active app starts location (D10).
        if step.view.phase != .ended, await ports.app.activity() == .active {
            let spec = LocationRequestMapper.spec(step.view.samplingPolicy, a.params)
            if await startLocation(spec) { setMode(.tracking) } else { setMode(.headless) }
        } else {
            setMode(step.view.phase == .ended ? .ending : .headless)
        }
        a.engine = step.state
        active = a
        await apply(step, prevView: nil, facts: RingFactsReader.facts(tripId: a.meta.tripId, list: list ?? [], ledger: ledger,
                                                                         nowWallMs: nowWall(), constants: constants))
        guard let cur = active, let view = cur.view, view.phase != .ended else { return }
        // Spec R2 (replaces G3, §5.8 step 2): ring again only when no system alarm ever took this ring.
        if (view.phase == .alarming || view.phase == .overshot) && view.alarmRinging
            && !(list ?? []).contains(where: { $0.tripId == cur.meta.tripId && $0.state == .alerting }) {
            let f = factsReader(cur.engine)
            let lastRing = f?.alarmLastRingAtMs
            let alarmWall = ledger.now?.fireAtWallMs ?? lastRing.map { toWall($0) } ?? nowWall()
            let lag = Int64(cur.params.fallbackLagS) * 1000
            let decision = RestoreRingPolicy.decide(info: info, ledger: ledger, list: list, nowWallMs: nowWall(), lagMs: lag,
                                                    graceMs: constants.nowAlertGraceMs, alarmWallMs: alarmWall)
            ports.journal.record("restore_ring", ["decision": "\(decision)".prefix(8).description])
            switch decision {
            case .none:
                break
            case let .silenced(w):
                let at = max(lastRing ?? Int64.min, toTrip(w))
                feeds.append(.alarmSilenced(atMs: nowTrip(), silencedAtMs: min(at, nowTrip())))
            case .ring:
                let reason = f?.alarmLastReason ?? view.alarmReason ?? .fallback
                let guardAt = nowWall() + lag
                if EffectPlanner.needsGuard(live: EffectPlanner.liveSlot(ledger, list: list), nowWallMs: nowWall(),
                                            guardAtWallMs: guardAt) {
                    await scheduleSlot(.guardSlot, targetAtMs: toTrip(guardAt), wallMs: guardAt)
                }
                await ring(RingRequest(tripId: cur.meta.tripId, reason: reason, snoozeAllowed: false, distanceM: nil,
                                       etaS: nil, batteryPct: nil, atWallMs: nowWall()))
            }
        }
        if trackingMode == .headless && (view.phase == .acquiring || view.phase == .tracking) && !ledger.interruptedAlerted {
            await ports.notifier.show(tripId: cur.meta.tripId, .interrupted, destinationName: nil)
            ledger.interruptedAlerted = true
            writeLedger()
        }
    }

    private func startLocation(_ spec: LocationRequestSpec) async -> Bool {
        do {
            try await ports.location.start(spec, sink: self)
            currentSpec = spec
            throttle.reset()
            ports.journal.record("loc", ["op": "start", "acc": spec.accuracy.rawValue])
            return true
        } catch {
            ports.journal.record("loc", ["op": "start", "err": "\(error)"])
            return false
        }
    }

    // MARK: - Start (§5.1)

    private func doStart(_ meta: TripMeta, _ lat: Double, _ lng: Double) async -> StartOutcome {
        await load()
        if active != nil {
            // A restored trip holds the gate.
            return .rejected(code: "trip-active", message: nil, details: nil)
        }
        func reject(_ code: String, _ message: String? = nil, _ details: [String]? = nil) -> StartOutcome {
            setMode(.idle)
            gate.release()
            return .rejected(code: code, message: message, details: details)
        }
        setMode(.starting)
        if await ports.app.activity() != .active { return reject("not-foreground") }
        let a = await ports.env.locationAccess()
        let c = await ports.env.channelAccess()
        var missing: [String] = []
        if !a.whenInUseOrAlways { missing.append("location") } else if !a.fullAccuracy { missing.append("precise") }
        if !a.servicesEnabled { missing.append("locationServices") }
        if !(c.alarmKit == .authorized || c.notifications) { missing.append("alarmChannel") }
        if !missing.isEmpty { return reject("permission-missing", nil, missing) }
        let params = EngineParamsFactory.fromOverrides(meta.engineParamsJson)
        let anchor = ClockAnchor.now(ports.time)
        var newClock = TripClock(anchor: anchor)
        let step0: Step
        do {
            step0 = try TripEngine.start(config: meta.config(destLat: lat, destLng: lng), params: params,
                                         nowMs: newClock.now(ports.time))
        } catch {
            return reject("invalid-config", "\(error)")
        }
        let spec = LocationRequestMapper.spec(step0.view.samplingPolicy, params)
        do {
            try await ports.location.start(spec, sink: self)
        } catch let e as LocationStartError {
            switch e {
            case .backgroundModeMissing: return reject("start-failed", "BackgroundModeMissing")
            case .notAuthorized: return reject("permission-missing", nil, ["location"])
            case .servicesOff: return reject("permission-missing", nil, ["locationServices"])
            }
        } catch {
            return reject("start-failed", String(describing: type(of: error)))
        }
        // From here the trip exists. Leftover alarms of an earlier trip (R2-1 of T15).
        for id in ledger.knownIds {
            let ch = [ledger.current, ledger.stale].compactMap { $0 }.first { $0.alarmId == id }?.channel
                ?? ledger.now?.channel ?? .alarmKit
            await ports.alarms.cancel(id: id, channel: ch)
        }
        ledger.activeTripId = meta.tripId
        ledger.current = nil
        ledger.stale = nil
        ledger.now = nil
        ledger.lastFired = nil
        ledger.interruptedAlerted = false
        writeLedger()
        clock = newClock
        currentSpec = spec
        throttle.reset()
        engineDueTripMs = nil
        batteryChoiceMem = nil
        lastBattery = nil
        lastAvailability = .available
        ringRetryPending = false
        expectedStops = []
        active = Active(meta: meta, engine: step0.state, view: nil, params: params)
        setMode(.tracking)
        await apply(step0, prevView: nil, facts: .none, persistBudgetMs: constants.startPersistBudgetMs)
        if let f = await ports.location.lastKnown() { locationSession(didReceive: f) }
        return .started
    }

    // MARK: - Step processing (§5.2)

    private func drainFeeds() async {
        while !feeds.isEmpty {
            let f = feeds.removeFirst()
            await process(f)
        }
    }

    private func process(_ input: EngineInput) async {
        if restorePending { await completeRestore() }
        guard let a = active, a.view != nil else { return }
        let step = TripEngine.reduce(a.engine, input)
        var facts = RingFacts.none
        var live: AlarmSlotRec?
        if step.events.contains(where: { if case let .alarm(x) = $0 { return x.ringNow }; return false }) {
            let fresh = await readList()
            // V2-2: an unreadable list says nothing about what rings now (a stale `lastList` could swallow the ring and the
            // guard); treat it as "nothing ringing", the safe side chosen by R1.
            if let fresh {
                lastList = fresh
                facts = RingFactsReader.facts(tripId: a.meta.tripId, list: fresh, ledger: ledger, nowWallMs: nowWall(),
                                              constants: constants)
            }
            live = EffectPlanner.liveSlot(ledger, list: fresh)  // spec R1: fresh list, nil when unreadable
        }
        await apply(step, prevView: a.view, facts: facts, liveSlot: live)
    }

    /// Commit + effects of one Step.
    private func apply(_ step: Step, prevView: TripView?, facts: RingFacts, persistBudgetMs: Int64? = nil,
                       liveSlot: AlarmSlotRec? = nil) async {
        guard var a = active else { return }
        a.engine = step.state
        a.view = step.view
        active = a
        if let c = clock { terminateCache.set((a.meta, c.anchor, a.engine, step.view.phase)) }
        ports.journal.record("step", ["phase": step.view.phase.jsonName, "gps": step.view.gps.jsonName,
                                      "tier": step.view.samplingPolicy?.tier.jsonName ?? "",
                                      "fbStatus": step.view.fallbackStatus.jsonName,
                                      "events": step.events.map(\.fixtureName).joined(separator: ","),
                                      "reason": step.events.compactMap { e -> String? in
                                          if case let .alarm(x) = e { return x.reason.jsonName }
                                          return nil
                                      }.first ?? ""])
        let fx = EffectPlanner.plan(PlanInput(
            prevView: prevView, step: step, meta: a.meta, mode: trackingMode, facts: facts, ledger: ledger,
            timerDueTripMs: engineDueTripMs, params: a.params, nowWallMs: nowWall(), nowTripMs: nowTrip(),
            constants: constants, liveSlot: liveSlot))
        if step.events.contains(where: { if case let .alarm(x) = $0 { return x.ringNow }; return false }),
           !fx.contains(where: { if case .ringNow = $0 { return true }; if case .feed(.fallbackFired) = $0 { return true }; return false }) {
            ports.journal.record("ring_live", [:])  // one ring per trip: the "now" alarm is live already
        }
        for f in fx {
            if case .persist = f, let b = persistBudgetMs {
                await execute(.persistNow(budgetMs: b), step: step, facts: facts)
            } else {
                await execute(f, step: step, facts: facts)
            }
        }
    }

    private func execute(_ f: Effect, step: Step, facts: RingFacts) async {
        guard let a = active else { return }
        switch f {
        case let .armRingGuard(w):
            await scheduleSlot(.guardSlot, targetAtMs: toTrip(w), wallMs: w)
        case let .persistNow(budget):
            await persistNow(budget)
        case let .ringNow(req):
            await ring(req)
        case let .feed(input):
            if case .fallbackFired = input { ports.journal.record("fb_fired", ["src": "planner"]) }
            if case let .fallbackFired(_, firedAt) = input, let id = facts.ringingAlarmId, ledger.lastFired?.alarmId != id {
                ledger.lastFired = FiredRec(alarmId: id, kind: facts.ringingKind ?? .fallback, generation: 0, firedAtMs: firedAt,
                                            firedAtWallMs: facts.ringStartedAtWallMs ?? nowWall())
                writeLedger()
            }
            feeds.append(input)
        case let .stopRinging(cause):
            await stopRinging(cause)
        case let .notice(show, clear):
            if let s = show { await ports.notifier.show(tripId: a.meta.tripId, s, destinationName: a.meta.destinationName) }
            if let c = clear { await ports.notifier.clear(tripId: a.meta.tripId, c) }
        case let .applySampling(spec):
            currentSpec = spec
            await ports.location.retune(spec)
            ports.journal.record("loc", ["op": "retune", "acc": spec.accuracy.rawValue])
        case let .scheduleFallback(t):
            await scheduleSlot(.fallback, targetAtMs: t, wallMs: toWall(t))
        case .cancelFallbacks:
            await cancelSlots()
        case let .setTimer(due):
            engineDueTripMs = due
        case .cancelTimer:
            engineDueTripMs = nil
        case .persist:
            let failed = await writer.lastFailed
            if !step.events.isEmpty || failed || nowWall() - lastPersistWallMs >= constants.snapshotMinIntervalMs,
               let t = storedTrip() {
                lastPersistWallMs = nowWall()
                await writer.submit(t)
            }
        case .publish:
            let choice = batteryChoiceMem
            for key in listeners.keys.sorted() {
                if let l = listeners[key] { await l(a.meta.tripId, step.view, choice, step.events) }
            }
        case let .endTrip(rec):
            await endTrip(rec)
        }
    }

    private func persistNow(_ budgetMs: Int64) async {
        guard let t = storedTrip() else { return }
        lastPersistWallMs = nowWall()
        await writer.submit(t)
        let shot = OneShot()
        let writer = self.writer
        let sleeper = ports.sleeper
        Task { await writer.waitIdle(); shot.fire() }
        Task { await sleeper.sleep(ms: budgetMs); shot.fire() }
        await shot.wait()
    }

    // MARK: - Alarms (§5.6)

    private func channels() async -> [AlarmChannelKind] {
        let c = await ports.env.channelAccess()
        var out: [AlarmChannelKind] = []
        if c.alarmKit == .authorized { out.append(.alarmKit) }
        if c.notifications { out.append(.notification) }
        return out
    }

    private func locale() -> String { ports.localeTag() }

    private func ring(_ req: RingRequest) async {
        guard let a = active else { return }
        let chans = await channels()
        let id = UUID().uuidString
        let g = ledger.nextGeneration
        ledger.nextGeneration += 1
        let fire = nowWall() + constants.akNowLeadMs
        let first = chans.first ?? .alarmKit
        ledger.now = NowRingRec(alarmId: id, generation: g, fireAtWallMs: fire, reason: req.reason.jsonName, confirmed: false,
                                seenAlerting: false, channel: first)
        writeLedger()
        let bg = ports.bgTasks.begin("napstop.ring")
        let title = NativeCopy.alarmTitle(req.reason, destinationName: a.meta.destinationName, locale: locale())
        var okChannel: AlarmChannelKind?
        for ch in chans {
            do {
                try await ports.alarms.schedule(SystemAlarmRequest(id: id, tripId: a.meta.tripId, kind: .now, generation: g,
                                                                   fireAtWallMs: fire, title: title, channel: ch))
                okChannel = ch
                ports.journal.record("ak", ["op": "schedule", "kind": "now", "gen": "\(g)", "ok": "true", "ch": ch.rawValue])
                break
            } catch {
                ports.journal.record("ak", ["op": "schedule", "kind": "now", "gen": "\(g)", "ok": "false",
                                            "err": String(describing: type(of: error)), "ch": ch.rawValue])
            }
        }
        if let ch = okChannel {
            ledger.now = NowRingRec(alarmId: id, generation: g, fireAtWallMs: fire, reason: req.reason.jsonName, confirmed: true,
                                    seenAlerting: false, channel: ch)
            writeLedger()
            ringRetryPending = false
        } else {
            // G2 (§5.6.3): the guard slot stays; the UI shows the alarm as silenced so a re-ring stays possible.
            warn("ring failed")
            feeds.append(.alarmSilenced(atMs: nowTrip(), silencedAtMs: nowTrip()))
            await ports.notifier.show(tripId: a.meta.tripId, .ringFailed, destinationName: a.meta.destinationName)
            ringRetryPending = true
            lastRingRetryWallMs = nowWall()
        }
        if trackingMode == .headless && okChannel != nil {
            addDeferred(nowWall() + constants.nowObserveHoldMs, .endBgTask(token: bg))
        } else {
            ports.bgTasks.end(bg)
        }
    }

    private func stateOf(_ id: String) -> SystemAlarmState? { lastList.first { $0.id == id }?.state }

    /// `alarms.list()` with alarms the ledger knows re-attributed to the trip when the id registry lost them (review #2).
    private func readList() async -> [SystemAlarmInfo]? {
        guard let l = await ports.alarms.list() else { return nil }
        return adopt(l)
    }

    private func adopt(_ l: [SystemAlarmInfo]) -> [SystemAlarmInfo] {
        guard let trip = ledger.activeTripId ?? active?.meta.tripId else { return l }
        return l.map { x in
            guard x.tripId.isEmpty else { return x }
            var kind: SystemAlarmKind?
            if x.id == ledger.now?.alarmId { kind = .now }
            if let s = [ledger.current, ledger.stale].compactMap({ $0 }).first(where: { $0.alarmId == x.id }) { kind = s.kind }
            guard let k = kind else { return x }
            return SystemAlarmInfo(id: x.id, tripId: trip, kind: k, generation: x.generation, state: x.state,
                                   fireAtWallMs: x.fireAtWallMs, channel: x.channel)
        }
    }

    /// §5.6.2: new slot first, ledger, then cancel the old one (never an alerting one).
    private func scheduleSlot(_ kind: SystemAlarmKind, targetAtMs: Int64, wallMs: Int64) async {
        guard let a = active else { return }
        let old = ledger.current
        let id = UUID().uuidString
        let g = ledger.nextGeneration
        ledger.nextGeneration += 1
        let chans = await channels()
        let title = kind == .fallback
            ? NativeCopy.fallbackTitle(destinationName: a.meta.destinationName, locale: locale())
            : NativeCopy.alarmTitle(a.view?.alarmReason ?? .fallback, destinationName: a.meta.destinationName, locale: locale())
        guard let ch = chans.first else {
            ports.journal.record("ak", ["op": "schedule", "kind": kind.rawValue, "gen": "\(g)", "ok": "false", "err": "noChannel"])
            if kind == .fallback { feeds.append(.fallbackScheduled(atMs: nowTrip(), fallbackAtMs: targetAtMs, ok: false)) }
            return
        }
        do {
            try await ports.alarms.schedule(SystemAlarmRequest(id: id, tripId: a.meta.tripId, kind: kind, generation: g,
                                                               fireAtWallMs: wallMs, title: title, channel: ch))
        } catch {
            warn("alarm schedule failed (\(type(of: error)))")
            ports.journal.record("ak", ["op": "schedule", "kind": kind.rawValue, "gen": "\(g)", "ok": "false",
                                        "err": String(describing: type(of: error))])
            if kind == .fallback { feeds.append(.fallbackScheduled(atMs: nowTrip(), fallbackAtMs: targetAtMs, ok: false)) }
            return
        }
        ports.journal.record("ak", ["op": "schedule", "kind": kind.rawValue, "gen": "\(g)", "ok": "true"])
        ledger.current = AlarmSlotRec(alarmId: id, kind: kind, generation: g, targetAtMs: targetAtMs, targetAtWallMs: wallMs,
                                      setAtWallMs: nowWall(), channel: ch)
        // Every earlier slot is replaced, the previous `stale` one too (tester T17 #1: overwriting `stale` orphaned it; a clock
        // change re-scheduling a live `stale` slot must retire it, not the dead `current`).
        let previous = [old, ledger.stale].compactMap { $0 }.filter { $0.alarmId != id }
        ledger.stale = old
        writeLedger()
        if !previous.isEmpty {
            // Fresh read: an old slot may have started ringing while the new one was being scheduled (T10.5 §8).
            let l = await readList()
            if let l { lastList = l }
            var keep: AlarmSlotRec?
            for p in previous {
                if l != nil && stateOf(p.alarmId) == .alerting { continue }  // never cancel a ringing slot (K4 #4)
                if l == nil && p.alarmId == old?.alarmId {
                    // Unreadable list: the slot just replaced may be ringing; keep it as `stale` to retire later (#10).
                    keep = p
                    continue
                }
                if l == nil && p.targetAtWallMs <= nowWall() {
                    // Review T17 R4-1: the previous `stale` slot with the list unreadable again. Not due yet → it cannot be
                    // ringing, cancel is enough; due → it may be ringing, stop it first.
                    await ports.alarms.stop(id: p.alarmId, channel: p.channel)
                }
                await ports.alarms.cancel(id: p.alarmId, channel: p.channel)
                expectedStops.insert(p.alarmId)
            }
            ledger.stale = keep
            writeLedger()
        }
        if kind == .fallback { feeds.append(.fallbackScheduled(atMs: nowTrip(), fallbackAtMs: targetAtMs, ok: true)) }
    }

    private func cancelSlots() async {
        // A slot known to be ringing is not cancelled (K4 #4). With an unreadable list every slot of the ledger is cancelled
        // anyway (V2-6): forgetting it uncancelled would let it ring after the trip ended; cancelling an unrung slot is harmless.
        let fresh = await readList()
        if let fresh { lastList = fresh }
        for s in [ledger.current, ledger.stale].compactMap({ $0 }) where fresh == nil || stateOf(s.alarmId) != .alerting {
            await ports.alarms.cancel(id: s.alarmId, channel: s.channel)
            expectedStops.insert(s.alarmId)
        }
        ledger.current = nil
        ledger.stale = nil
        writeLedger()
    }

    private func stopRinging(_ cause: StopCause) async {
        guard let a = active else { return }
        let list = await readList()
        if let list { lastList = list }
        // Match by trip and by the ids the ledger knows: a registry ref may be missing (review T17 #2).
        let known = Set(ledger.knownIds)
        let nowId = ledger.now?.alarmId
        let mine = (list ?? []).filter { $0.tripId == a.meta.tripId || known.contains($0.id) }
        for x in mine {
            if x.state == .alerting {
                await ports.alarms.stop(id: x.id, channel: x.channel)
                expectedStops.insert(x.id)
            } else if cause == .tripEnded || x.kind == .now || x.id == nowId {
                await ports.alarms.cancel(id: x.id, channel: x.channel)
                expectedStops.insert(x.id)
            }
        }
        // Not listed (unreadable list, or not reported): stop and cancel what the ledger knows (harmless, D22).
        let seen = Set(mine.map(\.id))
        for s in [ledger.current, ledger.stale].compactMap({ $0 }) where cause == .tripEnded && !seen.contains(s.alarmId) {
            await ports.alarms.stop(id: s.alarmId, channel: s.channel)
            await ports.alarms.cancel(id: s.alarmId, channel: s.channel)
            expectedStops.insert(s.alarmId)
        }
        if let n = ledger.now, !seen.contains(n.alarmId) {
            await ports.alarms.stop(id: n.alarmId, channel: n.channel)
            await ports.alarms.cancel(id: n.alarmId, channel: n.channel)
            expectedStops.insert(n.alarmId)
        }
        // V2-2: the "now" alarm was stopped or cancelled above; it must not count as live any more (RingFactsReader).
        if ledger.now != nil {
            ledger.now = nil
            writeLedger()
        }
        ringRetryPending = false
    }

    private func endTrip(_ rec: FinishedRecord) async {
        guard let a = active else { return }
        terminateCache.set(nil)
        setMode(.ending)
        await stopRinging(.tripEnded)
        await ports.location.stop()
        ports.journal.record("loc", ["op": "stop"])
        engineDueTripMs = nil
        deferred.removeAll { if case .endBgTask = $0.kind { return false }; return true }
        await ports.notifier.clearAll(tripId: a.meta.tripId)
        await writer.cancelPendingAndWait()
        do {
            try ports.store.writeFinished(rec)
            ports.store.deleteActive()
        } catch {
            warn("finished write failed (\(type(of: error)))")
            pendingFinishedMem.append(rec)
            if let t = storedTrip() { await writer.submit(t) }
        }
        ledger.activeTripId = nil
        ledger.current = nil
        ledger.stale = nil
        ledger.now = nil
        ledger.interruptedAlerted = false
        ledger.markEnded(a.meta.tripId, max: constants.endedTripIdsMax)
        writeLedger()
        ports.store.removeRingEvents(tripId: a.meta.tripId)
        active = nil
        clock = nil
        currentSpec = nil
        restorePending = false
        batteryChoiceMem = nil
        setMode(.idle)
        gate.release()
    }

    // MARK: - Inputs

    private func handleFix(_ raw: RawFix) async {
        await load()
        guard let a = active, a.view != nil, trackingMode == .tracking, !restorePending else { return }
        guard let fix = FixMapper.map(raw, nowWallMs: nowWall(), nowTripMs: nowTrip()) else {
            droppedPlatform += 1
            ports.journal.record("fix", ["drop": "platform"])
            return
        }
        let interval = currentSpec?.intervalMs ?? Int64(a.params.samplingDenseIntervalS) * 1000
        if !throttle.forward(fix, intervalMs: interval) { return }
        ports.journal.record("fix", ["fixAt": "\(fix.fixAtMs)","ageMs": "\(fix.atMs - fix.fixAtMs)", "hasSpd": fix.speedMps == nil ? "false" : "true"])
        await process(.locationFix(fix))
    }

    private func handleAvailability(_ cause: AvailabilityCause) async {
        await load()
        guard active != nil, cause != lastAvailability else { return }
        lastAvailability = cause
        await process(.locationAvailability(atMs: nowTrip(), cause: cause))
    }

    private func handleBattery(_ b: BatteryReading) async {
        await load()
        guard active != nil, b != lastBattery else { return }
        lastBattery = b
        await process(.batterySample(atMs: nowTrip(), levelPct: b.levelPct, charging: b.charging))
    }

    private func doUserAction(_ tripId: String, _ kind: UserActionKind) async {
        await load()
        if restorePending { await completeRestore() }
        guard let a = active, a.meta.tripId == tripId, a.view?.phase != .ended else { return }
        if BridgeMapper.batteryChoice(kind) != nil { batteryChoiceMem = kind }
        await process(.userAction(atMs: nowTrip(), action: kind))
    }

    private func doCurrent() async -> CurrentBox {
        await load()
        if restorePending { await completeRestore() }
        guard let a = active, let v = a.view, v.phase != .ended else { return CurrentBox(value: nil) }
        return CurrentBox(value: (a.meta, v))
    }

    private func doPendingFinished() async -> [FinishedRecord] {
        await load()
        var byId: [String: FinishedRecord] = [:]
        for r in ports.store.readFinished() { byId[r.tripId] = r }
        for r in pendingFinishedMem where byId[r.tripId] == nil { byId[r.tripId] = r }
        return byId.values.sorted { ($0.endedAtMs, $0.tripId) < ($1.endedAtMs, $1.tripId) }
    }

    private func doAck(_ ids: [String]) {
        ports.store.deleteFinished(ids)
        let s = Set(ids)
        pendingFinishedMem.removeAll { s.contains($0.tripId) }
    }

    private func doAddListener(_ l: @escaping RuntimeListener) async -> Int {
        await load()
        let token = nextListener
        nextListener += 1
        listeners[token] = l
        if active?.view != nil { feeds.append(.tick(atMs: nowTrip())) }
        return token
    }

    private func handleTimer(_ generation: Int64) async {
        guard generation == timerGen else { return }
        armedWallMs = nil
        let wall = nowWall()
        let due = deferred.filter { $0.dueWallMs <= wall }
        deferred.removeAll { $0.dueWallMs <= wall }
        for d in due {
            await runDeferred(d.kind)
            await drainFeeds()  // D2: feeds right after the Step that made them (review #11)
        }
        // Consume the engine wake now, so a skipped Tick never re-arms a 0 ms timer.
        var tickDue = false
        if let d = engineDueTripMs, clock == nil || d <= nowTrip() {
            engineDueTripMs = nil
            tickDue = clock != nil
        }
        guard let a = active, a.view != nil, !restorePending else { return }
        if let b = await ports.env.battery(), b != lastBattery {
            lastBattery = b
            await process(.batterySample(atMs: nowTrip(), levelPct: b.levelPct, charging: b.charging))
            await drainFeeds()
        }
        if trackingMode == .tracking {
            let cause = await ports.env.locationAccess().availability
            if cause != lastAvailability {
                lastAvailability = cause
                await process(.locationAvailability(atMs: nowTrip(), cause: cause))
                await drainFeeds()
            }
        }
        if ledger.current?.channel == .notification || ledger.now?.channel == .notification,
           let l = await readList() {
            await interpretUpdates(l)
            await drainFeeds()
        }
        await ringRetryIfDue()
        await drainFeeds()
        if tickDue { await process(.tick(atMs: nowTrip())) }
    }

    private func ringRetryIfDue() async {
        guard ringRetryPending, let a = active, let v = a.view, v.phase == .alarming || v.phase == .overshot else { return }
        if nowWall() - lastRingRetryWallMs < constants.ringRetryMs { return }
        let list = await readList() ?? lastList
        lastList = list
        if list.contains(where: { $0.tripId == a.meta.tripId && $0.state == .alerting }) { ringRetryPending = false; return }
        if let c = ledger.current, list.contains(where: { $0.id == c.alarmId && $0.state == .scheduled }) { return }
        lastRingRetryWallMs = nowWall()
        let at = nowWall() + Int64(a.params.fallbackLagS) * 1000
        await scheduleSlot(.guardSlot, targetAtMs: toTrip(at), wallMs: at)
    }

    private func runDeferred(_ k: DeferredKind) async {
        switch k {
        case .restoreSettle:
            await completeRestore()
        case let .goneCheck(id, goneAt):
            guard let a = active, let v = a.view, v.alarmRinging else { return }
            let events = ringEvents()
            if events.contains(where: { $0.alarmId == id }) { return }
            await process(.alarmSilenced(atMs: nowTrip(), silencedAtMs: toTrip(goneAt)))
        case let .endBgTask(token):
            ports.bgTasks.end(token)
        }
    }

    private func addDeferred(_ wall: Int64, _ k: DeferredKind) { deferred.append(Deferred(dueWallMs: wall, kind: k)) }

    /// One in-process timer for the engine wake and the deferred checks (D11).
    private func rearm() {
        var due: Int64?
        if let d = engineDueTripMs, clock != nil { due = nowWall() + max(0, d - nowTrip()) }
        for x in deferred { due = min(due ?? x.dueWallMs, x.dueWallMs) }
        if due == armedWallMs { return }
        armedWallMs = due
        timerGen += 1
        if let d = due {
            ports.timer.set(delayMs: max(0, d - nowWall()), generation: timerGen)
        } else {
            ports.timer.cancel()
        }
    }

    private func handleSystemAlarms(_ list: [SystemAlarmInfo]) async {
        await load()
        await interpretUpdates(list)
    }

    private func interpretUpdates(_ raw: [SystemAlarmInfo]) async {
        let list = adopt(raw)
        let tripId = restorePending ? nil : active?.meta.tripId
        let actions = AlarmUpdateInterpreter.interpret(tripId: tripId, prev: prevUpdates, cur: list, ledger: ledger,
                                                       expectedStops: expectedStops, nowWallMs: nowWall())
        prevUpdates = list
        lastList = list
        for act in actions { await perform(act) }
    }

    private func perform(_ act: AlarmAction) async {
        switch act {
        case let .fallbackFired(id, kind, gen, wall):
            guard ledger.lastFired?.alarmId != id else { return }
            let t = toTrip(wall)
            ledger.lastFired = FiredRec(alarmId: id, kind: kind, generation: gen, firedAtMs: active == nil ? nil : t,
                                        firedAtWallMs: wall)
            writeLedger()
            ports.journal.record("ak_state", ["kind": kind.rawValue, "gen": "\(gen)", "state": "alerting"])
            if active?.view != nil {
                ports.journal.record("fb_fired", ["src": "interpreter"])
                feeds.append(.fallbackFired(atMs: nowTrip(), firedAtMs: t))
            }
            forgetSlot(id)
        case let .cancel(id, ch):
            await ports.alarms.cancel(id: id, channel: ch)
            forgetSlot(id)
            expectedStops.insert(id)
        case let .stop(id, ch):
            await ports.alarms.stop(id: id, channel: ch)
            forgetSlot(id)
            expectedStops.insert(id)
        case let .nowSeenAlerting(id):
            if var n = ledger.now, n.alarmId == id {
                n.seenAlerting = true
                ledger.now = n
                writeLedger()
            }
            ringRetryPending = false
            ports.journal.record("ak_state", ["kind": "now", "state": "alerting"])
            for d in deferred { if case let .endBgTask(token) = d.kind { ports.bgTasks.end(token) } }
            deferred.removeAll { if case .endBgTask = $0.kind { return true }; return false }
        case let .checkGone(id, wall):
            addDeferred(nowWall() + constants.stopIntentGraceMs, .goneCheck(id: id, goneAtWallMs: wall))
        }
    }

    private func handleStopIntent(_ e: RingEventRec) async {
        await load()
        expectedStops.insert(e.alarmId)
        let known = active?.meta.tripId == e.tripId
        ports.journal.record("stop_intent", ["kind": e.kind.rawValue, "known": known ? "true" : "false"])
        if known, restorePending {
            // The ring event normally is on disk (D12 step 1); keep it in memory too, in case that write failed (tester
            // T17 #2). The restore then plans DISMISSED; if the trip still runs afterwards, the dismiss below ends it.
            memoryRingEvents.append(e)
            await completeRestore()
            memoryRingEvents.removeAll { $0.tripId == e.tripId }
            if active == nil || active?.view?.phase == .ended { return }
        }
        if known, let a = active, let v = a.view, v.phase != .ended {
            if e.kind != .now && ledger.lastFired?.alarmId != e.alarmId {
                // The slot rang while the app was suspended and no alarmUpdates came (spec R4 S3, any phase: queued fixes
                // may have rung meanwhile): tell the engine first.
                let wall = [ledger.current, ledger.stale].compactMap { $0 }.first { $0.alarmId == e.alarmId }?.targetAtWallMs
                    ?? e.atWallMs
                await perform(.fallbackFired(alarmId: e.alarmId, kind: e.kind, generation: 0, firedAtWallMs: wall))
                await drainFeeds()
            }
            await process(.userAction(atMs: nowTrip(), action: .dismiss))
            ports.store.removeRingEvents(tripId: e.tripId)
            return
        }
        // Unknown or ended trip (§5.6.5).
        let ch = (await readList())?.first { $0.id == e.alarmId }?.channel ?? .alarmKit
        await ports.alarms.cancel(id: e.alarmId, channel: ch)
        ledger.markEnded(e.tripId, max: constants.endedTripIdsMax)
        writeLedger()
        ports.store.removeRingEvents(tripId: e.tripId)
    }

    private func handleAppActive() async {
        await load()
        if restorePending { await completeRestore(); return }
        guard trackingMode == .headless, let a = active, let v = a.view, v.phase != .ended else { return }
        let spec = LocationRequestMapper.spec(v.samplingPolicy, a.params)
        if await startLocation(spec) {
            setMode(.tracking)
            await ports.notifier.clear(tripId: a.meta.tripId, .interrupted)
            ledger.interruptedAlerted = false
            writeLedger()
            feeds.append(.tick(atMs: nowTrip()))
        }
    }

    private func handleWillTerminate() async {
        guard let a = active, let v = a.view else { return }
        await persistNow(constants.startPersistBudgetMs)
        if (v.phase == .acquiring || v.phase == .tracking) && !ledger.interruptedAlerted {
            await ports.notifier.show(tripId: a.meta.tripId, .interrupted, destinationName: nil)
            ledger.interruptedAlerted = true
            writeLedger()
        }
    }

    /// Ring events on disk plus the ones handed over in memory (same record twice is harmless).
    private func ringEvents() -> [RingEventRec] { ports.store.readRingEvents() + memoryRingEvents }

    /// The ledger stops pointing at a slot that rang or was cancelled (review T17 #1: a dead slot must not block a guard).
    private func forgetSlot(_ id: String) {
        var changed = false
        if ledger.current?.alarmId == id { ledger.current = nil; changed = true }
        if ledger.stale?.alarmId == id { ledger.stale = nil; changed = true }
        if changed { writeLedger() }
    }

    private func handleClockChanged() async {
        await load()
        guard active?.view != nil else { return }
        // Spec R1: only a live slot is moved; a cancelled/rung one would ring at once on the new wall clock.
        let l = await readList()
        if let l { lastList = l }
        guard let live = EffectPlanner.liveSlot(ledger, list: l) else { return }
        await scheduleSlot(live.kind, targetAtMs: live.targetAtMs, wallMs: toWall(live.targetAtMs))
    }
}

extension EngineFacts {
    /// battery.choice of the stored state (for TripStateMsg.batteryChoice after a restore).
    static func batteryChoice(_ s: EngineState) -> UserActionKind? {
        struct Snap: Decodable { struct B: Decodable { var choice: String? }; var battery: B }
        guard let snap = try? JSONDecoder().decode(Snap.self, from: Data(TripEngine.encodeSnapshot(s).utf8)) else { return nil }
        return snap.battery.choice.flatMap(UserActionKind.init(jsonName:))
    }
}
