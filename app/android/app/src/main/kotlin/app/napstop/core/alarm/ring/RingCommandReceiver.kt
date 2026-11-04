package app.napstop.core.alarm.ring

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import app.napstop.core.alarm.RingCommand
import app.napstop.core.alarm.RingInput
import app.napstop.core.alarm.RingIntents

/**
 * Commands to the ring session (spec T16 §4.5), process `:ring`, not exported: UPDATE / OVERSHOOT / STOP from the main
 * process, SNOOZE from the notification button. Unknown command, enum or tripId → dropped. The session thread does
 * the work; onReceive returns at once.
 */
class RingCommandReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val cmd = RingIntents.parseCommand(intent) ?: return
        val session = RingSession.get(context)
        when (cmd) {
            is RingCommand.Update -> session.post(RingInput.Update(cmd.start))
            is RingCommand.Overshoot -> session.post(RingInput.Overshoot(cmd.tripId, cmd.pastM))
            is RingCommand.Stop -> session.post(RingInput.Stop(cmd.tripId, cmd.cause, cmd.stopSeq))
            is RingCommand.Snooze -> session.snoozeFromNotification(cmd.tripId, cmd.atWallMs)
        }
    }
}
