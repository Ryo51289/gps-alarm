import CoreLocation
import Foundation

/// S3-13 (optional, H10): CLMonitor circle of 200 m around the start point + UNLocationNotificationTrigger on exit.
/// The centre only lives in memory and inside the system's monitor; it is never logged.
final class WalkMonitor {
    static let monitorName = "napstop-probe-walk"
    static let conditionId = "walk"

    private var monitor: CLMonitor?
    private var task: Task<Void, Never>?
    private let events = EventLog.shared

    func start(center: CLLocationCoordinate2D, runId: String) async {
        let m = await CLMonitor(Self.monitorName)
        let condition = CLMonitor.CircularGeographicCondition(center: center, radius: TriggerLogic.walkRadiusM)
        await m.add(condition, identifier: Self.conditionId, assuming: .satisfied)
        monitor = m
        observe(m, runId: runId)
        events.log(to: runId, "walk_start", ["radiusM": .num(TriggerLogic.walkRadiusM)])

        let region = CLCircularRegion(center: center, radius: TriggerLogic.walkRadiusM, identifier: Self.monitorName)
        region.notifyOnEntry = false
        region.notifyOnExit = true
        await NotificationChannel.shared.addLocationTrigger(region: region, runId: runId)
    }

    /// A new process must re-create the monitor with the same name to receive its events ([I21]).
    func resume(runId: String) async {
        guard monitor == nil else { return }
        let m = await CLMonitor(Self.monitorName)
        monitor = m
        observe(m, runId: runId)
        events.log(to: runId, "walk_resume")
    }

    /// `removeCondition`: the run was a walk run. If this process never re-created the monitor (e.g. the run ended by
    /// timeout right after a relaunch), open it by name just to remove the condition, so the system stops monitoring
    /// the start point (review #7).
    func stop(removeCondition: Bool) {
        task?.cancel()
        task = nil
        let existing = monitor
        monitor = nil
        if let m = existing {
            Task { await m.remove(Self.conditionId) }
        } else if removeCondition {
            let events = self.events
            Task {
                let m = await CLMonitor(Self.monitorName)
                await m.remove(Self.conditionId)
                events.log("walk_condition_removed")
            }
        }
    }

    private func observe(_ m: CLMonitor, runId: String) {
        task?.cancel()
        let events = self.events
        task = Task {
            do {
                for try await event in await m.events {
                    let state = Self.stateName(event.state)
                    let appState = await MainActor.run { DeviceSnapshot.appState() }
                    events.log(to: runId, "walk_event", ["state": .str(state), "appState": .str(appState)])
                }
            } catch {
                events.log(to: runId, "walk_error", ["err": .str(String(describing: error))])
            }
        }
    }

    static func stateName(_ state: CLMonitor.Event.State) -> String {
        if state == .satisfied { return "satisfied" }
        if state == .unsatisfied { return "unsatisfied" }
        if state == .unknown { return "unknown" }
        return "other"
    }
}
