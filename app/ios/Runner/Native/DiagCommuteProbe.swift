#if NAPSTOP_DIAG
  import AppIntents
  import CoreLocation
  import Foundation
  import NapStopIOS
  import TripRuntime
  import UIKit
  import UserNotifications

  /// Spike T23.8-B0 (docs/spikes/T23.8.md §2): region A/B wake probe, diagnostic builds only.
  ///
  /// - Regions: `CLMonitor` named `napstop.diag.commute` (conditions "A", "B") and/or the legacy API (regions
  ///   `napstop.diag.commute.A|B`). The system keeps the region centres; this probe never writes a coordinate. Centres are
  ///   read back from the system only in memory (moving a point to the other API, distance of the first fix).
  /// - Every region event → journal `probe_region` + `Documents/napstop_diag/commute_probe.json` (kinds, wall times,
  ///   durations, rounded distances, accuracy buckets). An outside → inside entry starts continuous updates from
  ///   wherever the app is (H2; no `CLBackgroundActivitySession`), optionally under a `CLServiceSession(.always)` (H2b),
  ///   schedules an AlarmKit alarm (H3) and posts a notification with a non-foreground "Dừng" action (H4).
  /// - Read the results with the Shortcut "NapStop: probe vùng — kết quả" or from the files (T17 protocol B.2.1).
  @MainActor
  final class DiagCommuteProbe: NSObject, CLLocationManagerDelegate, UNUserNotificationCenterDelegate {
    private(set) static var shared: DiagCommuteProbe?

    nonisolated static let monitorName = "napstop.diag.commute"
    nonisolated static let legacyPrefix = "napstop.diag.commute."
    nonisolated static let category = "napstop.diag.commute"
    nonisolated static let stopAction = "napstop.diag.commute.stop"
    nonisolated static let notificationId = "napstop.diag.commute.started"
    static let alarmTripId = "diag-commute"

    private let journal: RuntimeJournal
    private let alarms: SystemAlarms
    private let url: URL
    private let procStartWallMs = RuntimeHost.nowWallMs()
    private var file: CommuteProbeFile
    /// The process has been in the foreground at least once (else it was launched in the background).
    private var everActive = false
    private var seenEvent = false
    private var observers: [NSObjectProtocol] = []

    /// Legacy regions, authorization requests and the one-shot location of the set-up Shortcut.
    private let regionManager = CLLocationManager()
    /// Continuous session started by an entry (nil = none).
    private var updates: CLLocationManager?
    private var monitorTask: Any?  // Task<CLMonitor, Never>, iOS 17+
    private var serviceSession: AnyObject?  // CLServiceSession, iOS 18+
    private var bgTask: UIBackgroundTaskIdentifier = .invalid
    private var authWaiter: CheckedContinuation<Void, Never>?
    private var authBefore: CLAuthorizationStatus = .notDetermined
    private var locationWaiter: CheckedContinuation<CLLocation?, Never>?

    // Running session (memory only).
    private var sessionStartWallMs: Int64 = 0
    private var holdMs: Int64 = 0
    private var centre: CLLocation?
    private var alarmId: String?
    private var minuteStartWallMs: Int64 = 0
    private var minuteFixes = 0
    private var minuteMaxGapMs: Int64 = 0
    private var lastFixWallMs: Int64?

    private init(journal: RuntimeJournal, alarms: SystemAlarms) {
      self.journal = journal
      self.alarms = alarms
      let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSTemporaryDirectory())
      let dir = docs.appendingPathComponent("napstop_diag", isDirectory: true)
      try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      url = dir.appendingPathComponent("commute_probe.json")
      file = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(CommuteProbeFile.self, from: $0) }
        ?? CommuteProbeFile()
      super.init()
    }

    /// AppDelegate `didFinishLaunching`: re-creates the monitor / legacy delegate / service session only when a probe is
    /// configured (spec D4, [I6], [F2]); otherwise nothing happens.
    static func launch(launchOptions: [UIApplication.LaunchOptionsKey: Any]?, host: RuntimeHost) {
      let p = ensure(host: host)
      guard p.file.config != nil else { return }
      p.journal.record("probe_launch", [
        "locKey": launchOptions?[.location] != nil ? "true" : "false",
        "app": p.appState(), "auth": p.authCode(), "bar": p.barCode(),
        "lowPower": ProcessInfo.processInfo.isLowPowerModeEnabled ? "true" : "false",
      ])
      p.arm()
    }

    /// Intents: the probe without arming anything new.
    static func ensure(host: RuntimeHost = AlarmIntents.host()) -> DiagCommuteProbe {
      if let s = shared { return s }
      let p = DiagCommuteProbe(journal: host.journal, alarms: host.alarms)
      shared = p
      p.everActive = UIApplication.shared.applicationState == .active
      p.observers.append(
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
          MainActor.assumeIsolated { DiagCommuteProbe.shared?.everActive = true }
        })
      p.closeInterruptedSession()
      return p
    }

    // MARK: Arming

    private func arm() {
      guard let c = file.config else { return }
      UNUserNotificationCenter.current().delegate = self
      registerCategory()
      if c.serviceSession { startServiceSession() }
      if c.apiMode.apis.contains(.legacy) { regionManager.delegate = self }
      if c.apiMode.apis.contains(.clmonitor), #available(iOS 17.0, *) {
        Task { _ = await self.monitor() }
      }
    }

    @available(iOS 17.0, *)
    private func monitor() async -> CLMonitor {
      if let t = monitorTask as? Task<CLMonitor, Never> { return await t.value }
      let t = Task { await CLMonitor(Self.monitorName) }
      monitorTask = t
      let m = await t.value
      Task { [weak self] in
        do {
          for try await e in await m.events {
            self?.onMonitorEvent(e)
          }
          self?.journal.record("probe_error", ["op": "events", "err": "ended"])
        } catch {
          self?.journal.record("probe_error", ["op": "events", "err": String(describing: type(of: error))])
        }
      }
      return m
    }

    private func startServiceSession() {
      guard serviceSession == nil else { return }
      if #available(iOS 18.0, *) {
        serviceSession = CLServiceSession(authorization: .always)
        journal.record("probe_svc", ["op": "start", "ok": "true", "app": appState()])
      } else {
        journal.record("probe_svc", ["op": "start", "ok": "false", "err": "ios<18"])
      }
    }

    private func stopServiceSession() {
      guard let s = serviceSession else { return }
      if #available(iOS 18.0, *) { (s as? CLServiceSession)?.invalidate() }
      serviceSession = nil
      journal.record("probe_svc", ["op": "stop"])
    }

    private func registerCategory() {
      let stop = UNNotificationAction(identifier: Self.stopAction, title: "Dừng", options: [.destructive])
      let cat = UNNotificationCategory(identifier: Self.category, actions: [stop], intentIdentifiers: [], options: [])
      Task {
        let center = UNUserNotificationCenter.current()
        let existing = await center.notificationCategories()
        center.setNotificationCategories(existing.filter { $0.identifier != Self.category }.union([cat]))
      }
    }

    // MARK: Region events

    @available(iOS 17.0, *)
    private func onMonitorEvent(_ e: CLMonitor.Event) {
      guard let point = ProbePoint(rawValue: e.identifier) else { return }
      let state: ProbeRegionState
      switch e.state {
      case .satisfied: state = .inside
      case .unsatisfied: state = .outside
      default: state = .unknown
      }
      var flags: [String] = []
      if #available(iOS 18.0, *) {
        if e.authorizationDenied { flags.append("denied") }
        if e.authorizationDeniedGlobally { flags.append("deniedGlobally") }
        if e.authorizationRestricted { flags.append("restricted") }
        if e.insufficientlyInUse { flags.append("insufficientlyInUse") }
        if e.accuracyLimited { flags.append("accuracyLimited") }
        if e.conditionLimitExceeded { flags.append("limitExceeded") }
        if e.conditionUnsupported { flags.append("unsupported") }
        if e.persistenceUnavailable { flags.append("persistenceUnavailable") }
        if e.serviceSessionRequired { flags.append("serviceSessionRequired") }
      }
      onRegion(.clmonitor, point, state, eventDate: e.date, flags: flags)
    }

    private func onRegion(_ api: ProbeApi, _ point: ProbePoint, _ state: ProbeRegionState, eventDate: Date?, flags: [String]) {
      let now = RuntimeHost.nowWallMs()
      let key = CommuteProbeFile.stateKey(api, point)
      let transition = CommuteProbe.transition(prev: file.states[key] ?? .unknown, new: state)
      if state != .unknown { file.states[key] = state }
      let ev = ProbeEventRecord(
        api: api, point: point, state: state, transition: transition,
        eventWallMs: eventDate.map { Int64(($0.timeIntervalSince1970 * 1000).rounded(.down)) }, receivedWallMs: now,
        appState: appState(), procAgeS: Int((now - procStartWallMs) / 1000),
        launchedInBackground: !everActive, firstOfProcess: !seenEvent)
      seenEvent = true
      file.events.append(ev)
      journal.record("probe_region", [
        "api": api.rawValue, "pt": point.rawValue, "state": state.rawValue, "tr": transition.rawValue,
        "ageS": ev.ageS.map(String.init) ?? "na", "app": ev.appState, "procAgeS": "\(ev.procAgeS)",
        "bgLaunch": ev.launchedInBackground ? "true" : "false", "first": ev.firstOfProcess ? "true" : "false",
        "flags": flags.joined(separator: ","), "auth": authCode(), "locked": lockedCode(),
      ])
      if transition == .entry { onEntry(ev) }
      file.trim()
      save()
    }

    private func onEntry(_ ev: ProbeEventRecord) {
      var notStarted: String?
      if updates != nil {
        notStarted = "running"
      } else if regionManager.authorizationStatus != .authorizedAlways {
        notStarted = "not-always"
      } else if !CLLocationManager.locationServicesEnabled() {
        notStarted = "services-off"
      }
      let id = String(UUID().uuidString.prefix(8))
      file.wakes.append(ProbeWakeRecord(id: id, event: ev, notStarted: notStarted, serviceSession: serviceSession != nil))
      guard notStarted == nil else {
        journal.record("probe_session", ["op": "skip", "why": notStarted ?? "?", "api": ev.api.rawValue])
        return
      }
      file.activeWakeId = id
      startSession(ev)
    }

    // MARK: Continuous session (H2, H2b, H3, H4)

    private func startSession(_ ev: ProbeEventRecord) {
      bgTask = UIApplication.shared.beginBackgroundTask(withName: "napstop.diag.commute") { [weak self] in
        MainActor.assumeIsolated { self?.endBackgroundTask() }
      }
      let c = file.config
      let m = CLLocationManager()
      m.delegate = self
      m.activityType = .otherNavigation
      m.desiredAccuracy = kCLLocationAccuracyBest
      m.distanceFilter = kCLDistanceFilterNone
      m.pausesLocationUpdatesAutomatically = false
      m.allowsBackgroundLocationUpdates = true
      m.showsBackgroundLocationIndicator = true
      updates = m
      let now = RuntimeHost.nowWallMs()
      sessionStartWallMs = now
      holdMs = Int64(max(1, c?.holdMin ?? 70)) * 60_000
      minuteStartWallMs = now
      minuteFixes = 0
      minuteMaxGapMs = 0
      lastFixWallMs = nil
      centre = nil
      m.startUpdatingLocation()
      journal.record("probe_session", [
        "op": "start", "api": ev.api.rawValue, "pt": ev.point.rawValue, "app": appState(),
        "svc": serviceSession != nil ? "true" : "false", "holdMin": "\(holdMs / 60_000)",
      ])
      Task { await self.loadCentre(ev.api, ev.point) }
      if let min = c?.alarmMin, min > 0 { scheduleAlarm(afterMin: min) }
      postStartedNotification(ev)
      DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
        MainActor.assumeIsolated { self?.endBackgroundTask() }
      }
      save()
    }

    private func loadCentre(_ api: ProbeApi, _ point: ProbePoint) async {
      if let c = await region(point, api) { centre = CLLocation(latitude: c.centre.latitude, longitude: c.centre.longitude) }
    }

    private func onFix(_ l: CLLocation) {
      guard let id = file.activeWakeId, let i = file.wakes.firstIndex(where: { $0.id == id }) else { return }
      let now = RuntimeHost.nowWallMs()
      if let gap = file.wakes[i].stats.add(wallMs: now) {
        journal.record("probe_gap", ["gapS": "\(gap / 1000)", "app": appState(), "locked": lockedCode()])
      }
      if let last = lastFixWallMs { minuteMaxGapMs = max(minuteMaxGapMs, now - last) }
      lastFixWallMs = now
      minuteFixes += 1
      let acc = CommuteProbe.accuracyBucket(l.horizontalAccuracy)
      if file.wakes[i].stats.count == 1 {
        let d = centre.map { CommuteProbe.roundTo10(l.distance(from: $0)) }
        file.wakes[i].firstFixDistM = d
        file.wakes[i].firstFixAccuracy = acc
        journal.record("probe_fix", [
          "first": "true", "acc": acc, "sinceEntryS": "\((now - sessionStartWallMs) / 1000)",
          "fromCentreM": d.map(String.init) ?? "na", "app": appState(),
        ])
        save()
        endBackgroundTask()
      }
      if now - minuteStartWallMs >= 60_000 {
        journal.record("probe_min", [
          "n": "\(minuteFixes)", "maxGapS": "\(minuteMaxGapMs / 1000)", "acc": acc, "app": appState(),
          "locked": lockedCode(), "sinceStartMin": "\((now - sessionStartWallMs) / 60_000)",
        ])
        minuteStartWallMs = now
        minuteFixes = 0
        minuteMaxGapMs = 0
        save()
      }
      if now - sessionStartWallMs >= holdMs { endSession("hold") }
    }

    private func endSession(_ reason: String) {
      guard let m = updates else { return }
      m.stopUpdatingLocation()
      m.allowsBackgroundLocationUpdates = false
      updates = nil
      let now = RuntimeHost.nowWallMs()
      if let id = file.activeWakeId, let i = file.wakes.firstIndex(where: { $0.id == id }) {
        file.wakes[i].endedWallMs = now
        file.wakes[i].endReason = reason
        let s = file.wakes[i].stats
        journal.record("probe_session", [
          "op": "end", "why": reason, "durS": "\((now - sessionStartWallMs) / 1000)", "n": "\(s.count)",
          "maxGapS": "\(s.maxGapMs / 1000)", "bigGaps": "\(s.bigGaps)",
          "passed": file.wakes[i].sessionPassed ? "true" : "false",
        ])
      }
      file.activeWakeId = nil
      centre = nil
      if let a = alarmId {
        alarmId = nil
        let alarms = self.alarms
        Task { await alarms.cancel(id: a, channel: .alarmKit) }
      }
      UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.notificationId])
      endBackgroundTask()
      save()
    }

    /// A session of a previous process (killed while tracking): closed as `interrupted` at its last fix.
    private func closeInterruptedSession() {
      guard let id = file.activeWakeId else { return }
      if let i = file.wakes.firstIndex(where: { $0.id == id }) {
        file.wakes[i].endedWallMs = file.wakes[i].stats.lastWallMs ?? file.wakes[i].event.receivedWallMs
        file.wakes[i].endReason = "interrupted"
        journal.record("probe_session", ["op": "end", "why": "interrupted", "n": "\(file.wakes[i].stats.count)"])
      }
      file.activeWakeId = nil
      save()
    }

    private func endBackgroundTask() {
      guard bgTask != .invalid else { return }
      UIApplication.shared.endBackgroundTask(bgTask)
      bgTask = .invalid
    }

    private func scheduleAlarm(afterMin: Int) {
      let id = UUID().uuidString
      alarmId = id
      let req = SystemAlarmRequest(
        id: id, tripId: Self.alarmTripId, kind: .now, generation: 1,
        fireAtWallMs: RuntimeHost.nowWallMs() + Int64(afterMin) * 60_000, title: "NapStop probe", channel: .alarmKit)
      let alarms = self.alarms
      let wakeId = file.activeWakeId
      Task {
        var outcome = "ok"
        do { try await alarms.schedule(req) } catch { outcome = String(describing: type(of: error)) }
        self.journal.record("ak", ["op": "schedule", "kind": "diag_commute", "ok": outcome == "ok" ? "true" : "false",
                                   "err": outcome == "ok" ? "" : outcome, "app": self.appState()])
        if let w = wakeId, let i = self.file.wakes.firstIndex(where: { $0.id == w }) {
          self.file.wakes[i].alarm = outcome
          self.save()
        }
      }
    }

    private func postStartedNotification(_ ev: ProbeEventRecord) {
      let content = UNMutableNotificationContent()
      content.title = "NapStop probe: đã bật theo dõi"
      content.body = "Vào vùng \(ev.point.rawValue) (\(ev.api.label)). Bấm Dừng để tắt."
      content.categoryIdentifier = Self.category
      content.sound = .default
      let req = UNNotificationRequest(identifier: Self.notificationId, content: content, trigger: nil)
      Task {
        do {
          try await UNUserNotificationCenter.current().add(req)
          self.journal.record("probe_notif", ["op": "post", "ok": "true", "app": self.appState()])
        } catch {
          self.journal.record("probe_notif", ["op": "post", "ok": "false", "err": String(describing: type(of: error))])
        }
      }
    }

    private func onNotificationResponse(_ action: String) {
      journal.record("probe_stop", [
        "action": action == Self.stopAction ? "stop" : (action == UNNotificationDefaultActionIdentifier ? "open" : "other"),
        "app": appState(), "running": updates != nil ? "true" : "false",
      ])
      guard action == Self.stopAction else { return }
      if let id = file.activeWakeId, let i = file.wakes.firstIndex(where: { $0.id == id }) {
        file.wakes[i].stopTapped = true
      }
      save()
      endSession("stop-action")
    }

    // MARK: Shortcuts

    /// Sets region `point` around `place` (nil = current location) with the given API mode; asks for Always first.
    func setPoint(_ point: ProbePoint, mode: ProbeApiMode, place: CLLocation?, radiusM: Int, serviceSession useSession: Bool,
                  holdMin: Int, alarmMin: Int) async -> String {
      if #unavailable(iOS 17.0), mode != .legacy { return "CLMonitor cần iOS 17. Chọn API legacy." }
      let before = regionManager.authorizationStatus
      if before == .authorizedWhenInUse || before == .notDetermined { await requestAlways() }
      let source = place == nil ? "current" : "place"
      var loc = place
      if loc == nil { loc = await currentLocation() }
      guard let loc else {
        journal.record("probe_setup", ["pt": point.rawValue, "ok": "false", "err": "no-location", "auth": authCode()])
        return "Chưa lấy được vị trí. Bật định vị và thử lại khi đứng ngoài trời."
      }
      let radius = Double(min(max(radiusM, 100), 1000))
      let old = file.config
      let oldApis = Set(old?.apiMode.apis ?? [])
      let newApis = Set(mode.apis)
      var points = Set(old?.points ?? [])
      if oldApis != newApis, let from = oldApis.first {
        // Keep the other point: copy its region (read from the system, memory only) to the new API(s).
        for p in points where p != point {
          if let r = await region(p, from) {
            for api in newApis.subtracting(oldApis) { await addRegion(p, r.centre, r.radius, api) }
          } else {
            points.remove(p)
          }
        }
        for api in oldApis.subtracting(newApis) {
          for p in ProbePoint.allCases { await removeRegion(p, api) }
        }
        for api in ProbeApi.allCases {
          for p in ProbePoint.allCases { file.states[CommuteProbeFile.stateKey(api, p)] = nil }
        }
      }
      for api in ProbeApi.allCases {
        await removeRegion(point, api)
        file.states[CommuteProbeFile.stateKey(api, point)] = nil
      }
      for api in newApis { await addRegion(point, loc.coordinate, radius, api) }
      points.insert(point)
      file.config = CommuteProbeConfig(
        apiMode: mode, serviceSession: useSession, holdMin: max(1, holdMin), alarmMin: max(0, alarmMin),
        radiusM: Int(radius), points: ProbePoint.allCases.filter(points.contains))
      if useSession { startServiceSession() } else { stopServiceSession() }
      arm()
      save()
      let acc = CommuteProbe.accuracyBucket(loc.horizontalAccuracy)
      journal.record("probe_setup", [
        "pt": point.rawValue, "api": mode.rawValue, "r": "\(Int(radius))", "src": source, "acc": acc,
        "auth": authCode(), "svc": useSession ? "true" : "false", "ok": "true",
      ])
      var msg = "Đã đặt vùng \(point.rawValue) (\(mode.rawValue), \(Int(radius)) m, nguồn: "
        + "\(place == nil ? "vị trí hiện tại, sai số \(acc) m" : "địa điểm chọn")). Quyền: \(authLabel())."
      if Bundle.main.object(forInfoDictionaryKey: "NSLocationAlwaysAndWhenInUseUsageDescription") == nil {
        msg += " IPA này thiếu khoá quyền Luôn (không phải bản DIAG của CI): probe không chạy được."
      } else if regionManager.authorizationStatus != .authorizedAlways {
        msg += " Chưa có quyền Luôn: vào Cài đặt › NapStop › Vị trí › Luôn."
      }
      return msg
    }

    func stop(clearRegions: Bool, clearResults: Bool) async -> String {
      endSession("stop-intent")
      if clearRegions {
        for api in ProbeApi.allCases {
          for p in ProbePoint.allCases { await removeRegion(p, api) }
        }
        stopServiceSession()
        file.config = nil
        file.states = [:]
      }
      if clearResults {
        file.events = []
        file.wakes = []
        file.activeWakeId = nil
      }
      save()
      journal.record("probe_clear", ["regions": clearRegions ? "true" : "false", "results": clearResults ? "true" : "false"])
      return "Đã dừng theo dõi liên tục" + (clearRegions ? ", đã gỡ vùng" : "") + (clearResults ? ", đã xoá kết quả" : "") + "."
    }

    func report() async -> String {
      var monitored: [String] = []
      if #available(iOS 17.0, *), file.config?.apiMode.apis.contains(.clmonitor) == true || monitorTask != nil {
        let ids = await monitor().identifiers
        monitored += ids.sorted().map { "CLMonitor \($0)" }
      }
      monitored += regionManager.monitoredRegions.map(\.identifier).filter { $0.hasPrefix(Self.legacyPrefix) }.sorted()
        .map { "Legacy \($0.dropFirst(Self.legacyPrefix.count))" }
      let live = ProbeLiveStatus(
        authorization: authLabel(), fullAccuracy: regionManager.accuracyAuthorization == .fullAccuracy,
        backgroundRefresh: barLabel(), lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
        sessionRunning: updates != nil, monitored: monitored)
      return CommuteProbe.report(file, live: live, utcOffsetS: TimeZone.current.secondsFromGMT())
    }

    // MARK: Regions (both APIs)

    private func addRegion(_ point: ProbePoint, _ c: CLLocationCoordinate2D, _ radius: CLLocationDistance, _ api: ProbeApi) async {
      switch api {
      case .clmonitor:
        if #available(iOS 17.0, *) {
          await monitor().add(CLMonitor.CircularGeographicCondition(center: c, radius: radius), identifier: point.rawValue)
        }
      case .legacy:
        regionManager.delegate = self
        let r = CLCircularRegion(
          center: c, radius: min(radius, regionManager.maximumRegionMonitoringDistance),
          identifier: Self.legacyPrefix + point.rawValue)
        r.notifyOnEntry = true
        r.notifyOnExit = true
        regionManager.startMonitoring(for: r)
      }
    }

    private func removeRegion(_ point: ProbePoint, _ api: ProbeApi) async {
      switch api {
      case .clmonitor:
        if #available(iOS 17.0, *), file.config?.apiMode.apis.contains(.clmonitor) == true || monitorTask != nil {
          await monitor().remove(point.rawValue)
        }
      case .legacy:
        for r in regionManager.monitoredRegions where r.identifier == Self.legacyPrefix + point.rawValue {
          regionManager.stopMonitoring(for: r)
        }
      }
    }

    /// Centre and radius kept by the system (memory only, never stored or logged).
    private func region(_ point: ProbePoint, _ api: ProbeApi) async -> (centre: CLLocationCoordinate2D, radius: CLLocationDistance)? {
      switch api {
      case .clmonitor:
        if #available(iOS 17.0, *),
          let c = await monitor().record(for: point.rawValue)?.condition as? CLMonitor.CircularGeographicCondition
        {
          return (c.center, c.radius)
        }
        return nil
      case .legacy:
        let r = regionManager.monitoredRegions.first { $0.identifier == Self.legacyPrefix + point.rawValue } as? CLCircularRegion
        return r.map { ($0.center, $0.radius) }
      }
    }

    // MARK: Authorization and one-shot location

    /// [I4]: only the first call can show the prompt ("further calls have no effect"); later calls do not wait.
    private func requestAlways() async {
      // [I5]: without the key iOS ignores the request. Only CI diag builds add it (scripts/diag-always-key.sh).
      guard Bundle.main.object(forInfoDictionaryKey: "NSLocationAlwaysAndWhenInUseUsageDescription") != nil else {
        journal.record("probe_auth", ["op": "skip", "why": "no-plist-key", "now": authCode()])
        return
      }
      let askedKey = "napstop.diag.commute.alwaysAsked"
      guard !UserDefaults.standard.bool(forKey: askedKey) else {
        journal.record("probe_auth", ["op": "skip", "why": "asked-before", "now": authCode()])
        return
      }
      UserDefaults.standard.set(true, forKey: askedKey)
      regionManager.delegate = self
      authBefore = regionManager.authorizationStatus
      journal.record("probe_auth", ["op": "request", "before": authCode()])
      regionManager.requestAlwaysAuthorization()
      await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
        authWaiter = c
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
          MainActor.assumeIsolated { self?.resumeAuth() }
        }
      }
      journal.record("probe_auth", ["op": "result", "after": authCode()])
    }

    private func resumeAuth() {
      let c = authWaiter
      authWaiter = nil
      c?.resume()
    }

    private func currentLocation() async -> CLLocation? {
      regionManager.delegate = self
      regionManager.desiredAccuracy = kCLLocationAccuracyBest
      regionManager.requestLocation()
      return await withCheckedContinuation { (c: CheckedContinuation<CLLocation?, Never>) in
        locationWaiter = c
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
          MainActor.assumeIsolated { self?.resumeLocation(self?.regionManager.location) }
        }
      }
    }

    private func resumeLocation(_ l: CLLocation?) {
      let c = locationWaiter
      locationWaiter = nil
      c?.resume(returning: l)
    }

    // MARK: CLLocationManagerDelegate (main thread: the managers are created on main)

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
      MainActor.assumeIsolated {
        if manager === updates {
          for l in locations.sorted(by: { $0.timestamp < $1.timestamp }) { onFix(l) }
        } else if manager === regionManager, let l = locations.last {
          resumeLocation(l)
        }
      }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
      MainActor.assumeIsolated {
        let code = (error as? CLError)?.code.rawValue ?? -1
        if manager === updates {
          journal.record("probe_error", ["op": "updates", "code": "\(code)"])
        } else if manager === regionManager, locationWaiter != nil {
          if (error as? CLError)?.code != .locationUnknown { resumeLocation(nil) }
        }
      }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
      MainActor.assumeIsolated {
        guard manager === regionManager else { return }
        if authWaiter != nil, manager.authorizationStatus != authBefore { resumeAuth() }
        if file.config != nil { journal.record("probe_auth", ["op": "changed", "now": authCode()]) }
      }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
      MainActor.assumeIsolated {
        // H8 parity with CLMonitor: ask for the initial state of a new legacy region.
        manager.requestState(for: region)
      }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
      MainActor.assumeIsolated {
        guard region.identifier.hasPrefix(Self.legacyPrefix),
          let point = ProbePoint(rawValue: String(region.identifier.dropFirst(Self.legacyPrefix.count)))
        else { return }
        let s: ProbeRegionState
        switch state {
        case .inside: s = .inside
        case .outside: s = .outside
        default: s = .unknown
        }
        onRegion(.legacy, point, s, eventDate: nil, flags: [])
      }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
      MainActor.assumeIsolated {
        journal.record("probe_error", ["op": "legacy-monitor", "code": "\((error as? CLError)?.code.rawValue ?? -1)"])
      }
    }

    nonisolated func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
      MainActor.assumeIsolated { journal.record("probe_error", ["op": "paused"]) }
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
      _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
      withCompletionHandler completionHandler: @escaping () -> Void
    ) {
      let category = response.notification.request.content.categoryIdentifier
      let action = response.actionIdentifier
      Task { @MainActor in
        if category == Self.category { self.onNotificationResponse(action) }
        completionHandler()
      }
    }

    nonisolated func userNotificationCenter(
      _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
      withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
      // Other notifications keep the behaviour of an app without a delegate (not shown in the foreground).
      completionHandler(notification.request.content.categoryIdentifier == Self.category ? [.banner, .list, .sound] : [])
    }

    // MARK: Helpers

    private func save() {
      guard let d = try? JSONEncoder().encode(file) else { return }
      do {
        try d.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      } catch {
        journal.record("probe_error", ["op": "save", "err": String(describing: type(of: error))])
      }
    }

    private func appState() -> String {
      switch UIApplication.shared.applicationState {
      case .active: return "active"
      case .inactive: return "inactive"
      case .background: return "background"
      @unknown default: return "other"
      }
    }

    private func lockedCode() -> String { UIApplication.shared.isProtectedDataAvailable ? "false" : "true" }

    private func authCode() -> String {
      switch regionManager.authorizationStatus {
      case .authorizedAlways: return "always"
      case .authorizedWhenInUse: return "whenInUse"
      case .denied: return "denied"
      case .restricted: return "restricted"
      case .notDetermined: return "notDetermined"
      @unknown default: return "other"
      }
    }

    private func authLabel() -> String {
      switch regionManager.authorizationStatus {
      case .authorizedAlways: return "Luôn"
      case .authorizedWhenInUse: return "Khi dùng ứng dụng"
      case .denied: return "Từ chối"
      case .restricted: return "Bị hạn chế"
      case .notDetermined: return "Chưa hỏi"
      @unknown default: return "Khác"
      }
    }

    private func barCode() -> String {
      switch UIApplication.shared.backgroundRefreshStatus {
      case .available: return "available"
      case .denied: return "denied"
      case .restricted: return "restricted"
      @unknown default: return "other"
      }
    }

    private func barLabel() -> String {
      switch UIApplication.shared.backgroundRefreshStatus {
      case .available: return "bật"
      case .denied: return "tắt"
      case .restricted: return "bị hạn chế"
      @unknown default: return "khác"
      }
    }
  }

  // MARK: - Shortcuts (App Intents)

  @available(iOS 16.0, *)
  enum DiagProbePoint: String, AppEnum {
    case a, b

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Điểm"
    static var caseDisplayRepresentations: [DiagProbePoint: DisplayRepresentation] = [.a: "A", .b: "B"]

    var point: ProbePoint { self == .a ? .a : .b }
  }

  @available(iOS 16.0, *)
  enum DiagProbeApi: String, AppEnum {
    case clmonitor, legacy, both

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "API vùng"
    static var caseDisplayRepresentations: [DiagProbeApi: DisplayRepresentation] = [
      .clmonitor: "CLMonitor", .legacy: "Legacy (startMonitoring)", .both: "Cả hai (chỉ so độ trễ)",
    ]

    var mode: ProbeApiMode { ProbeApiMode(rawValue: rawValue) ?? .clmonitor }
  }

  /// Spike T23.8-B0: sets region A or B (current location or a place picked in Shortcuts). Opens the app so that the
  /// "Change to Always Allow" prompt and the one-shot location can run in the foreground.
  @available(iOS 16.0, *)
  struct DiagCommuteProbeIntent: AppIntent {
    static var title: LocalizedStringResource = "NapStop: probe vùng — đặt điểm"
    static var openAppWhenRun = true

    @Parameter(title: "Điểm", default: .a)
    var point: DiagProbePoint

    @Parameter(title: "API", default: .clmonitor)
    var api: DiagProbeApi

    @Parameter(title: "Địa điểm (trống = vị trí hiện tại)")
    var place: CLPlacemark?

    @Parameter(title: "Bán kính (m)", default: 200)
    var radiusM: Int

    @Parameter(title: "Giữ phiên Always (H2b, iOS 18+)", default: false)
    var serviceSession: Bool

    @Parameter(title: "Theo dõi liên tục (phút)", default: 70)
    var holdMin: Int

    @Parameter(title: "Báo thức sau (phút, 0 = tắt)", default: 10)
    var alarmMin: Int

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
      let text = await DiagCommuteProbe.ensure().setPoint(
        point.point, mode: api.mode, place: place?.location, radiusM: radiusM, serviceSession: serviceSession,
        holdMin: holdMin, alarmMin: alarmMin)
      return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
  }

  /// Spike T23.8-B0: text summary of the probe (per API: entries, relaunches, delays, sessions; last 10 entries).
  @available(iOS 16.0, *)
  struct DiagCommuteReportIntent: AppIntent {
    static var title: LocalizedStringResource = "NapStop: probe vùng — kết quả"

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
      let text = await DiagCommuteProbe.ensure().report()
      return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
  }

  /// Spike T23.8-B0: stops the continuous session; optionally removes the regions and/or clears the results.
  @available(iOS 16.0, *)
  struct DiagCommuteStopIntent: AppIntent {
    static var title: LocalizedStringResource = "NapStop: probe vùng — dừng"

    @Parameter(title: "Gỡ vùng A/B", default: false)
    var clearRegions: Bool

    @Parameter(title: "Xoá kết quả", default: false)
    var clearResults: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
      let text = await DiagCommuteProbe.ensure().stop(clearRegions: clearRegions, clearResults: clearResults)
      return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
  }
#endif
