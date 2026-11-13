#if NAPSTOP_DIAG
  #if canImport(ActivityKit)
    import ActivityKit
  #endif
  import AppIntents
  import Foundation
  import NapStopIOS
  import TripRuntime

  /// IM06 (spec T17 §5.13): re-schedules a fallback-like alarm at now + 120 s, `perHour` times an hour, new before old;
  /// every 6th time the old one is left until ~10 s before it rings (T10.5 §8). Fake trip `diag-<uuid>`, no engine.
  @available(iOS 16.0, *)
  struct DiagFallbackStressIntent: AppIntent {
    static var title: LocalizedStringResource = "NapStop: thử đặt lại báo dày"

    @Parameter(title: "Lần mỗi giờ", default: 60)
    var perHour: Int

    @Parameter(title: "Số phút", default: 60)
    var minutes: Int

    func perform() async throws -> some IntentResult {
      let host = RuntimeHost.shared ?? RuntimeHost.bootstrap(options: AlarmIntents.options(), intentFactory: AlarmIntents.factory)
      let alarms = host.alarms
      let journal = host.journal
      let perHour = max(1, self.perHour)
      let minutes = max(1, self.minutes)
      Task.detached {
        let trip = "diag-\(UUID().uuidString.prefix(8))"
        let gapMs = Int64(3_600_000 / perHour)
        let endWall = RuntimeHost.nowWallMs() + Int64(minutes) * 60_000
        var old: (id: String, fire: Int64)?
        var n: Int64 = 0
        while RuntimeHost.nowWallMs() < endWall {
          n += 1
          if n % 6 == 0, let o = old {
            let wait = o.fire - 10_000 - RuntimeHost.nowWallMs()
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait) * 1_000_000) }
          }
          let id = UUID().uuidString
          let fire = RuntimeHost.nowWallMs() + 120_000
          let started = RuntimeHost.nowWallMs()
          var ok = true
          do {
            try await alarms.schedule(
              SystemAlarmRequest(id: id, tripId: trip, kind: .fallback, generation: n, fireAtWallMs: fire,
                                 title: "NapStop diag", channel: .alarmKit))
          } catch {
            ok = false
            journal.record("ak", ["op": "schedule", "kind": "diag", "gen": "\(n)", "ok": "false",
                                  "err": String(describing: type(of: error))])
          }
          if ok {
            journal.record("ak", ["op": "schedule", "kind": "diag", "gen": "\(n)", "ok": "true",
                                  "ms": "\(RuntimeHost.nowWallMs() - started)"])
            if let o = old { await alarms.cancel(id: o.id, channel: .alarmKit) }
            old = (id, fire)
          }
          try? await Task.sleep(nanoseconds: UInt64(gapMs) * 1_000_000)
        }
        if let o = old { await alarms.cancel(id: o.id, channel: .alarmKit) }
        journal.record("diag", ["op": "stress_end", "count": "\(n)"])
      }
      return .result()
    }
  }

  /// One "now"-like alarm for a fake trip, `delayS` seconds from now (IC05, IM).
  @available(iOS 16.0, *)
  struct DiagRingNowIntent: AppIntent {
    static var title: LocalizedStringResource = "NapStop: thử báo ngay"

    @Parameter(title: "Sau (giây)", default: 20)
    var delayS: Int

    func perform() async throws -> some IntentResult {
      let host = RuntimeHost.shared ?? RuntimeHost.bootstrap(options: AlarmIntents.options(), intentFactory: AlarmIntents.factory)
      let req = SystemAlarmRequest(
        id: UUID().uuidString, tripId: "diag-now", kind: .now, generation: 1,
        fireAtWallMs: RuntimeHost.nowWallMs() + Int64(max(1, delayS)) * 1000, title: "NapStop diag", channel: .alarmKit)
      do {
        try await host.alarms.schedule(req)
        host.journal.record("ak", ["op": "schedule", "kind": "diag_now", "ok": "true"])
      } catch {
        host.journal.record("ak", ["op": "schedule", "kind": "diag_now", "ok": "false", "err": String(describing: type(of: error))])
      }
      return .result()
    }
  }

  #if canImport(ActivityKit)
    /// Spike T23.6-B0 (docs/spikes/T23.6.md H3): starts or ends a sample Live Activity (NapStopB0Attributes) from
    /// Shortcuts. A LiveActivityIntent may start an activity while the app is in the background. The journal gets the
    /// outcome or the error type only (event `la`), never any content.
    @available(iOS 17.0, *)
    struct DiagLiveActivityIntent: LiveActivityIntent {
      static var title: LocalizedStringResource = "NapStop: thử Live Activity"

      @Parameter(title: "Bắt đầu (tắt = kết thúc)", default: true)
      var start: Bool

      func perform() async throws -> some IntentResult {
        let host = RuntimeHost.shared ?? RuntimeHost.bootstrap(options: AlarmIntents.options(), intentFactory: AlarmIntents.factory)
        if start {
          guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            host.journal.record("la", ["op": "start", "kind": "diag_b0", "ok": "false", "err": "disabled"])
            return .result()
          }
          do {
            let content = ActivityContent(
              state: NapStopB0Attributes.ContentState(label: "Live Activity B0"),
              staleDate: Date().addingTimeInterval(900))
            _ = try Activity.request(
              attributes: NapStopB0Attributes(title: "NapStop B0"), content: content, pushType: nil)
            host.journal.record("la", ["op": "start", "kind": "diag_b0", "ok": "true",
                                       "count": "\(Activity<NapStopB0Attributes>.activities.count)"])
          } catch {
            host.journal.record("la", ["op": "start", "kind": "diag_b0", "ok": "false",
                                       "err": String(describing: type(of: error))])
          }
        } else {
          let all = Activity<NapStopB0Attributes>.activities
          for activity in all {
            await activity.end(nil, dismissalPolicy: .immediate)
          }
          host.journal.record("la", ["op": "end", "kind": "diag_b0", "ok": "true", "count": "\(all.count)"])
        }
        return .result()
      }
    }
  #endif

  /// T29.2 §4.2 PM04: a native crash for Crashlytics. Opens the app, then crashes 8 s later so Dart has configured
  /// Firebase in this process (crashes before that are not recorded, RK-T292-5). The message is a literal (FU05).
  @available(iOS 16.0, *)
  struct DiagCrashIntent: AppIntent {
    static var title: LocalizedStringResource = "NapStop: thử crash native"
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
      Task {
        try? await Task.sleep(nanoseconds: 8_000_000_000)
        fatalError("T29.2 native probe")
      }
      return .result()
    }
  }
#endif
