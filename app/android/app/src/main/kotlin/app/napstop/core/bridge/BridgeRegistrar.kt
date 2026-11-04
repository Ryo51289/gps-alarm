package app.napstop.core.bridge

import android.app.Activity
import android.content.Context
import android.os.Build
import android.util.Log
import app.napstop.core.alarm.SoundPreviewPlayer
import app.napstop.core.bridge.permission.ActivityPermissionPrompter
import app.napstop.core.bridge.permission.AndroidPermissionSources
import app.napstop.core.bridge.permission.BackgroundCheckScheduler
import app.napstop.core.bridge.permission.PermissionHostApiImpl
import app.napstop.core.bridge.permission.SettingsLauncher
import app.napstop.core.bridge.permission.SharedPrefsPermissionFlags
import app.napstop.core.bridge.stub.StubStore
import app.napstop.core.bridge.stub.StubTripBackend
import app.napstop.core.trip.host.RuntimeHost
import io.flutter.plugin.common.BinaryMessenger
import java.io.File
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.plus

/**
 * Attaches the Pigeon APIs to a Flutter engine and detaches them when the engine is
 * cleaned up (spec T14 §2, §5.1). The trip backend lives per process, not per activity,
 * so a trip survives the activity/engine being destroyed. Each registration removes only
 * its own listener, so destroying one engine never silences another (review T14 M1).
 */
object BridgeRegistrar {
    private const val TAG = "NapStopBridge"

    @Volatile
    private var tripBackend: TripBackend? = null

    /** Process-wide backend (T15: CompositeTripBackend = real runtime + the T14 stub for "stub/" simulations). */
    fun backend(context: Context): TripBackend =
        tripBackend ?: synchronized(this) {
            tripBackend ?: createBackend(context.applicationContext).also { tripBackend = it }
        }

    /**
     * Production (T21 D1): the real PermissionHostApi bound to [activity] (permission dialogs,
     * rationale, settings pages). Everything that outlives the activity uses the
     * application context, so the backend never holds the activity.
     */
    fun register(messenger: BinaryMessenger, activity: Activity): Registration {
        val appContext = activity.applicationContext
        val prompter = ActivityPermissionPrompter(activity)
        val permissionApi =
            PermissionHostApiImpl(
                sources = AndroidPermissionSources(appContext, prompter),
                flags = SharedPrefsPermissionFlags(appContext),
                prompter = prompter,
                settings = SettingsLauncher.android(appContext) { prompter.activity },
                readDeviceInfo = ::readDeviceInfo,
                readDeviceStatus = DeviceStatusReader(appContext)::read,
                readMapsConfig = MapsConfigReader(appContext)::read,
                readDistances = LastKnownDistance(appContext)::distances,
                backgroundChecks = BackgroundCheckScheduler(appContext),
                warn = { Log.w(TAG, it) },
            )
        // T16 §4.7: real sound preview; never over a ring that is on.
        val host = RuntimeHost.get(appContext)
        val alarmApi = AlarmHostApiImpl(SoundPreviewPlayer.get(appContext), ringActive = host.alarm::ringActive)
        return register(messenger, backend(appContext), permissionApi = permissionApi, prompter = prompter, alarmApi = alarmApi)
    }

    /**
     * [register] with an explicit backend and sources (JVM tests). [permissionApi] null =
     * [PermissionHostApiStub] built from [mapsConfig], [distances] and [deviceStatus].
     * [deviceStatus] stays the last parameter so existing tests can pass it as a trailing lambda.
     */
    internal fun register(
        messenger: BinaryMessenger,
        backend: TripBackend,
        mapsConfig: () -> MapsConfigMsg = { MapsConfigMsg() },
        distances: suspend (List<Double>, Long) -> List<Double>? = { _, _ -> null },
        permissionApi: PermissionHostApi? = null,
        prompter: ActivityPermissionPrompter? = null,
        alarmApi: AlarmHostApi? = null,
        deviceStatus: () -> DeviceStatusMsg = { PermissionHostApiStub.UNKNOWN_DEVICE_STATUS },
    ): Registration {
        TripHostApi.setUp(messenger, TripHostApiImpl(backend))
        PermissionHostApi.setUp(messenger, permissionApi ?: PermissionHostApiStub(deviceStatus, mapsConfig, distances))
        AlarmHostApi.setUp(messenger, alarmApi ?: AlarmHostApiImpl(NoSoundPreview, ringActive = { false }))
        val updates = TripUpdatesHandler(backend)
        val eventChannel = TripUpdatesStreamHandler.register(messenger, updates)
        return Registration(messenger, eventChannel, updates, prompter)
    }

    /** Real `deviceInfo()` on Android; [PermissionHostApiStub] uses it too (review T21 #7). */
    internal fun readDeviceInfo(): DeviceInfoMsg =
        DeviceInfoMsg(
            platform = PlatformMsg.ANDROID,
            manufacturer = Build.MANUFACTURER.orEmpty(),
            brand = Build.BRAND.orEmpty(),
            model = Build.MODEL.orEmpty(),
            osVersion = Build.VERSION.RELEASE.orEmpty(),
            androidSdkInt = Build.VERSION.SDK_INT.toLong(),
            iosMajor = null,
        )

    private fun createBackend(appContext: Context): TripBackend {
        val stub =
            StubTripBackend(
                store = StubStore(File(appContext.noBackupFilesDir, StubStore.DIR_NAME)),
                clock = System::currentTimeMillis,
                // Last line of defence (review T14 M3): the backend catches its own failures,
                // but nothing launched here may crash the app. Class name only, never messages.
                scope =
                    MainScope() +
                        CoroutineExceptionHandler { _, e -> Log.e(TAG, "trip backend: ${e.javaClass.simpleName}") },
                io = Dispatchers.IO,
            )
        // T15: the real trip runtime; loading the snapshot starts as soon as the app opens (spec §5.8).
        val host = RuntimeHost.get(appContext)
        host.scope.launch { host.runtime.ensureLoaded() }
        val real = RealTripBackend(host.runtime, ListenerHub { Log.w(TAG, it) })
        return CompositeTripBackend(real, stub)
    }

    class Registration internal constructor(
        private val messenger: BinaryMessenger,
        private val eventChannel: TripUpdatesEventChannel,
        private val updates: TripUpdatesHandler,
        private val prompter: ActivityPermissionPrompter? = null,
    ) {
        fun unregister() {
            TripHostApi.setUp(messenger, null)
            PermissionHostApi.setUp(messenger, null)
            AlarmHostApi.setUp(messenger, null)
            eventChannel.setStreamHandler(null)
            updates.detach()
            // A request() still waiting returns the current status.
            prompter?.detach()
        }

        /** From MainActivity.onRequestPermissionsResult; true when the result was ours. */
        fun onRequestPermissionsResult(requestCode: Int): Boolean =
            prompter?.onRequestPermissionsResult(requestCode) ?: false
    }
}
