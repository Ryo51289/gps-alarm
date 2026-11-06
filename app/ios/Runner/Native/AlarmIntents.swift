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
      handOver: { r in await AlarmIntents.host().onStopIntent(r) })
    if let journal = RuntimeHost.shared?.journal {
      StopIntentFlow.recordWriteFailure(written: written, journal)  // review T17 R4-2
    }
    return .result()
  }
}

/// "Báo lại sau {minutes} phút", the secondary button of a "now"/fallback/guard alarm (spec T17.2 D2, D4, D5). Runs in the
/// background ([AI-MODES]): the app is not opened. Parameters: ids only.
@available(iOS 26.0, *)
struct NapStopSnoozeIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Báo lại"
  static let supportedModes: IntentModes = .background

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
    // T17.2.1 §2 (order tested on Linux, SnoozeIntentFlow): (1) ring event with the rescue id on disk, (2) the rescue
    // alarm at tap + snooze + lag, (3) the runtime for at most SNOOZE_HANDOVER_BUDGET_MS, (4) stop the ring only when
    // something rings for this snooze (the docs do not say whether a `.custom` button stops it; Code=0 is fine).
    // The values come from the loaded trip, else the defaults (§2.1): the host is not created before (1).
    let (rec, rescue) = SnoozeIntentFlow.prepare(
      tripId: tripId, alarmId: alarmID, kind: SystemAlarmKind(rawValue: kind) ?? .fallback,
      tapWallMs: RuntimeHost.nowWallMs(), rescueId: UUID().uuidString,
      params: RuntimeHost.snoozeRescueParams(tripId: tripId), locale: RuntimeHost.localeTag())
    let result = await SnoozeIntentFlow.perform(
      rec, rescue: rescue, budgetMs: RuntimeConstants.default.snoozeHandoverBudgetMs,
      write: { try RuntimeHost.appendRingEventSync($0) },
      schedule: { try await AlarmIntents.host().alarms.schedule($0) },
      handOver: { r in await AlarmIntents.host().onSnoozeIntent(r) },
      stopSystemAlarm: { AlarmIntents.stopAlarm(alarmID) },
      journal: HostJournal())
    if let journal = RuntimeHost.shared?.journal {
      StopIntentFlow.recordWriteFailure(written: result.written, journal)
    }
    return .result()
  }
}

/// "Xem đường quay lại", the secondary button of an OVERSHOOT alarm (spec T17.2 D2, D7). Writes the launch action, ends
/// the trip, and brings the app to the foreground (screen 8, T27). Parameters: ids only.
@available(iOS 26.0, *)
struct NapStopRouteBackIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Xem đường quay lại"
  /// [AI-MODES]: starts in the background, the app comes to the foreground before the intent completes.
  static let supportedModes: IntentModes = [.background, .foreground(.deferred)]

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
    // D8: `consumeLaunchAction` waits for the launch action while this runs.
    RuntimeHost.routeBackInFlight.enter()
    defer { RuntimeHost.routeBackInFlight.leave() }
    let rec = RingEventRec(
      tripId: tripId, alarmId: alarmID, kind: SystemAlarmKind(rawValue: kind) ?? .fallback, action: .routeBack,
      atWallMs: RuntimeHost.nowWallMs())
    let written = await StopIntentFlow.perform(
      rec,
      write: { try RuntimeHost.appendRingEventSync($0) },
      stopSystemAlarm: { AlarmIntents.stopAlarm(alarmID) },
      handOver: { r in await AlarmIntents.host().onRouteBackIntent(r) })
    if let journal = RuntimeHost.shared?.journal {
      StopIntentFlow.recordWriteFailure(written: written, journal)
    }
    // [AI-CIF]: ask for the foreground explicitly (the launch action is on disk already). Throws when the system declines
    // (e.g. already foreground or not allowed); AM03 checks what the device does.
    try? await continueInForeground(nil, alwaysConfirm: false)
    return .result()
  }
}

/// The diagnostics journal of the host, looked up at each record (the snooze intent writes its ring event before the host
/// exists in a freshly launched process).
struct HostJournal: RuntimeJournal {
  func record(_ event: String, _ fields: [String: String]) {
    RuntimeHost.shared?.journal.record(event, fields)
  }
}

enum AlarmIntents {
  /// Injected into RuntimeHost: builds the intents of one alarm (AlarmKit needs `any LiveActivityIntent`).
  static let factory: AlarmIntentFactory = { alarmID, tripId, kind, secondary in
    if #available(iOS 26.0, *) {
      let stop = NapStopStopIntent(alarmID: alarmID, tripId: tripId, kind: kind)
      switch secondary {
      case .snooze?:
        return (stop, NapStopSnoozeIntent(alarmID: alarmID, tripId: tripId, kind: kind))
      case .routeBack?:
        return (stop, NapStopRouteBackIntent(alarmID: alarmID, tripId: tripId, kind: kind))
      case nil:
        return (stop, nil)
      }
    }
    return ((), nil)
  }

  /// The runtime host; an intent may run in a process the system just launched in the background.
  static func host() -> RuntimeHost {
    RuntimeHost.shared ?? RuntimeHost.bootstrap(options: options(), intentFactory: factory)
  }

  /// D4 (2): stop the alarm of a secondary button; "already stopped" (Code=0) is fine (K4 #11, D22).
  static func stopAlarm(_ alarmID: String) {
    #if canImport(AlarmKit)
      if #available(iOS 26.0, *), let id = UUID(uuidString: alarmID) {
        try? AlarmManager.shared.stop(id: id)
      }
    #endif
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
