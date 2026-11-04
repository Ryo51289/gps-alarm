package app.napstop.core.alarm.ring

import android.content.Context
import android.graphics.Typeface

/** Be Vietnam Pro (T20) read from the Flutter assets of the APK; missing → the system font. */
object AlarmFonts {
    enum class Weight(val file: String) {
        REGULAR("Regular"),
        MEDIUM("Medium"),
        SEMI_BOLD("SemiBold"),
        BOLD("Bold"),
    }

    private val cache = HashMap<Weight, Typeface?>()

    @Synchronized
    fun get(ctx: Context, w: Weight): Typeface? =
        cache.getOrPut(w) {
            try {
                Typeface.createFromAsset(ctx.assets, "flutter_assets/assets/fonts/BeVietnamPro/BeVietnamPro-${w.file}.ttf")
            } catch (e: Exception) {
                null
            }
        }
}
