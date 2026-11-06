// System alarm port (docs/specs/T17.md §4.2): AlarmKit (iOS 26+) or the notification channel (T17.3), and the router.
import Foundation

public enum SystemAlarmKind: String, Sendable, Codable, Equatable { case now, fallback, guardSlot = "guard" }
public enum AlarmChannelKind: String, Sendable, Codable, Equatable { case alarmKit, notification }
/// other = countdown/paused/unknown; notification channel (T17.3 D4): delivered and its alerting window is over.
public enum SystemAlarmState: Sendable, Equatable { case scheduled, alerting, other }

/// One alarm of this app as the system reports it. tripId/kind/generation come from the app's own id registry
/// (AlarmKit `Alarm` carries no metadata) or the notification userInfo.
public struct SystemAlarmInfo: Sendable, Equatable {
    /// UUID string (AlarmKit Alarm.ID / logical id of the notification requests "<id>#0…2", T17.3 D1).
    public let id: String
    public let tripId: String
    public let kind: SystemAlarmKind
    public let generation: Int64
    public let state: SystemAlarmState
    /// .fixed date (AlarmKit) / fire time of "#0" (notification).
    public let fireAtWallMs: Int64?
    public let channel: AlarmChannelKind

    public init(id: String, tripId: String, kind: SystemAlarmKind, generation: Int64, state: SystemAlarmState,
                fireAtWallMs: Int64?, channel: AlarmChannelKind) {
        self.id = id
        self.tripId = tripId
        self.kind = kind
        self.generation = generation
        self.state = state
        self.fireAtWallMs = fireAtWallMs
        self.channel = channel
    }
}

/// The one secondary button of an AlarmKit alert (docs/specs/T17.2.md D1, [AK-ALERT]); nil = Stop only (T17).
public enum SecondaryAction: Sendable, Equatable, Codable {
    /// "Báo lại sau {minutes} phút" → NapStopSnoozeIntent.
    case snooze(minutes: Int)
    /// "Xem đường quay lại" → NapStopRouteBackIntent (opens the app, T27 screen 8).
    case routeBack
}

public struct SystemAlarmRequest: Sendable, CustomStringConvertible {
    public let id: String
    public let tripId: String
    public let kind: SystemAlarmKind
    public let generation: Int64
    public let fireAtWallMs: Int64
    /// Resolved NativeCopy; may contain the destination name: NEVER log.
    public let title: String
    public let channel: AlarmChannelKind
    /// T17.2 D1: nil = only the Stop button (T17 behaviour).
    public let secondary: SecondaryAction?
    /// T17.2 D10: bundle file for `AlertSound.named`; nil = `AlertSound.default`.
    public let soundFile: String?

    public init(id: String, tripId: String, kind: SystemAlarmKind, generation: Int64, fireAtWallMs: Int64, title: String,
                channel: AlarmChannelKind, secondary: SecondaryAction? = nil, soundFile: String? = nil) {
        self.id = id
        self.tripId = tripId
        self.kind = kind
        self.generation = generation
        self.fireAtWallMs = fireAtWallMs
        self.title = title
        self.channel = channel
        self.secondary = secondary
        self.soundFile = soundFile
    }

    public var description: String { "SystemAlarmRequest(\(kind.rawValue), gen \(generation), <redacted>)" }
}

/// D6 (T17.3, fixes T17 tester O8): what `list()` read. `alarmKitUnreadable`: the AlarmKit channel exists but its list
/// threw; `items` then holds the other channels only, and decisions about AlarmKit alarms treat the list as unreadable.
public struct SystemAlarmList: Sendable, Equatable {
    public let items: [SystemAlarmInfo]
    public let alarmKitUnreadable: Bool

    public init(items: [SystemAlarmInfo], alarmKitUnreadable: Bool = false) {
        self.items = items
        self.alarmKitUnreadable = alarmKitUnreadable
    }
}

/// `budgetExceeded` (T17.3 D7): the notification channel would pass NOTIF_PENDING_BUDGET pending requests.
public enum AlarmChannelError: Error, Equatable { case notAuthorized, badId, unavailable, budgetExceeded }

public protocol SystemAlarms: Sendable {
    /// Throws on failure (authorization, AlarmError.maximumLimitReached, UNError, AlarmChannelError…). Never prompts (D14).
    func schedule(_ r: SystemAlarmRequest) async throws
    /// Never throws; "already stopped" is fine (D22).
    func cancel(id: String, channel: AlarmChannelKind) async
    /// Alerting alarm; never throws.
    func stop(id: String, channel: AlarmChannelKind) async
    /// All alarms of this app; nil only when nothing could be read (T17.3 D6).
    func list() async -> SystemAlarmList?
}

/// Routes by `request.channel`; `list()` reads both channels independently (T17.3 D6): an AlarmKit read error gives the
/// notification alarms with `alarmKitUnreadable`, never nil for both. nil when the notification channel is unreadable
/// (it has no flag of its own; `NotificationAlarmChannel` always reads).
public final class SystemAlarmsRouter: SystemAlarms, @unchecked Sendable {
    let alarmKit: SystemAlarms?
    let notifications: SystemAlarms

    public init(alarmKit: SystemAlarms?, notifications: SystemAlarms) {
        self.alarmKit = alarmKit
        self.notifications = notifications
    }

    private func pick(_ c: AlarmChannelKind) -> SystemAlarms? { c == .alarmKit ? alarmKit : notifications }

    public func schedule(_ r: SystemAlarmRequest) async throws {
        guard let s = pick(r.channel) else { throw AlarmChannelError.unavailable }
        try await s.schedule(r)
    }

    public func cancel(id: String, channel: AlarmChannelKind) async { await pick(channel)?.cancel(id: id, channel: channel) }
    public func stop(id: String, channel: AlarmChannelKind) async { await pick(channel)?.stop(id: id, channel: channel) }

    public func list() async -> SystemAlarmList? {
        var items: [SystemAlarmInfo] = []
        var akUnreadable = false
        if let ak = alarmKit {
            if let l = await ak.list() {
                items += l.items
                akUnreadable = l.alarmKitUnreadable
            } else {
                akUnreadable = true
            }
        }
        guard let n = await notifications.list() else { return nil }
        items += n.items
        return SystemAlarmList(items: items, alarmKitUnreadable: akUnreadable || n.alarmKitUnreadable)
    }
}
