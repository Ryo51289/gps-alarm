package app.napstop.core.bridge

import android.content.Context
import android.util.Log
import app.napstop.core.bridge.stub.StubStore
import app.napstop.core.bridge.stub.StubTripBackend
import io.flutter.plugin.common.BinaryMessenger
import java.io.File
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.MainScope
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

    /** Process-wide backend; T15 swaps the implementation here. */
    fun backend(context: Context): TripBackend =
        tripBackend ?: synchronized(this) {
            tripBackend ?: createBackend(context.applicationContext).also { tripBackend = it }
        }

    fun register(messenger: BinaryMessenger, context: Context): Registration {
        val appContext = context.applicationContext
        return register(
            messenger,
            backend(context),
            mapsConfig = MapsConfigReader(appContext)::read,
            distances = LastKnownDistance(appContext)::distances,
            deviceStatus = DeviceStatusReader(appContext)::read,
        )
    }

    /**
     * [register] with an explicit backend and sources (JVM tests). [deviceStatus] stays the
     * last parameter so existing tests can pass it as a trailing lambda.
     */
    internal fun register(
        messenger: BinaryMessenger,
        backend: TripBackend,
        mapsConfig: () -> MapsConfigMsg = { MapsConfigMsg() },
        distances: suspend (List<Double>, Long) -> List<Double>? = { _, _ -> null },
        deviceStatus: () -> DeviceStatusMsg = { PermissionHostApiStub.UNKNOWN_DEVICE_STATUS },
    ): Registration {
        TripHostApi.setUp(messenger, TripHostApiImpl(backend))
        PermissionHostApi.setUp(messenger, PermissionHostApiStub(deviceStatus, mapsConfig, distances))
        AlarmHostApi.setUp(messenger, AlarmHostApiStub())
        val updates = TripUpdatesHandler(backend)
        val eventChannel = TripUpdatesStreamHandler.register(messenger, updates)
        return Registration(messenger, eventChannel, updates)
    }

    private fun createBackend(appContext: Context): TripBackend =
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

    class Registration internal constructor(
        private val messenger: BinaryMessenger,
        private val eventChannel: TripUpdatesEventChannel,
        private val updates: TripUpdatesHandler,
    ) {
        fun unregister() {
            TripHostApi.setUp(messenger, null)
            PermissionHostApi.setUp(messenger, null)
            AlarmHostApi.setUp(messenger, null)
            eventChannel.setStreamHandler(null)
            updates.detach()
        }
    }
}
