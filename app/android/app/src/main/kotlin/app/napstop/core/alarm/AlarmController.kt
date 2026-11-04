package app.napstop.core.alarm

import android.app.Activity
import android.content.Context
import android.os.SystemClock
import android.util.Log
import app.napstop.core.trip.host.RuntimeDebugFlags
import app.napstop.core.trip.runtime.FileRuntimeStore
import app.napstop.core.trip.runtime.RingConfig
import java.io.File
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * The [AlarmPort] of the main process (spec T16 §4.3): [AlarmControllerCore] bound to Android — transport (FGS start,
 * broadcasts to `:ring`, backup / pre-alert notifications), the ring book through [CachedRingFacts] (no unbounded disk
 * I/O on the runtime actor, T15 O2) and one watchdog coroutine per ringing trip on [scope] (D6). The sound itself never
 * depends on this process: it plays in `:ring` (RK14), and the auto-stop is a timer there (T15 F4).
 */
class AlarmController(
    context: Context,
    private val scope: CoroutineScope,
    /** The ring is gone for good → runtime.onRingEvent(SILENCED). */
    onRingLost: (tripId: String, atWallMs: Long) -> Unit,
    private val warn: (String) -> Unit = { Log.w(TAG, it) },
) : AlarmPort {
    private val ctx = context.applicationContext
    private val io = Executors.newSingleThreadExecutor { r -> Thread(r, "napstop-ring-book").apply { isDaemon = true } }
    private val store = RingFactsStore(File(ctx.noBackupFilesDir, RingFactsStore.DIR_NAME))
    private val cached = CachedRingFacts(store, io, SystemClock::elapsedRealtime, warn)
    private val ringConfigs = ConcurrentHashMap<String, RingConfig>()
    private val tripStore = FileRuntimeStore(File(ctx.noBackupFilesDir, FileRuntimeStore.DIR_NAME), warn)
    private val watchers = ConcurrentHashMap<String, Job>()
    private val locale: () -> Locale = { ctx.resources.configuration.locales[0] ?: Locale.getDefault() }

    val constants: AlarmConstants = AlarmConstantsHolder.load(ctx)

    private val core =
        AlarmControllerCore(
            transport = AndroidRingTransport(ctx, BackupRingNotifier(ctx) { constants.ringMaxMs }, PreAlertNotifier(ctx, locale)),
            facts = cached,
            clock = AndroidRingClock(ctx),
            ringConfig = ::ringConfig,
            onRingLost = onRingLost,
            onWatch = ::watch,
            c = constants,
            warn = warn,
            locale = locale,
        )

    init {
        AlarmChannels.ensure(ctx)
    }

    override fun ringNow(request: RingRequest) {
        // Debug `ring_fail on` (T15 protocol LM7): the "now" ring cannot start.
        if (RuntimeDebugFlags.ringFail) throw RingStartException("debug ring_fail")
        core.ringNow(request)
    }

    override fun ringFallback(request: RingRequest) = core.ringFallback(request)

    override fun stopRinging(tripId: String, cause: StopCause) = core.stopRinging(tripId, cause)

    override fun preAlert(request: PreAlertRequest) = core.preAlert(request)

    override fun overshoot(tripId: String, pastM: Int) = core.overshoot(tripId, pastM)

    override fun ringFacts(tripId: String): RingFacts = core.ringFacts(tripId)

    override fun clearTrip(tripId: String) {
        core.clearTrip(tripId)
        ringConfigs.remove(tripId)
        watchers.remove(tripId)?.cancel()
    }

    /** RING_EVENT from `:ring`: it has just written the book, so the next read goes to the disk. */
    fun onRingEvent(tripId: String) = cached.invalidate(tripId)

    fun onBackupDeleted(tripId: String) {
        cached.invalidate(tripId)
        core.onBackupDeleted(tripId)
    }

    /** A ring is (probably) on in this process' view: no sound preview over it (§4.7). Memory only. */
    fun ringActive(): Boolean = watchers.values.any { it.isActive }

    /** MainActivity.onStart (§5.11): a live ring → AlarmActivity on top. */
    fun onAppVisible(activity: Activity) {
        scope.launch(Dispatchers.IO) {
            val trips = core.liveRings()
            if (trips.isEmpty()) return@launch
            withContext(Dispatchers.Main) {
                for (t in trips) {
                    try {
                        activity.startActivity(RingIntents.activity(activity, t))
                    } catch (e: Exception) {
                        warn("alarm activity failed (${e.javaClass.simpleName})")
                    }
                }
            }
        }
    }

    /** Debug: waits for queued book writes. */
    fun flush() = cached.flush()

    private fun watch(tripId: String) {
        val cur = watchers[tripId]
        if (cur != null && cur.isActive) return
        val job =
            scope.launch(Dispatchers.IO) {
                try {
                    while (isActive) {
                        delay(constants.watchdogMs)
                        if (!core.watchTick(tripId)) break
                    }
                } finally {
                    watchers.remove(tripId, coroutineContext[Job])
                }
            }
        watchers[tripId] = job
    }

    /** ring_config.properties of the trip, read once per trip off the actor thread (bounded wait). */
    private fun ringConfig(tripId: String): RingConfig? {
        ringConfigs[tripId]?.let { return it }
        return try {
            io.submit<RingConfig?> { tripStore.readRingConfig() }.get(READ_BUDGET_MS, TimeUnit.MILLISECONDS)
                ?.takeIf { it.tripId == tripId }
                ?.also { ringConfigs[tripId] = it }
        } catch (e: Exception) {
            warn("ring config read failed (${e.javaClass.simpleName})")
            null
        }
    }

    private companion object {
        const val TAG = "NapStopAlarm"
        const val READ_BUDGET_MS = 250L
    }
}
