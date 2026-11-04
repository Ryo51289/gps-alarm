package app.napstop.core.trip.runtime

/**
 * Who set a fallback slot (designer "sau test" §5): ENGINE = FallbackAlarmChanged; GUARD = ring guard armed before every
 * "now" ring (G1); SAFETY = set from the ledger after a reboot while the snapshot is not readable yet (B2).
 */
enum class SlotKind { ENGINE, GUARD, SAFETY }

/** One OS fallback alarm (spec T15 §5.6). [targetAtMs] is on the trip clock, [targetAtWallMs] what the OS was given. */
data class FallbackSlotRec(
    val slot: Int,
    val generation: Long,
    val targetAtMs: Long,
    val setAtWallMs: Long,
    val kind: SlotKind = SlotKind.ENGINE,
    val targetAtWallMs: Long = targetAtMs,
)

/**
 * A fallback alarm that went off. [firedAtMs] is on the trip clock, null when the receiver ran before the runtime had
 * loaded the trip (no anchor yet); restore then uses [firedAtWallMs] (implementation notes).
 */
data class FiredRec(val generation: Long, val targetAtMs: Long, val firedAtMs: Long?, val firedAtWallMs: Long)

/** fallback_ledger.properties: which slots hold an OS alarm, written synchronously around every change (D7, D8). */
data class FallbackLedger(
    val ledgerVersion: Int,
    val activeTripId: String?,
    val nextGeneration: Long,
    val current: FallbackSlotRec?,
    val stale: FallbackSlotRec?,
    val lastFired: FiredRec?,
    /** Last trips that ended (newest last): a fallback alarm of one of them is stale and is ignored (review T15 #2). */
    val endedTripIds: List<String> = emptyList(),
    /** "Interrupted" already alerted in this HEADLESS period (any process); cleared when the FGS is back / trip ends. */
    val interruptedAlerted: Boolean = false,
) {
    companion object {
        val EMPTY = FallbackLedger(1, null, 1L, null, null, null)
    }
}

/**
 * Two-slot fallback alarm (D7, T10 §4.10 obligation 1): set the other slot first, record it, then cancel the old one.
 * A failed set keeps the old slot. Runs inside the runtime actor; [save] writes the ledger (and never throws).
 */
class FallbackScheduler(private val scheduler: OsAlarmScheduler, private val warn: (String) -> Unit) {
    class Result(val ledger: FallbackLedger, val ok: Boolean)

    suspend fun schedule(
        ledger: FallbackLedger,
        tripId: String,
        targetAtMs: Long,
        triggerWallMs: Long,
        nowWallMs: Long,
        kind: SlotKind = SlotKind.ENGINE,
        save: suspend (FallbackLedger) -> Unit,
    ): Result {
        val old = ledger.current
        val newSlot = if (old?.slot == 0) 1 else 0
        val generation = ledger.nextGeneration
        val exact =
            try {
                scheduler.canScheduleExact()
            } catch (e: Exception) {
                warn("canScheduleExact failed (${e.javaClass.simpleName})")
                false
            }
        try {
            scheduler.setFallback(newSlot, tripId, generation, targetAtMs, triggerWallMs, exact, kind)
        } catch (e: Exception) {
            warn("fallback set failed (${e.javaClass.simpleName})")
            return Result(ledger, false)
        }
        var l =
            ledger.copy(
                nextGeneration = generation + 1,
                current = FallbackSlotRec(newSlot, generation, targetAtMs, nowWallMs, kind, triggerWallMs),
                stale = old,
            )
        save(l)
        if (old != null) {
            try {
                scheduler.cancelFallback(old.slot)
                l = l.copy(stale = null)
                save(l)
            } catch (e: Exception) {
                warn("fallback cancel failed (${e.javaClass.simpleName})")
            }
        }
        // Without the exact-alarm permission the inexact alarm still stands, but ok=false so the UI warns (PRD §3.1).
        return Result(l, exact)
    }

    /** Cancels both slots (idempotent). */
    suspend fun cancelAll(ledger: FallbackLedger, save: suspend (FallbackLedger) -> Unit): FallbackLedger {
        for (slot in 0..1) {
            try {
                scheduler.cancelFallback(slot)
            } catch (e: Exception) {
                warn("fallback cancel failed (${e.javaClass.simpleName})")
            }
        }
        val l = ledger.copy(current = null, stale = null)
        if (l != ledger) save(l)
        return l
    }
}
