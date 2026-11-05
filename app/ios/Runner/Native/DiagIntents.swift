#if NAPSTOP_DIAG
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
      let host = RuntimeHost.shared ?? RuntimeHost.bootstrap(options: AlarmIntents.options(), stopIntentFactory: AlarmIntents.factory)
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
      let host = RuntimeHost.shared ?? RuntimeHost.bootstrap(options: AlarmIntents.options(), stopIntentFactory: AlarmIntents.factory)
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
#endif
