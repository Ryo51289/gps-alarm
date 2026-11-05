package app.napstop.core.trip.host

import android.content.Context
import android.util.Log
import app.napstop.BuildConfig
import app.napstop.core.alarm.AlarmController
import app.napstop.core.alarm.AppLocale
import app.napstop.core.location.AndroidDeviceEnv
import app.napstop.core.location.AndroidTimeSource
import app.napstop.core.location.AndroidTrackingController
import app.napstop.core.location.FusedLocationSource
import app.napstop.core.trip.runtime.RingEvent
import app.napstop.core.trip.runtime.RingEventKind
import app.napstop.core.trip.runtime.RuntimeConstants
import app.napstop.core.trip.runtime.RuntimeJournal
import app.napstop.core.trip.runtime.RuntimePorts
import app.napstop.core.trip.runtime.SwitchableLocationSource
import app.napstop.core.trip.runtime.TripRuntime
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Process-wide trip runtime (spec T15 D2): binds the ports of `:core-runtime` to Android. Every entry point (bridge,
 * LocationService, receivers, MainActivity) gets the same [Host]; the runtime loads the snapshot on first use.
 * Logs carry class names, enums and ids only — never coordinates, distances or the destination name.
 */
object RuntimeHost {
    private const val TAG = "NapStopRuntime"

    class Host internal constructor(
        val runtime: TripRuntime,
        val notifications: TripNotifications,
        val alarm: AlarmController,
        val location: SwitchableLocationSource,
        val scope: CoroutineScope,
        val constants: RuntimeConstants,
        val journal: RuntimeJournal,
    )

    @Volatile
    private var host: Host? = null

    fun get(context: Context): Host = host ?: synchronized(this) { host ?: create(context.applicationContext).also { host = it } }

    @OptIn(ExperimentalCoroutinesApi::class)
    private fun create(ctx: Context): Host {
        val warn: (String) -> Unit = { Log.w(TAG, it) }
        val scope =
            CoroutineScope(
                SupervisorJob() + Dispatchers.Default + CoroutineExceptionHandler { _, e -> Log.e(TAG, "runtime: ${e.javaClass.simpleName}") },
            )
        val constants = RuntimeConstants()
        // T28: channels in the app language, created / renamed on IO (no disk read on the main thread here).
        AppLocale.refreshChannels(ctx)
        val notifications = TripNotifications(ctx).also { it.ensureChannels() }
        val location = SwitchableLocationSource(FusedLocationSource(ctx, constants.stepWakelockMs))
        val journal = debugJournal(ctx)
        lateinit var runtime: TripRuntime
        // T16: the real alarm (ring service in process :ring). A ring lost for good → SILENCED to the runtime.
        val alarm =
            AlarmController(ctx, scope, onRingLost = { tripId, at ->
                scope.launch { runtime.onRingEvent(RingEvent(tripId, RingEventKind.SILENCED, at)) }
            })
        runtime =
            TripRuntime(
                ports =
                    RuntimePorts(
                        time = AndroidTimeSource(ctx),
                        location = location,
                        tracking = AndroidTrackingController(ctx, notifications),
                        scheduler = AndroidAlarmScheduler(ctx),
                        alarm = alarm,
                        notifier = notifications,
                        store = AndroidRuntimeStore.create(ctx, warn),
                        visibility = AppVisibilityTracker,
                        env = AndroidDeviceEnv(ctx),
                        journal = journal,
                        // T18: bundled traces (Flutter assets) and the CPU kept awake while a simulation runs.
                        traces = FlutterAssetTraceStore(ctx),
                        keepAwake = WakeLockKeepAwake(ctx),
                    ),
                scope = scope,
                actorDispatcher = Dispatchers.Default.limitedParallelism(1),
                io = Dispatchers.IO,
                main = Dispatchers.Main,
                constants = constants,
                warn = warn,
            )
        return Host(runtime, notifications, alarm, location, scope, constants, journal)
    }

    /** Debug builds: the file journal of src/debug (DebugRuntimeHooks); release: none (no class, no file). */
    private fun debugJournal(ctx: Context): RuntimeJournal {
        if (!BuildConfig.DEBUG) return RuntimeJournal.NoOp
        return try {
            val hooks = Class.forName("app.napstop.core.trip.host.DebugRuntimeHooks")
            hooks.getMethod("journal", Context::class.java).invoke(null, ctx) as RuntimeJournal
        } catch (e: Exception) {
            Log.w(TAG, "debug journal unavailable (${e.javaClass.simpleName})")
            RuntimeJournal.NoOp
        }
    }
}
