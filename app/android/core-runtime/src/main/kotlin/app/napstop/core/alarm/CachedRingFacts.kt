package app.napstop.core.alarm

import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

/**
 * The ring book as the main process sees it (TASKS T16 / test report T15 O2: `ringFacts` must not do unbounded disk I/O
 * on the runtime actor). Every disk access runs in order on [io] (one thread). A read younger than [freshMs] is
 * answered from memory; an older one waits at most [readBudgetMs] for the disk and otherwise answers with the last value
 * known (a hung disk never holds the actor). Writes update memory at once (the actor sees its own writes) and are
 * queued; the value the disk ends up with replaces the memory copy. [invalidate] forces the next read to the disk
 * (RING_EVENT: `:ring` just wrote).
 */
class CachedRingFacts(
    private val backing: RingFactsSource,
    private val io: ExecutorService,
    private val nowMs: () -> Long,
    private val warn: (String) -> Unit,
    private val freshMs: Long = 1_000L,
    private val readBudgetMs: Long = 250L,
) : RingFactsSource {
    private class Entry(val record: RingFactsRecord?, val atMs: Long)

    private val cache = ConcurrentHashMap<String, Entry>()

    /** Writes queued per trip: a read that finishes meanwhile must not replace the newer value in memory. */
    private val pending = ConcurrentHashMap<String, Int>()

    private fun pendingOf(tripId: String): Int = pending[tripId] ?: 0

    private val inflight = ConcurrentHashMap<String, Future<RingFactsRecord?>>()

    override fun read(tripId: String): RingFactsRecord? {
        val e = cache[tripId]
        if (e != null && nowMs() - e.atMs in 0..freshMs) return e.record
        // One disk read per trip at a time: on a hung disk the callers share it instead of piling up reads (review T16 #7).
        val f: Future<RingFactsRecord?> =
            inflight.compute(tripId) { _, cur ->
                cur?.takeUnless { it.isDone }
                    ?: io.submit<RingFactsRecord?> {
                        val r = backing.read(tripId)
                        if (pendingOf(tripId) == 0) {
                            cache[tripId] = Entry(r, nowMs())
                            r
                        } else {
                            cache[tripId]?.record
                        }
                    }
            }!!
        return try {
            f.get(readBudgetMs, TimeUnit.MILLISECONDS)
        } catch (t: TimeoutException) {
            warn("ring book read over budget")
            e?.record
        } catch (t: Exception) {
            warn("ring book read failed (${(t.cause ?: t).javaClass.simpleName})")
            e?.record
        }
    }

    override fun update(tripId: String, f: (RingFactsRecord?) -> RingFactsRecord?): RingFactsRecord? {
        val guess = f(cache[tripId]?.record)
        cache[tripId] = Entry(guess, nowMs())
        pending.merge(tripId, 1, Int::plus)
        io.execute {
            try {
                val stored = backing.update(tripId, f)
                if (pendingOf(tripId) <= 1) cache[tripId] = Entry(stored, nowMs())
            } catch (e: Exception) {
                warn("ring book write failed (${e.javaClass.simpleName})")
            } finally {
                pending.compute(tripId) { _, n -> if (n == null || n <= 1) null else n - 1 }
            }
        }
        return guess
    }

    override fun delete(tripId: String) {
        cache[tripId] = Entry(null, nowMs())
        pending.merge(tripId, 1, Int::plus)
        io.execute {
            try {
                backing.delete(tripId)
            } catch (e: Exception) {
                warn("ring book delete failed (${e.javaClass.simpleName})")
            } finally {
                pending.compute(tripId) { _, n -> if (n == null || n <= 1) null else n - 1 }
            }
        }
    }

    override fun listRinging(): List<RingFactsRecord> =
        try {
            io.submit<List<RingFactsRecord>> { backing.listRinging() }.get(readBudgetMs * 4, TimeUnit.MILLISECONDS)
        } catch (e: Exception) {
            warn("ring book list failed (${e.javaClass.simpleName})")
            cache.values.mapNotNull { it.record }.filter { it.ringing }
        }

    fun invalidate(tripId: String) {
        cache.remove(tripId)
    }

    /** Waits until every queued write is on disk (tests, debug). */
    fun flush(timeoutMs: Long = 2_000L) {
        try {
            io.submit {}.get(timeoutMs, TimeUnit.MILLISECONDS)
        } catch (e: Exception) {
            warn("ring book flush failed (${e.javaClass.simpleName})")
        }
    }
}
