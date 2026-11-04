package app.napstop.core.trip.host

import io.flutter.embedding.engine.plugins.FlutterPlugin
import java.io.ByteArrayInputStream
import java.io.FileNotFoundException
import java.io.InputStream
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** T18 SM32: bundled traces are opened by id through the Flutter asset lookup, never by path. */
class FlutterAssetTraceStoreTest {
    private class FakeAssets : FlutterPlugin.FlutterAssets {
        val asked = ArrayList<String>()

        override fun getAssetFilePathByName(assetFileName: String): String {
            asked += assetFileName
            return "flutter_assets/$assetFileName"
        }

        override fun getAssetFilePathByName(assetFileName: String, packageName: String): String = error("not used")

        override fun getAssetFilePathBySubpath(assetSubpath: String): String = error("not used")

        override fun getAssetFilePathBySubpath(assetSubpath: String, packageName: String): String = error("not used")
    }

    private val files = mapOf("flutter_assets/assets/sim/train_hn_dh.gpx" to "<gpx/>")
    private val opened = ArrayList<String>()
    private val open: (String) -> InputStream = { path ->
        opened += path
        ByteArrayInputStream((files[path] ?: throw FileNotFoundException(path)).toByteArray())
    }

    @Test
    fun opensByIdOnlyThroughTheFlutterLookup() {
        val assets = FakeAssets()
        val store = FlutterAssetTraceStore({ assets }, open)
        assertEquals("<gpx/>", store.open("train_hn_dh")!!.readBytes().decodeToString())
        assertEquals(listOf("assets/sim/train_hn_dh.gpx"), assets.asked)
        assertEquals(listOf("flutter_assets/assets/sim/train_hn_dh.gpx"), opened)
        for (bad in listOf("../x", "stub/normal", "UPPER", "", "a".repeat(65))) {
            assertNull(bad, store.open(bad))
        }
        assertEquals("a bad id never reaches the lookup", 1, assets.asked.size)
        assertNull("missing file", store.open("nope"))
        assertTrue(opened.last().endsWith("assets/sim/nope.gpx"))
    }

    @Test
    fun noFlutterEngineYetIsNull() {
        val store = FlutterAssetTraceStore({ null }, open)
        assertNull(store.open("train_hn_dh"))
        assertTrue(opened.isEmpty())
    }
}
