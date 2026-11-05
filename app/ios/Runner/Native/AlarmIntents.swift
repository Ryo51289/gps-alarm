import AppIntents
import Foundation
import NapStopIOS
import TripRuntime

#if canImport(AlarmKit)
  import AlarmKit
#endif

/// Stop button of the AlarmKit alert (spec T17 §5.6.5, D12). Lives in the app target so the App Intents metadata is
/// extracted (as in the S3 probe). Parameters: ids only, never coordinates or the destination name.
@available(iOS 26.0, *)
struct NapStopStopIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Tắt báo thức"

  @Parameter(title: "Alarm")
  var alarmID: String

  @Parameter(title: "Trip")
  var tripId: String

  @Parameter(title: "Kind")
  var kind: String

  init() {
    self.alarmID = ""
    self.tripId = ""
    self.kind = ""
  }

  init(alarmID: String, tripId: String, kind: String) {
    self.alarmID = alarmID
    self.tripId = tripId
    self.kind = kind
  }

  func perform() async throws -> some IntentResult {
    let rec = RingEventRec(
      tripId: tripId, alarmId: alarmID, kind: SystemAlarmKind(rawValue: kind) ?? .fallback, action: .dismiss,
      atWallMs: RuntimeHost.nowWallMs())
    let id = UUID(uuidString: alarmID)
    // Order tested on Linux (StopIntentFlow): (1) on disk before anything else (T10 §7.2), (2) stop on iOS 26.0,
    // (3) hand over to the runtime, also when (1) failed.
    let written = await StopIntentFlow.perform(
      rec,
      write: { try RuntimeHost.appendRingEventSync($0) },
      stopSystemAlarm: {
        #if canImport(AlarmKit)
          if #unavailable(iOS 26.1), let id {
            try? AlarmManager.shared.stop(id: id)  // K4 #12; Code=0 is fine (D22)
          }
        #endif
      },
      handOver: { r in
        let host =
          RuntimeHost.shared
          ?? RuntimeHost.bootstrap(options: AlarmIntents.options(), stopIntentFactory: AlarmIntents.factory)
        await host.onStopIntent(r)
      })
    if let journal = RuntimeHost.shared?.journal {
      StopIntentFlow.recordWriteFailure(written: written, journal)  // review T17 R4-2
    }
    return .result()
  }
}

enum AlarmIntents {
  /// Injected into RuntimeHost: builds the StopIntent of one alarm (AlarmKit needs `any LiveActivityIntent`).
  static let factory: StopIntentFactory = { alarmID, tripId, kind in
    if #available(iOS 26.0, *) {
      return NapStopStopIntent(alarmID: alarmID, tripId: tripId, kind: kind)
    }
    return ()
  }

  /// Diagnostics only in builds with NAPSTOP_DIAG (§5.13); the fake alarm port only on the Simulator, on request.
  static func options() -> RuntimeOptions {
    #if NAPSTOP_DIAG
      #if targetEnvironment(simulator)
        let fake = UserDefaults.standard.bool(forKey: "napstop.diag.fakeAlarms")
      #else
        let fake = false
      #endif
      return RuntimeOptions(diagnostics: true, fakeAlarms: fake)
    #else
      return RuntimeOptions()
    #endif
  }
}
