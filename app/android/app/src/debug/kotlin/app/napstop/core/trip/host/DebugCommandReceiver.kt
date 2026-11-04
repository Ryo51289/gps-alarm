package app.napstop.core.trip.host

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import app.napstop.core.alarm.RingSettings
import app.napstop.core.trip.AccuracyLevel
import app.napstop.core.trip.AlarmMode
import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.SamplingPolicy
import app.napstop.core.trip.SamplingTier
import app.napstop.core.trip.VehicleKind
import app.napstop.core.trip.runtime.FlpMapper
import app.napstop.core.trip.runtime.RuntimeListener
import app.napstop.core.trip.runtime.StartOutcome
import app.napstop.core.trip.runtime.TripMeta
import java.io.File
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * Debug-only adb commands of spec T15 §5.14 (exported, guarded by android.permission.DUMP: only `adb shell` can send).
 *
 *   adb shell am broadcast -a app.napstop.action.DEBUG -n app.napstop.dev/app.napstop.core.trip.host.DebugCommandReceiver \
 *     --es cmd <command> [extras]
 *
 * replay (--es file x.gpx --es expect x.expect.json [--ef speedScale 1.0] [--ei dropAfterS N] [--es hint unknown|train|coach|bus]
 * [--es mode distance|time|smart --ei threshold N]; files in getExternalFilesDir("replay"); the app must be visible),
 * replay_stop, force_tier sparse|medium|dense|off (--es value), gps_drop on|off, snapshot_fail on|off, ring_fail on|off,
 * slow_read <ms> (persisted, 0 clears; disk reads sleep that long, e.g. to test a reboot on a slow disk), listener_throw on|off,
 * fb_test (--ei leadS 10 --ei cancelDelayS 0), journal_clear, dump. Results go to logcat tag NapStopDebug (no coordinates).
 */
class DebugCommandReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val host = RuntimeHost.get(context)
        val cmd = intent.getStringExtra("cmd") ?: return
        val value = intent.getStringExtra("value")
        when (cmd) {
            "replay" ->
                try {
                    replay(context, host, intent)
                } catch (e: Exception) {
                    Log.w(TAG, "replay failed (${e.javaClass.simpleName})")
                }
            "replay_stop" -> {
                replaySource?.cancel()
                replaySource = null
                host.location.setOverride(null)
                Log.i(TAG, "replay stopped")
            }
            "force_tier" -> {
                val p = EngineParams()
                host.runtime.debugSpecOverride =
                    when (value) {
                        "sparse" -> FlpMapper.spec(SamplingPolicy(SamplingTier.SPARSE, p.samplingSparseIntervalS, p.samplingSparseMinIntervalS, AccuracyLevel.BALANCED), p)
                        "medium" -> FlpMapper.spec(SamplingPolicy(SamplingTier.MEDIUM, p.samplingMediumIntervalS, p.samplingMediumMinIntervalS, AccuracyLevel.HIGH), p)
                        "dense" -> FlpMapper.spec(SamplingPolicy(SamplingTier.DENSE, p.samplingDenseIntervalS, p.samplingDenseMinIntervalS, AccuracyLevel.HIGH), p)
                        else -> null
                    }
                host.runtime.debugReapplySampling()
                Log.i(TAG, "force_tier ${value ?: "off"}")
            }
            "gps_drop" -> {
                host.runtime.debugDropFixes = value == "on"
                Log.i(TAG, "gps_drop $value")
            }
            "snapshot_fail" -> {
                RuntimeDebugFlags.snapshotFail = value == "on"
                Log.i(TAG, "snapshot_fail $value")
            }
            "ring_fail" -> {
                RuntimeDebugFlags.ringFail = value == "on"
                Log.i(TAG, "ring_fail $value")
            }
            "slow_read" -> {
                // Persisted: also applies to the restore right after a reboot. `--es value 0` clears it.
                val f = File(File(context.noBackupFilesDir, app.napstop.core.trip.runtime.FileRuntimeStore.DIR_NAME), AndroidRuntimeStore.SLOW_READ_FILE)
                val ms = value?.toLongOrNull() ?: 0L
                if (ms > 0) {
                    f.parentFile?.mkdirs()
                    f.writeText(ms.toString())
                } else {
                    f.delete()
                }
                Log.i(TAG, "slow_read $ms ms")
            }
            "listener_throw" -> {
                throwingListener?.invoke()
                throwingListener = null
                if (value == "on") throwingListener = host.runtime.addListener(RuntimeListener { _, _, _, _ -> throw IllegalStateException("debug listener_throw") })
                Log.i(TAG, "listener_throw $value")
            }
            "fb_test" -> fbTest(context, host, intent.getIntExtra("leadS", 10), intent.getIntExtra("cancelDelayS", 0))
            "journal_clear" -> {
                DebugRuntimeHooks.journal?.clear()
                Log.i(TAG, "journal cleared")
            }
            "dump" -> {
                val pending = goAsync()
                host.scope.launch {
                    try {
                        Log.i(TAG, host.runtime.debugDump())
                    } finally {
                        pending.finish()
                    }
                }
            }
            else -> Log.w(TAG, "unknown cmd")
        }
    }

    private fun replay(context: Context, host: RuntimeHost.Host, intent: Intent) {
        val dir =
            context.getExternalFilesDir("replay") ?: run {
                Log.w(TAG, "no replay dir")
                return
            }
        val gpx = File(dir, intent.getStringExtra("file") ?: return)
        val expect = JSONObject(File(dir, intent.getStringExtra("expect") ?: return).readText())
        val dest = expect.getJSONObject("destination")
        val samples = ReplayLocationSource.readGpx(gpx)
        val speedScale = intent.getFloatExtra("speedScale", 1f).toDouble().takeIf { it > 0 } ?: 1.0
        val drop = if (intent.hasExtra("dropAfterS")) intent.getIntExtra("dropAfterS", 0) else null
        val mode =
            when (intent.getStringExtra("mode")) {
                "time" -> AlarmMode.TIME
                "smart" -> AlarmMode.SMART
                else -> AlarmMode.DISTANCE
            }
        val threshold = intent.getIntExtra("threshold", if (mode == AlarmMode.TIME) 15 else 1000)
        val hint =
            when (intent.getStringExtra("hint") ?: expect.getJSONObject("trace").getString("vehicle")) {
                "train" -> VehicleKind.TRAIN
                "coach" -> VehicleKind.COACH
                "bus" -> VehicleKind.BUS
                else -> VehicleKind.UNKNOWN
            }
        val source = ReplayLocationSource(samples, speedScale, drop, host.scope)
        replaySource?.cancel()
        replaySource = source
        host.location.setOverride(source)
        val meta =
            TripMeta(
                tripId = "replay-${System.currentTimeMillis()}",
                destinationName = dest.optString("name", "Replay"),
                mode = mode,
                distanceThresholdM = if (mode == AlarmMode.DISTANCE) threshold else null,
                timeThresholdMin = if (mode == AlarmMode.TIME) threshold else null,
                preAlertEnabled = false,
                vehicleHint = hint,
                alarm = RingSettings("default", 1.0, false, "medium", false, false, "swipe"),
                engineParamsJson = null,
            )
        val pending = goAsync()
        host.scope.launch {
            try {
                val r = host.runtime.start(meta, dest.getDouble("lat"), dest.getDouble("lng"))
                Log.i(TAG, "replay ${gpx.name}: ${if (r == StartOutcome.Started) "started" else r.toString()} samples=${samples.size}")
            } finally {
                pending.finish()
            }
        }
    }

    /** LM4: A at +40 s; when A has [leadS] left set B at +40 s; [cancelDelayS] later cancel A. One ring expected. */
    private fun fbTest(context: Context, host: RuntimeHost.Host, leadS: Int, cancelDelayS: Int) {
        val scheduler = AndroidAlarmScheduler(context)
        val tripId = "fbtest-${System.currentTimeMillis() % 100_000}"
        host.scope.launch {
            if (!host.runtime.debugArmFallbackTest(tripId)) {
                Log.w(TAG, "fb_test: a trip is running")
                return@launch
            }
            val now = System.currentTimeMillis()
            scheduler.setFallback(0, tripId, 1, now + 40_000, now + 40_000, exact = true)
            Log.i(TAG, "fb_test $tripId: A set")
            delay(maxOf(0, 40_000L - leadS * 1000L))
            val t = System.currentTimeMillis()
            scheduler.setFallback(1, tripId, 2, t + 40_000, t + 40_000, exact = true)
            Log.i(TAG, "fb_test $tripId: B set")
            delay(cancelDelayS * 1000L)
            scheduler.cancelFallback(0)
            Log.i(TAG, "fb_test $tripId: A cancelled")
            delay(120_000)
            host.runtime.debugArmFallbackTest(null)
            Log.i(TAG, "fb_test $tripId: done")
        }
    }

    private companion object {
        const val TAG = "NapStopDebug"

        @Volatile
        var replaySource: ReplayLocationSource? = null

        @Volatile
        var throwingListener: (() -> Unit)? = null
    }
}
