import ActivityKit
import AlarmKit
import Foundation
import SwiftUI

/// AlarmKit channel (S3 §6.4): Alert presentation only (no countdown → no widget extension needed, [I7]),
/// `.fixed(date)` schedules, stop button → ProbeStopIntent. `alarmUpdates` → `ak_state` lines.
final class AlarmKitChannel: AlarmChannel {
    static let shared = AlarmKitChannel()

    private let store = RunStore.shared
    private let events = EventLog.shared
    private var observeTask: Task<Void, Never>?
    /// Last state logged per alarm id; touched only by the observing task (main actor).
    private var lastStates: [UUID: String] = [:]

    var authorizationState: String { StatusNames.alarmKit(AlarmManager.shared.authorizationState) }

    func requestAuthorization() async -> String {
        do {
            let state = try await AlarmManager.shared.requestAuthorization()
            let name = StatusNames.alarmKit(state)
            events.log("ak_auth", ["state": .str(name)])
            return name
        } catch {
            events.log("ak_auth", ["state": "error", "err": .str(String(describing: error))])
            return "error"
        }
    }

    /// Schedules one alert-only alarm and logs `ak_schedule`. Returns the id when it was scheduled.
    @discardableResult
    func schedule(kind: String, runId: String, at date: Date, defaultSound: Bool = false) async -> (id: UUID?, result: ScheduleResult) {
        let id = UUID()
        store.setAlarmRef(id.uuidString, AlarmRef(runId: runId, kind: kind))
        let title = kind == "test" ? "NapStop Probe — thử AlarmKit" : "NapStop Probe — tới mốc"
        let attributes = AlarmAttributes<ProbeAlarmMetadata>(
            presentation: AlarmPresentation(alert: Self.alert(title: title)),
            metadata: ProbeAlarmMetadata(runId: runId, kind: kind),
            tintColor: Color.orange
        )
        let sound: AlertConfiguration.AlertSound = defaultSound ? .default : .named(ToneFile.fileName)
        let configuration: AlarmManager.AlarmConfiguration<ProbeAlarmMetadata> = .alarm(
            schedule: .fixed(date),
            attributes: attributes,
            stopIntent: ProbeStopIntent(alarmID: id.uuidString, runId: runId, kind: kind),
            secondaryIntent: nil,
            sound: sound
        )
        let start = Date()
        var result = ScheduleResult(ok: true, err: nil, ms: 0)
        do {
            _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
        } catch {
            result.ok = false
            result.err = String(describing: error)
            store.setAlarmRef(id.uuidString, nil)
        }
        result.ms = Elapsed.ms(since: start)
        events.log(to: runId, "ak_schedule", [
            "kind": .str(kind), "id": .str(id.uuidString), "fireAt": .str(IsoTime.local(date)), "ok": .flag(result.ok),
            "err": .str(result.err), "ms": .num(result.ms), "sound": .str(defaultSound ? "default" : ToneFile.fileName),
        ])
        return (result.ok ? id : nil, result)
    }

    /// AlarmPresentation.Alert(title:stopButton:…) is deprecated since iOS 26.1; the new initializer has a system
    /// stop button. Deployment target is 26.0 (D2), hence the availability check.
    private static func alert(title: String) -> AlarmPresentation.Alert {
        let resource = LocalizedStringResource(stringLiteral: title)
        if #available(iOS 26.1, *) {
            return AlarmPresentation.Alert(title: resource)
        } else {
            return AlarmPresentation.Alert(
                title: resource,
                stopButton: AlarmButton(text: "Tắt", textColor: .white, systemImageName: "stop.circle")
            )
        }
    }

    /// S3-0 quick test: alarm 10 s from now, from the foreground, outside any run.
    func test(defaultSound: Bool) async {
        await schedule(kind: "test", runId: "", at: Date().addingTimeInterval(10), defaultSound: defaultSound)
    }

    // MARK: - AlarmChannel

    func prearm(at date: Date, runId: String) async -> ScheduleResult {
        let (id, result) = await schedule(kind: "prearm", runId: runId, at: date)
        if let id { store.prearmAlarmId = id.uuidString }
        return result
    }

    /// Schedules the new fallback alarm first, then cancels the old one (never left without a fallback).
    func reschedulePrearm(at date: Date, runId: String) async -> ScheduleResult {
        let old = store.prearmAlarmId
        let (id, result) = await schedule(kind: "prearm", runId: runId, at: date)
        if let id {
            store.prearmAlarmId = id.uuidString
            if let old { cancel(old, runId: runId) }
        }
        return result
    }

    /// Review #3 (approved deviation from §6.8): schedule the "now" alarm first; drop the fallback alarm(s) of this run
    /// only if that succeeded, so a failed schedule from the background still leaves the fallback to ring.
    func fireNow(runId: String) async {
        let (id, _) = await schedule(kind: "now", runId: runId, at: Date().addingTimeInterval(TriggerLogic.akLeadS))
        guard id != nil else {
            events.log(to: runId, "prearm_kept", ["channel": "AK", "reason": "now_failed"])
            return
        }
        for prearmId in store.alarmIds(run: runId) where store.alarmRef(prearmId)?.kind == "prearm" {
            cancel(prearmId, runId: runId)
        }
        store.prearmAlarmId = nil
    }

    func cancelAll(runId: String) async {
        for id in store.alarmIds(run: runId) {
            cancel(id, runId: runId)
        }
        if let prearm = store.prearmAlarmId, store.alarmRef(prearm)?.runId == runId || store.alarmRef(prearm) == nil {
            store.prearmAlarmId = nil
        }
    }

    private func cancel(_ idText: String, runId: String) {
        guard let id = UUID(uuidString: idText) else { return }
        do {
            try AlarmManager.shared.cancel(id: id)
        } catch {
            events.log(to: runId, "ak_cancel_error", ["id": .str(idText), "err": .str(String(describing: error))])
        }
        // The ref is dropped when alarmUpdates reports the alarm gone, so that `ak_state gone` still has its run.
    }

    // MARK: - ak_state

    /// Call once from the main actor at launch.
    @MainActor
    func startObserving() {
        guard observeTask == nil else { return }
        observeTask = Task { @MainActor [weak self] in
            for await alarms in AlarmManager.shared.alarmUpdates {
                self?.handle(alarms)
            }
        }
    }

    @MainActor
    private func handle(_ alarms: [Alarm]) {
        var seen = Set<UUID>()
        for alarm in alarms {
            seen.insert(alarm.id)
            let state = StatusNames.alarmState(alarm.state)
            if lastStates[alarm.id] != state {
                lastStates[alarm.id] = state
                logState(alarm.id, state)
            }
        }
        for id in Array(lastStates.keys) where !seen.contains(id) {
            lastStates[id] = nil
            logState(id, "gone")
            store.setAlarmRef(id.uuidString, nil)
        }
    }

    private func logState(_ id: UUID, _ state: String) {
        let ref = store.alarmRef(id.uuidString)
        events.log(to: ref?.runId ?? "", "ak_state", [
            "id": .str(id.uuidString), "kind": .str(ref?.kind ?? "?"), "state": .str(state),
        ])
    }
}
