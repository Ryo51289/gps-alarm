package app.napstop

import app.napstop.core.bridge.BridgeRegistrar
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

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
}
