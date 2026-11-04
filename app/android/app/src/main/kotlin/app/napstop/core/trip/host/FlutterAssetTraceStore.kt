package app.napstop.core.trip.host

import android.content.Context
import app.napstop.core.trip.runtime.TraceStore
import app.napstop.core.trip.runtime.sim.SimTraceIds
import io.flutter.embedding.engine.plugins.FlutterPlugin
import java.io.FileNotFoundException
import java.io.InputStream

/**
 * Bundled simulation traces (T18 §8, D10, D11): `assets/sim/<id>.gpx` of the Flutter app, looked up with
 * [FlutterPlugin.FlutterAssets.getAssetFilePathByName] [F-FA] and opened with the AssetManager. Takes an id, never a
 * path: an id that is not `^[a-z0-9]+(_[a-z0-9]+)*$` (≤ 64), a missing file, or no Flutter engine yet → null
 * (`simulation-unavailable` "TraceNotFound" / "TraceIdInvalid" at the runtime).
 */
class FlutterAssetTraceStore internal constructor(
    private val flutterAssets: () -> FlutterPlugin.FlutterAssets?,
    private val openAsset: (String) -> InputStream,
) : TraceStore {
    constructor(context: Context) : this({ SimAssetsPlugin.assets }, context.applicationContext.assets::open)

    override fun open(traceId: String): InputStream? {
        if (!SimTraceIds.valid(traceId)) return null
        val path = flutterAssets()?.getAssetFilePathByName("$ASSET_DIR$traceId.gpx") ?: return null
        return try {
            openAsset(path)
        } catch (e: FileNotFoundException) {
            null
        }
    }

    companion object {
        /** Flutter asset directory of the traces (pubspec `assets/sim/`, built by `tracegen bundle-sim`). */
        const val ASSET_DIR = "assets/sim/"
    }
}
