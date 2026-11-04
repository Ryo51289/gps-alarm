package app.napstop.core.alarm.ring

import android.content.Context
import android.content.Intent
import android.util.Log
import app.napstop.core.trip.runtime.RingEventKind

/**
 * RING_EVENT `:ring` → main process (T15 §4.4): explicit broadcast to RingEventReceiver, which starts the main process if
 * it died. The receiver is named by class name so nothing of the main process' runtime is loaded here.
 */
object RingEventSender {
    const val ACTION_RING_EVENT = "app.napstop.action.RING_EVENT"
    private const val RECEIVER = "app.napstop.core.trip.host.RingEventReceiver"

    fun send(ctx: Context, tripId: String, kind: RingEventKind, atWallMs: Long) {
        try {
            ctx.sendBroadcast(
                Intent(ACTION_RING_EVENT)
                    .setClassName(ctx.packageName, RECEIVER)
                    .putExtra("tripId", tripId)
                    .putExtra("kind", kind.name)
                    .putExtra("atWallMs", atWallMs),
            )
        } catch (e: Exception) {
            Log.w("NapStopRing", "ring event failed (${e.javaClass.simpleName})")
        }
    }
}
