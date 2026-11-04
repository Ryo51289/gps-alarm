package app.napstop.core.trip.runtime.sim

import app.napstop.core.trip.runtime.FixSink
import app.napstop.core.trip.runtime.FlpRequestSpec
import app.napstop.core.trip.runtime.LocationSource
import app.napstop.core.trip.runtime.RawFix
import app.napstop.core.trip.runtime.SimTimeline
import app.napstop.core.trip.runtime.TimeSource
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/**
 * Location source of a simulated trip (T18 §4, D4): plays [samples] on the trip clock, sample t at trip time
 * [startTripMs] + t·1000, with the `policy` rule of the harness (fixtures/traces/README.md §6): a sample is delivered
 * when t − last delivered ≥ the requested interval. While no request is on ([stop], HEADLESS) samples are skipped, as
 * if there were no GPS. Each fix carries its trip time ([RawFix.simFixAtMs]) so fixAtMs is exact whatever the
 * delivery delay. After the last sample nothing more comes (the engine sees GPS lost). Coordinates are never logged.
 */
class SimulatedLocationSource(
    private val samples: List<TraceSample>,
    /** Trip clock at commit (D2) = trace t 0. */
    private val startTripMs: Long,
    private val timeline: SimTimeline,
    /** Real time; only for [RawFix.elapsedRealtimeNanos]. */
    private val time: TimeSource,
    private val scope: CoroutineScope,
    private val dispatcher: CoroutineDispatcher,
    private val pollMaxMs: Long,
    private val warn: (String) -> Unit = {},
) : LocationSource {
    private val lock = Any()

    @Volatile
    private var active: Pair<FlpRequestSpec, FixSink>? = null
    private var job: Job? = null
    private var cancelled = false

    /** Stores spec + sink (effective from the next sample); starts the player once. */
    override fun request(spec: FlpRequestSpec, sink: FixSink) {
        synchronized(lock) {
            if (cancelled) return
            active = spec to sink
            if (job == null) job = scope.launch(dispatcher) { play() }
        }
    }

    /** The player keeps the trip time; samples are skipped until the next [request]. */
    override fun stop() {
        synchronized(lock) { active = null }
    }

    override suspend fun lastKnown(): RawFix? = null

    /** The trip ended: nothing is delivered any more. */
    fun cancel() {
        synchronized(lock) {
            cancelled = true
            active = null
            job?.cancel()
        }
    }

    private suspend fun play() {
        var lastT: Int? = null
        for (s in samples) {
            val due = startTripMs + s.t * 1000L
            timeline.awaitTrip(due, pollMaxMs)
            val (spec, sink) = active ?: continue
            val last = lastT
            if (last != null && (s.t - last) * 1000L < spec.intervalMs) continue
            lastT = s.t
            try {
                sink.onFix(RawFix(s.lat, s.lng, s.accM, s.spdMps, time.elapsedNanos(), simFixAtMs = due)) { }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                warn("sim fix delivery failed (${e.javaClass.simpleName})")
            }
        }
    }
}
