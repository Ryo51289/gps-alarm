package app.napstop.core.alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import app.napstop.core.trip.host.runAsync

/** The backup ring notification was swiped away (spec T16 §5.9): the ring ended → SILENCED to the runtime. */
class BackupRingReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION) return
        val tripId = RingIntents.validTripId(intent.getStringExtra(RingIntents.EXTRA_TRIP_ID)) ?: return
        runAsync(context, "backup deleted") { host -> host.alarm.onBackupDeleted(tripId) }
    }

    companion object {
        const val ACTION = "app.napstop.action.BACKUP_RING_DELETED"
    }
}
