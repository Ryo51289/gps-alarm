package app.napstop.core.alarm

import android.content.Context
import android.content.res.Configuration
import android.os.LocaleList
import android.util.Log
import app.napstop.core.trip.host.TripNotifications
import java.io.File
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Per-app language of the native strings (spec T28 D9): tracking / alarm notifications, pre-alert, backup ring and the
 * alarm screen. One mechanism for every API level: a Context from `createConfigurationContext` with the chosen locale
 * (the AppCompat per-app API only works with an AppCompatActivity context on API ≤ 32; no LocaleManager, no
 * localeConfig). The main process stores the choice in a small file under noBackupFilesDir; Dart pushes it at every app
 * start and on change. `:ring` never reads the file: it gets the tag through RING_START (`RingStart.localeTag`).
 */
object AppLocale {
    /** In noBackupFilesDir; content "vi" | "en"; absent = follow the device. */
    const val FILE = "napstop_app_locale"

    private const val TAG = "NapStopLocale"
    private val SUPPORTED = setOf("vi", "en")

    @Volatile
    private var loaded = false

    @Volatile
    private var cached: String? = null

    /** Last localized application context, by tag (the tracking notification asks often). */
    @Volatile
    private var lastLocalized: Pair<String, Context>? = null

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val preloading = AtomicBoolean(false)

    /** One writer at a time; each write stores the LATEST choice. */
    @OptIn(ExperimentalCoroutinesApi::class)
    private val writer = Dispatchers.IO.limitedParallelism(1)

    /** Pure: trimmed "vi" / "en" → itself; anything else (null, blank, "fr", "vi-VN") → null (device). */
    fun parse(raw: String?): String? = raw?.trim()?.takeIf { it in SUPPORTED }

    /** The chosen tag, or null (device). The first call reads [FILE] (≤ 16 bytes; errors → null). Main process only. */
    fun tag(ctx: Context): String? {
        if (!loaded) {
            synchronized(this) {
                if (!loaded) {
                    cached = fileOf(ctx).read()
                    loaded = true
                }
            }
        }
        return cached
    }

    /**
     * Applies [tag] at once (memory), then writes the file and renames the notification channels on IO (D10). Never
     * throws. Main process only.
     */
    fun set(ctx: Context, tag: String?) {
        val app = ctx.applicationContext
        synchronized(this) {
            cached = parse(tag)
            loaded = true
        }
        scope.launch(writer) {
            val latest = cached
            try {
                fileOf(app).write(latest)
            } catch (e: Exception) {
                Log.w(TAG, "locale write failed (${e.javaClass.simpleName})")
            }
            renameChannels(app)
        }
    }

    /**
     * Process start (main process): reads the file if needed and creates / renames every channel in the chosen language,
     * on IO and serialized with [set], so a start never renames over a newer choice (review T28 #2, #7).
     */
    fun refreshChannels(ctx: Context) {
        val app = ctx.applicationContext
        scope.launch(writer) { renameChannels(app) }
    }

    /**
     * Never touches the disk (main thread callers, e.g. the ongoing notification): the chosen tag when already read,
     * else null (device language for now) and the read is started on IO; later posts get the right language.
     */
    fun tagNow(ctx: Context): String? {
        if (loaded) return cached
        if (preloading.compareAndSet(false, true)) {
            val app = ctx.applicationContext
            scope.launch { tag(app) }
        }
        return null
    }

    /** Whether the choice is known in memory (read once, or set). */
    val isLoaded: Boolean get() = loaded

    private fun renameChannels(app: Context) {
        try {
            AlarmChannels.ensure(app, localizedWith(app, tag(app)))
            TripNotifications(app).ensureChannels()
        } catch (e: Exception) {
            Log.w(TAG, "channel rename failed (${e.javaClass.simpleName})")
        }
    }

    /** [ctx] with the chosen language (main process). */
    fun localized(ctx: Context): Context = localizedWith(ctx, tag(ctx))

    /** [ctx] when [tag] is null (device language), else a configuration context with that locale. */
    fun localizedWith(ctx: Context, tag: String?): Context {
        val t = parse(tag) ?: return ctx
        val app = ctx.applicationContext
        if (ctx === app) {
            lastLocalized?.let { (k, c) -> if (k == t) return c }
        }
        val conf = Configuration(ctx.resources.configuration).apply { setLocales(LocaleList(Locale.forLanguageTag(t))) }
        val out = ctx.createConfigurationContext(conf)
        if (ctx === app) lastLocalized = t to out
        return out
    }

    /** Locale for number and time formatting (main process): the chosen one, else the resources locale. */
    fun locale(ctx: Context): Locale = localeWith(ctx, tag(ctx))

    /** Like [locale] with an explicit [tag] (`:ring`). */
    fun localeWith(ctx: Context, tag: String?): Locale =
        parse(tag)?.let { Locale.forLanguageTag(it) } ?: ctx.resources.configuration.locales[0] ?: Locale.getDefault()

    private fun fileOf(ctx: Context) = LocaleFile(ctx.applicationContext.noBackupFilesDir)
}

/** The language file of [AppLocale] in [dir] (JVM-testable). */
class LocaleFile(private val dir: File) {
    private val file get() = File(dir, AppLocale.FILE)

    /** The stored tag; missing, unreadable, larger than [MAX_BYTES] or not "vi"/"en" → null. Never throws. */
    fun read(): String? =
        try {
            val f = file
            if (!f.isFile || f.length() > MAX_BYTES) null else AppLocale.parse(f.readText(Charsets.UTF_8))
        } catch (e: Exception) {
            null
        }

    /** Stores [tag] (write tmp + rename); null or unsupported deletes the file. */
    fun write(tag: String?) {
        val t = AppLocale.parse(tag)
        val f = file
        if (t == null) {
            if (f.exists() && !f.delete()) throw java.io.IOException("delete failed")
            return
        }
        dir.mkdirs()
        val tmp = File(dir, "${AppLocale.FILE}.tmp")
        tmp.writeText(t, Charsets.UTF_8)
        if (!tmp.renameTo(f)) {
            // Windows-like filesystems (JVM tests) do not replace on rename.
            f.delete()
            if (!tmp.renameTo(f)) throw java.io.IOException("rename failed")
        }
    }

    companion object {
        const val MAX_BYTES = 16L
    }
}
