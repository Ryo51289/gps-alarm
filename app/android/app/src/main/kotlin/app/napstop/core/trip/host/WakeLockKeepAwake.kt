package app.napstop.core.trip.host

import android.content.Context
import android.os.PowerManager
import android.util.Log
import app.napstop.core.trip.runtime.KeepAwake

/**
 * PARTIAL_WAKE_LOCK "napstop:sim" while a simulated trip runs (T18 D8, [A-WL]): its timers are coroutines and no FLP
 * wakes the CPU. Not reference counted; [hold] uses acquire(timeout) so the lock never outlives the cap.
 */
class WakeLockKeepAwake(context: Context) : KeepAwake {
    private val ctx = context.applicationContext
    private val lock: PowerManager.WakeLock? by lazy {
        ctx.getSystemService(PowerManager::class.java)?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, TAG_SIM)?.apply {
            setReferenceCounted(false)
        }
    }

    override fun hold(capMs: Long) {
        lock?.acquire(capMs)
    }

    override fun release() {
        try {
            lock?.let { if (it.isHeld) it.release() }
        } catch (e: RuntimeException) {
            Log.w("NapStopRuntime", "sim wake lock release failed (${e.javaClass.simpleName})")
        }
    }

    private companion object {
        const val TAG_SIM = "napstop:sim"
    }
}
