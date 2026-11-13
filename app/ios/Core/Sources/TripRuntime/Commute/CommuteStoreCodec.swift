// JSON files of the commute store (docs/specs/T23.8.md §5.1, §5.11): route.json, state.json, auto_starts.json.
// Pure; the file port (FileCommuteStore, C2) only moves bytes. Every file has {"version": 1, ...}.
import Foundation

public enum CommuteStoreError: Error, Equatable, CustomStringConvertible {
    /// Reading: not JSON or not the expected shape.
    case corrupt
    /// Reading: another file version.
    case version
    /// Writing: the value cannot be encoded (e.g. a non-finite Double). The caller must keep the existing file (review C1 #6).
    case encode

    public var description: String {
        switch self {
        case .corrupt: "commuteStore: corrupt"
        case .version: "commuteStore: version"
        case .encode: "commuteStore: encode"
        }
    }
}

public enum CommuteStoreCodec {
    public static let version = 1

    private struct VersionOnly: Codable { var version: Int }
    private struct RouteFile: Codable { var version: Int; var route: CommuteRoute }
    private struct StateFile: Codable { var version: Int; var state: CommuteState }
    private struct AutoStartsFile: Codable { var version: Int; var records: [AutoStartRecord] }

    public static func encodeRoute(_ r: CommuteRoute) throws(CommuteStoreError) -> Data {
        try encode(RouteFile(version: version, route: r))
    }

    public static func decodeRoute(_ d: Data) throws(CommuteStoreError) -> CommuteRoute {
        try decode(RouteFile.self, d).route
    }

    public static func encodeState(_ s: CommuteState) throws(CommuteStoreError) -> Data {
        try encode(StateFile(version: version, state: s))
    }

    /// Day keys further than `keepDays` from `todayKey` (and malformed ones) are dropped while loading (§5.2).
    public static func decodeState(_ d: Data, todayKey: String,
                                   keepDays: Int = CommuteConstants.default.firedKeepDays) throws(CommuteStoreError)
        -> CommuteState {
        try decode(StateFile.self, d).state.pruned(todayKey: todayKey, keepDays: keepDays)
    }

    public static func encodeAutoStarts(_ r: [AutoStartRecord]) throws(CommuteStoreError) -> Data {
        try encode(AutoStartsFile(version: version, records: r))
    }

    public static func decodeAutoStarts(_ d: Data) throws(CommuteStoreError) -> [AutoStartRecord] {
        try decode(AutoStartsFile.self, d).records
    }

    /// Never returns empty bytes: a failed encoding throws instead of producing a file that would read back as corrupt.
    private static func encode<T: Encodable>(_ v: T) throws(CommuteStoreError) -> Data {
        guard let d = try? LedgerCodec.encode(v), !d.isEmpty else { throw .encode }
        return d
    }

    private static func decode<T: Decodable>(_ t: T.Type, _ d: Data) throws(CommuteStoreError) -> T {
        guard let v = try? JSONDecoder().decode(VersionOnly.self, from: d) else { throw .corrupt }
        if v.version != version { throw .version }
        guard let r = try? JSONDecoder().decode(t, from: d) else { throw .corrupt }
        return r
    }
}
