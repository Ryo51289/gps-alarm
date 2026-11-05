// System alarm port (docs/specs/T17.md §4.2): AlarmKit (iOS 26+) or the minimal notification channel (§5.6.6).
import Foundation

public enum SystemAlarmKind: String, Sendable, Codable, Equatable { case now, fallback, guardSlot = "guard" }
public enum AlarmChannelKind: String, Sendable, Codable, Equatable { case alarmKit, notification }
/// other = countdown/paused/unknown.
public enum SystemAlarmState: Sendable, Equatable { case scheduled, alerting, other }

/// One alarm of this app as the system reports it. tripId/kind/generation come from the app's own id registry
/// (AlarmKit `Alarm` carries no metadata) or the notification userInfo.
public struct SystemAlarmInfo: Sendable, Equatable {
    /// UUID string (AlarmKit Alarm.ID / notification identifier).
    public let id: String
    public let tripId: String
    public let kind: SystemAlarmKind
    public let generation: Int64
    public let state: SystemAlarmState
    /// .fixed date (AlarmKit) / trigger date (notification).
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

public struct SystemAlarmRequest: Sendable, CustomStringConvertible {
    public let id: String
    public let tripId: String
    public let kind: SystemAlarmKind
    public let generation: Int64
    public let fireAtWallMs: Int64
    /// Resolved NativeCopy; may contain the destination name: NEVER log.
    public let title: String
    public let channel: AlarmChannelKind

    public init(id: String, tripId: String, kind: SystemAlarmKind, generation: Int64, fireAtWallMs: Int64, title: String,
                channel: AlarmChannelKind) {
        self.id = id
        self.tripId = tripId
        self.kind = kind
        self.generation = generation
        self.fireAtWallMs = fireAtWallMs
        self.title = title
        self.channel = channel
    }

    public var description: String { "SystemAlarmRequest(\(kind.rawValue), gen \(generation), <redacted>)" }
}

public protocol SystemAlarms: Sendable {
    /// Throws on failure (authorization, AlarmError.maximumLimitReached, UNError…). Never prompts (D14).
    func schedule(_ r: SystemAlarmRequest) async throws
    /// Never throws; "already stopped" is fine (D22).
    func cancel(id: String, channel: AlarmChannelKind) async
    /// Alerting alarm; never throws.
    func stop(id: String, channel: AlarmChannelKind) async
    /// All alarms of this app; nil when unreadable. Notification channel: pending → scheduled, delivered → other.
    func list() async -> [SystemAlarmInfo]?
}
