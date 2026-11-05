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

    /// Call once on the main thread from `application(_:didFinishLaunchingWithOptions:)`.
    @discardableResult
    public static func bootstrap(options: Options = Options(), stopIntentFactory: StopIntentFactory?) -> RuntimeHost {
        if let s = shared { return s }
        let h = RuntimeHost(options: options, stopIntentFactory: stopIntentFactory)
        shared = h
        h.start()
        return h
    }

    static func localeTag() -> String {
        NativeCopy.localeTag(stored: UserDefaults.standard.string(forKey: appLocaleKey), preferredLanguages: Locale.preferredLanguages)
    }

    private init(options: Options, stopIntentFactory: StopIntentFactory?) {
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
            akChannel = AlarmKitSystemAlarms(registry: registry, stopIntent: stopIntentFactory,
                                             stopLabel: { NativeCopy.string("alarmKitStop", RuntimeHost.localeTag()) })
        }
        #endif
        let alarms: SystemAlarms = fake ?? SystemAlarmsRouter(alarmKit: akChannel, notifications: NotificationSystemAlarms())
        self.alarms = alarms
        self.journal = journal
        let ports = RuntimePorts(time: IOSTime(), location: CoreLocationSession(), alarms: alarms, store: store,
                                 env: fake == nil ? IOSDeviceEnv() : FakeChannelEnv(base: IOSDeviceEnv()), app: IOSAppState(), notifier: notifier,
                                 timer: timer, sleeper: TaskSleeper(), bgTasks: UIKitBackgroundTasks(), journal: journal,
                                 localeTag: { RuntimeHost.localeTag() })
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
            let mapper = AlarmKitSystemAlarms(registry: registry, stopIntent: nil, stopLabel: { "" })
            alarmTask = Task.detached {
                for await list in AlarmManager.shared.alarmUpdates {
                    await rt.onSystemAlarms(mapper.map(list))
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
#endif
