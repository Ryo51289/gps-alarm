// Launch action of the iOS route-back button (docs/specs/T17.2.md D7, D8; parity Android `LaunchActions`, T16 §4.5,
// T27 D5). Pure; the waiting loop takes its clock and reads as closures so it runs on Linux.
import Foundation

public enum LaunchActionSlot {
    /// Largest `pastM` kept (1 000 km, as Android `PAST_M_MAX`); anything else becomes "unknown".
    public static let pastMMax = 1_000_000

    /// `[A-Za-z0-9_-]{1,64}` (Android `RingIntents.validTripId`).
    public static func validTripId(_ s: String) -> Bool {
        let u = s.unicodeScalars
        guard !u.isEmpty, u.count <= 64 else { return false }
        return u.allSatisfy { c in
            (c >= "A" && c <= "Z") || (c >= "a" && c <= "z") || (c >= "0" && c <= "9") || c == "_" || c == "-"
        }
    }

    /// D8: the record when it is still usable, else nil. Age = elapsed time when the boot session is the same (and known),
    /// else wall time; usable when 0 ≤ age ≤ `ttlMs`. Unknown kind or bad trip id → nil; `pastM` outside 0…1 000 000 → nil.
    public static func valid(_ r: LaunchActionRec, nowWallMs: Int64, nowElapsedMs: Int64, bootSessionId: String?,
                             ttlMs: Int64) -> LaunchActionRec? {
        guard r.kind == LaunchActionRec.overshootRoute, validTripId(r.tripId) else { return nil }
        let sameBoot = bootSessionId != nil && r.bootSessionId == bootSessionId
        let age = sameBoot ? nowElapsedMs - r.atElapsedMs : nowWallMs - r.atWallMs
        guard age >= 0 && age <= ttlMs else { return nil }
        let past = r.pastM.flatMap { (0...pastMMax).contains($0) ? $0 : nil }
        return LaunchActionRec(kind: r.kind, tripId: r.tripId, pastM: past, atWallMs: r.atWallMs, atElapsedMs: r.atElapsedMs,
                               bootSessionId: r.bootSessionId)
    }
}

public enum LaunchActionWait {
    /// D8 safety net for the order of Flutter `resumed` and `NapStopRouteBackIntent.perform()`: take the action; when there
    /// is none yet and a route-back intent is in flight, poll every `pollMs` up to `waitMs`, plus one last read after the
    /// intent finished. `read` takes (reads + deletes) the action.
    public static func consume(waitMs: Int64, pollMs: Int64, inFlight: @Sendable () -> Bool,
                               read: @Sendable () async -> LaunchActionRec?,
                               sleep: @Sendable (Int64) async -> Void) async -> LaunchActionRec? {
        if let r = await read() { return r }
        var waited: Int64 = 0
        var polled = false
        while inFlight() && waited < waitMs {
            let step = min(pollMs, waitMs - waited)
            await sleep(step)
            waited += step
            polled = true
            if let r = await read() { return r }
        }
        // The intent may have written the file and cleared its flag between the last read and the loop check.
        return polled ? await read() : nil
    }
}
