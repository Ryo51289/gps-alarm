package app.napstop.core.trip.host

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import app.napstop.core.trip.runtime.RestoreCause
import app.napstop.core.trip.runtime.SlotKind
import app.napstop.core.trip.runtime.RingEvent
import app.napstop.core.trip.runtime.RingEventKind
import app.napstop.core.trip.UserActionKind
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

// Receivers of the trip runtime (spec T15 §5.5, §5.6, §5.8, §4.4). Each one: goAsync(), hand over to the runtime
// actor, finish within RECEIVER_BUDGET_MS (S2 A14). None of them starts LocationService (D9). Not exported.

private const val TAG = "NapStopRuntime"
private val TRIP_ID = Regex("^[A-Za-z0-9_-]{1,64}$")

/** goAsync + one runtime call on the host scope, bounded by the receiver budget. */
internal fun BroadcastReceiver.runAsync(context: Context, what: String, block: suspend (RuntimeHost.Host) -> Unit) {
    val pending = goAsync()
    val host = RuntimeHost.get(context)
    host.scope.launch {
        try {
            withTimeoutOrNull(host.constants.receiverBudgetMs) { block(host) } ?: Log.w(TAG, "$what: over budget")
        } catch (e: Exception) {
            Log.w(TAG, "$what failed (${e.javaClass.simpleName})")
        } finally {
            pending.finish()
        }
    }
}

/**
 * wakeAtMs (setExactAndAllowWhileIdle): battery / location checks, then Tick at the delivery time; the wake is logged
 * with the time it was set for, before any restore (F5). Also the restoreRetry alarm (designer "sau test" B3).
 */
class WakeAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val retry = intent.getIntExtra(EXTRA_RESTORE_RETRY, -1)
        if (retry >= 0) {
            val cause = intent.getStringExtra(EXTRA_CAUSE)?.let { c -> RestoreCause.entries.firstOrNull { it.name == c } } ?: RestoreCause.PROCESS_START
            val since = intent.getLongExtra(EXTRA_SINCE_WALL, System.currentTimeMillis())
            runAsync(context, "restore retry") {
                it.runtime.onRestoreRetry(retry, cause, since)
                it.runtime.awaitNotices()
            }
            return
        }
        val at = intent.getLongExtra(EXTRA_WAKE_AT, -1L).takeIf { it >= 0 }
        val atWall = intent.getLongExtra(EXTRA_WAKE_AT_WALL, -1L).takeIf { it >= 0 }
        runAsync(context, "wake") {
            it.runtime.onWake(at, atWall)
            // A load that timed out in onWake is retried within the budget (RestoreLoop, B1), then the Tick is sent.
            if (it.runtime.liveTrip() == null) {
                it.runtime.ensureLoaded()
                if (it.runtime.liveTrip() != null) it.runtime.onWake()
            }
            it.runtime.awaitNotices()
        }
    }

    companion object {
        const val EXTRA_WAKE_AT = "wakeAtMs"
        const val EXTRA_WAKE_AT_WALL = "wakeAtWallMs"
        const val EXTRA_RESTORE_RETRY = "restoreRetry"
        const val EXTRA_CAUSE = "cause"
        const val EXTRA_SINCE_WALL = "sinceWallMs"
    }
}

/** Fallback alarm (setAlarmClock): record → ring → cancel the other slot → FallbackFired (D8). */
class FallbackAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val tripId = intent.getStringExtra(EXTRA_TRIP_ID)?.takeIf { TRIP_ID.matches(it) } ?: return
        val slot = intent.getIntExtra(EXTRA_SLOT, -1).takeIf { it == 0 || it == 1 } ?: return
        val generation = intent.getLongExtra(EXTRA_GENERATION, -1L)
        val target = intent.getLongExtra(EXTRA_TARGET_AT, -1L)
        val kind = intent.getStringExtra(EXTRA_KIND)?.let { k -> SlotKind.entries.firstOrNull { it.name == k } }
        runAsync(context, "fallback") {
            // Ring first (never behind a snapshot read), then make sure the trip gets loaded (RestoreLoop, B1).
            it.runtime.onFallbackFired(tripId, slot, generation, target, kind)
            it.runtime.ensureLoaded()
            it.runtime.awaitNotices()
        }
    }

    companion object {
        const val EXTRA_TRIP_ID = "tripId"
        const val EXTRA_SLOT = "slot"
        const val EXTRA_GENERATION = "generation"
        const val EXTRA_TARGET_AT = "targetAtMs"
        const val EXTRA_KIND = "kind"
    }
}

/** BOOT_COMPLETED / MY_PACKAGE_REPLACED: restore with MISSING (alarms gone or uncertain), "interrupted" notice. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val cause =
            when (intent.action) {
                Intent.ACTION_BOOT_COMPLETED -> RestoreCause.BOOT
                Intent.ACTION_MY_PACKAGE_REPLACED -> RestoreCause.PACKAGE_REPLACED
                else -> return
            }
        runAsync(context, "boot") {
            it.runtime.ensureLoaded(cause)
            it.runtime.awaitNotices()
        }
    }
}

/**
 * RING_EVENT from `:ring` (T16, cross-process, explicit component, §4.4). `:ring` wrote the ring book (pendingDismiss,
 * snoozedAt, silencedAt) before sending it; the controller's cached view of the book is dropped first.
 */
class RingEventReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_RING_EVENT) return
        val tripId = intent.getStringExtra(EXTRA_TRIP_ID)?.takeIf { TRIP_ID.matches(it) } ?: return
        val kind = intent.getStringExtra(EXTRA_KIND)?.let { k -> RingEventKind.entries.firstOrNull { it.name == k } } ?: return
        val at = intent.getLongExtra(EXTRA_AT_WALL_MS, System.currentTimeMillis())
        runAsync(context, "ring event") { host ->
            host.alarm.onRingEvent(tripId)
            host.runtime.ensureLoaded()
            host.runtime.onRingEvent(RingEvent(tripId, kind, at))
        }
    }

    companion object {
        const val ACTION_RING_EVENT = "app.napstop.action.RING_EVENT"
        const val EXTRA_TRIP_ID = "tripId"
        const val EXTRA_KIND = "kind"
        const val EXTRA_AT_WALL_MS = "atWallMs"
    }
}

/** "Dừng theo dõi" on the ongoing / interrupted notification. */
class TripActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_STOP) return
        val tripId = intent.getStringExtra(EXTRA_TRIP_ID)?.takeIf { TRIP_ID.matches(it) } ?: return
        runAsync(context, "stop action") {
            it.runtime.ensureLoaded()
            it.runtime.userAction(tripId, UserActionKind.STOP_TRIP)
        }
    }

    companion object {
        const val ACTION_STOP = "app.napstop.action.STOP_TRIP"
        const val EXTRA_TRIP_ID = "tripId"
    }
}
