package app.napstop.core.bridge

import android.app.Activity
import android.content.Context
import android.os.Build
import android.util.Log
import app.napstop.core.alarm.AppLocale
import app.napstop.core.alarm.LaunchActions
import app.napstop.core.alarm.SoundPreviewPlayer
import app.napstop.core.bridge.permission.ActivityPermissionPrompter
import app.napstop.core.bridge.permission.AndroidPermissionSources
import app.napstop.core.bridge.permission.BackgroundCheckScheduler
import app.napstop.core.bridge.permission.PermissionHostApiImpl
import app.napstop.core.bridge.permission.SettingsLauncher
import app.napstop.core.bridge.permission.SharedPrefsPermissionFlags
import app.napstop.core.trip.host.RuntimeHost
import app.napstop.core.trip.runtime.TripRuntime
import io.flutter.plugin.common.BinaryMessenger
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

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

    /** Process-wide backend: the real trip runtime, for real and simulated trips (T18 D13). */
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
                readDistances = LastKnownDistance(appContext)::distances,
                backgroundChecks = BackgroundCheckScheduler(appContext),
                warn = { Log.w(TAG, it) },
            )
        // T16 §4.7: real sound preview; never over a ring that is on. T27 §9: launch action slot and the native alarm
        // screen; the activity is reached through the prompter, which forgets it on unregister.
        val host = RuntimeHost.get(appContext)
        // T28: read the language file once off the main thread, before the first notification needs it.
        host.scope.launch(Dispatchers.IO) { AppLocale.tag(appContext) }
        val alarmApi =
            AlarmHostApiImpl(
                SoundPreviewPlayer.get(appContext),
                ringActive = host.alarm::ringActive,
                setLocale = { tag -> AppLocale.set(appContext, tag) },
                consumeLaunch = LaunchActions::consume,
                showAlarm = { tripId -> prompter.activity?.let { host.alarm.showAlarmScreen(it, tripId) } ?: false },
            )
        return register(messenger, backend(appContext), permissionApi = permissionApi, prompter = prompter, alarmApi = alarmApi)
    }

    /**
     * [register] with an explicit backend and sources (JVM tests). [permissionApi] null =
     * [PermissionHostApiStub] built from [distances] and [deviceStatus].
     * [deviceStatus] stays the last parameter so existing tests can pass it as a trailing lambda.
     */
    internal fun register(
        messenger: BinaryMessenger,
        backend: TripBackend,
        distances: suspend (List<Double>, Long) -> List<Double>? = { _, _ -> null },
        permissionApi: PermissionHostApi? = null,
        prompter: ActivityPermissionPrompter? = null,
        alarmApi: AlarmHostApi? = null,
        deviceStatus: () -> DeviceStatusMsg = { PermissionHostApiStub.UNKNOWN_DEVICE_STATUS },
    ): Registration {
        TripHostApi.setUp(messenger, TripHostApiImpl(backend))
        PermissionHostApi.setUp(messenger, permissionApi ?: PermissionHostApiStub(deviceStatus, distances))
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
        // T15: the real trip runtime; loading the snapshot starts as soon as the app opens (spec §5.8).
        val host = RuntimeHost.get(appContext)
        host.scope.launch { host.runtime.ensureLoaded() }
        // T18 D13: the T14 stub is gone; its files of an older install are removed once (best effort).
        host.scope.launch(Dispatchers.IO) { deleteStubLeftovers(appContext.noBackupFilesDir) }
        return createBackend(host.runtime) { Log.w(TAG, it) }
    }

    /** The backend on [runtime] (JVM tests pass a runtime on fakes, SM31). */
    internal fun createBackend(runtime: TripRuntime, warn: (String) -> Unit): TripBackend = RealTripBackend(runtime, ListenerHub(warn))

    /** Directory of the T14 stub backend (removed in T18) under noBackupFilesDir. */
    internal const val STUB_LEFTOVER_DIR = "napstop_stub"

    /** Deletes what the T14/T15 stub backend left in [noBackupDir]; true when nothing is left. Never throws. */
    internal fun deleteStubLeftovers(noBackupDir: File): Boolean =
        try {
            val dir = File(noBackupDir, STUB_LEFTOVER_DIR)
            !dir.exists() || dir.deleteRecursively()
        } catch (e: Exception) {
            false
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
