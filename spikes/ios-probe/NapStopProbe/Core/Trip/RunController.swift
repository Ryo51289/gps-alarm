import Combine
import CoreLocation
import Foundation
import UIKit

/// Holds a UIBackgroundTaskIdentifier for the expiration handler.
private final class BackgroundTaskBox: @unchecked Sendable {
    var id: UIBackgroundTaskIdentifier = .invalid
}

/// One run at a time (S3 §6.8): start/stop, phases, trigger on fix, fallback alarm (prearm) and its re-arming,
/// "stop location (keep run)", "self-exit after 30 s", resume in a new process.
@MainActor
final class RunController: ObservableObject {
    static let shared = RunController()

    @Published private(set) var config: RunConfig?
    @Published private(set) var fired = false
    @Published private(set) var fixCount = 0
    @Published private(set) var lastFixAt: Date?
    @Published private(set) var phase: Phase = .dense
    @Published private(set) var locationRunning = false
    @Published private(set) var selfExitAt: Date?
    @Published private(set) var device = DeviceInfo()
    @Published var message: String?

    let location = LocationRecorder()
    let walk = WalkMonitor()

    private let store = RunStore.shared
    private let events = EventLog.shared
    private var state = RunState()
    private var lastDeliveredPoll: Date?
    private var sawActiveThisLaunch = false

    private init() {
        config = store.loadConfig()
        state = store.loadState()
        fired = state.fired
        location.onFix = { [unowned self] date in
            MainActor.assumeIsolated { self.onFix(at: date) }
        }
        location.onAuthChange = { [unowned self] in
            MainActor.assumeIsolated { self.refreshDeviceSoon() }
        }
    }

    // MARK: - Start

    func start(preset: ScenarioPreset, channel: ProbeChannel, delayMin: Int, longHours: Int, denseMin: Int, prearm: Bool) async {
        let now = Date()
        let durationMin = preset.longRun ? max(1, longHours) * 60 : delayMin
        let dense = preset.longRun ? min(max(1, denseMin), durationMin) : durationMin
        let runId = "\(IsoTime.compact(now, offsetSeconds: TimeZone.current.secondsFromGMT(for: now)))-\(preset.id)-\(channel.rawValue)"
        let cfg = RunConfig(
            runId: runId, scenario: preset.id, channel: channel, delayMin: durationMin, durationMin: durationMin,
            densePhaseMin: dense, prearm: prearm, walk: false, startedAt: now,
            deadline: now.addingTimeInterval(Double(durationMin) * 60)
        )
        await begin(cfg)
    }

    /// S3-13: a run whose location only arms the walk monitor (TS channel, no deadline alarm).
    func startWalk() async {
        let now = Date()
        let runId = "\(IsoTime.compact(now, offsetSeconds: TimeZone.current.secondsFromGMT(for: now)))-S3-13-TS"
        let cfg = RunConfig(
            runId: runId, scenario: "S3-13", channel: .TS, delayMin: 60, durationMin: 60, densePhaseMin: 60,
            prearm: false, walk: true, startedAt: now, deadline: now.addingTimeInterval(3600)
        )
        await begin(cfg)
    }

    private func begin(_ cfg: RunConfig) async {
        guard config == nil else {
            message = "Đang có lượt chạy. Dừng lượt đó trước."
            return
        }
        guard UIApplication.shared.applicationState == .active else { return }
        let auth = location.authorizationStatus
        guard auth == .authorizedWhenInUse || auth == .authorizedAlways else {
            message = "Chưa có quyền vị trí. Bấm “Cấp Khi dùng app” trước."
            return
        }
        config = cfg
        state = RunState()
        // Review R2-2: a fix arriving while begin() awaits must not start a re-arm next to the first prearm.
        state.lastReschedule = cfg.startedAt
        fired = false
        fixCount = 0
        lastFixAt = nil
        store.saveConfig(cfg)
        store.saveState(state)
        store.markCleanExit(false)
        events.currentRunId = cfg.runId
        let model = DeviceSnapshot.model()
        events.log("run_start", [
            "scenario": .str(cfg.scenario), "channel": .str(cfg.channel.rawValue), "delayMin": .num(cfg.delayMin),
            "durationMin": .num(cfg.durationMin), "densePhaseMin": .num(cfg.densePhaseMin), "prearm": .flag(cfg.prearm),
            "deadline": .str(IsoTime.local(cfg.deadline)), "ios": .str(UIDevice.current.systemVersion), "model": .str(model),
            "walk": .flag(cfg.walk),
        ])
        // Location first, while surely in the foreground (CLBackgroundActivitySession, When In Use).
        startLocation()

        let info = await DeviceSnapshot.collect(location: location.manager)
        device = info
        events.log(to: cfg.runId, "perm_snapshot", DeviceSnapshot.permFields(info))
        let channelAuth = cfg.channel == .AK ? info.alarmKitAuth : info.notifAuth
        if channelAuth != "authorized" {
            message = "Kênh \(cfg.channel.label) chưa được cấp quyền (\(channelAuth)). Lượt vẫn chạy."
        }
        await channel(cfg.channel).cancelAll(runId: cfg.runId)
        if cfg.prearm { await armPrearm(cfg, reschedule: false) }
    }

    private func channel(_ c: ProbeChannel) -> AlarmChannel {
        c == .AK ? AlarmKitChannel.shared : NotificationChannel.shared
    }

    private func armPrearm(_ cfg: RunConfig, reschedule: Bool) async {
        let at = TriggerLogic.prearmDate(deadline: cfg.deadline)
        state.lastReschedule = Date()
        store.saveState(state)
        let result: ScheduleResult
        if reschedule {
            result = await channel(cfg.channel).reschedulePrearm(at: at, runId: cfg.runId)
        } else {
            result = await channel(cfg.channel).prearm(at: at, runId: cfg.runId)
        }
        events.log(to: cfg.runId, reschedule ? "prearm_reschedule" : "prearm_set", [
            "channel": .str(cfg.channel.rawValue), "at": .str(IsoTime.local(at)), "ok": .flag(result.ok),
            "err": .str(result.err), "ms": .num(result.ms),
        ])
    }

    private func startLocation() {
        guard let cfg = config else { return }
        let p = currentPhase(cfg, Date())
        phase = p
        location.start(phase: p)
        locationRunning = true
    }

    private func currentPhase(_ cfg: RunConfig, _ now: Date) -> Phase {
        TriggerLogic.phase(
            now: now, runStart: cfg.startedAt, durationS: Double(cfg.durationMin) * 60,
            densePhaseS: Double(cfg.densePhaseMin) * 60
        )
    }

    // MARK: - Fixes (foreground and background)

    private func onFix(at now: Date) {
        fixCount = location.fixCount
        lastFixAt = now
        guard let cfg = config else { return }

        let p = currentPhase(cfg, now)
        if p != phase {
            let boundary = TriggerLogic.denseStart(
                runStart: cfg.startedAt, durationS: Double(cfg.durationMin) * 60, densePhaseS: Double(cfg.densePhaseMin) * 60
            )
            events.log("phase_switch", [
                "from": .str(phase.rawValue), "to": .str(p.rawValue), "lateMs": .num(Int(now.timeIntervalSince(boundary) * 1000)),
            ])
            phase = p
            location.setPhase(p)
        }

        if cfg.walk {
            if TriggerLogic.isTimedOut(now: now, deadline: cfg.deadline) {
                stopRun(by: "timeout", alarmVia: nil)
                return
            }
            if !state.walkArmed, let center = location.lastLocation?.coordinate {
                state.walkArmed = true
                store.saveState(state)
                let runId = cfg.runId
                inBackgroundTask("walk_start") { await self.walk.start(center: center, runId: runId) }
            }
            return
        }

        // Review #2: fire is evaluated first, and no re-arm starts within 30 s of the deadline or after it
        // (TriggerLogic.shouldReschedule), so a re-arm never runs concurrently with fireNow.
        if TriggerLogic.shouldFire(now: now, deadline: cfg.deadline, alreadyFired: state.fired) {
            fire(cfg, now: now)
        } else if cfg.prearm
            && TriggerLogic.shouldReschedule(
                last: state.lastReschedule, now: now, deadline: cfg.deadline, fired: state.fired
            ) {
            state.lastReschedule = now
            store.saveState(state)
            inBackgroundTask("prearm_reschedule") { await self.armPrearm(cfg, reschedule: true) }
        }

        if state.fired {
            if lastDeliveredPoll == nil || now.timeIntervalSince(lastDeliveredPoll ?? now) >= 10 {
                lastDeliveredPoll = now
                Task { await NotificationChannel.shared.syncDelivered() }
            }
        }

        if TriggerLogic.isTimedOut(now: now, deadline: cfg.deadline) {
            stopRun(by: "timeout", alarmVia: state.fired ? "timeout" : nil)
        }
    }

    private func fire(_ cfg: RunConfig, now: Date) {
        state.fired = true
        state.firedAt = now
        store.saveState(state)
        fired = true
        events.log("alarm_trigger", [
            "src": "fix", "planned": .str(IsoTime.local(cfg.deadline)),
            "lateMs": .num(Int(now.timeIntervalSince(cfg.deadline) * 1000)), "appState": .str(DeviceSnapshot.appState()),
            "protectedData": .flag(UIApplication.shared.isProtectedDataAvailable),
        ])
        let runId = cfg.runId
        switch cfg.channel {
        case .AK:
            inBackgroundTask("fire_ak") { await AlarmKitChannel.shared.fireNow(runId: runId) }
        case .TS:
            inBackgroundTask("fire_ts") { await NotificationChannel.shared.fireNow(runId: runId) }
        case .AU:
            BackgroundAudioProbe.shared.run(runId: runId)
            inBackgroundTask("fire_au") { await NotificationChannel.shared.fireNow(runId: runId) }
        }
    }

    /// Keeps the process alive until `work` is done (alarm API calls from the background).
    private func inBackgroundTask(_ name: String, _ work: @escaping @MainActor () async -> Void) {
        let box = BackgroundTaskBox()
        box.id = UIApplication.shared.beginBackgroundTask(withName: name) {
            if box.id != .invalid {
                UIApplication.shared.endBackgroundTask(box.id)
                box.id = .invalid
            }
        }
        Task { @MainActor in
            await work()
            if box.id != .invalid {
                UIApplication.shared.endBackgroundTask(box.id)
                box.id = .invalid
            }
        }
    }

    // MARK: - Stop

    /// "Dừng lượt" button.
    func userStop() {
        stopRun(by: "user", alarmVia: state.fired ? "user_stop" : nil)
    }

    /// The alarm was stopped (AlarmKit stop intent or notification action); alarm_stop is already logged.
    func alarmStopped(via: String, runId: String, kind: String) {
        guard let cfg = config, !runId.isEmpty, cfg.runId == runId else { return }
        stopRun(by: "alarm_stopped", alarmVia: nil)
    }

    func stopRun(by: String, alarmVia: String?) {
        guard let cfg = config else { return }
        if let via = alarmVia {
            // Which alarm (now / prearm) is ringing is not known here.
            events.log("alarm_stop", ["via": .str(via), "id": .null, "kind": .null])
        }
        location.stop()
        walk.stop(removeCondition: cfg.walk)
        locationRunning = false
        events.log("run_stop", ["by": .str(by)])
        let runId = cfg.runId
        let ch = channel(cfg.channel)
        inBackgroundTask("run_stop") {
            // Delivered notifications are evidence: log them before removing them.
            await NotificationChannel.shared.syncDelivered()
            await ch.cancelAll(runId: runId)
            if cfg.channel != .AK { await AlarmKitChannel.shared.cancelAll(runId: runId) }
            EventLog.shared.flushSync()
        }
        config = nil
        state = RunState()
        fired = false
        selfExitAt = nil
        store.saveConfig(nil)
        store.saveState(state)
        store.markCleanExit(true)
        events.currentRunId = ""
    }

    /// "Dừng vị trí (giữ lượt)": stop location but keep the run and the fallback alarm (S3-6).
    func suspendLocation() {
        guard config != nil else { return }
        events.log("loc_suspend_user")
        location.stop()
        locationRunning = false
        state.locSuspended = true
        store.saveState(state)
    }

    /// "Tự thoát sau 30 giây" (S3-7, S3-13): simulate the system terminating the app.
    func scheduleSelfExit() {
        guard selfExitAt == nil else { return }
        events.log("self_exit_scheduled", ["delayS": .num(TriggerLogic.selfExitDelayS)])
        selfExitAt = Date().addingTimeInterval(TriggerLogic.selfExitDelayS)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(TriggerLogic.selfExitDelayS * 1_000_000_000))
            self.performSelfExit()
        }
    }

    private func performSelfExit() {
        events.log("self_exit_now")
        store.markCleanExit(true)
        events.flushSync()
        exit(0)
    }

    // MARK: - Lifecycle

    /// New process with a run still active (S3 §6.8 resumeAfterLaunch).
    func resumeAfterLaunch(appState: String) {
        guard let cfg = config else { return }
        events.log("run_resume", [
            "appState": .str(appState), "fired": .flag(state.fired), "locSuspended": .flag(state.locSuspended),
        ])
        Task { await NotificationChannel.shared.syncDelivered() }
        if TriggerLogic.isTimedOut(now: Date(), deadline: cfg.deadline) {
            stopRun(by: "timeout", alarmVia: state.fired ? "timeout" : nil)
            return
        }
        if cfg.walk {
            let runId = cfg.runId
            Task { await self.walk.resume(runId: runId) }
        }
        if state.locSuspended { return }
        let auth = location.authorizationStatus
        if appState == "background" && auth != .authorizedAlways {
            events.log("loc_start_skipped", ["appState": .str(appState), "locAuth": .str(StatusNames.location(auth))])
            return
        }
        startLocation()
    }

    /// scenePhase from the App.
    func scenePhaseChanged(_ state: String) {
        var fields: [String: JSONScalar] = ["state": .str(state)]
        if state == "active" && !sawActiveThisLaunch {
            // Review #6: proc_start.appState is read before the scene connects; this tells a user launch apart.
            sawActiveThisLaunch = true
            fields["firstActiveInLaunch"] = .flag(true)
            fields["sinceLaunchMs"] = .num(Int((ProcessInfo.processInfo.systemUptime - events.startUptime) * 1000))
        }
        events.log("app_state", fields)
        guard state == "active" else { return }
        refreshDeviceSoon()
        guard let cfg = config else { return }
        Task { await NotificationChannel.shared.syncDelivered() }
        if TriggerLogic.isTimedOut(now: Date(), deadline: cfg.deadline) {
            stopRun(by: "timeout", alarmVia: self.state.fired ? "timeout" : nil)
            return
        }
        if !location.running && !self.state.locSuspended {
            startLocation()
        }
    }

    // MARK: - UI helpers

    func refreshDevice() async {
        device = await DeviceSnapshot.collect(location: location.manager)
    }

    func refreshDeviceSoon() {
        Task { await self.refreshDevice() }
    }

    func requestLocationWhenInUse() { location.requestWhenInUse() }

    func requestLocationAlways() { location.requestAlways() }

    func requestNotifications() async {
        _ = await NotificationChannel.shared.requestAuthorization()
        await refreshDevice()
    }

    func requestAlarmKit() async {
        _ = await AlarmKitChannel.shared.requestAuthorization()
        await refreshDevice()
    }

    func testAlarmKit(defaultSound: Bool) async {
        await AlarmKitChannel.shared.test(defaultSound: defaultSound)
        message = "Đã đặt báo thức thử sau 10 giây. Khoá máy và chờ."
    }

    func testNotification() async {
        await NotificationChannel.shared.test()
        message = "Đã đặt thông báo thử sau 10 giây. Khoá máy và chờ."
    }
}
