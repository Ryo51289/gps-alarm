package app.napstop.core.alarm

import android.content.Context
import android.os.SystemClock
import android.provider.Settings

/** Clocks of the ring book: wall for reports, elapsedRealtime for liveness, BOOT_COUNT to drop rings of an old boot. */
class AndroidRingClock(context: Context) : RingClock {
    private val ctx = context.applicationContext

    override fun wallMs(): Long = System.currentTimeMillis()

    override fun elapsedMs(): Long = SystemClock.elapsedRealtime()

    override fun elapsedNanos(): Long = SystemClock.elapsedRealtimeNanos()

    override fun bootCount(): Int? =
        try {
            Settings.Global.getInt(ctx.contentResolver, Settings.Global.BOOT_COUNT)
        } catch (e: Exception) {
            null
        }
}
