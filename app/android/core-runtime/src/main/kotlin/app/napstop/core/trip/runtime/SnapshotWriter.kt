package app.napstop.core.trip.runtime

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Best-effort snapshot writer (spec T15 §5.7, D4). One coroutine on [io]: always writes the newest snapshot (older
 * pending ones are dropped), retries after [retryMs] when a write fails, never throws back to the actor. The actor
 * waits for a write only through [persistNow], with a budget; the write itself goes on after the budget ran out.
 * Finishing a trip runs through the same loop, so it can never race a snapshot write of that trip.
 */
class SnapshotWriter(
    private val scope: CoroutineScope,
    private val io: CoroutineDispatcher,
    private val store: RuntimeStore,
    private val retryMs: Long,
    private val nowWallMs: () -> Long,
    private val warn: (String) -> Unit,
    private val journal: (ok: Boolean, ms: Long) -> Unit = { _, _ -> },
) {
    private sealed interface Op

    private class Write(val trip: StoredTrip) : Op

    private class Exclusive(val block: () -> Unit, val done: CompletableDeferred<Throwable?>) : Op

    private val lock = Any()
    private var pending: StoredTrip? = null
    private val waiters = ArrayList<CompletableDeferred<Boolean>>()
    private val exclusives = ArrayList<Exclusive>()
    private val signal = Channel<Unit>(Channel.CONFLATED)

    /** Writes attempted, for tests (L14 "retries ≥ 2"). */
    @Volatile
    var attempts: Int = 0
        private set

    init {
        scope.launch(io) { loop() }
    }

    /** Replaces any pending snapshot; non-blocking. */
    fun submit(t: StoredTrip) {
        synchronized(lock) { pending = t }
        signal.trySend(Unit)
    }

    /** [submit] and wait up to [budgetMs] for this (or a newer) snapshot to be on disk. False on failure or timeout. */
    suspend fun persistNow(t: StoredTrip, budgetMs: Long): Boolean {
        val done = CompletableDeferred<Boolean>()
        synchronized(lock) {
            pending = t
            waiters += done
        }
        signal.trySend(Unit)
        return withTimeoutOrNull(budgetMs) { done.await() } ?: false
    }

    /** Drops the pending snapshot and runs [block] on the writer after any write in progress. Rethrows its failure. */
    suspend fun exclusive(block: () -> Unit) {
        val done = CompletableDeferred<Throwable?>()
        synchronized(lock) {
            pending = null
            exclusives += Exclusive(block, done)
            waiters.forEach { it.complete(false) }
            waiters.clear()
        }
        signal.trySend(Unit)
        done.await()?.let { throw it }
    }

    private fun next(): Pair<Op, List<CompletableDeferred<Boolean>>>? =
        synchronized(lock) {
            exclusives.removeFirstOrNull()?.let { return@synchronized it to emptyList() }
            val t = pending ?: return@synchronized null
            val ws = waiters.toList()
            waiters.clear()
            Write(t) to ws
        }

    private suspend fun loop() {
        for (x in signal) {
            while (true) {
                val (op, ws) = next() ?: break
                when (op) {
                    is Exclusive -> {
                        val err =
                            try {
                                op.block()
                                null
                            } catch (e: Exception) {
                                e
                            }
                        op.done.complete(err)
                    }
                    is Write -> {
                        val started = nowWallMs()
                        attempts++
                        val ok =
                            try {
                                store.writeActive(op.trip)
                                true
                            } catch (e: Exception) {
                                warn("snapshot write failed (${e.javaClass.simpleName})")
                                false
                            }
                        journal(ok, nowWallMs() - started)
                        synchronized(lock) { if (ok && pending === op.trip) pending = null }
                        ws.forEach { it.complete(ok) }
                        // Failed: the same (or a newer) snapshot is retried after retryMs.
                        if (!ok) delay(retryMs)
                    }
                }
            }
        }
    }
}
