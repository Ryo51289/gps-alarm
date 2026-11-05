// Which secondary button an AlarmKit alarm gets (docs/specs/T17.2.md D1, D3). Pure.
import Trip

public enum SecondaryActionPlanner {
    /// Minutes shown on the snooze button for `snoozeS` (whole minutes, at least 1). The engine allows 30…600 s; non-whole
    /// minutes only come from engine overrides (dev), they round to the nearest minute.
    public static func snoozeMinutes(_ snoozeS: Int) -> Int { max(1, (snoozeS + 30) / 60) }

    /// D1. `kind`:
    /// - `.now`: reason OVERSHOOT → route back; else snooze when the engine allows it (`snoozeAllowed`) and the switch is on.
    /// - `.guardSlot` with the reason of the ring it guards (`reason != nil`): the same button as that "now" alarm.
    /// - `.fallback`, or a guard without a known ring: snooze when `snoozeCount < maxSnoozes` at scheduling time and the
    ///   switch is on (a fallback that rings = the engine will allow a snooze by the same rule, T15 §5.6).
    /// `constants.snoozeButtonEnabled == false` (Q3 → C) never gives `.snooze`.
    public static func action(kind: SystemAlarmKind, reason: AlarmReason?, snoozeAllowed: Bool, snoozeCount: Int,
                              maxSnoozes: Int, snoozeMinutes: Int, constants: RuntimeConstants) -> SecondaryAction? {
        let snooze = SecondaryAction.snooze(minutes: max(1, snoozeMinutes))
        switch kind {
        case .now, .guardSlot:
            if let r = reason {
                if r == .overshoot { return .routeBack }
                return snoozeAllowed && constants.snoozeButtonEnabled ? snooze : nil
            }
            if kind == .now { return nil }
            return snoozeCount < maxSnoozes && constants.snoozeButtonEnabled ? snooze : nil
        case .fallback:
            return snoozeCount < maxSnoozes && constants.snoozeButtonEnabled ? snooze : nil
        }
    }
}
