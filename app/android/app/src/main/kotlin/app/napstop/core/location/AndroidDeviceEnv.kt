package app.napstop.core.location

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.LocationManager
import android.os.BatteryManager
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import androidx.core.content.ContextCompat
import app.napstop.core.trip.runtime.BatteryReading
import app.napstop.core.trip.runtime.DeviceEnv
import app.napstop.core.trip.runtime.LocationAccess
import app.napstop.core.trip.runtime.TimeSource
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability

/** Permissions, location settings, Play services and the sticky battery broadcast (spec T15 §5.12). */
class AndroidDeviceEnv(context: Context) : DeviceEnv {
    private val ctx = context.applicationContext

    override fun locationAccess(): LocationAccess =
        LocationAccess(
            fineGranted = granted(Manifest.permission.ACCESS_FINE_LOCATION),
            coarseGranted = granted(Manifest.permission.ACCESS_COARSE_LOCATION),
            servicesEnabled = servicesEnabled(),
            playServicesAvailable =
                try {
                    GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(ctx) == ConnectionResult.SUCCESS
                } catch (e: Exception) {
                    false
                },
        )

    /** Level = EXTRA_LEVEL * 100 / EXTRA_SCALE rounded down; charging = CHARGING or FULL [A-BAT]. */
    override fun battery(): BatteryReading? {
        val i: Intent =
            ContextCompat.registerReceiver(ctx, null, IntentFilter(Intent.ACTION_BATTERY_CHANGED), ContextCompat.RECEIVER_NOT_EXPORTED)
                ?: return null
        return reading(
            i.getIntExtra(BatteryManager.EXTRA_LEVEL, -1),
            i.getIntExtra(BatteryManager.EXTRA_SCALE, -1),
            i.getIntExtra(BatteryManager.EXTRA_STATUS, -1),
        )
    }

    private fun granted(p: String) = ctx.checkSelfPermission(p) == PackageManager.PERMISSION_GRANTED

    private fun servicesEnabled(): Boolean {
        val lm = ctx.getSystemService(LocationManager::class.java) ?: return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            lm.isLocationEnabled
        } else {
            lm.isProviderEnabled(LocationManager.GPS_PROVIDER) || lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
        }
    }

    companion object {
        fun reading(level: Int, scale: Int, status: Int): BatteryReading? {
            if (level < 0 || scale <= 0) return null
            val charging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
            return BatteryReading((level * 100) / scale, charging)
        }
    }
}

/** Trip clock sources (T10 §2.6). BOOT_COUNT may be unreadable on some ROMs: null, the runtime uses elapsed instead. */
class AndroidTimeSource(context: Context) : TimeSource {
    private val resolver = context.applicationContext.contentResolver

    override fun wallMs(): Long = System.currentTimeMillis()

    override fun elapsedMs(): Long = SystemClock.elapsedRealtime()

    override fun elapsedNanos(): Long = SystemClock.elapsedRealtimeNanos()

    override fun bootCount(): Int? =
        try {
            Settings.Global.getInt(resolver, Settings.Global.BOOT_COUNT)
        } catch (e: Exception) {
            null
        }
}
