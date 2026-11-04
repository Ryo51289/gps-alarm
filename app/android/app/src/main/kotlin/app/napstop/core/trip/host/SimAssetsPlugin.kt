package app.napstop.core.trip.host

import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * Keeps the [FlutterPlugin.FlutterAssets] of the app's Flutter engine for [FlutterAssetTraceStore] (T18 §8, [F-FPB]).
 * Added by MainActivity.configureFlutterEngine. The lookup only maps an asset name to its path in the APK, so the last
 * engine's value stays valid after that engine is gone.
 */
class SimAssetsPlugin : FlutterPlugin {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        assets = binding.flutterAssets
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) = Unit

    companion object {
        @Volatile
        var assets: FlutterPlugin.FlutterAssets? = null
            private set
    }
}
