package app.napstop.core.bridge

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import java.security.MessageDigest

/**
 * `PermissionHostApi.mapsConfig()` on Android (spec T23 §6, D4): the Maps/Places key of
 * this build (manifest meta-data filled from `secrets.properties` per flavor) and the app
 * identity the Places REST calls need for an Android-restricted key (package name, SHA-1
 * of the signing certificate). Synchronous Pigeon method on the main thread: only cheap
 * PackageManager reads. Each field that cannot be read is null; never throws.
 *
 * PRIVACY: never log the key or the result.
 */
class MapsConfigReader(context: Context) {
    private val appContext = context.applicationContext

    fun read(): MapsConfigMsg {
        val pkg = appContext.packageName
        return MapsConfigMsg(
            apiKey = readOrNull("key") { apiKey(pkg) },
            androidPackage = pkg,
            androidCertSha1 = readOrNull("cert") { certSha1(pkg) },
            iosBundleId = null,
        )
    }

    private fun apiKey(pkg: String): String? {
        val info = appContext.packageManager.getApplicationInfo(pkg, PackageManager.GET_META_DATA)
        return CertFingerprint.usableKey(info.metaData?.getString(META_API_KEY))
    }

    private fun certSha1(pkg: String): String? {
        val pm = appContext.packageManager
        val der: ByteArray? =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                pm.getPackageInfo(pkg, PackageManager.GET_SIGNING_CERTIFICATES)
                    .signingInfo
                    ?.apkContentsSigners
                    ?.firstOrNull()
                    ?.toByteArray()
            } else {
                @Suppress("DEPRECATION")
                pm.getPackageInfo(pkg, PackageManager.GET_SIGNATURES)
                    .signatures
                    ?.firstOrNull()
                    ?.toByteArray()
            }
        return der?.let(CertFingerprint::sha1Hex)
    }

    /** [block], or null after logging the item and the exception class only. */
    private inline fun <T> readOrNull(item: String, block: () -> T?): T? =
        try {
            block()
        } catch (e: Exception) {
            Log.w(TAG, "maps $item: ${e.javaClass.simpleName}")
            null
        }

    private companion object {
        const val TAG = "NapStopBridge"
        const val META_API_KEY = "com.google.android.geo.API_KEY"
    }
}

/** Pure parts of [MapsConfigReader], JVM-testable (T23 TK01). */
object CertFingerprint {
    /** Placeholder written by the build when no key is configured (T23 §7). */
    const val PLACEHOLDER_KEY = "DEFAULT_API_KEY"

    /** SHA-1 of [der] as 40 upper-case hex characters, no colons (`X-Android-Cert`). */
    fun sha1Hex(der: ByteArray): String =
        MessageDigest.getInstance("SHA-1").digest(der).joinToString("") { "%02X".format(it) }

    /** The key, or null when missing, blank or the build placeholder. */
    fun usableKey(raw: String?): String? {
        val key = raw?.trim()
        return if (key.isNullOrEmpty() || key == PLACEHOLDER_KEY) null else key
    }
}
