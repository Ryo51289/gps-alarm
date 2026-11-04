package app.napstop.core.location

import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.location.LocationManager
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import app.napstop.core.trip.host.RuntimeHost
import app.napstop.core.trip.host.TripNotifications
import app.napstop.core.trip.runtime.ForegroundResult
import app.napstop.core.trip.runtime.StartReason
import app.napstop.core.trip.runtime.TrackingController
import app.napstop.core.trip.runtime.TrackingNotice
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Foreground service `location` (spec T15 D2, §5.1, §5.8): only a shell that holds the ongoing notification and keeps
 * the process allowed to receive while-in-use location. The engine lives in the process-wide runtime.
 *
 * - ACTION_START (from [AndroidTrackingController], i.e. from the visible app, ADR-001): `startForeground(LOCATION)`
 *   first thing [A-FGSLAUNCH], then tells the runtime (Started / Failed(class name)).
 * - Sticky restart (`intent == null`, [A-SVC]): loads the trip; goes foreground again if there is a live trip (a
 *   SecurityException leaves the runtime HEADLESS), otherwise stops.
 * - Destroyed without the runtime asking (system / OEM): the runtime goes HEADLESS.
 * While foreground it listens to battery, location settings and clock changes (§5.12, §5.3).
 */
class LocationService : Service() {
    private val receiver =
        object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val runtime = RuntimeHost.get(context).runtime
                when (intent.action) {
                    Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED -> runtime.onTimeChanged()
                    else -> runtime.onDeviceStateChanged()
                }
            }
        }
    private var receiverRegistered = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val host = RuntimeHost.get(this)
        when (intent?.action) {
            ACTION_START -> {
                val tripId = intent.getStringExtra(EXTRA_TRIP_ID)
                if (tripId == null) {
                    stopSelf()
                    return START_NOT_STICKY
                }
                goForeground(tripId)
            }
            null ->
                host.scope.launch {
                    host.runtime.ensureLoaded()
                    val tripId = host.runtime.liveTrip()
                    withContext(Dispatchers.Main) { if (tripId == null) stopSelf() else goForeground(tripId) }
                }
            else -> Unit
        }
        return START_STICKY
    }

    private fun goForeground(tripId: String) {
        val host = RuntimeHost.get(this)
        try {
            val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION else 0
            ServiceCompat.startForeground(this, TripNotifications.ID_TRACKING, host.notifications.tracking(null), type)
            isForegroundNow = true
            stopRequested = false
            registerStateReceivers()
            host.runtime.onForegroundResult(tripId, ForegroundResult.Started)
        } catch (e: Exception) {
            // SecurityException (no location permission / background start), ForegroundServiceStartNotAllowedException.
            Log.w(TAG, "startForeground failed (${e.javaClass.simpleName})")
            host.runtime.onForegroundResult(tripId, ForegroundResult.Failed(e.javaClass.simpleName))
            stopSelf()
        }
    }

    private fun registerStateReceivers() {
        if (receiverRegistered) return
        val filter =
            IntentFilter().apply {
                addAction(Intent.ACTION_BATTERY_CHANGED)
                addAction(LocationManager.PROVIDERS_CHANGED_ACTION)
                addAction(Intent.ACTION_TIME_CHANGED)
                addAction(Intent.ACTION_TIMEZONE_CHANGED)
            }
        ContextCompat.registerReceiver(this, receiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED)
        receiverRegistered = true
    }

    override fun onDestroy() {
        if (receiverRegistered) {
            try {
                unregisterReceiver(receiver)
            } catch (e: Exception) {
                Log.w(TAG, "unregister failed (${e.javaClass.simpleName})")
            }
            receiverRegistered = false
        }
        val wasForeground = isForegroundNow
        isForegroundNow = false
        if (wasForeground && !stopRequested) RuntimeHost.get(this).runtime.onForegroundLost()
        stopRequested = false
        super.onDestroy()
    }

    companion object {
        private const val TAG = "NapStopRuntime"
        const val ACTION_START = "app.napstop.action.START_TRACKING"
        const val EXTRA_TRIP_ID = "tripId"

        @Volatile
        internal var isForegroundNow = false

        @Volatile
        internal var stopRequested = false
    }
}

/** [TrackingController] on [LocationService]. start() is only reached from the visible app (TripRuntime, D9). */
class AndroidTrackingController(context: Context, private val notifications: TripNotifications) : TrackingController {
    private val ctx = context.applicationContext

    override fun start(tripId: String, reason: StartReason) {
        val i = Intent(ctx, LocationService::class.java).setAction(LocationService.ACTION_START).putExtra(LocationService.EXTRA_TRIP_ID, tripId)
        ContextCompat.startForegroundService(ctx, i)
    }

    override fun updateTrackingNotification(content: TrackingNotice) {
        if (LocationService.isForegroundNow) notifications.updateTracking(content)
    }

    override fun stop() {
        LocationService.stopRequested = true
        ctx.stopService(Intent(ctx, LocationService::class.java))
    }

    override val isForeground: Boolean get() = LocationService.isForegroundNow
}
