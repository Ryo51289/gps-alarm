package app.napstop.core.trip.runtime

import app.napstop.core.alarm.RingFacts
import app.napstop.core.trip.EngineState
import app.napstop.core.trip.FallbackRestoreStatus
import app.napstop.core.trip.RestoreInfo

enum class RestoreCause { PROCESS_START, BOOT, PACKAGE_REPLACED }

/** RestoreInfo of the fallback alarm while the process was gone (spec T15 §5.8, T10 §7.2). Pure. */
object RestorePlanner {
    /**
     * [toTrip] maps a wall time to the trip clock of the restored process. A [FiredRec] written before the runtime had
     * loaded the trip has no trip time yet; its wall time is used instead.
     */
    fun plan(
        s: EngineState,
        ledger: FallbackLedger,
        facts: RingFacts,
        cause: RestoreCause,
        nowTripMs: Long,
        toTrip: (Long) -> Long,
    ): RestoreInfo {
        val fb = s.fallback.targetAtMs
        val fired = ledger.lastFired
        val firedAt = fired?.let { it.firedAtMs ?: toTrip(it.firedAtWallMs) }
        val pendingDismiss = facts.pendingDismissAtWallMs
        if (pendingDismiss != null) {
            val ringStart = fired?.firedAtWallMs ?: facts.ringStartedAtWallMs
            return RestoreInfo(
                FallbackRestoreStatus.DISMISSED,
                firedAtMs = firedAt ?: ringStart?.let(toTrip),
                dismissedAtMs = toTrip(pendingDismiss),
            )
        }
        if (fb != null && firedAt != null && firedAt > s.nowMs) return RestoreInfo(FallbackRestoreStatus.RANG, firedAtMs = firedAt)
        // A reboot clears every alarm [A-AM]; after an app update it is not certain they are still there.
        if (cause == RestoreCause.BOOT || cause == RestoreCause.PACKAGE_REPLACED) return RestoreInfo(FallbackRestoreStatus.MISSING)
        // Due without a trace that it rang (force-stop, OEM).
        if (fb != null && fb <= nowTripMs) return RestoreInfo(FallbackRestoreStatus.MISSING)
        return RestoreInfo(FallbackRestoreStatus.PENDING)
    }
}
