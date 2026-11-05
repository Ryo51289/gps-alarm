// Alarm sound catalogue of iOS (docs/specs/T17.2.md D10), port of Android `AlarmSounds` (T16, PO Q3 = A). Pure.
public enum AlarmSoundCatalog {
    /// Ids the settings screen offers (T28), display order; `default` is the stored default and means `horn`.
    public static let catalog = ["horn", "bell", "beep", "system"]

    /// `default`, empty, nil or unknown → `horn`; `system` stays `system` (Android `AlarmSounds.resolve`).
    public static func resolve(_ id: String?) -> String {
        guard let id, catalog.contains(id) else { return "horn" }
        return id
    }

    /// File in the Runner bundle (`Runner/Sounds/`, 28–29.5 s WAV PCM) for a sound id (resolved first); `system` → nil
    /// (`AlertSound.default`).
    public static func fileName(_ id: String) -> String? {
        let r = resolve(id)
        return r == "system" ? nil : "alarm_\(r).wav"
    }

    /// Bundle files, for tests and the generator script.
    public static let files = ["alarm_horn.wav", "alarm_bell.wav", "alarm_beep.wav"]
}
