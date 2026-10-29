import AlarmKit
import AppIntents
import Foundation

/// Stop button of the AlarmKit alert (S3 §6.4). Runs in the app process (launched in the background if needed).
struct ProbeStopIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Tắt báo thức thử"

    @Parameter(title: "alarmID")
    var alarmID: String

    @Parameter(title: "runId")
    var runId: String

    @Parameter(title: "kind")
    var kind: String

    init() {
        self.alarmID = ""
        self.runId = ""
        self.kind = ""
    }

    init(alarmID: String, runId: String, kind: String) {
        self.alarmID = alarmID
        self.runId = runId
        self.kind = kind
    }

    func perform() async throws -> some IntentResult {
        let events = EventLog.shared
        events.log(to: runId, "alarm_stop", ["via": "intent", "id": .str(alarmID), "kind": .str(kind)])
        if let id = UUID(uuidString: alarmID) {
            do {
                try AlarmManager.shared.stop(id: id)
            } catch {
                events.log(to: runId, "ak_stop_error", ["id": .str(alarmID), "err": .str(String(describing: error))])
            }
        }
        await RunController.shared.alarmStopped(via: "intent", runId: runId, kind: kind)
        events.flushSync()
        return .result()
    }
}
