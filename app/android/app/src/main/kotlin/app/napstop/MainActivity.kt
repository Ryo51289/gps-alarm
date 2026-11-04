package app.napstop

import android.content.Intent
import app.napstop.core.alarm.LaunchActions
import app.napstop.core.alarm.RingIntents
import app.napstop.core.alarm.SoundPreviewPlayer
import app.napstop.core.bridge.BridgeRegistrar
import app.napstop.core.trip.host.AppVisibilityTracker
import app.napstop.core.trip.host.RuntimeHost
import app.napstop.core.trip.host.TripNotifications
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import kotlinx.coroutines.launch

class MainActivity : FlutterActivity() {
    private var bridge: BridgeRegistrar.Registration? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
        onVisible(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        onVisible(intent)
    }

    override fun onStop() {
        AppVisibilityTracker.onActivityStopped()
        // T16 §5.11: a sound preview never outlives the visible app.
        SoundPreviewPlayer.get(this).stop()
        super.onStop()
    }

    private fun onVisible(intent: Intent?) {
        val resumeTripId = intent?.getStringExtra(TripNotifications.EXTRA_RESUME_TRIP_ID)
        intent?.removeExtra(TripNotifications.EXTRA_RESUME_TRIP_ID)
        // T16 §4.5: "Xem đường quay lại" opened the app; T27 reads the action on the Flutter side.
        // MainActivity is exported (launcher): only the known action with a valid trip id is kept.
        intent?.getStringExtra(LaunchActions.EXTRA_LAUNCH)?.let { action ->
            val trip = RingIntents.validTripId(intent.getStringExtra(LaunchActions.EXTRA_TRIP_ID))
            if (action == LaunchActions.OVERSHOOT_ROUTE && trip != null) LaunchActions.set(action, trip)
            intent.removeExtra(LaunchActions.EXTRA_LAUNCH)
            intent.removeExtra(LaunchActions.EXTRA_TRIP_ID)
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
