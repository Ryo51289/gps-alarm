// Keeps private data out of iCloud / computer backups (docs/specs/T17.1.md §6, D10). `napstop_db/` holds destination
// coordinates (History) and the screen 0 flags; `napstop_trip/` the runtime files (T17). [I-BAK], [I-BAK-GUIDE]:
// the flag is set on the directory, again at every launch (some file operations reset resource values). It is a hint
// to the system, not a guarantee.
#if os(iOS)
import Foundation

public enum BackupExclusion {
    /// For each name: `Library/Application Support/<name>/` is created if missing and marked `isExcludedFromBackup`.
    /// Returns name → success. Never throws: a failure must not block the launch.
    @discardableResult
    public static func excludeAppSupportSubdirectories(_ names: [String]) -> [String: Bool] {
        let fm = FileManager.default
        guard let support = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
                                        create: true) else {
            return Dictionary(names.map { ($0, false) }, uniquingKeysWith: { a, _ in a })
        }
        var result: [String: Bool] = [:]
        for name in names {
            var url = support.appendingPathComponent(name, isDirectory: true)
            do {
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try url.setResourceValues(values)
                result[name] = true
            } catch {
                result[name] = false
            }
        }
        return result
    }
}
#endif
