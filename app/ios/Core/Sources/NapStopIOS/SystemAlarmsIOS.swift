// System alarm channels (docs/specs/T17.md §4.2, D3, D4, D14, D22; T17.3): AlarmKit (iOS 26+), the notification channel,
// and the diagnostics fake (the router is in TripRuntime since T17.3). AlarmKit's `Alarm` carries no metadata, so
// tripId/kind/generation are kept in the id registry.
#if os(iOS)
import Foundation
import Trip
import TripRuntime
import UserNotifications
#if canImport(AlarmKit)
import ActivityKit
import AlarmKit
import AppIntents
import SwiftUI
#endif

/// The App Intents of one alarm (Runner target, so App Intents metadata is extracted there): the StopIntent, and the
/// intent of the secondary button when `secondary` is set (T17.2 §3.1). Both are `any LiveActivityIntent` on iOS 26+.
public typealias AlarmIntentFactory = @Sendable (_ alarmID: String, _ tripId: String, _ kind: String,
                                                 _ secondary: SecondaryAction?) -> (stop: Any, secondary: Any?)

#if canImport(AlarmKit)
@available(iOS 26.0, *)
public struct NapStopAlarmMetadata: AlarmMetadata {
    public var tripId: String
    public var kind: String
    public var generation: Int64
}

@available(iOS 26.0, *)
public final class AlarmKitSystemAlarms: SystemAlarms, @unchecked Sendable {
    let registry: AlarmRefRegistry
    let intents: AlarmIntentFactory?
    let stopLabel: @Sendable () -> String
    let secondaryLabel: @Sendable (SecondaryAction) -> String

    public init(registry: AlarmRefRegistry, intents: AlarmIntentFactory?, stopLabel: @escaping @Sendable () -> String,
                secondaryLabel: @escaping @Sendable (SecondaryAction) -> String = { _ in "" }) {
        self.registry = registry
        self.intents = intents
        self.stopLabel = stopLabel
        self.secondaryLabel = secondaryLabel
    }

    /// T17.2 §3.1: label (NativeCopy, locale at scheduling time) + SF Symbol; VoiceOver reads the label.
    private func secondaryButton(_ a: SecondaryAction) -> AlarmButton {
        let symbol: String
        switch a {
        case .snooze: symbol = "zzz"
        case .routeBack: symbol = "arrow.uturn.backward"
        }
        return AlarmButton(text: LocalizedStringResource(stringLiteral: secondaryLabel(a)), textColor: .white,
                           systemImageName: symbol)
    }

    private func alert(_ title: String, _ secondary: SecondaryAction?) -> AlarmPresentation.Alert {
        let resource = LocalizedStringResource(stringLiteral: title)
        // [AK-ALERT]: one secondary button; `.custom` runs the app's secondaryIntent (no countdown, PLAN Q3 = A).
        let button = secondary.map(secondaryButton)
        let behavior: AlarmPresentation.Alert.SecondaryButtonBehavior? = button == nil ? nil : .custom
        if #available(iOS 26.1, *) {
            return AlarmPresentation.Alert(title: resource, secondaryButton: button, secondaryButtonBehavior: behavior)
        }
        return AlarmPresentation.Alert(title: resource,
                                       stopButton: AlarmButton(text: LocalizedStringResource(stringLiteral: stopLabel()),
                                                               textColor: .white, systemImageName: "stop.circle"),
                                       secondaryButton: button, secondaryButtonBehavior: behavior)
    }

    public func schedule(_ r: SystemAlarmRequest) async throws {
        // D14: never let AlarmKit prompt (it asks on the first schedule when not determined).
        guard AlarmManager.shared.authorizationState == .authorized else { throw AlarmChannelError.notAuthorized }
        guard let uuid = UUID(uuidString: r.id) else { throw AlarmChannelError.badId }
        let made = intents?(r.id, r.tripId, r.kind.rawValue, r.secondary)
        let stopIntent = made?.stop as? (any LiveActivityIntent)
        let secondaryIntent = made?.secondary as? (any LiveActivityIntent)
        // A button without its intent would do nothing: show it only with one.
        let secondary = secondaryIntent == nil ? nil : r.secondary
        let attributes = AlarmAttributes<NapStopAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert(r.title, secondary)),
            metadata: NapStopAlarmMetadata(tripId: r.tripId, kind: r.kind.rawValue, generation: r.generation),
            tintColor: Color.orange)
        let date = Date(timeIntervalSince1970: Double(r.fireAtWallMs) / 1000)
        // T17.2 D10: bundle file (`.named`, main bundle [I12]); nil = system default sound.
        let sound: AlertConfiguration.AlertSound = r.soundFile.map { .named($0) } ?? .default
        let config: AlarmManager.AlarmConfiguration<NapStopAlarmMetadata> = .alarm(
            schedule: .fixed(date), attributes: attributes, stopIntent: stopIntent, secondaryIntent: secondaryIntent,
            sound: sound)
        registry.beginSchedule(r.id, .init(tripId: r.tripId, kind: r.kind, generation: r.generation, fireAtWallMs: r.fireAtWallMs))
        do {
            _ = try await AlarmManager.shared.schedule(id: uuid, configuration: config)
            registry.endSchedule(r.id, ok: true)
        } catch {
            registry.endSchedule(r.id, ok: false)
            throw error
        }
    }

    public func cancel(id: String, channel: AlarmChannelKind) async {
        guard let uuid = UUID(uuidString: id) else { return }
        try? AlarmManager.shared.cancel(id: uuid)  // "already stopped" (Code=0) is fine (D22)
    }

    public func stop(id: String, channel: AlarmChannelKind) async {
        guard let uuid = UUID(uuidString: id) else { return }
        try? AlarmManager.shared.stop(id: uuid)
    }

    public func list() async -> SystemAlarmList? {
        // T17.3 D6: a read error is reported as unreadable (the router keeps the notification alarms).
        guard let alarms = try? AlarmManager.shared.alarms else { return nil }
        return SystemAlarmList(items: map(alarms))
    }

    public func map(_ alarms: [Alarm]) -> [SystemAlarmInfo] {
        registry.retain(Set(alarms.map { $0.id.uuidString }))
        return alarms.map { a in
            let id = a.id.uuidString
            let ref = registry.get(id)
            var fire: Int64? = ref?.fireAtWallMs
            if case let .fixed(d)? = a.schedule { fire = Int64((d.timeIntervalSince1970 * 1000).rounded(.down)) }
            let state: SystemAlarmState
            switch a.state {
            case .scheduled: state = .scheduled
            case .alerting: state = .alerting
            default: state = .other
            }
            return SystemAlarmInfo(id: id, tripId: ref?.tripId ?? "", kind: ref?.kind ?? .fallback,
                                   generation: ref?.generation ?? 0, state: state, fireAtWallMs: fire, channel: .alarmKit)
        }
    }
}
#endif

/// The notification channel on the device (docs/specs/T17.3.md D1–D3, D7–D10): `NotificationAlarmChannel` (TripRuntime,
/// tested on Linux) over the real UNUserNotificationCenter ([UN-CENTER]). No action buttons, no delegate (T17 §5.10).
public final class NotificationSystemAlarms: SystemAlarms, @unchecked Sendable {
    let channel: NotificationAlarmChannel

    public init(budget: Int = RuntimeConstants.default.notifPendingBudget) {
        channel = NotificationAlarmChannel(center: UNCenterPort(), now: { IOSTime().wallMs() }, budget: budget)
    }

    public func schedule(_ r: SystemAlarmRequest) async throws { try await channel.schedule(r) }
    public func cancel(id: String, channel c: AlarmChannelKind) async { await channel.cancel(id: id, channel: c) }
    public func stop(id: String, channel c: AlarmChannelKind) async { await channel.stop(id: id, channel: c) }
    public func list() async -> SystemAlarmList? { await channel.list() }

    /// NC02: the request of one plan. Sound: the T17.2 bundle file (< 30 s, PCM WAV, main bundle [UN-SOUND]) or the
    /// default sound; `.timeSensitive` ([UN-TS]; without the capability, T40.1, the system treats it as `.active`).
    public static func makeRequest(_ p: NotificationRequestPlan) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = p.title
        content.sound = p.soundFile.map { UNNotificationSound(named: UNNotificationSoundName(rawValue: $0)) } ?? .default
        content.interruptionLevel = .timeSensitive
        content.userInfo = p.userInfo
        let trigger = p.delayS.map { UNTimeIntervalNotificationTrigger(timeInterval: $0, repeats: false) }
        return UNNotificationRequest(identifier: p.id, content: content, trigger: trigger)
    }

    /// String entries of a notification's userInfo (the alarm requests only carry strings).
    static func strings(_ u: [AnyHashable: Any]) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in u {
            if let key = k as? String, let value = v as? String { out[key] = value }
        }
        return out
    }
}

/// [UN-CENTER] `add(_:)`, `removePendingNotificationRequests(withIdentifiers:)`,
/// `removeDeliveredNotifications(withIdentifiers:)`, `pendingNotificationRequests()`, `deliveredNotifications()`.
final class UNCenterPort: NotificationCenterPort, @unchecked Sendable {
    private var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }

    func add(_ request: NotificationRequestPlan) async throws {
        try await center.add(NotificationSystemAlarms.makeRequest(request))
    }

    func removePending(_ ids: [String]) async { center.removePendingNotificationRequests(withIdentifiers: ids) }

    func removeDelivered(_ ids: [String]) async { center.removeDeliveredNotifications(withIdentifiers: ids) }

    func pending() async -> [NotificationRecord] {
        await center.pendingNotificationRequests().map {
            NotificationRecord(id: $0.identifier, userInfo: NotificationSystemAlarms.strings($0.content.userInfo))
        }
    }

    func delivered() async -> [NotificationRecord] {
        await center.deliveredNotifications().map {
            NotificationRecord(id: $0.request.identifier, userInfo: NotificationSystemAlarms.strings($0.request.content.userInfo))
        }
    }
}

/// Diagnostics only (§5.13, IC04 on the Simulator): records commands, turns alarms `alerting` on time and reports them.
public final class FakeSystemAlarmsIOS: SystemAlarms, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: SystemAlarmInfo] = [:]
    var onUpdate: (@Sendable ([SystemAlarmInfo]) -> Void)?

    public init() {}

    private func now() -> Int64 { Int64((Date().timeIntervalSince1970 * 1000).rounded(.down)) }

    private func withItems<T>(_ body: (inout [String: SystemAlarmInfo]) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&items)
    }

    public func schedule(_ r: SystemAlarmRequest) async throws {
        withItems {
            $0[r.id] = SystemAlarmInfo(id: r.id, tripId: r.tripId, kind: r.kind, generation: r.generation, state: .scheduled,
                                       fireAtWallMs: r.fireAtWallMs, channel: r.channel)
        }
        // T17.2 AC04: what the newest request of each kind carried, for the Simulator integration test (shared_preferences
        // reads `flutter.`-prefixed standard defaults). Kind, button and sound file only: no title, no position.
        UserDefaults.standard.set(Self.summary(r), forKey: "flutter.napstop.diag.lastAlarm.\(r.kind.rawValue)")
        let delay = max(0, r.fireAtWallMs - now())
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(Int(delay))) { [weak self] in self?.fire(r.id) }
        report()
    }

    /// "secondary=snooze:1;sound=alarm_horn.wav" ("none" when absent).
    public static func summary(_ r: SystemAlarmRequest) -> String {
        let s: String
        switch r.secondary {
        case let .snooze(m)?: s = "snooze:\(m)"
        case .routeBack?: s = "routeBack"
        case nil: s = "none"
        }
        return "secondary=\(s);sound=\(r.soundFile ?? "none")"
    }

    private func fire(_ id: String) {
        withItems { items in
            if let a = items[id], a.state == .scheduled {
                items[id] = SystemAlarmInfo(id: id, tripId: a.tripId, kind: a.kind, generation: a.generation, state: .alerting,
                                            fireAtWallMs: a.fireAtWallMs, channel: a.channel)
            }
        }
        report()
    }

    private func report() { onUpdate?(withItems { Array($0.values) }) }

    public func cancel(id: String, channel: AlarmChannelKind) async {
        withItems { $0[id] = nil }
        report()
    }

    public func stop(id: String, channel: AlarmChannelKind) async { await cancel(id: id, channel: channel) }

    public func list() async -> SystemAlarmList? { SystemAlarmList(items: withItems { Array($0.values) }) }

    func anyAlerting() -> Bool { withItems { $0.values.contains { $0.state == .alerting } } }
}
#endif
