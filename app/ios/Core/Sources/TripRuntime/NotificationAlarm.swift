// Notification alarm channel (docs/specs/T17.3.md): used when AlarmKit is not available (iOS 16–25) or not authorized.
// One logical alarm = 3 notification requests 30 s apart (D1), a pure "alerting" window (D4, fixes T17 tester O7), a
// pending budget below the system limit of 64 requests (D7), and the channel itself over a small port of
// UNUserNotificationCenter that NapStopIOS adapts (so schedule/cancel/list are tested on Linux). Foundation only.
import Foundation

/// One `UNNotificationRequest` as planned (NapStopIOS builds the request from it, NC02).
public struct NotificationRequestPlan: Sendable, Equatable, CustomStringConvertible {
    /// "<logical id>#<rep>".
    public let id: String
    public let rep: Int
    /// Resolved NativeCopy; may contain the destination name: NEVER log.
    public let title: String
    /// T17.2 D10 bundle file (`UNNotificationSound(named:)`); nil = `UNNotificationSound.default`.
    public let soundFile: String?
    /// nil = `trigger: nil` (delivered at once); else `UNTimeIntervalNotificationTrigger(timeInterval:, repeats: false)`, ≥ 1 s.
    public let delayS: Double?
    /// tripId, kind, generation, fireAtWallMs (of `#0`), rep. Ids and times only (no coordinates, no destination name).
    public let userInfo: [String: String]

    public init(id: String, rep: Int, title: String, soundFile: String?, delayS: Double?, userInfo: [String: String]) {
        self.id = id
        self.rep = rep
        self.title = title
        self.soundFile = soundFile
        self.delayS = delayS
        self.userInfo = userInfo
    }

    public var description: String { "NotificationRequestPlan(\(id), <redacted>)" }
}

/// A pending or delivered notification of this app as the center reports it (identifier + string userInfo).
public struct NotificationRecord: Sendable, Equatable {
    public let id: String
    public let userInfo: [String: String]

    public init(id: String, userInfo: [String: String]) {
        self.id = id
        self.userInfo = userInfo
    }
}

public enum NotificationAlarmPlan {
    /// S3 `TS_REPEAT`.
    public static let repeats = 3
    /// S3 `TS_REPEAT_INTERVAL_S`.
    public static let repeatIntervalMs: Int64 = 30_000
    /// D4: 2·30 s + 30 s (the sound of each request is < 30 s, T17.2 D10).
    public static let alertWindowMs: Int64 = 90_000
    /// D5: a poll runs this long after each ring time and after the window.
    public static let pollLagMs: Int64 = 1_000

    /// Fire times (wall ms) of the requests of one logical alarm.
    public static func fireTimes(_ fireAtWallMs: Int64) -> [Int64] {
        (0..<repeats).map { fireAtWallMs + Int64($0) * repeatIntervalMs }
    }

    public static func requestId(_ logicalId: String, rep: Int) -> String { "\(logicalId)#\(rep)" }

    public static func requestIds(_ logicalId: String) -> [String] { (0..<repeats).map { requestId(logicalId, rep: $0) } }

    /// nil when `requestId` is not "<id>#<rep>" with rep in 0..<repeats (trip notices, other apps' ids).
    public static func parse(_ requestId: String) -> (logicalId: String, rep: Int)? {
        guard let i = requestId.lastIndex(of: "#") else { return nil }
        let logical = String(requestId[..<i])
        let digits = requestId[requestId.index(after: i)...]
        guard !logical.isEmpty, !digits.isEmpty, digits.allSatisfy({ $0 >= "0" && $0 <= "9" }), let rep = Int(digits),
              rep < repeats else { return nil }
        return (logical, rep)
    }

    /// D5: when the runtime reads `list()` for one logical alarm (each ring + 1 s, end of the window + 1 s).
    public static func pollTimes(_ fireAtWallMs: Int64) -> [Int64] {
        fireTimes(fireAtWallMs).map { $0 + pollLagMs } + [fireAtWallMs + alertWindowMs + pollLagMs]
    }

    /// D1, D2, D10: the requests of `r` planned at `nowWallMs`. `#0` of a "now" alarm is delivered at once; every other
    /// request has a time-interval trigger of max(1 s, its fire time − now).
    public static func requests(_ r: SystemAlarmRequest, nowWallMs: Int64) -> [NotificationRequestPlan] {
        fireTimes(r.fireAtWallMs).enumerated().map { rep, fire in
            let delay: Double? = rep == 0 && r.kind == .now ? nil : max(1, Double(fire - nowWallMs) / 1000)
            return NotificationRequestPlan(
                id: requestId(r.id, rep: rep), rep: rep, title: r.title, soundFile: r.soundFile, delayS: delay,
                userInfo: ["tripId": r.tripId, "kind": r.kind.rawValue, "generation": String(r.generation),
                           "fireAtWallMs": String(r.fireAtWallMs), "rep": String(rep)])
        }
    }
}

public enum NotificationAlarmState {
    /// D4 (spec §2 table). `pendingReps`/`deliveredReps`: reps (0…2) of one logical alarm in pendingNotificationRequests /
    /// deliveredNotifications. `scheduled` while nothing was delivered yet; `alerting` once something was delivered and
    /// `nowWallMs < fireAtWallMs + ALERT_WINDOW_MS`; `other` afterwards (or when the user removed everything; the caller
    /// never lists an alarm without any request).
    ///
    /// "Delivered" also counts a `#0` that is no longer pending although `#1`/`#2` still are: it was delivered and the user
    /// removed it from Notification Center (a cancel removes every rep). The alarm keeps ringing with the next reps, so it
    /// stays `alerting` instead of going back to `scheduled`.
    public static func state(fireAtWallMs: Int64, pendingReps: Set<Int>, deliveredReps: Set<Int>,
                             nowWallMs: Int64) -> SystemAlarmState {
        let started = !deliveredReps.isEmpty || (!pendingReps.isEmpty && !pendingReps.contains(0))
        if !started { return pendingReps.isEmpty ? .other : .scheduled }
        if nowWallMs < fireAtWallMs + NotificationAlarmPlan.alertWindowMs { return .alerting }
        return .other
    }
}

public enum NotificationAlarmList {
    /// Logical alarms of `pending` + `delivered` (records that are not alarm requests are ignored), ordered by fire time
    /// then id. tripId/kind/generation/fireAtWallMs come from the lowest rep present.
    public static func infos(pending: [NotificationRecord], delivered: [NotificationRecord],
                             nowWallMs: Int64) -> [SystemAlarmInfo] {
        struct Group {
            var pending = Set<Int>()
            var delivered = Set<Int>()
            var meta: (rep: Int, info: [String: String])?
        }
        var groups: [String: Group] = [:]
        func add(_ r: NotificationRecord, delivered isDelivered: Bool) {
            guard let p = NotificationAlarmPlan.parse(r.id) else { return }
            var g = groups[p.logicalId] ?? Group()
            if isDelivered { g.delivered.insert(p.rep) } else { g.pending.insert(p.rep) }
            if g.meta == nil || p.rep < g.meta!.rep { g.meta = (p.rep, r.userInfo) }
            groups[p.logicalId] = g
        }
        for r in pending { add(r, delivered: false) }
        for r in delivered { add(r, delivered: true) }
        var out: [SystemAlarmInfo] = []
        for (id, g) in groups {
            guard let u = g.meta?.info, let trip = u["tripId"], let kind = u["kind"].flatMap(SystemAlarmKind.init(rawValue:)),
                  let fire = u["fireAtWallMs"].flatMap({ Int64($0) }) else { continue }
            let state = NotificationAlarmState.state(fireAtWallMs: fire, pendingReps: g.pending, deliveredReps: g.delivered,
                                                     nowWallMs: nowWallMs)
            out.append(SystemAlarmInfo(id: id, tripId: trip, kind: kind, generation: u["generation"].flatMap { Int64($0) } ?? 0,
                                       state: state, fireAtWallMs: fire, channel: .notification))
        }
        return out.sorted { ($0.fireAtWallMs ?? 0, $0.id) < ($1.fireAtWallMs ?? 0, $1.id) }
    }
}

public enum NotificationBudget {
    /// D7: adding `adding` requests keeps the app's pending requests within `budget` (NOTIF_PENDING_BUDGET).
    public static func fits(pendingCount: Int, adding: Int, budget: Int) -> Bool { pendingCount + adding <= budget }
}

/// What the channel needs from UNUserNotificationCenter ([UN-CENTER]); NapStopIOS adapts the real center, tests fake it.
public protocol NotificationCenterPort: Sendable {
    func add(_ request: NotificationRequestPlan) async throws
    func removePending(_ ids: [String]) async
    func removeDelivered(_ ids: [String]) async
    /// Every pending request of the app.
    func pending() async -> [NotificationRecord]
    /// Every delivered notification of the app still in Notification Center.
    func delivered() async -> [NotificationRecord]
}

/// The notification channel (spec §3): `schedule` adds the 3 requests of one logical alarm or none, `cancel`/`stop` remove
/// every request of it (pending and delivered: a playing sound cannot be stopped, D9), `list` maps them with
/// `NotificationAlarmState`. Never prompts for authorization.
public final class NotificationAlarmChannel: SystemAlarms, @unchecked Sendable {
    let center: NotificationCenterPort
    let now: @Sendable () -> Int64
    let budget: Int

    public init(center: NotificationCenterPort, now: @escaping @Sendable () -> Int64,
                budget: Int = RuntimeConstants.default.notifPendingBudget) {
        self.center = center
        self.now = now
        self.budget = budget
    }

    public func schedule(_ r: SystemAlarmRequest) async throws {
        let plans = NotificationAlarmPlan.requests(r, nowWallMs: now())
        // A request with an identifier already pending replaces it: those do not count twice.
        let others = await center.pending().filter { NotificationAlarmPlan.parse($0.id)?.logicalId != r.id }
        guard NotificationBudget.fits(pendingCount: others.count, adding: plans.count, budget: budget) else {
            throw AlarmChannelError.budgetExceeded
        }
        do {
            for p in plans { try await center.add(p) }
        } catch {
            // Never leave half a logical alarm (spec §3).
            await removeAll(r.id)
            throw error
        }
    }

    private func removeAll(_ id: String) async {
        let ids = NotificationAlarmPlan.requestIds(id)
        await center.removePending(ids)
        await center.removeDelivered(ids)
    }

    public func cancel(id: String, channel: AlarmChannelKind) async { await removeAll(id) }

    public func stop(id: String, channel: AlarmChannelKind) async { await removeAll(id) }

    public func list() async -> SystemAlarmList? {
        let pending = await center.pending()
        let delivered = await center.delivered()
        return SystemAlarmList(items: NotificationAlarmList.infos(pending: pending, delivered: delivered, nowWallMs: now()))
    }
}
