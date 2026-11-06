// Process-wide host of the iOS trip runtime (docs/specs/T17.md §2, §5.8, §5.13): builds the ports, owns TripRuntime,
// forwards app lifecycle, battery, clock changes and AlarmKit `alarmUpdates`. Created by the Runner at launch.
#if os(iOS)
import Foundation
import os
import Trip
import TripRuntime
import UIKit
#if canImport(AlarmKit)
import AlarmKit
#endif

public final class RuntimeHost: @unchecked Sendable {
    /// Diagnostics switches (§5.13). The package never sees NAPSTOP_DIAG: only the Runner passes `diagnostics: true`.
    public typealias Options = RuntimeOptions

    public private(set) static var shared: RuntimeHost!
    public static let appLocaleKey = "napstop.appLocale"

    public let runtime: TripRuntime
    public let store: FileRuntimeStore
    public let options: Options
    /// The system alarm port (diagnostic App Intents use it directly, §5.13).
    public let alarms: SystemAlarms
    public let journal: RuntimeJournal
    let notifier: IOSTripNotifier
    let timer = DispatchWakeTimer()
    let registry: AlarmRefRegistry
    private var observers: [NSObjectProtocol] = []
    private var alarmTask: Task<Void, Never>?
    private let fakeAlarms: FakeSystemAlarmsIOS?

    /// T17.2 D8: number of `NapStopRouteBackIntent.perform()` running (static: set before the host exists).
    public static let routeBackInFlight = InFlightCounter()

    /// Call once on the main thread from `application(_:didFinishLaunchingWithOptions:)`.
    @discardableResult
    /// `traces`: bundled simulation traces (T18.1 D12; the Runner passes its Flutter asset store).
    public static func bootstrap(options: Options = Options(), intentFactory: AlarmIntentFactory?,
                                 traces: TraceStore = NoTraceStore()) -> RuntimeHost {
        if let s = shared { return s }
        let h = RuntimeHost(options: options, intentFactory: intentFactory, traces: traces)
        shared = h
        h.start()
        return h
    }

    public static func localeTag() -> String {
        NativeCopy.localeTag(stored: UserDefaults.standard.string(forKey: appLocaleKey), preferredLanguages: Locale.preferredLanguages)
    }

    private init(options: Options, intentFactory: AlarmIntentFactory?, traces: TraceStore) {
        self.options = options
        // Review #17: static strings + error type names only (never coordinates, names or values).
        let logger = Logger(subsystem: "app.napstop", category: "trip")
        let warn: @Sendable (String) -> Void = { s in logger.error("\(s, privacy: .public)") }
        let store = FileRuntimeStore(warn: warn)
        self.store = store
        let journal = options.journal { FileJournal() }
        let notifier = IOSTripNotifier(locale: { RuntimeHost.localeTag() })
        self.notifier = notifier
        let registry = AlarmRefRegistry(url: store.alarmRefsURL, now: { IOSTime().wallMs() })
        self.registry = registry
        var akChannel: SystemAlarms?
        let fake: FakeSystemAlarmsIOS? = options.fakeAlarms ? FakeSystemAlarmsIOS() : nil
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *), fake == nil {
            akChannel = AlarmKitSystemAlarms(registry: registry, intents: intentFactory,
                                             stopLabel: { NativeCopy.string("alarmKitStop", RuntimeHost.localeTag()) },
                                             secondaryLabel: { NativeCopy.secondaryLabel($0, locale: RuntimeHost.localeTag()) })
        }
        #endif
        let alarms: SystemAlarms = fake ?? SystemAlarmsRouter(alarmKit: akChannel, notifications: NotificationSystemAlarms())
        self.alarms = alarms
        self.fakeAlarms = fake
        self.journal = journal
        let ports = RuntimePorts(time: IOSTime(), location: CoreLocationSession(), alarms: alarms, store: store,
                                 env: fake == nil ? IOSDeviceEnv() : FakeChannelEnv(base: IOSDeviceEnv()), app: IOSAppState(), notifier: notifier,
                                 timer: timer, sleeper: TaskSleeper(), bgTasks: UIKitBackgroundTasks(), journal: journal,
                                 localeTag: { RuntimeHost.localeTag() }, traces: traces)
        runtime = TripRuntime(ports: ports, warn: warn)
        let rt = runtime
        timer.onFire = { g in Task { await rt.onTimer(generation: g) } }
        fake?.onUpdate = { l in Task { await rt.onSystemAlarms(l) } }
    }

    private func start() {
        let rt = runtime
        let nc = NotificationCenter.default
        func observe(_ name: Notification.Name, _ body: @escaping @Sendable () -> Void) {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { _ in body() })
        }
        observe(UIApplication.didBecomeActiveNotification) { Task { await rt.onAppActive() } }
        observe(UIScene.didActivateNotification) { Task { await rt.onAppActive() } }
        observe(UIApplication.didEnterBackgroundNotification) { Task { await rt.onAppBackground() } }
        observe(.NSSystemClockDidChange) { Task { await rt.onClockChanged() } }
        let battery: @Sendable () -> Void = {
            DispatchQueue.main.async {
                let d = UIDevice.current
                guard (0...1).contains(d.batteryLevel) else { return }
                rt.submitBattery(BatteryReading(levelPct: Int((d.batteryLevel * 100).rounded()),
                                                charging: d.batteryState == .charging || d.batteryState == .full))
            }
        }
        UIDevice.current.isBatteryMonitoringEnabled = true
        observe(UIDevice.batteryLevelDidChangeNotification, battery)
        observe(UIDevice.batteryStateDidChangeNotification, battery)
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *), !options.fakeAlarms {
            let mapper = AlarmKitSystemAlarms(registry: registry, intents: nil, stopLabel: { "" })
            alarmTask = Task.detached {
                for await list in AlarmManager.shared.alarmUpdates {
                    // AlarmKit alarms only: the runtime keeps what it knows of the notification channel (T17.3).
                    await rt.onSystemAlarms(mapper.map(list), channel: .alarmKit)
                }
            }
        }
        #endif
        Task { await rt.ensureLoaded() }
    }

    /// StopIntent step (1), before anything else (D12, T10 §7.2): write the ring event to disk synchronously.
    public static func appendRingEventSync(_ e: RingEventRec) throws {
        let store = shared?.store ?? FileRuntimeStore(warn: { _ in })
        try store.appendRingEvent(e)
    }

    /// StopIntent step (3): ensureLoaded + handling (§5.6.5).
    public func onStopIntent(_ e: RingEventRec) async { await runtime.onStopIntent(e) }

    /// T17.2.1 §2 step (3) of NapStopSnoozeIntent: the runtime's answer (the intent stops the ring only after it).
    @discardableResult
    public func onSnoozeIntent(_ e: RingEventRec) async -> SnoozeHandOverOutcome { await runtime.onSnoozeIntent(e) }

    /// T17.2.1 §2.1: snooze values of `tripId` for the rescue alarm (defaults before the trip is loaded). Never waits.
    public static func snoozeRescueParams(tripId: String) -> SnoozeRescueParams {
        shared?.runtime.snoozeRescueParams(tripId: tripId) ?? .defaults
    }

    /// T17.2 §3.2 step (3) of NapStopRouteBackIntent (launch action, then DISMISS).
    public func onRouteBackIntent(_ e: RingEventRec) async { await runtime.onRouteBackIntent(e) }

    /// T17.2 D8: launch_action.json, taken once (no wait; `IOSAlarmHostApi` waits for an intent in flight).
    public func consumeLaunchAction() async -> LaunchActionRec? { await runtime.consumeLaunchAction() }

    /// T17.2 D11: is an alarm of this app ringing now (no "Nghe thử" over it, T16 AE11)? Synchronous: AlarmKit's list on
    /// iOS 26+, the fake port in diagnostics; false when unreadable or before iOS 26.
    public func anyAlarmAlerting() -> Bool {
        if let fake = fakeAlarms { return fake.anyAlerting() }
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            return ((try? AlarmManager.shared.alarms) ?? []).contains { $0.state == .alerting }
        }
        #endif
        return false
    }

    /// `applicationWillTerminate`: synchronous snapshot, at most ~1 s (§7).
    public func willTerminate() {
        // Review #8: never block main on the runtime queue (a queued Step may be waiting for main). Write the last
        // committed snapshot directly and post "interrupted" best-effort (Câu hỏi mở 3 = A).
        guard let snap = runtime.terminateSnapshot(wallMs: IOSTime().wallMs()) else { return }
        try? store.writeActive(snap.trip)
        if snap.interrupted {
            let notifier = self.notifier
            Task.detached { await notifier.show(tripId: snap.tripId, .interrupted, destinationName: nil) }
        }
    }

    public static func nowWallMs() -> Int64 { IOSTime().wallMs() }
}

/// Thread-safe count of running intents (T17.2 D8).
public final class InFlightCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    public init() {}
    public func enter() { lock.lock(); n += 1; lock.unlock() }
    public func leave() { lock.lock(); n = max(0, n - 1); lock.unlock() }
    public var active: Bool { lock.lock(); defer { lock.unlock() }; return n > 0 }
}
#endif
