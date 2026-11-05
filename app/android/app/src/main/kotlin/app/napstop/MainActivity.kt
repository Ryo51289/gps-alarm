package app.napstop

import android.content.Intent
import android.os.Bundle
import app.napstop.core.alarm.LaunchActions
import app.napstop.core.alarm.SoundPreviewPlayer
import app.napstop.core.bridge.BridgeRegistrar
import app.napstop.core.trip.host.AppVisibilityTracker
import app.napstop.core.trip.host.RuntimeHost
import app.napstop.core.trip.host.SimAssetsPlugin
import app.napstop.core.trip.host.TripNotifications
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import kotlinx.coroutines.launch

class MainActivity : FlutterActivity() {
    private var bridge: BridgeRegistrar.Registration? = null

    // Review T27 #1: the intent of this creation is the task's original one given back by the system (process death,
    // Recents), not a new tap on "Xem đường quay lại". Cleared after the first onStart.
    private var replayedIntent = false

    override fun onCreate(savedInstanceState: Bundle?) {
        replayedIntent = LaunchActions.isReplay(savedInstanceState != null, intent?.flags ?: 0)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // T18 §8: asset lookup of the bundled simulation traces.
        flutterEngine.plugins.add(SimAssetsPlugin())
        // T21: the real PermissionHostApi needs the activity (dialogs, settings pages).
        bridge = BridgeRegistrar.register(flutterEngine.dartExecutor.binaryMessenger, this)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        bridge?.unregister()
        bridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        bridge?.onRequestPermissionsResult(requestCode)
        // Always: other plugins still get their own results.
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    // T15 (ADR-001 #2, spec D11): the activity is visible between onStart and onStop. Becoming visible (or a tap on the
    // "interrupted" notification) brings a trip whose foreground service died back to the foreground service.
    override fun onStart() {
        super.onStart()
        AppVisibilityTracker.onActivityStarted()
        onVisible(intent, replayed = replayedIntent)
        replayedIntent = false
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        onVisible(intent, replayed = false)
    }

    override fun onStop() {
        AppVisibilityTracker.onActivityStopped()
        // T16 §5.11: a sound preview never outlives the visible app.
        SoundPreviewPlayer.get(this).stop()
        super.onStop()
    }

    private fun onVisible(intent: Intent?, replayed: Boolean) {
        val resumeTripId = intent?.getStringExtra(TripNotifications.EXTRA_RESUME_TRIP_ID)
        intent?.removeExtra(TripNotifications.EXTRA_RESUME_TRIP_ID)
        // T16 §4.5, T27 D4: "Xem đường quay lại" opened the app; Flutter takes the action through consumeLaunchAction.
        // Stored here (onStart / onNewIntent), before onResume. MainActivity is exported (launcher): only the known
        // action with a valid trip id, tapped less than 10 min ago and not replayed by the system, is kept.
        intent?.getStringExtra(LaunchActions.EXTRA_LAUNCH)?.let { action ->
            val pastM = if (intent.hasExtra(LaunchActions.EXTRA_PAST_M)) intent.getIntExtra(LaunchActions.EXTRA_PAST_M, -1) else null
            val atWallMs = if (intent.hasExtra(LaunchActions.EXTRA_AT_WALL_MS)) intent.getLongExtra(LaunchActions.EXTRA_AT_WALL_MS, 0L) else null
            LaunchActions.fromIntent(
                action, intent.getStringExtra(LaunchActions.EXTRA_TRIP_ID), pastM, atWallMs,
                nowWallMs = System.currentTimeMillis(), restored = replayed, intentFlags = intent.flags,
            )?.let(LaunchActions::set)
            intent.removeExtra(LaunchActions.EXTRA_LAUNCH)
            intent.removeExtra(LaunchActions.EXTRA_TRIP_ID)
            intent.removeExtra(LaunchActions.EXTRA_PAST_M)
            intent.removeExtra(LaunchActions.EXTRA_AT_WALL_MS)
        }
        val host = RuntimeHost.get(this)
        // T16 D8, §5.11: a ring that is on is shown by the native alarm screen, over the Flutter UI.
        host.alarm.onAppVisible(this)
        host.scope.launch {
            if (resumeTripId != null) host.runtime.onNotificationResume(resumeTripId)
            host.runtime.onAppVisible()
        }
    }
}
