package app.napstop.core.alarm

import android.content.Context
import android.content.Intent
import android.os.Bundle
import app.napstop.core.alarm.ring.AlarmActivity
import app.napstop.core.alarm.ring.AlarmRingService
import app.napstop.core.alarm.ring.RingCommandReceiver

/** Intent contract between the main process and `:ring` (spec T16 §4.5). No coordinates in any extra. */
object RingIntents {
    const val ACTION_RING_START = "app.napstop.action.RING_START"
    const val ACTION_RING_ADOPT = "app.napstop.action.RING_ADOPT"
    const val ACTION_RING_COMMAND = "app.napstop.action.RING_COMMAND"
    const val EXTRA_TRIP_ID = "tripId"
    const val EXTRA_CMD = "cmd"
    const val EXTRA_PAST_M = "pastM"
    const val EXTRA_CAUSE = "cause"
    const val EXTRA_STOP_SEQ = "stopSeq"
    const val EXTRA_AT_WALL_MS = "atWallMs"
    const val EXTRA_RING_START = "RING_START"

    const val CMD_UPDATE = "UPDATE"
    const val CMD_OVERSHOOT = "OVERSHOOT"
    const val CMD_STOP = "STOP"
    const val CMD_SNOOZE = "SNOOZE"

    /** PendingIntent request codes 0x4E5750–0x4E575F (§5.9). */
    const val REQ_ACTIVITY = 0x4E5750
    const val REQ_SNOOZE = 0x4E5751
    const val REQ_BACKUP_DELETE = 0x4E5752
    const val REQ_PRE_ALERT_OPEN = 0x4E5753
    const val REQ_BACKUP_ACTIVITY = 0x4E5754
    const val REQ_BACKUP_ADOPT = 0x4E5755

    private val TRIP_ID = Regex("^[A-Za-z0-9_-]{1,64}$")

    fun validTripId(s: String?): String? = s?.takeIf { TRIP_ID.matches(it) }

    fun toBundle(s: RingStart): Bundle {
        val b = Bundle()
        for ((k, v) in RingStartCodec.toMap(s)) {
            when (v) {
                null -> Unit
                is String -> b.putString(k, v)
                is Long -> b.putLong(k, v)
                is Int -> b.putInt(k, v)
                is Boolean -> b.putBoolean(k, v)
                is Double -> b.putDouble(k, v)
                else -> Unit
            }
        }
        return b
    }

    @Suppress("DEPRECATION")
    fun fromBundle(b: Bundle?): RingStart? {
        if (b == null) return null
        val m = HashMap<String, Any?>()
        for (k in b.keySet()) m[k] = b.get(k)
        return RingStartCodec.fromMap(m)
    }

    fun startService(ctx: Context, s: RingStart): Intent =
        Intent(ctx, AlarmRingService::class.java).setAction(ACTION_RING_START).putExtras(toBundle(s))

    fun adoptService(ctx: Context, tripId: String, start: Bundle? = null): Intent =
        Intent(ctx, AlarmRingService::class.java).setAction(ACTION_RING_ADOPT).putExtra(EXTRA_TRIP_ID, tripId).also { i ->
            start?.let { i.putExtra(EXTRA_RING_START, it) }
        }

    fun command(ctx: Context, c: RingCommand): Intent {
        val i = Intent(ctx, RingCommandReceiver::class.java).setAction(ACTION_RING_COMMAND).putExtra(EXTRA_TRIP_ID, c.tripId)
        when (c) {
            is RingCommand.Update -> i.putExtra(EXTRA_CMD, CMD_UPDATE).putExtra(EXTRA_RING_START, toBundle(c.start))
            is RingCommand.Overshoot -> i.putExtra(EXTRA_CMD, CMD_OVERSHOOT).putExtra(EXTRA_PAST_M, c.pastM)
            is RingCommand.Stop -> i.putExtra(EXTRA_CMD, CMD_STOP).putExtra(EXTRA_CAUSE, c.cause.name).putExtra(EXTRA_STOP_SEQ, c.stopSeq)
            is RingCommand.Snooze -> i.putExtra(EXTRA_CMD, CMD_SNOOZE).putExtra(EXTRA_AT_WALL_MS, c.atWallMs)
        }
        return i
    }

    /** Parses a RING_COMMAND; unknown command / enum / bad tripId → null (the command is dropped). */
    fun parseCommand(i: Intent): RingCommand? {
        if (i.action != ACTION_RING_COMMAND) return null
        val trip = validTripId(i.getStringExtra(EXTRA_TRIP_ID)) ?: return null
        return when (i.getStringExtra(EXTRA_CMD)) {
            CMD_UPDATE -> fromBundle(i.getBundleExtra(EXTRA_RING_START))?.takeIf { it.request.tripId == trip }?.let { RingCommand.Update(it) }
            CMD_OVERSHOOT -> i.getIntExtra(EXTRA_PAST_M, -1).takeIf { it >= 0 }?.let { RingCommand.Overshoot(trip, it) }
            CMD_STOP -> {
                val cause = StopCause.entries.firstOrNull { it.name == i.getStringExtra(EXTRA_CAUSE) } ?: return null
                RingCommand.Stop(trip, cause, i.getLongExtra(EXTRA_STOP_SEQ, Long.MIN_VALUE))
            }
            CMD_SNOOZE -> RingCommand.Snooze(trip, i.getLongExtra(EXTRA_AT_WALL_MS, System.currentTimeMillis()))
            else -> null
        }
    }

    /** AlarmActivity of [tripId] (FSI / content intent / direct start). */
    fun activity(ctx: Context, tripId: String): Intent =
        Intent(ctx, AlarmActivity::class.java)
            .putExtra(EXTRA_TRIP_ID, tripId)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_USER_ACTION)
}
